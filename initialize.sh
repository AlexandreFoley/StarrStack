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

echo "Initializing container..."

# Create directories if they don't exist
mkdir -p /config /media
mkdir -p /config/radarr /config/sonarr /config/prowlarr /config/unpackerr
mkdir -p /etc/systemd/system.d

# /config base - readable only by root
chmod 755 /config
chown root:root /config

# Get actual UIDs/GIDs from the system
RADARR_UID=$(id -u radarr 2>/dev/null || echo 100)
RADARR_GID=$(id -g radarr 2>/dev/null || echo 100)
SONARR_UID=$(id -u sonarr 2>/dev/null || echo 101)
SONARR_GID=$(id -g sonarr 2>/dev/null || echo 101)
PROWLARR_UID=$(id -u prowlarr 2>/dev/null || echo 102)
PROWLARR_GID=$(id -g prowlarr 2>/dev/null || echo 102)
UNPACKERR_UID=$(id -u unpackerr 2>/dev/null || echo 103)
UNPACKERR_GID=$(id -g unpackerr 2>/dev/null || echo 103)

# Function to fix permissions for a service config directory
fix_mount_permissions() {
    local service_name="$1"
    local uid="$2"
    local gid="$3"
    local config_path="/config/$service_name"
    
    chmod 700 "$config_path"
    chown "$uid:$gid" "$config_path"
    find "$config_path" -type d -exec chmod 700 {} \; 2>/dev/null || true
    find "$config_path" -type f -exec chmod 600 {} \; 2>/dev/null || true
}


# Fix each service's config directory
fix_mount_permissions "radarr" "$RADARR_UID" "$RADARR_GID"
fix_mount_permissions "sonarr" "$SONARR_UID" "$SONARR_GID"
fix_mount_permissions "prowlarr" "$PROWLARR_UID" "$PROWLARR_GID"
fix_mount_permissions "unpackerr" "$UNPACKERR_UID" "$UNPACKERR_GID"

# /media - world readable/writable for all services
chmod 777 /media
chown root:root /media
find /media -type d -exec chmod 777 {} \; 2>/dev/null || true
find /media -type f -exec chmod 666 {} \; 2>/dev/null || true

# Create environment file for Unpackerr with dynamic values from arr services
# This allows Unpackerr to use user-supplied API keys and URLs
cat > /etc/systemd/system/unpackerr.service.d/environment.conf <<EOF
[Service]
Environment="UN_RADARR_0_API_KEY=${RADARR__AUTH__APIKEY}"
Environment="UN_RADARR_0_URL=http://127.0.0.1:${RADARR__SERVER__PORT}${RADARR__SERVER__URLBASE}"
Environment="UN_SONARR_0_API_KEY=${SONARR__AUTH__APIKEY}"
Environment="UN_SONARR_0_URL=http://127.0.0.1:${SONARR__SERVER__PORT}${SONARR__SERVER__URLBASE}"
EOF

chmod 644 /etc/systemd/system/unpackerr.service.d/environment.conf

# Reload systemd to pick up the new service configuration
systemctl daemon-reload

echo "Initialization complete:"
echo "  ✓ /config permissions set (service isolation)"
echo "  ✓ /config/radarr (700) - radarr owned"
echo "  ✓ /config/sonarr (700) - sonarr owned"
echo "  ✓ /config/prowlarr (700) - prowlarr owned"
echo "  ✓ /config/unpackerr (700) - unpackerr owned"
echo "  ✓ /media permissions set (777 - world accessible)"
echo "  ✓ Unpackerr environment configured from arr service settings"
echo "  ✓ Environment files created for all services"

