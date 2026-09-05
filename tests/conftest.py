import json
import os
import subprocess
import urllib.request
import uuid
from pathlib import Path
import pytest
from podman import PodmanClient

# One test suite, both images. By default every runtime test runs against
# both variants in a single session; VARIANT=ubi|alpine restricts to one
# (useful for fast dev loops and per-variant CI jobs).
VARIANTS = [os.environ["VARIANT"]] if "VARIANT" in os.environ else ["ubi", "alpine"]

# Repo root, resolved from this file - never from cwd, so the suite works no
# matter where pytest is invoked from.
REPO_ROOT = Path(__file__).resolve().parent.parent

DOCKERFILES = {v: str(REPO_ROOT / f"{v}.dockerfile") for v in ("ubi", "alpine")}

# Host ports per variant: the app ports inside the container are the same
# (7878/8989/9696); only the host-side publish differs so both containers can
# run side by side in one session without conflicting.
HOST_PORTS = {
    "ubi": {"7878": 7878, "8989": 8989, "9696": 9696},
    "alpine": {"7878": 17978, "8989": 17989, "9696": 17969},
}

def tag_for(variant):
    return f"starr-test-{variant}:latest"


def latest_unpackerr() -> str:
    """Latest unpackerr release tag (without the 'v' prefix). The alpine build
    needs a concrete version (its unpackerr is a release binary); the ubi build
    installs from the golift package repo and needs none."""
    with urllib.request.urlopen(
        "https://api.github.com/repos/Unpackerr/unpackerr/releases/latest",
        timeout=30,
    ) as resp:
        return json.load(resp)["tag_name"].lstrip("v")


@pytest.fixture(scope="session", params=VARIANTS)
def variant(request):
    return request.param


@pytest.fixture(scope="session")
def host_port(variant):
    return HOST_PORTS[variant]


@pytest.fixture(scope="session")
def api_key():
    # hex, 32 chars - also a valid unpackerr API key (it rejects other lengths)
    return uuid.uuid4().hex


def build_image(variant):
    """Build the image for the given variant, streaming output to stdout.
    CLI build because the sdk offers no easy way to stream build progress.
    """
    # CI can build with BuildKit so its GitHub Actions cache backend is
    # available. The resulting image is loaded into Podman before pytest.
    if os.environ.get("PREBUILT_IMAGE"):
        print(f"container: using prebuilt image {tag_for(variant)}", flush=True)
        return

    cmd = ["podman", "build", "--file", DOCKERFILES[variant], "--tag", tag_for(variant), str(REPO_ROOT)]
    # Registry-backed build cache (buildah's OCI cache images). CI sets
    # PODMAN_BUILD_CACHE_FROM/TO to a short-lived GHCR tag per variant, so
    # rebuilds reuse layers across runs instead of going fully cold.
    for flag, env in (("--cache-from", "PODMAN_BUILD_CACHE_FROM"),
                      ("--cache-to", "PODMAN_BUILD_CACHE_TO")):
        if os.environ.get(env):
            cmd[2:2] = [flag, os.environ[env]]
    if variant == "alpine":
        # Always-latest default (env UNPACKERR_VERSION overrides for pinning
        # or testing a specific release).
        version = os.environ.get("UNPACKERR_VERSION") or latest_unpackerr()
        print(f"container: building alpine image with unpackerr {version}", flush=True)
        cmd[2:2] = ["--build-arg", f"UNPACKERR_VERSION={version}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode:
        # CalledProcessError alone hides podman's message; surface the cause.
        tail = "\n".join((result.stderr or "").splitlines()[-10:])
        hint = ("Is the podman machine running? `podman machine start`. "
                ) if "Cannot connect" in (result.stderr or "")\
                else ""
        raise SystemExit(
            f"podman build failed for {variant} (exit {result.returncode})\n"
            f"cmd: {' '.join(cmd)}\n{hint}last output:\n{tail}"
        )

@pytest.fixture(scope="session")
def podman_client():
    """Connect to Podman daemon."""
    with PodmanClient() as client:
        yield client

@pytest.fixture(scope="session")
def built_image(podman_client:PodmanClient, variant):
    """Build image for the variant, yield image object.

    Equivalent command line for the ubi variant:
    podman build --file ubi.dockerfile --tag starr-test-ubi:latest .
    """
    build_image(variant)
    yield podman_client.images.get(tag_for(variant))

@pytest.fixture(scope="session")
def running_container(podman_client:PodmanClient, built_image, api_key, variant):
    """Start the variant's container (host ports differ per variant so both can
    run side by side), yield name, cleanup on exit.

    podman's --systemd default is true and auto-detects systemd by the
    command being /sbin/init, so no flag is needed for the ubi image (its
    /sbin/init really is systemd). The alpine image's /sbin/init is our OpenRC
    wrapper, which the same heuristic would misdetect - forcing systemd=false
    keeps podman's stop signal at SIGTERM so the wrapper's graceful
    `openrc shutdown` path runs on podman stop.
    """
    name = f"starr-test-{variant}-{uuid.uuid4()}"
    run_kwargs = dict(
        detach=True,
        tty=True,
        # stdin_open=True,
        name=name,
        ports={f"{p}/tcp": hp for p, hp in HOST_PORTS[variant].items()},
        environment={
            "RADARR__AUTH__APIKEY": api_key,
            "RADARR__SERVER__PORT": "7878",
            "SONARR__AUTH__APIKEY": api_key,
            "SONARR__SERVER__PORT": "8989",
            "PROWLARR__AUTH__APIKEY": api_key,
            "PROWLARR__SERVER__PORT": "9696",
        },
    )
    if variant == "alpine":
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


@pytest.fixture(scope="session")
def generated_key_container(podman_client: PodmanClient, built_image, variant):
    """Start a container without API keys and yield its name for exec checks."""
    name = f"starr-generated-{variant}-{uuid.uuid4()}"
    run_kwargs = dict(
        detach=True,
        tty=True,
        name=name,
        environment={
            "RADARR__SERVER__PORT": "7878",
            "SONARR__SERVER__PORT": "8989",
            "PROWLARR__SERVER__PORT": "9696",
        },
    )
    if variant == "alpine":
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
