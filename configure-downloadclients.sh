#!/bin/bash
# Configure download clients for Radarr and Sonarr
# This script should be run after all services are up and running

set -e

# Validate required environment variables for arr apps
if [ -z "$RADARR__SERVER__PORT" ] || [ -z "$SONARR__SERVER__PORT" ] || \
   [ -z "$RADARR__AUTH__APIKEY" ] || [ -z "$SONARR__AUTH__APIKEY" ]; then
    echo -e "${RED}Error: Missing required arr environment variables${NC}"
    echo "Required variables:"
    echo "  RADARR__SERVER__PORT (current: ${RADARR__SERVER__PORT:-NOT SET})"
    echo "  RADARR__AUTH__APIKEY (current: ${RADARR__AUTH__APIKEY:-NOT SET})"
    echo "  SONARR__SERVER__PORT (current: ${SONARR__SERVER__PORT:-NOT SET})"
    echo "  SONARR__AUTH__APIKEY (current: ${SONARR__AUTH__APIKEY:-NOT SET})"
    echo "Optional variables:"
    echo "  RADARR__SERVER__URLBASE, SONARR__SERVER__URLBASE"
    exit 1
fi

# Configuration - construct URLs from standard arr environment variables
RADARR_PORT="${RADARR__SERVER__PORT}"
RADARR_URLBASE="${RADARR__SERVER__URLBASE}"
RADARR_URL="http://localhost:${RADARR_PORT}${RADARR_URLBASE}"

SONARR_PORT="${SONARR__SERVER__PORT}"
SONARR_URLBASE="${SONARR__SERVER__URLBASE}"
SONARR_URL="http://localhost:${SONARR_PORT}${SONARR_URLBASE}"

RADARR_API_KEY="${RADARR__AUTH__APIKEY}"
SONARR_API_KEY="${SONARR__AUTH__APIKEY}"

# Download client configuration from environment variables
TORRENT_CLIENT="${TORRENT_CLIENT}"
TORRENT_HOST="${TORRENT_HOST}"
TORRENT_PORT="${TORRENT_PORT}"
TORRENT_USERNAME="${TORRENT_USERNAME}"
TORRENT_PASSWORD="${TORRENT_PASSWORD}"
TORRENT_CATEGORY_MOVIES="${TORRENT_CATEGORY_MOVIES:-radarr}"
TORRENT_CATEGORY_TV="${TORRENT_CATEGORY_TV:-sonarr}"
TORRENT_USE_SSL="${TORRENT_USE_SSL:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color


# Exit early if no torrent client configuration is provided
if [ -z "$TORRENT_CLIENT" ] || [ -z "$TORRENT_HOST" ] || [ -z "$TORRENT_PORT" ]; then
    echo "No torrent client configuration detected. Skipping download client setup."
    echo "To configure download clients, set: TORRENT_CLIENT, TORRENT_HOST, and TORRENT_PORT"
    echo "Additionally, TORRENT_USERNAME and TORRENT_PASSWORD are required for qBittorrent and Transmission"
    exit 0
fi

echo "==========================================="
echo "  Download Client Configuration Script"
echo "==========================================="
echo ""

# Function to wait for a service to be ready
wait_for_service() {
    local service_name=$1
    local url=$2
    local api_key=$3
    local max_attempts=30
    local attempt=0

    echo -n "Waiting for $service_name to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f -H "X-Api-Key: $api_key" "$url/api/v3/system/status" > /dev/null 2>&1; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    echo -e " ${RED}✗${NC}"
    echo -e "${RED}Error: $service_name did not become ready in time${NC}"
    return 1
}

