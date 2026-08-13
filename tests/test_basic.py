import time
import subprocess
import socket
import requests
import pytest

REQUIRED_PORTS = (7878, 8989, 9696)


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


def test_required_ports_available():
    """Required host ports should be free before starting the test container."""
    unavailable = [port for port in REQUIRED_PORTS if not port_is_available(port)]
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

def test_radarr_health(running_container, api_key):
    """Radarr should respond to health check within timeout."""
    url = f"http://localhost:7878/api/v3/system/status?apikey={api_key}"
    assert wait_for_service(url), "Radarr did not respond within 120s"

def test_sonarr_health(running_container, api_key):
    """Sonarr should respond to health check within timeout."""
    url = f"http://localhost:8989/api/v3/system/status?apikey={api_key}"
    assert wait_for_service(url), "Sonarr did not respond within 120s"

def test_prowlarr_health(running_container, api_key):
    """Prowlarr should respond to health check within timeout."""
    url = f"http://localhost:9696/api/v1/system/status?apikey={api_key}"
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


