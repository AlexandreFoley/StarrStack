#!/bin/bash
# Configure Radarr and Sonarr to use Prowlarr as indexer provider
# This script should be run after all services are up and running

set -e

# Configuration
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
SONARR_URL="${SONARR_URL:-http://localhost:8989}"
PROWLARR_URL="${PROWLARR_URL:-http://localhost:9696}"

RADARR_API_KEY="${RADARR__AUTH__APIKEY:-c59b53c7cb39521ead0c0dbc1a61a401}"
SONARR_API_KEY="${SONARR__AUTH__APIKEY:-c59b53c7cb39521ead0c0dbc1a61a401}"
PROWLARR_API_KEY="${PROWLARR__AUTH__APIKEY:-c59b53c7cb39521ead0c0dbc1a61a401}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Function to add Radarr application in Prowlarr
add_radarr_to_prowlarr() {
    echo -n "Adding Radarr to Prowlarr..."
    
    # Check if Radarr application already exists
    existing=$(curl -s -H "X-Api-Key: $PROWLARR_API_KEY" "$PROWLARR_URL/api/v1/applications" | \
               jq -r '.[] | select(.name == "Radarr") | .id')
    
    if [ -n "$existing" ]; then
        echo -e " ${YELLOW}Already configured (ID: $existing)${NC}"
        return 0
    fi
    
    # Add Radarr application
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -d '{
            "name": "Radarr",
            "syncLevel": "fullSync",
            "implementation": "Radarr",
            "configContract": "RadarrSettings",
            "tags": [],
            "fields": [
                {
                    "name": "baseUrl",
                    "value": "'"$RADARR_URL"'"
                },
                {
                    "name": "apiKey",
                    "value": "'"$RADARR_API_KEY"'"
                },
                {
                    "name": "syncCategories",
                    "value": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080]
                }
            ]
        }' \
        "$PROWLARR_URL/api/v1/applications")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        return 0
    else
        echo -e " ${RED}✗${NC}"
        echo -e "${RED}Error response: $response${NC}"
        return 1
    fi
}

# Function to add Sonarr application in Prowlarr
add_sonarr_to_prowlarr() {
    echo -n "Adding Sonarr to Prowlarr..."
    
    # Check if Sonarr application already exists
    existing=$(curl -s -H "X-Api-Key: $PROWLARR_API_KEY" "$PROWLARR_URL/api/v1/applications" | \
               jq -r '.[] | select(.name == "Sonarr") | .id')
    
    if [ -n "$existing" ]; then
        echo -e " ${YELLOW}Already configured (ID: $existing)${NC}"
        return 0
    fi
    
    # Add Sonarr application
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -d '{
            "name": "Sonarr",
            "syncLevel": "fullSync",
            "implementation": "Sonarr",
            "configContract": "SonarrSettings",
            "tags": [],
            "fields": [
                {
                    "name": "baseUrl",
                    "value": "'"$SONARR_URL"'"
                },
                {
                    "name": "apiKey",
                    "value": "'"$SONARR_API_KEY"'"
                },
                {
                    "name": "syncCategories",
                    "value": [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5070, 5080]
                }
            ]
        }' \
        "$PROWLARR_URL/api/v1/applications")
    
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

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "Install it with: dnf install jq (RHEL/Fedora) or apt install jq (Debian/Ubuntu)"
    exit 1
fi

# Wait for all services to be ready
wait_for_service "Radarr" "$RADARR_URL" "$RADARR_API_KEY" || exit 1
wait_for_service "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" || exit 1
wait_for_service "Prowlarr" "$PROWLARR_URL" "$PROWLARR_API_KEY" || exit 1

echo ""
echo "Configuring indexer providers..."

# Add applications to Prowlarr
add_radarr_to_prowlarr || exit 1
add_sonarr_to_prowlarr || exit 1

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
