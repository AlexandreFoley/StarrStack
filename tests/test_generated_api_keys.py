"""Runtime coverage for API keys generated when no key is supplied."""

import subprocess
import time

import pytest


SERVICES = {
    "radarr": ("RADARR__AUTH__APIKEY", "7878", "/api/v3/system/status"),
    "sonarr": ("SONARR__AUTH__APIKEY", "8989", "/api/v3/system/status"),
    "prowlarr": ("PROWLARR__AUTH__APIKEY", "9696", "/api/v1/system/status"),
}


def exec_container(container, *command):
    result = subprocess.run(
        ["podman", "exec", container, *command],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    return result


def wait_for_api(container, port, path, api_key, timeout=120):
    url = f"http://127.0.0.1:{port}{path}?apikey={api_key}"
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = exec_container(container, "curl", "--fail", "--silent", url)
        if result.returncode == 0:
            return result.stdout
        time.sleep(2)
    pytest.fail(f"{path} did not respond successfully within {timeout}s")


def generated_key(container, variant, service, timeout=120):
    env_name = SERVICES[service][0]
    deadline = time.time() + timeout
    while time.time() < deadline:
        if variant == "alpine":
            command = (
                "sh",
                "-c",
                f". /etc/conf.d/{service}; printf '%s' \"${env_name}\"",
            )
        else:
            command = ("systemctl", "show-environment")
        result = exec_container(container, *command)
        assert result.returncode == 0, result.stderr
        if variant == "alpine":
            value = result.stdout
        else:
            values = dict(
                line.split("=", 1)
                for line in result.stdout.splitlines()
                if "=" in line
            )
            value = values.get(env_name, "")
        if value:
            return value
        time.sleep(2)
    pytest.fail(f"{env_name} was not generated within {timeout}s")


@pytest.mark.parametrize("service", SERVICES)
def test_generated_key_authenticates_against_all_services(
    generated_key_container, variant, service
):
    _, port, path = SERVICES[service]
    api_key = generated_key(generated_key_container, variant, service)

    assert len(api_key) == 32
    assert all(char in "0123456789abcdef" for char in api_key)
    wait_for_api(generated_key_container, port, path, api_key)


@pytest.mark.parametrize("service", SERVICES)
def test_generated_key_rejects_wrong_key(
    generated_key_container, variant, service
):
    _, port, path = SERVICES[service]
    wait_for_api(
        generated_key_container,
        port,
        path,
        generated_key(generated_key_container, variant, service),
    )

    result = exec_container(
        generated_key_container,
        "curl",
        "--silent",
        "--output",
        "/dev/null",
        "--write-out",
        "%{http_code}",
        f"http://127.0.0.1:{port}{path}?apikey={'0' * 32}",
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "401"
