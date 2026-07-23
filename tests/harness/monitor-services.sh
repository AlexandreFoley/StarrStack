#!/bin/bash
# Monitor critical services and exit container on failure
# This script runs as a systemd service so it has access to systemd/journal operations

set +e  # Don't exit on error, we'll handle it

# Wait for services to be attempted to start
sleep 5

# Check for service failures
for service in qbittorrent.service starr.service; do
    state=$(systemctl show -p ActiveState --value "$service" 2>/dev/null)
    
    if [ "$state" = "failed" ]; then
        echo "========================================"
        echo "ERROR: Service $service has failed"
        echo "========================================"
        
        echo ""
        echo "--- Last 100 lines from $service journal ---"
        journalctl -u "$service" -n 100 --no-pager || true
        
        echo ""
        echo "--- Service status ---"
        systemctl status "$service" --no-pager || true
        
        echo ""
        echo "--- Full system journal (last 50 lines) ---"
        journalctl -n 50 --no-pager || true
        
        # Exit to signal failure
        exit 1
    fi
done

# If we get here, services are running
exit 0
