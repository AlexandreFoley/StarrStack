import time
import subprocess
import socket
import requests
import pytest


def port_is_available(port):
    """Return True when the host TCP port is free to bind."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True

def wait_for_service(url, timeout=120, poll_interval=10):
    """Wait for a service to respond to a health check."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            resp = requests.get(url, timeout=5)
            if resp.ok:
                return True
        except requests.ConnectionError:
            pass
        time.sleep(poll_interval)
    return False


def test_required_ports_available(host_port):
    """The variant's host ports must be free before starting the test
    container (both variants run side by side in one session, each on its
    own port range)."""
    unavailable = [port for port in host_port.values() if not port_is_available(port)]
    assert not unavailable, (
        "Required host ports are already in use: "
        f"{', '.join(str(port) for port in unavailable)}. "
        "Stop the conflicting service(s) and re-run tests."
    )

def test_starr_container_has_logs(running_container):
    """The starr container should emit at least some logs."""
    deadline = time.time() + 30
    while time.time() < deadline:
        result = subprocess.run(
            ["podman", "logs", running_container],
            capture_output=True,
            text=True,
            check=False,
        )
        logs = (result.stdout or "").strip()
        if logs:
            break
        time.sleep(2)
    else:
        pytest.fail("starr container produced no logs within 30s")

    assert logs

def test_radarr_health(running_container, api_key, host_port):
    """Radarr should respond to health check within timeout."""
    url = f"http://localhost:{host_port['7878']}/api/v3/system/status?apikey={api_key}"
    assert wait_for_service(url), "Radarr did not respond within 120s"

def test_sonarr_health(running_container, api_key, host_port):
    """Sonarr should respond to health check within timeout."""
    url = f"http://localhost:{host_port['8989']}/api/v3/system/status?apikey={api_key}"
    assert wait_for_service(url), "Sonarr did not respond within 120s"

def test_prowlarr_health(running_container, api_key, host_port):
    """Prowlarr should respond to health check within timeout."""
    url = f"http://localhost:{host_port['9696']}/api/v1/system/status?apikey={api_key}"
    assert wait_for_service(url), "Prowlarr did not respond within 120s"


def test_services_run_with_shared_media_group(running_container):
    """All services must run with primary gid 0 so /media sharing works via the
    host user's group (rootless maps host group to container gid 0) without the
    container ever modifying the media tree."""
    result = subprocess.run(
        ["podman", "exec", running_container, "sh", "-c",
         "for p in /proc/[0-9]*; do c=$(cat $p/comm 2>/dev/null); "
         "case $c in Radarr|Sonarr|Prowlarr|unpackerr) "
         "awk '/^Gid:/{print $2}' $p/status;; esac; done"],
        capture_output=True, text=True, check=False,
    )
    gids = result.stdout.split()
    assert len(gids) == 4 and all(g == "0" for g in gids), f"service primary gids: {gids}"


def test_config_dirs_owned_and_isolated(running_container):
    """Each /config/<svc> must be owned by its service with mode 700, and other
    services must not be able to enter it — even with the shared gid 0 that
    /media sharing grants them."""
    result = subprocess.run(
        ["podman", "exec", running_container, "stat", "-c", "%n %U %a",
         "/config/radarr", "/config/sonarr", "/config/prowlarr", "/config/unpackerr"],
        capture_output=True, text=True, check=True,
    )
    for line, svc in zip(result.stdout.splitlines(),
                         ["radarr", "sonarr", "prowlarr", "unpackerr"]):
        assert line == f"/config/{svc} {svc} 700", line
    probe = subprocess.run(
        ["podman", "exec", running_container,
         "runuser", "-u", "sonarr", "-g", "root", "--", "test", "-x", "/config/radarr"],
        capture_output=True, check=False,
    )
    assert probe.returncode != 0, "sonarr could traverse /config/radarr — isolation broken"


def test_opt_root_owned_not_group_writable(running_container):
    """/opt must be root-owned with no group/other write anywhere: services run
    with primary gid 0, so any group-writable file under /opt would be
    service-writable. Also guards the BuildKit backend, which preserves the
    builder stages' (wrong) ownership instead of resetting to root."""
    result = subprocess.run(
        ["podman", "exec", running_container, "stat", "-c", "%n %U %G %a",
         "/opt/Radarr", "/opt/Sonarr", "/opt/Prowlarr"],
        capture_output=True, text=True, check=True,
    )
    for line, d in zip(result.stdout.splitlines(), ["Radarr", "Sonarr", "Prowlarr"]):
        assert line == f"/opt/{d} root root 755", line
    writable = subprocess.run(
        ["podman", "exec", running_container, "sh", "-c",
         "find /opt \\( -type f -o -type d \\) -perm /022"],
        capture_output=True, text=True, check=True,
    )
    assert not writable.stdout.strip(), f"writable paths under /opt:\n{writable.stdout[:500]}"


def test_unpackerr_environment_file_root_only(running_container, variant):
    """The unpackerr arr credentials must be root-only on disk. ubi keeps them
    in a systemd drop-in; alpine in /etc/conf.d/unpackerr (written by the
    PID-1 harvest). Either way the daemon receives them via its environment,
    not by reading the file."""
    path = ("/etc/systemd/system/unpackerr.service.d/environment.conf"
            if variant == "ubi"
            else "/etc/conf.d/unpackerr")
    result = subprocess.run(
        ["podman", "exec", running_container, "stat", "-c", "%U %a", path],
        capture_output=True, text=True, check=True,
    )
    assert result.stdout.strip() == "root 600", result.stdout


