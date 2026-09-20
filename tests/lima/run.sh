#!/usr/bin/env bash
set -Eeuo pipefail

VM="${LIMA_VM:-starr-openrc}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="localhost/starr-openrc:lima"
CONTAINER="starr-openrc-lima"
RESULTS="$ROOT/tests/lima/results"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing required command: $1"; }
lima() { limactl shell "$VM" "$@"; }

unpackerr_version() {
    if [ -n "${UNPACKERR_VERSION:-}" ]; then
        printf '%s\n' "$UNPACKERR_VERSION"
        return
    fi
    curl -fsSL https://api.github.com/repos/Unpackerr/unpackerr/releases/latest |
        sed -nE 's/.*"tag_name": "v([^"]+)".*/\1/p' |
        sed -n '1p'
}

vm_exists() {
    limactl list --format '{{.Name}}' 2>/dev/null | grep -Fxq "$VM"
}

start_vm() {
    if ! vm_exists; then
        limactl create --tty=false --name "$VM" --mount "$ROOT:w" template:docker
    fi
    limactl start "$VM"
    for _ in {1..30}; do
        lima docker info >/dev/null 2>&1 && return
        sleep 2
    done
    die "Docker did not become ready in Lima VM '$VM'"
}

capture() {
    local name="$1"
    shift
    "$@" >"$RESULTS/$name" 2>&1 || true
}

collect() {
    mkdir -p "$RESULTS"
    capture docker-info.txt lima docker info
    capture docker-version.txt lima docker version
    capture vm-cgroup.txt lima sh -c \
        'printf "%s\n" "== /proc/cgroups =="; cat /proc/cgroups; printf "%s\n" "== /proc/self/cgroup =="; cat /proc/self/cgroup; printf "%s\n" "== cgroup mounts =="; grep cgroup /proc/mounts || true'
    capture container-inspect.txt lima docker inspect "$CONTAINER"
    capture container-cgroup.txt lima docker exec "$CONTAINER" sh -c \
        'printf "%s\n" "== /proc/1/cgroup =="; cat /proc/1/cgroup; printf "%s\n" "== /proc/self/cgroup =="; cat /proc/self/cgroup; printf "%s\n" "== cgroup mounts =="; grep cgroup /proc/mounts || true; printf "%s\n" "== rc-status =="; rc-status --all || true'
    capture container-mounts.txt lima docker exec "$CONTAINER" sh -c \
        'mount; printf "%s\n" "== openrc =="; ps -ef || true'
    capture container-logs.txt lima docker logs "$CONTAINER"
    echo "Diagnostics written to $RESULTS"
}

assert_running() {
    local state
    state="$(lima docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
    [ "$state" = running ] || {
        collect
        die "container '$CONTAINER' stopped (state: ${state:-missing}); see $RESULTS"
    }
}

up() {
    start_vm
    local unpackerr
    unpackerr="$(unpackerr_version)"
    [ -n "$unpackerr" ] || die "could not determine the Unpackerr release"
    lima docker build --build-arg "UNPACKERR_VERSION=$unpackerr" \
        -f "$ROOT/alpine.dockerfile" -t "$IMAGE" "$ROOT"
    lima docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    lima docker volume create starr-openrc-config >/dev/null
    lima docker volume create starr-openrc-media >/dev/null
    lima docker run -d --name "$CONTAINER" --restart=no \
        -p 7878:7878 -p 8989:8989 -p 9696:9696 \
        --tmpfs /run \
        -v starr-openrc-config:/config -v starr-openrc-media:/media \
        -e RADARR__AUTH__ENABLED=false \
        -e SONARR__AUTH__ENABLED=false \
        -e PROWLARR__AUTH__ENABLED=false \
        "$IMAGE" >/dev/null
    sleep "${LIMA_SETTLE_SECONDS:-90}"
    collect
    assert_running
}

down() {
    vm_exists || return 0
    collect
    lima docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    limactl stop "$VM" >/dev/null
}

reset() {
    if vm_exists; then
        limactl delete --force "$VM"
    fi
    rm -rf "$RESULTS"
}

need limactl
need curl
case "${1:-}" in
    up) up ;;
    collect) vm_exists || die "Lima VM '$VM' does not exist"; collect ;;
    down) down ;;
    reset) reset ;;
    *) echo "usage: $0 {up|collect|down|reset}" >&2; exit 2 ;;
esac
