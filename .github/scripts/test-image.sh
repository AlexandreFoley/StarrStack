#!/bin/bash
# Test a locally-built StarrStack image.
# Usage: test-image.sh <container-name> <image-tag>
set -e

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

# Use home directory for test mounts on macOS (podman runs in a machine VM)
# /tmp is not shared between host and podman machine on macOS
TEST_BASE_DIR="/tmp/starr-test"
if [ "$(uname)" = "Darwin" ]; then
  TEST_BASE_DIR="$HOME/.starr-test"
fi

mkdir -p "${TEST_BASE_DIR}/config-${CONTAINER}" "${TEST_BASE_DIR}/media-${CONTAINER}"

${CONTAINER_RUNTIME} run --rm -d --name "${CONTAINER}" \
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

echo "Waiting for services to start..."
for i in $(seq 1 12); do
  sleep 10
  echo "  ($((i * 10))s elapsed)"
  if curl -s http://localhost:7878/api/v3/system/status?apikey=${API_KEY}  2>&1 && \
     curl -s http://localhost:8989/api/v3/system/status?apikey=${API_KEY}  2>&1 && \
     curl -s http://localhost:9696/api/v1/system/status?apikey=${API_KEY}  2>&1; then
    echo "All services ready after $((i * 10)) seconds"
    break
  fi
  if [ "$i" -eq 12 ]; then
    echo "Services did not start within 120 seconds"
    ${CONTAINER_RUNTIME} logs "${CONTAINER}" 2>&1 | head -200 || true
    ${CONTAINER_RUNTIME} rm -f "${CONTAINER}" || true
    exit 1
  fi
done

echo "Testing Radarr..."
curl -s http://localhost:7878/api/v3/system/status?apikey=${API_KEY} && echo "✓ Radarr responding" || {
  echo "✗ Radarr not responding"
  ${CONTAINER_RUNTIME} logs "${CONTAINER}" 2>&1 | head -200 || true
  ${CONTAINER_RUNTIME} rm -f "${CONTAINER}" || true
  exit 1
}

echo "Testing Sonarr..."
curl -s http://localhost:8989/api/v3/system/status?apikey=${API_KEY} && echo "✓ Sonarr responding" || {
  echo "✗ Sonarr not responding"
  ${CONTAINER_RUNTIME} logs "${CONTAINER}" 2>&1 | head -200 || true
  ${CONTAINER_RUNTIME} rm -f "${CONTAINER}" || true
  exit 1
}

echo "Testing Prowlarr..."
curl -s http://localhost:9696/api/v1/system/status?apikey=${API_KEY} && echo "✓ Prowlarr responding" || {
  echo "✗ Prowlarr not responding"
  ${CONTAINER_RUNTIME} logs "${CONTAINER}" 2>&1 | head -200 || true
  ${CONTAINER_RUNTIME} rm -f "${CONTAINER}" || true
  exit 1
}

echo "Container logs:"
${CONTAINER_RUNTIME} logs "${CONTAINER}" 2>&1 | head -200 || true
${CONTAINER_RUNTIME} rm -f "${CONTAINER}" || true
