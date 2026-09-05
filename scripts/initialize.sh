#!/bin/bash
# Initialize container: fix permissions and create environment files for services
# Services can only access their own config directories.

set -e

echo "Initializing container..."

# Validate required environment variables. API keys are generated below when
# they were not supplied by the container runtime.
MISSING_VARS=()

[ -z "$RADARR__SERVER__PORT" ] && MISSING_VARS+=("RADARR__SERVER__PORT")
[ -z "$SONARR__SERVER__PORT" ] && MISSING_VARS+=("SONARR__SERVER__PORT")
[ -z "$PROWLARR__SERVER__PORT" ] && MISSING_VARS+=("PROWLARR__SERVER__PORT")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "Error: Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "All arr services require the following environment variables:"
    echo "  *__SERVER__PORT"
    echo "  *__SERVER__URLBASE (optional)"
    exit 1
fi

# Create directories if they don't exist (fresh bind mounts)
mkdir -p /config /media
mkdir -p /config/radarr /config/sonarr /config/prowlarr /config/unpackerr

# Each service owns its config directory; other services are shut out at the
# top dir (700). Unconditional: config trees are small, and this self-heals
# strays (root-owned files from restores or one-off root runs). A failed chown
# warns instead of silently downgrading isolation.
for svc in radarr sonarr prowlarr unpackerr; do
    chown -R "$svc:$svc" "/config/$svc" && chmod 700 "/config/$svc" \
        || echo "Warning: could not set ownership on /config/$svc"
done

# /media is never modified from inside the container. Services share it through
# the host user's group: units run with Group=root, which rootless Podman maps to
# the host user's primary group. Requirement: a group-writable tree (umask 002).
# Probe once as a service user and warn loudly instead of failing the boot.
if runuser -u radarr -g root -- sh -c '[ -r /media ] && [ -w /media ] && [ -x /media ]' 2>/dev/null; then
    echo "  ✓ /media is group-writable (shared via host user's group)"
else
    echo "  *** WARNING: services cannot write to /media."
    echo "  *** The media tree must be group-writable (664/775) by your host group."
    echo "  *** Use UMASK=002 on your download client (the qbittorrent unit already does)."
fi

# Resolve the stack's API key from the runtime environment. Keep this
# deliberately ephemeral: users who need a stable key can provide one.
API_KEY="${RADARR__AUTH__APIKEY:-${SONARR__AUTH__APIKEY:-${PROWLARR__AUTH__APIKEY:-}}}"
if [ -z "$API_KEY" ]; then
    API_KEY=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
fi

RADARR__AUTH__APIKEY="${RADARR__AUTH__APIKEY:-$API_KEY}"
SONARR__AUTH__APIKEY="${SONARR__AUTH__APIKEY:-$API_KEY}"
PROWLARR__AUTH__APIKEY="${PROWLARR__AUTH__APIKEY:-$API_KEY}"

if [ -d /run/systemd/system ]; then
    # systemd services receive container variables through PassEnvironment.
    # set-environment updates PID 1's environment without creating a secrets
    # file, so generated keys remain ephemeral.
    systemctl set-environment \
        RADARR__AUTH__APIKEY="$RADARR__AUTH__APIKEY" \
        SONARR__AUTH__APIKEY="$SONARR__AUTH__APIKEY" \
        PROWLARR__AUTH__APIKEY="$PROWLARR__AUTH__APIKEY"
else
    # PID 1 harvested the original container environment before initialize
    # started. Add generated values to the per-service env files it created.
    for svc in radarr sonarr prowlarr; do
        case "$svc" in
            radarr)    var=RADARR__AUTH__APIKEY ;;
            sonarr)    var=SONARR__AUTH__APIKEY ;;
            prowlarr)  var=PROWLARR__AUTH__APIKEY ;;
        esac
        printf 'export %s=%s\n' "$var" "'${!var}'" >> "/etc/conf.d/$svc"
        chmod 600 "/etc/conf.d/$svc"
    done

    for svc in initialize configure-indexers configure-downloadclients; do
        for var in RADARR__AUTH__APIKEY SONARR__AUTH__APIKEY PROWLARR__AUTH__APIKEY; do
            printf 'export %s=%s\n' "$var" "'${!var}'" >> "/etc/conf.d/$svc"
        done
        chmod 600 "/etc/conf.d/$svc"
    done

    svc=unpackerr
    {
        printf "export UN_RADARR_0_API_KEY='%s'\n" "$RADARR__AUTH__APIKEY"
        printf "export UN_RADARR_0_URL='%s'\n" \
            "http://127.0.0.1:${RADARR__SERVER__PORT}${RADARR__SERVER__URLBASE}"
        printf "export UN_SONARR_0_API_KEY='%s'\n" "$SONARR__AUTH__APIKEY"
        printf "export UN_SONARR_0_URL='%s'\n" \
            "http://127.0.0.1:${SONARR__SERVER__PORT}${SONARR__SERVER__URLBASE}"
    } >> "/etc/conf.d/$svc"
    chmod 600 "/etc/conf.d/$svc"
fi

# systemd build only (ubi). Unpackerr's UN_* env is a systemd drop-in there.
# On the OpenRC build (alpine) the container runtime env is harvested
# per-service into /etc/conf.d/<service> by container-init.sh (PID 1), which
# openrc-run sources for that service alone; generated values are appended above.
if [ -d /run/systemd/system ]; then
    cat > /etc/systemd/system/unpackerr.service.d/environment.conf <<EOF
[Service]
Environment="UN_RADARR_0_API_KEY=${RADARR__AUTH__APIKEY}"
Environment="UN_RADARR_0_URL=http://127.0.0.1:${RADARR__SERVER__PORT}${RADARR__SERVER__URLBASE}"
Environment="UN_SONARR_0_API_KEY=${SONARR__AUTH__APIKEY}"
Environment="UN_SONARR_0_URL=http://127.0.0.1:${SONARR__SERVER__PORT}${SONARR__SERVER__URLBASE}"
EOF

    # Root-only: contains the Radarr and Sonarr API keys. systemd (PID 1) reads
    # drop-ins regardless; services receive the values via their environment.
    chmod 600 /etc/systemd/system/unpackerr.service.d/environment.conf

    # Reload systemd to pick up the new service configuration
    systemctl daemon-reload
fi

echo "Initialization complete:"
echo "  ✓ /config service directories owned per-service (700, isolated)"
if [ -d /run/systemd/system ]; then
    echo "  ✓ Unpackerr environment configured from arr service settings"
fi

