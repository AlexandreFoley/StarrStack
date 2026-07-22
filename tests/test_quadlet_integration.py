"""Integration tests for quadlet files using podman-in-podman.

Builds a test harness container (UBI-init + podman) that has systemd,
installs quadlet files, and verifies the full quadlet -> systemd -> podman
deployment pipeline.
"""
import subprocess
import time
import uuid

import pytest
import requests

PROJECT_ROOT = __import__("pathlib").Path(__file__).resolve().parent.parent
HARNESS_DIR = PROJECT_ROOT / "tests" / "harness"
HARNESS_IMAGE = "starr-quadlet-harness:latest"
NETWORK_NAME = "starrstack"

API_KEY = "test-api-key-quadlet"
WEBUI_PASSWORD = "testpass"


def _run(cmd, check=True, timeout=60, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, text=True, capture_output=True,
                          timeout=timeout, **kwargs)


def _run_binary(cmd, check=True, timeout=60, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, capture_output=True,
                          timeout=timeout, **kwargs)


def _podman_exec(container, *cmd, timeout=10):
    full = ["podman", "exec", container, *cmd]
    return _run(full, check=False, timeout=timeout)


def _wait_for_url(url, headers=None, timeout_s=120, interval=5):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            resp = requests.get(url, timeout=5, headers=headers or {},
                                allow_redirects=True)
            if resp.ok or resp.status_code == 302:
                return resp
        except requests.ConnectionError:
            pass
        time.sleep(interval)
    return None


def _ensure_qbittorrent_on_host():
    """Ensure qbittorrent image is available on host podman."""
    result = _run(["podman", "images", "-q", "ghcr.io/alexandrefoley/qbittorrent:latest"])
    if result.stdout.strip():
        return
    print("Pulling qbittorrent image on host...")
    _run(["podman", "pull", "ghcr.io/alexandrefoley/qbittorrent:latest"], timeout=300)


# ── Fixtures ───────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def harness_image():
    """Build harness image with quadlet files and starr image built in.
    
    Builds using PROJECT_ROOT as context so quadlet files reference the
    single source of truth in quadlet/starrstack/.
    """
    _run([
        "podman", "build",
        "-t", HARNESS_IMAGE,
        "-f", str(HARNESS_DIR / "Dockerfile"),
        str(PROJECT_ROOT),
    ], timeout=300)
    
    yield HARNESS_IMAGE


def _poll_until(container, cmd, predicate, timeout_s=60, interval=0.5):
    """Poll a command inside container until predicate returns True or timeout."""
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        result = _podman_exec(container, *cmd, timeout=timeout_s)
        if result.returncode == 0 and predicate(result.stdout):
            return True
        time.sleep(interval)
    return False


@pytest.fixture(scope="module")
def running_harness(harness_image):
    """Start a privileged harness with systemd + quadlet files installed."""
    container = f"quadlet-harness-{uuid.uuid4().hex[:8]}"

    try:
        # Ensure qbittorrent image is available on host
        _ensure_qbittorrent_on_host()

        # Start harness with quadlet files and starr image built in
        _run([
            "podman", "run", "-d",
            "--name", container,
            "--privileged",
            "-p", "7878:7878",
            "-p", "8989:8989",
            "-p", "9696:9696",
            "-p", "8080:8080",
            harness_image,
        ], timeout=30)

        # Poll for systemd to be ready
        if not _poll_until(
            container,
            ["systemctl", "is-system-running"],
            lambda out: out.strip() in ("running", "degraded", "maintenance"),
            timeout_s=60
        ):
            pytest.fail("systemd did not reach a stable state within timeout")

        # Import qbittorrent image into harness (starr is already built in)
        qbittorrent_save = _run_binary(["podman", "save", "ghcr.io/alexandrefoley/qbittorrent:latest"])
        qbittorrent_proc = subprocess.Popen(
            ["podman", "exec", "-i", container, "podman", "load"],
            stdin=subprocess.PIPE
        )
        try:
            qbittorrent_proc.communicate(input=qbittorrent_save.stdout, timeout=120)
        except subprocess.TimeoutExpired:
            qbittorrent_proc.kill()
            pytest.fail("Failed to import qbittorrent image within timeout")
        
        if qbittorrent_proc.returncode != 0:
            pytest.fail("Failed to import qbittorrent image")

        # Start quadlet services
        _podman_exec(container, "systemctl", "daemon-reload")
        _podman_exec(container, "systemctl", "start",
                      "starr.service", "qbittorrent.service",
                      timeout=30)

        # Poll for containers to appear in podman ps
        if not _poll_until(
            container,
            ["podman", "ps", "--format", "{{.Names}}"],
            lambda out: "starr" in out and "qbittorrent" in out,
            timeout_s=60
        ):
            pytest.fail("Containers did not start within timeout")

        yield container

    finally:
        _run(["podman", "stop", "--time", "5", container], check=False, timeout=15)
        _run(["podman", "rm", "-f", container], check=False, timeout=10)


# ── Tests ──────────────────────────────────────────────────────────

class TestHarnessSanity:
    def test_harness_running(self, running_harness):
        result = _podman_exec(running_harness, "systemctl", "is-system-running")
        assert result.stdout.strip() in ("running", "degraded", "maintenance")


class TestQuadletProcessing:
    def test_starr_unit_generated(self, running_harness):
        result = _podman_exec(running_harness,
                              "systemctl", "list-unit-files", "--type=service")
        assert "starr.service" in result.stdout

    def test_qbittorrent_unit_generated(self, running_harness):
        result = _podman_exec(running_harness,
                              "systemctl", "list-unit-files", "--type=service")
        assert "qbittorrent.service" in result.stdout

    def test_network_exists(self, running_harness):
        result = _podman_exec(running_harness, "podman", "network", "ls")
        assert NETWORK_NAME in result.stdout


class TestContainersFromQuadlet:
    def test_starr_container_running(self, running_harness):
        result = _podman_exec(running_harness, "podman", "ps", "--format", "{{.Names}}")
        assert "starr" in result.stdout

    def test_qbittorrent_container_running(self, running_harness):
        result = _podman_exec(running_harness, "podman", "ps", "--format", "{{.Names}}")
        assert "qbittorrent" in result.stdout

    def test_radarr_responds(self, running_harness):
        resp = _wait_for_url(
            "http://localhost:7878/api/v3/system/status",
            headers={"X-Api-Key": API_KEY},
        )
        assert resp is not None, "Radarr not reachable on localhost:7878"
        assert resp.ok

    def test_sonarr_responds(self, running_harness):
        resp = _wait_for_url(
            "http://localhost:8989/api/v3/system/status",
            headers={"X-Api-Key": API_KEY},
        )
        assert resp is not None, "Sonarr not reachable on localhost:8989"
        assert resp.ok

    def test_prowlarr_responds(self, running_harness):
        resp = _wait_for_url(
            "http://localhost:9696/api/v1/system/status",
            headers={"X-Api-Key": API_KEY},
        )
        assert resp is not None, "Prowlarr not reachable on localhost:9696"
        assert resp.ok

    def test_qbittorrent_webui(self, running_harness):
        resp = _wait_for_url("http://localhost:8080")
        assert resp is not None, "qBittorrent WebUI not reachable on localhost:8080"
