"""Integration tests for quadlet files using podman-in-podman.

Builds a test harness container (UBI-init + podman) that has systemd,
installs quadlet files, and verifies the full quadlet -> systemd -> podman
deployment pipeline.
"""
import subprocess
import time
import uuid

import pytest

PROJECT_ROOT = __import__("pathlib").Path(__file__).resolve().parent.parent
HARNESS_DIR = PROJECT_ROOT / "tests" / "harness"
HARNESS_IMAGE = "starr-quadlet-harness:latest"


def _run(cmd, check=True, timeout=60, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, text=True, capture_output=True,
                          timeout=timeout, **kwargs)


def _podman_exec(container, *cmd, timeout=10):
    full = ["podman", "exec", container, *cmd]
    return _run(full, check=False, timeout=timeout)


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
    """Build harness image with quadlet files.
    
    Builds using PROJECT_ROOT as context so quadlet files reference the
    single source of truth in quadlet/starrstack/.
    Images (starr and qbittorrent) are imported into the running container
    by the running_harness fixture rather than built into the image.
    """
    try:
        _run([
            "podman", "build",
            "-t", HARNESS_IMAGE,
            "-f", str(HARNESS_DIR / "Dockerfile"),
            str(PROJECT_ROOT),
        ], timeout=300)
    except subprocess.CalledProcessError as e:
        pytest.skip(
            f"Harness image build failed: {e.stderr}"
        )
    
    yield HARNESS_IMAGE


def _poll_until(container, cmd, predicate, timeout_s=60, interval=0.5):
    """Poll a command inside container until predicate returns True or timeout."""
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        result = _podman_exec(container, *cmd, timeout=timeout_s)
        if predicate(result.stdout):
            return True
        time.sleep(interval)
    return False


@pytest.fixture(scope="module")
def running_harness(harness_image):
    """Start a privileged harness with systemd + quadlet files installed."""
    container = f"quadlet-harness-{uuid.uuid4().hex[:8]}"

    try:
        # Ensure both qbittorrent and starr images are available on host
        _ensure_qbittorrent_on_host()
        print("Building starr image on host...")
        _run([
            "podman", "build",
            "-t", "ghcr.io/alexandrefoley/starrstack:latest",
            "-f", "ubi.dockerfile",
            ".",
        ], timeout=300, cwd=PROJECT_ROOT)

        # Start harness with quadlet files installed
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

        # Poll for systemd to be ready (can take 10-15 seconds)
        if not _poll_until(
            container,
            ["systemctl", "is-system-running"],
            lambda out: out.strip() in ("running", "degraded", "maintenance"),
            timeout_s=90
        ):
            pytest.fail("systemd did not reach a stable state within timeout")

        # Pull images inside the container instead of importing
        print("Pulling starr image inside container...")
        starr_pull = _podman_exec(container, "podman", "pull", "ghcr.io/alexandrefoley/starrstack:latest", timeout=300)
        if "Error" in starr_pull.stderr or starr_pull.returncode != 0:
            pytest.fail(f"Failed to pull starr image: {starr_pull.stderr}")
        
        print("Pulling qbittorrent image inside container...")
        qbit_pull = _podman_exec(container, "podman", "pull", "ghcr.io/alexandrefoley/qbittorrent:latest", timeout=300)
        if "Error" in qbit_pull.stderr or qbit_pull.returncode != 0:
            pytest.fail(f"Failed to pull qbittorrent image: {qbit_pull.stderr}")

        # Start quadlet services (systemd will handle dependencies automatically)
        _podman_exec(container, "systemctl", "daemon-reload")
        _podman_exec(container, "systemctl", "start",
                      "starr.service", "qbittorrent.service",
                      timeout=30)

        # Poll for both containers to appear in podman ps
        if not _poll_until(
            container,
            ["podman", "ps", "--format", "{{.Names}}"],
            lambda out: "starr" in out and "qbittorrent" in out,
            timeout_s=60
        ):
            # Debug: get full journal logs for services
            journal = _podman_exec(container, "journalctl", "-u", "starr.service", "-n", "50", "--no-pager", timeout=10)
            qbit_status = _podman_exec(container, "systemctl", "status", "qbittorrent.service", timeout=10)
            starr_status = _podman_exec(container, "systemctl", "status", "starr.service", timeout=10)
            pytest.fail(f"Containers did not start within timeout\nStarr journal:\n{journal.stdout}\nqbittorrent status:\n{qbit_status.stdout}\nstarr status:\n{starr_status.stdout}")

        # Give applications time to initialize (radarr, sonarr, prowlarr can take 60-90s to fully start)
        print("Waiting for applications to start up...")
        time.sleep(90)

        yield container

    finally:
        # If the container exited, capture its logs to see what happened
        check_status = _run(["podman", "inspect", container], check=False, timeout=5)
        if check_status.returncode == 0:
            # Container still exists, capture logs before stopping
            logs = _run(["podman", "logs", container], check=False, timeout=10)
            if logs.stdout or logs.stderr:
                print("\n" + "="*60)
                print("Container logs:")
                print("="*60)
                if logs.stdout:
                    print(logs.stdout)
                if logs.stderr:
                    print("STDERR:", logs.stderr)
                print("="*60 + "\n")
        
        _run(["podman", "stop", "--time", "5", container], check=False, timeout=15)
        _run(["podman", "rm", "-f", container], check=False, timeout=10)


# ── Tests ──────────────────────────────────────────────────────────

class TestHarnessSanity:

    def test_harness_image_exists(self, harness_image):
        result = _run(["podman", "images", "-q", harness_image], check=False)
        assert result.stdout.strip(), f"Harness image {harness_image} not found"
    def test_harness_running(self, running_harness):
        result = _podman_exec(running_harness, "systemctl", "is-system-running")
        assert result.stdout.strip() in ("running", "degraded", "maintenance")


class TestServiceHealthChecks:
    """Health checks for core services."""
    
    def test_qbittorrent_health(self, running_harness):
        """Check qBittorrent WebUI responds."""
        result = _podman_exec(running_harness, "curl", "-s", "-f", 
                             "http://localhost:8080", timeout=5)
        assert result.returncode == 0, f"qBittorrent health check failed: {result.stderr}"
    
    def test_radarr_health(self, running_harness, api_key):
        """Check Radarr API responds."""
        result = _podman_exec(running_harness, "curl", "-s", "-f",
                             "-H", f"X-Api-Key: {api_key}",
                             "http://localhost:7878/api/v3/system/status",
                             timeout=5)
        assert result.returncode == 0, f"Radarr health check failed: {result.stderr}"
    
    def test_sonarr_health(self, running_harness, api_key):
        """Check Sonarr API responds."""
        result = _podman_exec(running_harness, "curl", "-s", "-f",
                             "-H", f"X-Api-Key: {api_key}",
                             "http://localhost:8989/api/v3/system/status",
                             timeout=5)
        assert result.returncode == 0, f"Sonarr health check failed: {result.stderr}"
    
    def test_prowlarr_health(self, running_harness, api_key):
        """Check Prowlarr API responds."""
        result = _podman_exec(running_harness, "curl", "-s", "-f",
                             "-H", f"X-Api-Key: {api_key}",
                             "http://localhost:9696/api/v1/system/status",
                             timeout=5)
        assert result.returncode == 0, f"Prowlarr health check failed: {result.stderr}"
