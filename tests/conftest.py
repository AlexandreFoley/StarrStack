import json
import os
import subprocess
import urllib.request
import uuid
import pytest
from podman import PodmanClient

# One test suite, two images. VARIANT=ubi (default) | alpine picks the
# dockerfile and the container run flags; the runtime tests in test_basic.py
# are shared except where the images genuinely differ (the unpackerr env file).
VARIANT = os.environ.get("VARIANT", "ubi")

DOCKERFILES = {"ubi": "ubi.dockerfile", "alpine": "alpine.dockerfile"}

TAG = f"starr-test-{VARIANT}:latest"


def latest_unpackerr() -> str:
    """Latest unpackerr release tag (without the 'v' prefix). The alpine build
    needs a concrete version (its unpackerr is a release binary); the ubi build
    installs from the golift package repo and needs none."""
    with urllib.request.urlopen(
        "https://api.github.com/repos/Unpackerr/unpackerr/releases/latest",
        timeout=30,
    ) as resp:
        return json.load(resp)["tag_name"].lstrip("v")


@pytest.fixture(scope="session")
def variant():
    return VARIANT


@pytest.fixture(scope="session")
def api_key():
    # hex, 32 chars - also a valid unpackerr API key (it rejects other lengths)
    return uuid.uuid4().hex


def build_image():
    """Build the image for the active VARIANT, streaming output to stdout.
    CLI build because the sdk offers no easy way to stream build progress.
    """
    cmd = ["podman", "build", "--file", DOCKERFILES[VARIANT], "--tag", TAG, "."]
    if VARIANT == "alpine":
        # Always-latest default (env UNPACKERR_VERSION overrides for pinning
        # or testing a specific release).
        version = os.environ.get("UNPACKERR_VERSION") or latest_unpackerr()
        print(f"container: building alpine image with unpackerr {version}", flush=True)
        cmd[2:2] = ["--build-arg", f"UNPACKERR_VERSION={version}"]
    result = subprocess.run(cmd)
    result.check_returncode()

@pytest.fixture(scope="session")
def podman_client():
    """Connect to Podman daemon."""
    with PodmanClient() as client:
        yield client

@pytest.fixture(scope="session")
def built_image(podman_client:PodmanClient):
    """Build image for the active VARIANT, yield image object.

    Equivalent command line for the ubi variant:
    podman build --file ubi.dockerfile --tag starr-test-ubi:latest .
    """
    build_image()
    yield podman_client.images.get(TAG)

@pytest.fixture(scope="session")
def running_container(podman_client:PodmanClient, built_image, api_key):
    """Start container, yield name, cleanup on exit.

    Equivalent command line for the ubi variant:
    podman run -d --name starr-test-<uuid> -p 7878:7878 -p 8989:8989 -p 9696:9696 \
      -e RADARR__AUTH__APIKEY=<key> -e RADARR__SERVER__PORT=7878 \
      -e SONARR__AUTH__APIKEY=<key> -e SONARR__SERVER__PORT=8989 \
      -e PROWLARR__AUTH__APIKEY=<key> -e PROWLARR__SERVER__PORT=9696 \
      starr-test-ubi:latest
    podman's --systemd default is true and auto-detects systemd by the
    command being /sbin/init, so no flag is needed for the ubi image (its
    /sbin/init really is systemd). The alpine image's /sbin/init is our OpenRC
    wrapper, which the same heuristic would misdetect - forcing systemd=false
    keeps podman's stop signal at SIGTERM so the wrapper's graceful
    `openrc shutdown` path runs on podman stop.
    """
    name = f"starr-test-{uuid.uuid4()}"
    run_kwargs = dict(
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
    )
    if VARIANT == "alpine":
        run_kwargs["systemd"] = "false"
    try:
        podman_client.containers.run(built_image, **run_kwargs)
        yield name
    finally:
        subprocess.run(
            ["podman", "rm", "-f", name],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
