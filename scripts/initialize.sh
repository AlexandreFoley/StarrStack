#!/bin/bash
# Initialize container: fix permissions and create environment files for services
# Services can only access their own config directories

set -e

echo "Initializing container..."

# Validate required environment variables
MISSING_VARS=()

[ -z "$RADARR__AUTH__APIKEY" ] && MISSING_VARS+=("RADARR__AUTH__APIKEY")
[ -z "$RADARR__SERVER__PORT" ] && MISSING_VARS+=("RADARR__SERVER__PORT")
[ -z "$SONARR__AUTH__APIKEY" ] && MISSING_VARS+=("SONARR__AUTH__APIKEY")
[ -z "$SONARR__SERVER__PORT" ] && MISSING_VARS+=("SONARR__SERVER__PORT")
[ -z "$PROWLARR__AUTH__APIKEY" ] && MISSING_VARS+=("PROWLARR__AUTH__APIKEY")
[ -z "$PROWLARR__SERVER__PORT" ] && MISSING_VARS+=("PROWLARR__SERVER__PORT")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "Error: Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "All arr services require the following environment variables:"
    echo "  *__AUTH__APIKEY"
    echo "  *__SERVER__PORT"
    echo "  *__SERVER__URLBASE (optional)"
    exit 1
fi

# Create directories if they don't exist (fresh bind mounts)
mkdir -p /config /media
mkdir -p /config/radarr /config/sonarr /config/prowlarr /config/unpackerr

# Each service owns its config directory; other services are shut out at the
# top dir (700). Unconditional: config trees are small, and this self-heals
# strays (root-owned files from restores or one-off root runs). A failed chown
# warns instead of silently downgrading isolation.
for svc in radarr sonarr prowlarr unpackerr; do
    chown -R "$svc:$svc" "/config/$svc" && chmod 700 "/config/$svc" \
        || echo "Warning: could not set ownership on /config/$svc"
done

# /media is never modified from inside the container. Services share it through
# the host user's group: units run with Group=root, which rootless Podman maps to
# the host user's primary group. Requirement: a group-writable tree (umask 002).
# Probe once as a service user and warn loudly instead of failing the boot.
if runuser -u radarr -g root -- sh -c '[ -r /media ] && [ -w /media ] && [ -x /media ]' 2>/dev/null; then
    echo "  ✓ /media is group-writable (shared via host user's group)"
else
    echo "  *** WARNING: services cannot write to /media."
    echo "  *** The media tree must be group-writable (664/775) by your host group."
    echo "  *** Use UMASK=002 on your download client (the qbittorrent unit already does)."
fi

# Create environment file for Unpackerr with dynamic values from arr services
# This allows Unpackerr to use user-supplied API keys and URLs
cat > /etc/systemd/system/unpackerr.service.d/environment.conf <<EOF
[Service]
Environment="UN_RADARR_0_API_KEY=${RADARR__AUTH__APIKEY}"
Environment="UN_RADARR_0_URL=http://127.0.0.1:${RADARR__SERVER__PORT}${RADARR__SERVER__URLBASE}"
Environment="UN_SONARR_0_API_KEY=${SONARR__AUTH__APIKEY}"
Environment="UN_SONARR_0_URL=http://127.0.0.1:${SONARR__SERVER__PORT}${SONARR__SERVER__URLBASE}"
EOF

# Root-only: contains the Radarr and Sonarr API keys. systemd (PID 1) reads
# drop-ins regardless; services receive the values via their environment.
chmod 600 /etc/systemd/system/unpackerr.service.d/environment.conf

# Reload systemd to pick up the new service configuration
systemctl daemon-reload

echo "Initialization complete:"
echo "  ✓ /config service directories owned per-service (700, isolated)"
echo "  ✓ Unpackerr environment configured from arr service settings"

