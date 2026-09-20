"""The Prowlarr "<App>-autoconf" applications must follow the container's env.

The arr API keys are supplied externally, so a rotated key (or a changed URL
base) must not leave Prowlarr holding the stale one: configure-indexers
refreshes the existing entry on every startup.
"""

import json
import subprocess
import time

import pytest


PROWLARR = "http://127.0.0.1:9696"
APPS = f"{PROWLARR}/api/v1/applications"
BAD_KEY = "0" * 32


def run_shell(container, script, timeout=300):
    """Run a shell script inside the container via stdin (no quoting games)."""
    return subprocess.run(
        ["podman", "exec", "-i", container, "sh"],
        input=script, capture_output=True, text=True, check=False, timeout=timeout,
    )


def wait_for_prowlarr(container, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        probe = run_shell(
            container,
            f'curl -sf -H "X-Api-Key: $PROWLARR__AUTH__APIKEY" {PROWLARR}/api/v1/system/status',
        )
        if probe.returncode == 0:
            return
        time.sleep(2)
    pytest.fail("Prowlarr did not become ready")


def autoconf_application(container, name="Radarr-autoconf"):
    """The stored Prowlarr application, or None before it has been created.
    Secret fields (apiKey) come back masked as '********'."""
    result = run_shell(
        container,
        f'curl -s -H "X-Api-Key: $PROWLARR__AUTH__APIKEY" {APPS} | '
        f"jq -c 'first(.[] | select(.name == \"{name}\")) // empty'",
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout) if result.stdout.strip() else None


def wait_for_autoconf(container, timeout=120):
    """Prowlarr answers before configure-indexers creates the entries, so poll."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        app = autoconf_application(container)
        if app:
            return app
        time.sleep(2)
    pytest.fail("Radarr-autoconf did not appear in Prowlarr")


def field_value(app, name):
    return next(field["value"] for field in app["fields"] if field["name"] == name)


def test_configure_indexers_refreshes_existing_entry(running_container, api_key):
    """An existing autoconf application is refreshed on every
    configure-indexers run (every container start), not skipped.

    Prowlarr masks apiKey in API responses, so the refreshed baseUrl is the
    observable field; the script's exit code covers the key as well, because
    Prowlarr rejects an update whose apiKey fails the connection test (400)."""
    wait_for_prowlarr(running_container)
    app = wait_for_autoconf(running_container)
    assert field_value(app, "baseUrl") == "http://localhost:7878"

    # Make the stored connection stale; forceSave skips the connection test.
    corrupt = run_shell(
        running_container,
        f'''set -e
app=$(curl -s -H "X-Api-Key: $PROWLARR__AUTH__APIKEY" {APPS} | jq -c 'first(.[] | select(.name == "Radarr-autoconf"))')
id=$(printf '%s' "$app" | jq -r .id)
printf '%s' "$app" | jq -c '.fields |= map(if .name == "baseUrl" then .value = "http://127.0.0.1:1/"
                                            elif .name == "apiKey" then .value = "{BAD_KEY}"
                                            else . end)' |
  curl -sf -o /dev/null -X PUT -H "Content-Type: application/json" \
    -H "X-Api-Key: $PROWLARR__AUTH__APIKEY" --data-binary @- \
    "{APPS}/$id?forceSave=true"
''',
    )
    assert corrupt.returncode == 0, corrupt.stderr
    app = autoconf_application(running_container)
    assert field_value(app, "baseUrl") == "http://127.0.0.1:1/"

    rerun = run_shell(running_container, "/usr/local/bin/configure-indexers.sh")
    assert rerun.returncode == 0, rerun.stdout + rerun.stderr

    app = autoconf_application(running_container)
    assert field_value(app, "baseUrl") == "http://localhost:7878"
