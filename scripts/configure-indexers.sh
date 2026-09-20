#!/bin/bash
# Configure Radarr and Sonarr to use Prowlarr as indexer provider
# This script should be run after all services are up and running

set -e

# Configuration - construct URLs from standard arr environment variables
RADARR_PORT="${RADARR__SERVER__PORT:-7878}"
RADARR_URLBASE="${RADARR__SERVER__URLBASE}"
RADARR_URL="http://localhost:${RADARR_PORT}${RADARR_URLBASE}"

SONARR_PORT="${SONARR__SERVER__PORT:-8989}"
SONARR_URLBASE="${SONARR__SERVER__URLBASE}"
SONARR_URL="http://localhost:${SONARR_PORT}${SONARR_URLBASE}"

PROWLARR_PORT="${PROWLARR__SERVER__PORT:-9696}"
PROWLARR_URLBASE="${PROWLARR__SERVER__URLBASE}"
PROWLARR_URL="http://localhost:${PROWLARR_PORT}${PROWLARR_URLBASE}"

RADARR_API_KEY="${RADARR__AUTH__APIKEY}"
SONARR_API_KEY="${SONARR__AUTH__APIKEY}"
PROWLARR_API_KEY="${PROWLARR__AUTH__APIKEY}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate required environment variables
if [ -z "$RADARR__SERVER__PORT" ] || [ -z "$SONARR__SERVER__PORT" ] || [ -z "$PROWLARR__SERVER__PORT" ] || \
   [ -z "$RADARR__AUTH__APIKEY" ] || [ -z "$SONARR__AUTH__APIKEY" ] || [ -z "$PROWLARR__AUTH__APIKEY" ]; then
    echo -e "${RED}Error: Missing required environment variables${NC}"
    echo "Required variables:"
    echo "  RADARR__SERVER__PORT (current: ${RADARR__SERVER__PORT:-NOT SET})"
    echo "  RADARR__AUTH__APIKEY (current: ${RADARR__AUTH__APIKEY:-NOT SET})"
    echo "  SONARR__SERVER__PORT (current: ${SONARR__SERVER__PORT:-NOT SET})"
    echo "  SONARR__AUTH__APIKEY (current: ${SONARR__AUTH__APIKEY:-NOT SET})"
    echo "  PROWLARR__SERVER__PORT (current: ${PROWLARR__SERVER__PORT:-NOT SET})"
    echo "  PROWLARR__AUTH__APIKEY (current: ${PROWLARR__AUTH__APIKEY:-NOT SET})"
    echo "Optional variables:"
    echo "  RADARR__SERVER__URLBASE, SONARR__SERVER__URLBASE, PROWLARR__SERVER__URLBASE"
    exit 1
fi

echo "==========================================="
echo "  Prowlarr Indexer Configuration Script"
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
        if curl -s -f -H "X-Api-Key: $api_key" "$url/api/v3/system/status" > /dev/null 2>&1 || \
           curl -s -f -H "X-Api-Key: $api_key" "$url/api/v1/system/status" > /dev/null 2>&1; then
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

# Function to add an arr application in Prowlarr, or refresh it when it
# already exists. The "<App>-autoconf" entry is owned by this container: the
# API keys are supplied externally, so a rotated key (or a changed URL base)
# must not leave Prowlarr talking to the app with stale credentials. The
# connection fields are overwritten on every startup; the rest of the entry
# (tags, sync level, ...) is preserved.
add_app_to_prowlarr() {
    local app_name=$1
    local app_url=$2
    local app_api_key=$3
    local implementation=$4
    local sync_categories=$5
    local autoconf_name="${app_name}-autoconf"
    local existing existing_id payload method endpoint response

    existing=$(curl -s -H "X-Api-Key: $PROWLARR_API_KEY" "$PROWLARR_URL/api/v1/applications" | \
               jq -c "first(.[] | select(.name == \"${autoconf_name}\")) // empty")

    if [ -n "$existing" ]; then
        existing_id=$(printf '%s' "$existing" | jq -r '.id')
        echo -n "Refreshing ${autoconf_name} in Prowlarr..."
        # Round-trip the resource Prowlarr returned and overwrite only the
        # fields this container owns, so user-set values survive.
        payload=$(printf '%s' "$existing" | jq -c \
            --arg url "$app_url" --arg key "$app_api_key" \
            '.fields |= map(if .name == "baseUrl" then .value = $url
                            elif .name == "apiKey" then .value = $key
                            else . end)')
        method=PUT
        endpoint="${PROWLARR_URL}/api/v1/applications/${existing_id}"
    else
        echo -n "Adding ${autoconf_name} to Prowlarr..."
        payload=$(jq -c -n \
            --arg name "$autoconf_name" \
            --arg implementation "$implementation" \
            --arg url "$app_url" \
            --arg key "$app_api_key" \
            --argjson sync_categories "$sync_categories" \
            '{name: $name, syncLevel: "fullSync", implementation: $implementation,
              configContract: ($implementation + "Settings"), tags: [],
              fields: [{name: "baseUrl", value: $url},
                       {name: "apiKey", value: $key},
                       {name: "syncCategories", value: $sync_categories}]}')
        method=POST
        endpoint="${PROWLARR_URL}/api/v1/applications"
    fi

    response=$(curl -s -X "$method" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -d "$payload" \
        "$endpoint")

    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        return 0
    else
        echo -e " ${RED}✗${NC}"
        echo -e "${RED}Error response: $response${NC}"
        return 1
    fi
}

# Function to trigger sync from Prowlarr
trigger_prowlarr_sync() {
    echo -n "Triggering Prowlarr sync..."
    
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -d '{"name": "ApplicationIndexerSync"}' \
        "$PROWLARR_URL/api/v1/command")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        return 0
    else
        echo -e " ${YELLOW}Sync command sent (may already be running)${NC}"
        return 0
    fi
}

# Main execution
echo "Configuration:"
echo "  Radarr:   $RADARR_URL"
echo "  Sonarr:   $SONARR_URL"
echo "  Prowlarr: $PROWLARR_URL"
echo ""

# Wait for all services to be ready
wait_for_service "Radarr" "$RADARR_URL" "$RADARR_API_KEY" || exit 1
wait_for_service "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" || exit 1
wait_for_service "Prowlarr" "$PROWLARR_URL" "$PROWLARR_API_KEY" || exit 1

echo ""
echo "Configuring indexer providers..."

# Add applications to Prowlarr
add_app_to_prowlarr "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "Radarr" \
    "[2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080]" || exit 1
add_app_to_prowlarr "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "Sonarr" \
    "[5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5070, 5080]" || exit 1

# Trigger sync
echo ""
trigger_prowlarr_sync

echo ""
echo -e "${GREEN}==========================================="
echo -e "  Configuration completed successfully!"
echo -e "===========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Add indexers in Prowlarr (Settings > Indexers)"
echo "  2. Indexers will automatically sync to Radarr and Sonarr"
echo ""
