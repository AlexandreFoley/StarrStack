#!/bin/bash
# Test a locally-built StarrStack image.
# Usage: test-image.sh <container-name> <image-tag>
set -euo pipefail

CONTAINER="$1"
IMAGE="$2"

# Default API key for testing (from compose.yaml)
API_KEY="ccf889af356d47bebd03fc30f79b1127"

# Detect container runtime (docker or podman)
if command -v docker &> /dev/null; then
  CONTAINER_RUNTIME="docker"
elif command -v podman &> /dev/null; then
  CONTAINER_RUNTIME="podman"
else
  echo "Error: Neither docker nor podman found"
  exit 1
fi

cleanup() {
  echo "--- ${CONTAINER_RUNTIME} ps -a ---"
  ${CONTAINER_RUNTIME} ps -a | head -20 || true
  echo "--- ${CONTAINER_RUNTIME} logs (${CONTAINER}) ---"
  ${CONTAINER_RUNTIME} logs "${CONTAINER}" 2>&1 | head -200 || true
  ${CONTAINER_RUNTIME} rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Use home directory for test mounts on macOS (podman runs in a machine VM)
# /tmp is not shared between host and podman machine on macOS
TEST_BASE_DIR="/tmp/starr-test"
if [ "$(uname)" = "Darwin" ]; then
  echo "MacOS detected, working in $HOME/.starr-test"
  TEST_BASE_DIR="$HOME/.starr-test"
fi

mkdir -p "${TEST_BASE_DIR}/config-${CONTAINER}" "${TEST_BASE_DIR}/media-${CONTAINER}"

# NOTE: do NOT use --rm in detached mode; we want logs available if it crashes early.
${CONTAINER_RUNTIME} run -d --name "${CONTAINER}" \
  -p 7878:7878 \
  -p 8989:8989 \
  -p 9696:9696 \
  -e RADARR__AUTH__APIKEY="${API_KEY}" \
  -e RADARR__SERVER__PORT="7878" \
  -e SONARR__AUTH__APIKEY="${API_KEY}" \
  -e SONARR__SERVER__PORT="8989" \
  -e PROWLARR__AUTH__APIKEY="${API_KEY}" \
  -e PROWLARR__SERVER__PORT="9696" \
  -v "${TEST_BASE_DIR}/config-${CONTAINER}:/config" \
  -v "${TEST_BASE_DIR}/media-${CONTAINER}:/media" \
  "${IMAGE}"

# Fail fast if container is not running immediately after start
if ! ${CONTAINER_RUNTIME} ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  echo "Container '${CONTAINER}' is not running right after start."
  exit 1
fi

echo "Waiting for services to start..."
for i in $(seq 1 12); do
  sleep 10
  echo "  ($((i * 10))s elapsed)"

  # Fail fast if the container exited during startup
  if ! ${CONTAINER_RUNTIME} ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "Container '${CONTAINER}' exited during startup."
    exit 1
  fi

  if curl -fsS "http://localhost:7878/api/v3/system/status?apikey=${API_KEY}" >/dev/null && \
     curl -fsS "http://localhost:8989/api/v3/system/status?apikey=${API_KEY}" >/dev/null && \
     curl -fsS "http://localhost:9696/api/v1/system/status?apikey=${API_KEY}" >/dev/null; then
    echo "All services ready after $((i * 10)) seconds"
    break
  fi

  if [ "$i" -eq 12 ]; then
    echo "Services did not start within 120 seconds"
    exit 1
  fi
done

echo "Testing Radarr..."
curl -fsS "http://localhost:7878/api/v3/system/status?apikey=${API_KEY}" >/dev/null \
  && echo "✓ Radarr responding" || { echo "✗ Radarr not responding"; exit 1; }

echo "Testing Sonarr..."
curl -fsS "http://localhost:8989/api/v3/system/status?apikey=${API_KEY}" >/dev/null \
  && echo "✓ Sonarr responding" || { echo "✗ Sonarr not responding"; exit 1; }

echo "Testing Prowlarr..."
curl -fsS "http://localhost:9696/api/v1/system/status?apikey=${API_KEY}" >/dev/null \
  && echo "✓ Prowlarr responding" || { echo "✗ Prowlarr not responding"; exit 1; }

echo "✓ All services responding"
