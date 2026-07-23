#!/bin/bash
# Entrypoint for test harness container.
# Starts systemd as PID 1 for proper systemd/journalctl operation.
# Service monitoring is handled by systemd service units.

# Create mount point directories for quadlet files
mkdir -p /etc/containers/systemd/mounts/qbittorrent-config
mkdir -p /etc/containers/systemd/mounts/config
mkdir -p /etc/containers/systemd/mounts/media

# Change ownership to the testuser (who runs podman as rootless)
# This is needed because quadlet will try to access these directories
chown -R 1000:1000 /etc/containers/systemd/mounts/

# Source test configuration
set -a
source /harness/test_api_key
set +a

# Create podman secrets with test values
# These are required by the quadlet container files
echo "testpass" | podman secret create webui_password - || true
echo "$API_KEY" | podman secret create sonarr_apikey - || true
echo "$API_KEY" | podman secret create radarr_apikey - || true
echo "$API_KEY" | podman secret create prowlarr_apikey - || true

# Start systemd as PID 1
# This allows journalctl and systemd operations to work properly
exec /sbin/init
