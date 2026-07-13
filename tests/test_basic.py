import time
import requests
import pytest

API_KEY = "ccf889af356d47bebd03fc30f79b1127"

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

def test_container_running(running_container):
    """Container should be running after fixture setup."""
    assert running_container is not None

def test_radarr_health(running_container):
    """Radarr should respond to health check within timeout."""
    url = f"http://localhost:7878/api/v3/system/status?apikey={API_KEY}"
    assert wait_for_service(url), "Radarr did not respond within 120s"

def test_sonarr_health(running_container):
    """Sonarr should respond to health check within timeout."""
    url = f"http://localhost:8989/api/v3/system/status?apikey={API_KEY}"
    assert wait_for_service(url), "Sonarr did not respond within 120s"

def test_prowlarr_health(running_container):
    """Prowlarr should respond to health check within timeout."""
    url = f"http://localhost:9696/api/v1/system/status?apikey={API_KEY}"
    assert wait_for_service(url), "Prowlarr did not respond within 120s"
