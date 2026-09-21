"""An existing "<Client>-autoconf" download client must be refreshed from the
environment on every configure-downloadclients run (every container start).

The torrent host and credentials are supplied externally, so changed values
must replace the ones Radarr/Sonarr stored, not be skipped.
"""

import json
import subprocess
import time

import pytest


RADARR = "http://127.0.0.1:7878"
SONARR = "http://127.0.0.1:8989"
CLIENT_NAME = "Qbittorrent-autoconf"  # ${TORRENT_CLIENT^}-autoconf, as the script derives it
TORRENT = {
    "TORRENT_CLIENT": "qbittorrent",
    "TORRENT_HOST": "torrentbox",
    "TORRENT_PORT": "9999",
    "TORRENT_USERNAME": "torrentuser",
    "TORRENT_PASSWORD": "torrentpass",
    "TORRENT_CATEGORY_MOVIES": "movies-cat",
    "TORRENT_CATEGORY_TV": "tv-cat",
    "TORRENT_USE_SSL": "true",
}


def run_shell(container, script, timeout=300):
    """Run a shell script inside the container via stdin (no quoting games)."""
    return subprocess.run(
        ["podman", "exec", "-i", container, "sh"],
        input=script, capture_output=True, text=True, check=False, timeout=timeout,
    )


def wait_for_arr(container, url, api_key, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        probe = run_shell(container, f'curl -sf -H "X-Api-Key: {api_key}" {url}/api/v3/system/status')
        if probe.returncode == 0:
            return
        time.sleep(2)
    pytest.fail(f"{url} did not become ready")


def stored_client(container, url, api_key):
    result = run_shell(
        container,
        f'curl -s -H "X-Api-Key: {api_key}" {url}/api/v3/downloadclient | '
        f"jq -c 'first(.[] | select(.name == \"{CLIENT_NAME}\")) // empty'",
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout) if result.stdout.strip() else None


def client_fields(client):
    return {field["name"]: field.get("value") for field in client["fields"]}


def create_stale_client(container, url, api_key, category_field):
    """Create the disabled entry the refresh will find. Disabled, because a
    disabled client is stored without running the qBittorrent connection test
    (there is no torrent client in the test environment)."""
    payload = json.dumps({
        "enable": False,
        "protocol": "torrent",
        "priority": 1,
        "name": CLIENT_NAME,
        "implementation": "QBittorrent",
        "configContract": "QBittorrentSettings",
        "fields": [
            {"name": "host", "value": "stale-host"},
            {"name": "port", "value": 1},
            {"name": "useSsl", "value": False},
            {"name": "urlBase", "value": ""},
            {"name": "username", "value": "stale-user"},
            {"name": "password", "value": "stale-pass"},
            {"name": category_field, "value": "stale-cat"},
        ],
    })
    result = run_shell(
        container,
        f"curl -sf -X POST -H 'Content-Type: application/json' -H 'X-Api-Key: {api_key}' "
        f"-d '{payload}' {url}/api/v3/downloadclient",
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_configure_downloadclients_refreshes_existing_client(running_container, api_key):
    """A stale host/credentials/category stored in an existing autoconf entry
    is overwritten by the next configure-downloadclients run. The API masks
    the password field in responses, so the refreshed value is asserted on the
    update request itself (a curl wrapper logs what the script sends)."""
    wait_for_arr(running_container, RADARR, api_key)
    wait_for_arr(running_container, SONARR, api_key)
    create_stale_client(running_container, RADARR, api_key, "movieCategory")
    create_stale_client(running_container, SONARR, api_key, "tvCategory")
    assert client_fields(stored_client(running_container, RADARR, api_key))["host"] == "stale-host"

    exports = "\n".join(f"export {name}={value}" for name, value in TORRENT.items())
    run = run_shell(
        running_container,
        f'''set -e
{exports}
mkdir -p /tmp/curllog
cat > /tmp/curllog/curl <<'WRAP'
#!/bin/sh
url=""; body=""; prev=""
for arg in "$@"; do
    case "$arg" in http*) url=$arg ;; esac
    if [ "$prev" = "-d" ] || [ "$prev" = "--data-binary" ]; then body=$arg; fi
    prev=$arg
done
printf '%s\t%s\n' "$url" "$body" >> /tmp/curllog/requests.log
exec /usr/bin/curl "$@"
WRAP
chmod +x /tmp/curllog/curl
PATH=/tmp/curllog:$PATH /usr/local/bin/configure-downloadclients.sh
''',
    )
    assert run.returncode == 0, run.stdout + run.stderr

    # What the script sent: both refreshes carry the environment's values.
    log = run_shell(running_container, "cat /tmp/curllog/requests.log").stdout
    updates = []
    for line in log.splitlines():
        url, _, body = line.partition("\t")
        if "forceSave=true" in url and body:
            updates.append(json.loads(body))
    assert len(updates) == 2

    def update_field(update, name):
        return next(field.get("value") for field in update["fields"] if field["name"] == name)

    radarr_update = next(u for u in updates if any(f["name"] == "movieCategory" for f in u["fields"]))
    sonarr_update = next(u for u in updates if any(f["name"] == "tvCategory" for f in u["fields"]))
    for update, category_field, category in (
        (radarr_update, "movieCategory", "movies-cat"),
        (sonarr_update, "tvCategory", "tv-cat"),
    ):
        assert update_field(update, "host") == "torrentbox"
        assert update_field(update, "port") == 9999
        assert update_field(update, "useSsl") is True
        assert update_field(update, "username") == "torrentuser"
        assert update_field(update, "password") == "torrentpass"
        assert update_field(update, category_field) == category

    # And what Radarr/Sonarr now store (password comes back masked).
    for url, category_field, category in (
        (RADARR, "movieCategory", "movies-cat"),
        (SONARR, "tvCategory", "tv-cat"),
    ):
        fields = client_fields(stored_client(running_container, url, api_key))
        assert fields["host"] == "torrentbox"
        assert fields["port"] == 9999
        assert fields["useSsl"] is True
        assert fields["username"] == "torrentuser"
        assert fields[category_field] == category
        assert fields["password"] == "********"