# Function to get download client config
get_client_config() {
    local client_type=$1
    local category=$2
    local client_name="${client_type^}"
    
    # Client-specific configurations
    local url_base=""
    local extra_fields=""
    
    case "${client_type,,}" in
        qbittorrent)
            extra_fields=$(cat <<'EXTRA'
        {
            "name": "recentMoviePriority",
            "value": 0
        },
        {
            "name": "olderMoviePriority",
            "value": 0
        },
        {
            "name": "initialState",
            "value": 0
        },
        {
            "name": "sequentialOrder",
            "value": false
        },
        {
            "name": "firstAndLast",
            "value": false
        }
EXTRA
)
            ;;
        transmission)
            url_base="/transmission/"
            extra_fields=$(cat <<'EXTRA'
        {
            "name": "recentMoviePriority",
            "value": 0
        },
        {
            "name": "olderMoviePriority",
            "value": 0
        },
        {
            "name": "addPaused",
            "value": false
        }
EXTRA
)
            ;;
        deluge)
            extra_fields=$(cat <<'EXTRA'
        {
            "name": "recentMoviePriority",
            "value": 0
        },
        {
            "name": "olderMoviePriority",
            "value": 0
        },
        {
            "name": "addPaused",
            "value": false
        }
EXTRA
)
            ;;
    esac
    
    # Common fields
    cat <<EOF
{
    "enable": true,
    "protocol": "torrent",
    "priority": 1,
    "name": "${client_name}-autoconf",
    "fields": [
        {
            "name": "host",
            "value": "${TORRENT_HOST}"
        },
        {
            "name": "port",
            "value": ${TORRENT_PORT}
        },
        {
            "name": "useSsl",
            "value": ${TORRENT_USE_SSL}
        },
        {
            "name": "urlBase",
            "value": "${url_base}"
        },
EOF

    # Add username field only for qBittorrent and Transmission
    if [[ "${client_type,,}" != "deluge" ]]; then
        cat <<EOF
        {
            "name": "username",
            "value": "${TORRENT_USERNAME}"
        },
EOF
    fi

    # Password and category fields
    cat <<EOF
        {
            "name": "password",
            "value": "${TORRENT_PASSWORD}"
        },
        {
            "name": "movieCategory",
            "value": "${category}"
        },
${extra_fields}
    ],
    "implementationName": "${client_name}",
    "implementation": "${client_name}",
    "configContract": "${client_name}Settings",
    "tags": []
}
EOF
}

# Function to add download client to Radarr
add_downloadclient_to_radarr() {
    local client_name="${TORRENT_CLIENT^}-autoconf"
    echo -n "Adding ${client_name} to Radarr..."
    
    # Check if download client already exists by name
    existing=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/downloadclient" | \
               jq -r ".[] | select(.name == \"${client_name}\") | .id")
    
    if [ -n "$existing" ]; then
        echo -e " ${YELLOW}Already configured (ID: $existing)${NC}"
        return 0
    fi
    
    # Get config
    config=$(get_client_config "${TORRENT_CLIENT,,}" "$TORRENT_CATEGORY_MOVIES")
    
    # Add download client
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $RADARR_API_KEY" \
        -d "$config" \
        "$RADARR_URL/api/v3/downloadclient")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        return 0
    else
        echo -e " ${RED}✗${NC}"
        echo -e "${RED}Error response: $response${NC}"
        return 1
    fi
}

# Function to add download client to Sonarr
add_downloadclient_to_sonarr() {
    local client_name="${TORRENT_CLIENT^}-autoconf"
    echo -n "Adding ${client_name} to Sonarr..."
    
    # Check if download client already exists by name
    existing=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/downloadclient" | \
               jq -r ".[] | select(.name == \"${client_name}\") | .id")
    
    if [ -n "$existing" ]; then
        echo -e " ${YELLOW}Already configured (ID: $existing)${NC}"
        return 0
    fi
    
    # Get config
    config=$(get_client_config "${TORRENT_CLIENT,,}" "$TORRENT_CATEGORY_TV")
    
    # Add download client
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -d "$config" \
        "$SONARR_URL/api/v3/downloadclient")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        return 0
    else
        echo -e " ${RED}✗${NC}"
        echo -e "${RED}Error response: $response${NC}"
        return 1
    fi
}

# Main execution
echo "Configuration:"
echo "  Radarr:          $RADARR_URL"
echo "  Sonarr:          $SONARR_URL"
echo "  Client Type:     $TORRENT_CLIENT"
echo "  Client Host:     $TORRENT_HOST:$TORRENT_PORT"
echo "  Movie Category:  $TORRENT_CATEGORY_MOVIES"
echo "  TV Category:     $TORRENT_CATEGORY_TV"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "Install it with: dnf install jq (RHEL/Fedora) or apt install jq (Debian/Ubuntu)"
    exit 1
fi

# Wait for services to be ready
wait_for_service "Radarr" "$RADARR_URL" "$RADARR_API_KEY" || exit 1
wait_for_service "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" || exit 1

echo ""
echo "Configuring download clients..."

# Add download clients
add_downloadclient_to_radarr || exit 1
add_downloadclient_to_sonarr || exit 1

echo ""
echo -e "${GREEN}==========================================="
echo -e "  Configuration completed successfully!"
echo -e "===========================================${NC}"
echo ""
echo "Download clients have been configured for both Radarr and Sonarr."
echo ""
