#!/bin/bash
# Entrypoint for test harness container.
# Waits for systemd to be ready, then runs the test script if provided.
set -e

# Wait for systemd to finish initialising
while ! systemctl is-system-running --wait 2>/dev/null | grep -q "running\|degraded\|maintenance"; do
    sleep 0.5
done

echo "Systemd ready, processing quadlet files..."

# Generate systemd units from quadlet files
systemctl daemon-reload

# List what quadlet produced
echo "=== Generated units ==="
systemctl list-unit-files --type=service --state=generated 2>/dev/null || true

# If a test command was passed, run it
if [ $# -gt 0 ]; then
    exec "$@"
fi
