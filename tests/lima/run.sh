#!/usr/bin/env bash
set -Eeuo pipefail

VM="${LIMA_VM:-starr-openrc}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="localhost/starr-openrc:lima"
CONTAINER="starr-openrc-lima"
RESULTS="$ROOT/tests/lima/results"
RUNTIME="${REPRODUCER_RUNTIME:-lima}"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing required command: $1"; }
lima() { limactl shell "$VM" "$@"; }

rdocker() {
    if [ "$RUNTIME" = docker ]; then
        docker "$@"
    else
        lima docker "$@"
    fi
}

rvm_sh() {
    if [ "$RUNTIME" = docker ]; then
        sh -c "$1"
    else
        lima sh -c "$1"
    fi
}

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
    if [ "$RUNTIME" = docker ]; then
        rdocker info >/dev/null 2>&1 || die "Docker is not available"
        return
    fi
    if ! vm_exists; then
        limactl create --tty=false --name "$VM" --mount "$ROOT:w" template:docker
    fi
    limactl start "$VM"
    for _ in {1..30}; do
        rdocker info >/dev/null 2>&1 && return
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
    capture docker-info.txt rdocker info
    capture docker-version.txt rdocker version
    capture vm-cgroup.txt rvm_sh \
        'printf "%s\n" "== /proc/cgroups =="; cat /proc/cgroups; printf "%s\n" "== /proc/self/cgroup =="; cat /proc/self/cgroup; printf "%s\n" "== cgroup mounts =="; grep cgroup /proc/mounts || true'
    capture container-inspect.txt rdocker inspect "$CONTAINER"
    capture container-cgroup.txt rdocker exec "$CONTAINER" sh -c \
        'printf "%s\n" "== /proc/1/cgroup =="; cat /proc/1/cgroup; printf "%s\n" "== /proc/self/cgroup =="; cat /proc/self/cgroup; printf "%s\n" "== cgroup mounts =="; grep cgroup /proc/mounts || true; printf "%s\n" "== rc-status =="; rc-status --all || true'
    capture container-mounts.txt rdocker exec "$CONTAINER" sh -c \
        'mount; printf "%s\n" "== openrc =="; ps -ef || true'
    capture container-logs.txt rdocker logs "$CONTAINER"
    echo "Diagnostics written to $RESULTS"
}

assert_running() {
    local state
    state="$(rdocker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
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
    rdocker build --build-arg "UNPACKERR_VERSION=$unpackerr" \
        -f "$ROOT/alpine.dockerfile" -t "$IMAGE" "$ROOT"
    rdocker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rdocker volume create starr-openrc-config >/dev/null
    rdocker volume create starr-openrc-media >/dev/null
    rdocker run -d --name "$CONTAINER" --restart=no \
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
    if [ "$RUNTIME" = docker ]; then
        collect
        rdocker rm -f "$CONTAINER" >/dev/null 2>&1 || true
        return 0
    fi
    vm_exists || return 0
    collect
    rdocker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    limactl stop "$VM" >/dev/null
}

reset() {
    if [ "$RUNTIME" = docker ]; then
        rdocker rm -f "$CONTAINER" >/dev/null 2>&1 || true
        rdocker volume rm starr-openrc-config starr-openrc-media >/dev/null 2>&1 || true
    elif vm_exists; then
        limactl delete --force "$VM"
    fi
    rm -rf "$RESULTS"
}

if [ "$RUNTIME" = docker ]; then
    need docker
else
    need limactl
fi
need curl
case "${1:-}" in
    up) up ;;
    collect)
        if [ "$RUNTIME" != docker ]; then
            vm_exists || die "Lima VM '$VM' does not exist"
        fi
        collect ;;
    down) down ;;
    reset) reset ;;
    *) echo "usage: $0 {up|collect|down|reset}" >&2; exit 2 ;;
esac
