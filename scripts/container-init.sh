#!/bin/sh
# Container init (PID 1) for the Starr stack image.
#
# Runs the same OpenRC runlevels openrc-init would (sysinit, boot, default),
# but actually EXITS when a required oneshot fails, which stops the container
# (FailureAction=exit parity with the ubi image).
#
# Why not openrc-init itself: openrc-init ends its shutdown path with
# reboot(2), which the kernel denies inside a user-namespace container
# (reboot() requires init-ns CAP_SYS_BOOT), and PID 1 is SIGKILL-immune in
# rootless runtimes - so openrc-init can never terminate a rootless container.
#
# Oneshot scripts (initialize, configure-*) write /run/starr-failed on failure:
# indexing that marker is the only reliable failure signal, since `openrc
# default` exits 0 even when services fail to start.

# --- per-service environment harvest ---
# OpenRC's runlevel runner strips the container environment (env_filter() in
# src/shared/misc.c keeps only a static allowlist + rc_env_allow). On ubi,
# systemd's PassEnvironment scopes vars per unit; here PID 1 is the only
# process with the full container env, so we write each service's variables
# into /etc/conf.d/<service>, which openrc-run sources for that service only.
# Files are root-only: daemons receive the values through their process
# environment, never by reading the files. This replaces rc_env_allow="*"
# (which leaked every env var to every service).

sq() {  # single-quote a value for the conf.d shell source
    case $1 in
        *\'*)
            printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
            ;;
        *) printf "'%s'" "$1" ;;
    esac
}

write_env() {  # dest pattern...
    dest=$1; shift
    file="/etc/conf.d/$dest"
    : > "$file"
    env | while IFS='=' read -r key val; do
        # Only valid shell identifiers may land in the sourced file. The key
        # comes from the container env: a malformed name (e.g. `RADARR__X;rm`)
        # would be written unquoted and executed when openrc-run sources it.
        case $key in
            *[!A-Za-z0-9_]*|''|[0-9]*) continue ;;
        esac
        for pat in "$@"; do
            case $key in
            $pat)
                printf 'export %s=%s\n' "$key" "$(sq "$val")" >> "$file"
                break
                ;;
            esac
        done
    done
    chmod 600 "$file"
}

harvest_env() {
    rm -f /etc/conf.d/radarr /etc/conf.d/sonarr /etc/conf.d/prowlarr \
          /etc/conf.d/unpackerr /etc/conf.d/initialize \
          /etc/conf.d/configure-indexers /etc/conf.d/configure-downloadclients
    write_env radarr 'RADARR__*'
    write_env sonarr 'SONARR__*'
    write_env prowlarr 'PROWLARR__*'
    write_env unpackerr 'UN_*'
    # ubi parity: initialize.sh derives the UN_RADARR_0_*/UN_SONARR_0_* values
    # from the arr API keys/ports (into a systemd drop-in there). Derive the
    # same here from PID 1's env; appended after the UN_* copy so the derived
    # values win, exactly like the drop-in clobbers on ubi.
    if [ -n "$RADARR__AUTH__APIKEY" ]; then
        printf 'export UN_RADARR_0_API_KEY=%s\n' "$(sq "$RADARR__AUTH__APIKEY")" >> /etc/conf.d/unpackerr
        printf 'export UN_RADARR_0_URL=%s\n' \
            "$(sq "http://127.0.0.1:${RADARR__SERVER__PORT}${RADARR__SERVER__URLBASE}")" >> /etc/conf.d/unpackerr
    fi
    if [ -n "$SONARR__AUTH__APIKEY" ]; then
        printf 'export UN_SONARR_0_API_KEY=%s\n' "$(sq "$SONARR__AUTH__APIKEY")" >> /etc/conf.d/unpackerr
        printf 'export UN_SONARR_0_URL=%s\n' \
            "$(sq "http://127.0.0.1:${SONARR__SERVER__PORT}${SONARR__SERVER__URLBASE}")" >> /etc/conf.d/unpackerr
    fi
    write_env initialize 'RADARR__*' 'SONARR__*' 'PROWLARR__*'
    write_env configure-indexers 'RADARR__*' 'SONARR__*' 'PROWLARR__*'
    write_env configure-downloadclients \
        'TORRENT_*' 'RADARR__*' 'SONARR__*' 'RADARR_ROOT_DIR' 'SONARR_ROOT_DIR'
}
harvest_env

openrc sysinit
openrc boot
openrc default

if [ -e /run/starr-failed ]; then
	echo "ERROR: a required oneshot failed; stopping container (FailureAction=exit parity)"
	exit 1
fi

# Graceful shutdown on podman stop (openrc-init's signal handling).
trap 'openrc shutdown 2>/dev/null; exit 143' TERM INT

# PID 1 duty: reap children until the container is stopped.
while :; do
	wait
done