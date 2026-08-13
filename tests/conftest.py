import subprocess
import uuid
import pytest
from podman import PodmanClient

@pytest.fixture(scope="session")
def api_key():
    return uuid.uuid4().hex


def build_image():
    """Build the image fresh (no cache), streaming output to stdout in real-time.
    We are using cli command because calling through the sdk gives no easy way to output before the build is completed.
    It simpler to just call the cli.
    """
    result = subprocess.run(
        [
            "podman", "build",
            "--file", "ubi.dockerfile",
            "--tag", "starr-test:latest",
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
    """Build image fresh, yield image object.

    Equivalent command line:
    podman build --file ubi.dockerfile --tag starr-test:latest .
    """
    build_image()
    yield podman_client.images.get("starr-test:latest")

@pytest.fixture(scope="session")
def running_container(podman_client:PodmanClient, built_image, api_key):
    """Start container, yield name, cleanup on exit.

    Equivalent command line:
    podman run -d --name starr-test-<uuid> -p 7878:7878 -p 8989:8989 -p 9696:9696 \
      -e RADARR__AUTH__APIKEY=<key> -e RADARR__SERVER__PORT=7878 \
      -e SONARR__AUTH__APIKEY=<key> -e SONARR__SERVER__PORT=8989 \
      -e PROWLARR__AUTH__APIKEY=<key> -e PROWLARR__SERVER__PORT=9696 \
      --systemd=true starr-test:latest
    """
    name = f"starr-test-{uuid.uuid4()}"
    try:
        podman_client.containers.run(
            built_image,
            detach=True,
            tty=True,
            # stdin_open=True,
            name=name,
            ports={"7878/tcp": 7878, "8989/tcp": 8989, "9696/tcp": 9696},
            environment={
                "RADARR__AUTH__APIKEY": api_key,
                "RADARR__SERVER__PORT": "7878",
                "SONARR__AUTH__APIKEY": api_key,
                "SONARR__SERVER__PORT": "8989",
                "PROWLARR__AUTH__APIKEY": api_key,
                "PROWLARR__SERVER__PORT": "9696",
            },
            systemd="true",
        )
        yield name
    finally:
        subprocess.run(
            ["podman", "rm", "-f", name],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
