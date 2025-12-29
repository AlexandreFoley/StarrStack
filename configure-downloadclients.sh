#!/bin/bash
# Configure download clients for Radarr and Sonarr
# This script should be run after all services are up and running

set -e

# Configuration - Arr apps
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
SONARR_URL="${SONARR_URL:-http://localhost:8989}"

RADARR_API_KEY="${RADARR__AUTH__APIKEY:-c59b53c7cb39521ead0c0dbc1a61a401}"
SONARR_API_KEY="${SONARR__AUTH__APIKEY:-c59b53c7cb39521ead0c0dbc1a61a401}"

# Download client configuration from environment variables
TORRENT_CLIENT="${TORRENT_CLIENT:-qbittorrent}"  # qbittorrent, transmission, deluge
TORRENT_HOST="${TORRENT_HOST:-localhost}"
TORRENT_PORT="${TORRENT_PORT:-8080}"
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

# Function to get download client config for qBittorrent
get_qbittorrent_config() {
    local category=$1
    cat <<EOF
{
    "enable": true,
    "protocol": "torrent",
    "priority": 1,
    "name": "qBittorrent",
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
            "value": ""
        },
        {
            "name": "username",
            "value": "${TORRENT_USERNAME}"
        },
        {
            "name": "password",
            "value": "${TORRENT_PASSWORD}"
        },
        {
            "name": "movieCategory",
            "value": "${category}"
        },
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
    ],
    "implementationName": "qBittorrent",
    "implementation": "QBittorrent",
    "configContract": "QBittorrentSettings",
    "tags": []
}
EOF
}

# Function to get download client config for Transmission
get_transmission_config() {
    local category=$1
    cat <<EOF
{
    "enable": true,
    "protocol": "torrent",
    "priority": 1,
    "name": "Transmission",
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
            "value": "/transmission/"
        },
        {
            "name": "username",
            "value": "${TORRENT_USERNAME}"
        },
        {
            "name": "password",
            "value": "${TORRENT_PASSWORD}"
        },
        {
            "name": "movieCategory",
            "value": "${category}"
        },
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
    ],
    "implementationName": "Transmission",
    "implementation": "Transmission",
    "configContract": "TransmissionSettings",
    "tags": []
}
EOF
}

# Function to get download client config for Deluge
get_deluge_config() {
    local category=$1
    cat <<EOF
{
    "enable": true,
    "protocol": "torrent",
    "priority": 1,
    "name": "Deluge",
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
            "value": ""
        },
        {
            "name": "password",
            "value": "${TORRENT_PASSWORD}"
        },
        {
            "name": "movieCategory",
            "value": "${category}"
        },
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
    ],
    "implementationName": "Deluge",
    "implementation": "Deluge",
    "configContract": "DelugeSettings",
    "tags": []
}
EOF
}

# Function to add download client to Radarr
add_downloadclient_to_radarr() {
    echo -n "Adding ${TORRENT_CLIENT} to Radarr..."
    
    # Check if download client already exists
    existing=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/downloadclient" | \
               jq -r ".[] | select(.implementation == \"${TORRENT_CLIENT^}\") | .id")
    
    if [ -n "$existing" ]; then
        echo -e " ${YELLOW}Already configured (ID: $existing)${NC}"
        return 0
    fi
    
    # Get config based on client type
    case "${TORRENT_CLIENT,,}" in
        qbittorrent)
            config=$(get_qbittorrent_config "$TORRENT_CATEGORY_MOVIES")
            ;;
        transmission)
            config=$(get_transmission_config "$TORRENT_CATEGORY_MOVIES")
            ;;
        deluge)
            config=$(get_deluge_config "$TORRENT_CATEGORY_MOVIES")
            ;;
        *)
            echo -e " ${RED}✗${NC}"
            echo -e "${RED}Unsupported torrent client: $TORRENT_CLIENT${NC}"
            return 1
            ;;
    esac
    
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
    echo -n "Adding ${TORRENT_CLIENT} to Sonarr..."
    
    # Check if download client already exists
    existing=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/downloadclient" | \
               jq -r ".[] | select(.implementation == \"${TORRENT_CLIENT^}\") | .id")
    
    if [ -n "$existing" ]; then
        echo -e " ${YELLOW}Already configured (ID: $existing)${NC}"
        return 0
    fi
    
    # Get config based on client type
    case "${TORRENT_CLIENT,,}" in
        qbittorrent)
            config=$(get_qbittorrent_config "$TORRENT_CATEGORY_TV")
            ;;
        transmission)
            config=$(get_transmission_config "$TORRENT_CATEGORY_TV")
            ;;
        deluge)
            config=$(get_deluge_config "$TORRENT_CATEGORY_TV")
            ;;
        *)
            echo -e " ${RED}✗${NC}"
            echo -e "${RED}Unsupported torrent client: $TORRENT_CLIENT${NC}"
            return 1
            ;;
    esac
    
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
