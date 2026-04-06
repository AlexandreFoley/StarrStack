#!/usr/bin/env bash
# Bridge a Docker-stored image into the Podman image store.
# Usage: docker-to-podman.sh <image:tag>
set -euo pipefail

IMAGE="${1:?Usage: $0 <image:tag>}"

docker image inspect "$IMAGE" >/dev/null
docker save "$IMAGE" | podman load
podman image exists "$IMAGE"
