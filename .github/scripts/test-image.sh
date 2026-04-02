#!/bin/bash
# Test a locally-built StarrStack image.
# Usage: test-image.sh <container-name> <image-tag>
set -e

CONTAINER="$1"
IMAGE="$2"

mkdir -p "/tmp/test-config-${CONTAINER}" "/tmp/test-media-${CONTAINER}"

docker run --rm -d --name "${CONTAINER}" \
  -p 7878:7878 \
  -p 8989:8989 \
  -p 9696:9696 \
  -v "/tmp/test-config-${CONTAINER}:/config" \
  -v "/tmp/test-media-${CONTAINER}:/media" \
  "${IMAGE}"

echo "Waiting for services to start..."
for i in $(seq 1 12); do
  sleep 10
  echo "  ($((i * 10))s elapsed)"
  if curl -fsS http://localhost:7878/api/v3/system/status >/dev/null 2>&1 && \
     curl -fsS http://localhost:8989/api/v3/system/status >/dev/null 2>&1 && \
     curl -fsS http://localhost:9696/api/v1/system/status >/dev/null 2>&1; then
    echo "All services ready after $((i * 10)) seconds"
    break
  fi
  if [ "$i" -eq 12 ]; then
    echo "Services did not start within 120 seconds"
    docker logs "${CONTAINER}" 2>&1 | head -200 || true
    docker rm -f "${CONTAINER}" || true
    exit 1
  fi
done

echo "Testing Radarr..."
curl -fsS http://localhost:7878/api/v3/system/status >/dev/null && echo "✓ Radarr responding" || {
  echo "✗ Radarr not responding"
  docker logs "${CONTAINER}" 2>&1 | head -200 || true
  docker rm -f "${CONTAINER}" || true
  exit 1
}

echo "Testing Sonarr..."
curl -fsS http://localhost:8989/api/v3/system/status >/dev/null && echo "✓ Sonarr responding" || {
  echo "✗ Sonarr not responding"
  docker logs "${CONTAINER}" 2>&1 | head -200 || true
  docker rm -f "${CONTAINER}" || true
  exit 1
}

echo "Testing Prowlarr..."
curl -fsS http://localhost:9696/api/v1/system/status >/dev/null && echo "✓ Prowlarr responding" || {
  echo "✗ Prowlarr not responding"
  docker logs "${CONTAINER}" 2>&1 | head -200 || true
  docker rm -f "${CONTAINER}" || true
  exit 1
}

echo "Container logs:"
docker logs "${CONTAINER}" 2>&1 | head -200 || true
docker rm -f "${CONTAINER}" || true
