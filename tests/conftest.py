import subprocess
import uuid
import pytest
from podman import PodmanClient

# Read API key from test_api_key file
_env_file = __import__("pathlib").Path(__file__).resolve().parent.parent / "test_api_key"
_API = dict(line.split("=", 1) for line in open(_env_file) if "=" in line and not line.startswith("#"))
API_KEY = _API["API_KEY"]


@pytest.fixture(scope="session")
def api_key():
    return API_KEY


def build_image(podman_client: PodmanClient):
    """Build the image fresh (no cache), streaming output to stdout in real-time."""
    result = subprocess.run(
        [
            "podman", "build",
            "--file", "ubi.dockerfile",
            "--tag", "starr-test:latest",
            # "--no-cache",
            # "--rm=false",
            ".",
        ],
    )
    result.check_returncode()

@pytest.fixture(scope="session")
def podman_client():
    """Connect to Podman daemon."""
    with PodmanClient() as client:
        yield client

@pytest.fixture(scope="session")
def built_image(podman_client:PodmanClient):
    """Build image fresh, yield image object."""
    build_image(podman_client)
    yield podman_client.images.get("starr-test:latest")

@pytest.fixture(scope="session")
def running_container(podman_client:PodmanClient, built_image):
    """Start container, yield name, cleanup on exit."""
    name = f"starr-test-{uuid.uuid4()}"
    podman_client.containers.run(
        built_image,
        detach=True,
        name=name,
        ports={"7878/tcp": 7878, "8989/tcp": 8989, "9696/tcp": 9696},
        environment={
            "RADARR__AUTH__APIKEY": API_KEY,
            "RADARR__SERVER__PORT": "7878",
            "SONARR__AUTH__APIKEY": API_KEY,
            "SONARR__SERVER__PORT": "8989",
            "PROWLARR__AUTH__APIKEY": API_KEY,
            "PROWLARR__SERVER__PORT": "9696",
        },
        systemd="true",
    )
    yield name
    try:
        podman_client.containers.get(name).stop()
        podman_client.containers.get(name).remove()
    except Exception:
        pass
