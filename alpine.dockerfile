# Alpine (musl) variant of the Starr stack image.
# Mirrors ubi.dockerfile stage-for-stage; final stage ~250MB smaller.
# One behavior difference by design: PID 1 is openrc-init, and a failed
# oneshot (initialize/configure-*) powers the container off (FailureAction=exit parity).
# Requires the ARR_OS parameterization in scripts/arrstack-install.sh
# (os=${ARR_OS:-linux}; ubi builds are unaffected - the default is unchanged).

# Stage 1: base builder with common tools and GNU-user-tool shims
FROM alpine:3.24 AS builder-base

ARG TARGETARCH

# TARGETARCH is fixed for the whole build, so validate it once here instead of
# in every stage that downloads an arch-specific asset (the unpackerr release
# names use it directly).
# GNU wget: busybox wget has no --content-disposition (arrstack-install.sh needs it)
RUN apk add --no-cache bash wget && mkdir -p /etc/systemd/system && \
    case "$TARGETARCH" in \
      amd64|arm64) ;; \
      *) echo "unsupported target arch '$TARGETARCH' (supported: amd64, arm64)" >&2; exit 1 ;; \
    esac
COPY scripts/alpine/bin/ /usr/local/bin/
COPY scripts/arrstack-install.sh /arrstack-install.sh

# Stage 2: Download and build Radarr
FROM builder-base AS radarr-builder
ARG RADARR_VERSION
RUN echo "Building Radarr ${RADARR_VERSION}" && \
    ARR_OS=linuxmusl bash arrstack-install.sh radarr radarr root "${RADARR_VERSION}" && \
    rm -rf /opt/Radarr/Radarr.Update

# Stage 3: Download and build Sonarr
FROM builder-base AS sonarr-builder
ARG SONARR_VERSION
RUN echo "Building Sonarr ${SONARR_VERSION}" && \
    ARR_OS=linuxmusl bash arrstack-install.sh sonarr sonarr root "${SONARR_VERSION}" && \
    rm -rf /opt/Sonarr/Sonarr.Update

# Stage 4: Download and build Prowlarr
FROM builder-base AS prowlarr-builder
ARG PROWLARR_VERSION
RUN echo "Building Prowlarr ${PROWLARR_VERSION}" && \
    ARR_OS=linuxmusl bash arrstack-install.sh prowlarr prowlarr root "${PROWLARR_VERSION}" && \
    rm -rf /opt/Prowlarr/Prowlarr.Update

# Stage 5: Download and build Unpackerr (static Go binary; no Alpine package exists).
# Asset naming is unpackerr_<ver>_linux_<arch>.tar.gz (changed in v0.16; the
# old unpackerr.<arch>.linux.gz only existed up to 0.15.x). The release ships
# checksums.sha256.txt - verify the archive against it (moving-target integrity).
FROM alpine:3.24 AS unpackerr-builder
ARG UNPACKERR_VERSION
ARG TARGETARCH
RUN apk add --no-cache curl && \
    cd /tmp && \
    curl -fsSL -O "https://github.com/Unpackerr/unpackerr/releases/download/v${UNPACKERR_VERSION}/checksums.sha256.txt" && \
    curl -fsSL -O "https://github.com/Unpackerr/unpackerr/releases/download/v${UNPACKERR_VERSION}/unpackerr_${UNPACKERR_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    grep -F "unpackerr_${UNPACKERR_VERSION}_linux_${TARGETARCH}.tar.gz" checksums.sha256.txt | sha256sum -c && \
    tar -xzf "unpackerr_${UNPACKERR_VERSION}_linux_${TARGETARCH}.tar.gz" unpackerr && \
    install -m0755 /tmp/unpackerr /usr/bin/unpackerr

# Stage 6: Consolidation - combine all services and deduplicate
FROM builder-base AS consolidator

COPY --from=radarr-builder /opt/Radarr /opt/Radarr
COPY --from=sonarr-builder /opt/Sonarr /opt/Sonarr
COPY --from=prowlarr-builder /opt/Prowlarr /opt/Prowlarr
COPY --from=unpackerr-builder /usr/bin/unpackerr /usr/bin/unpackerr

# Add update method info (same as ubi)
RUN echo -e "UpdateMethod=External\nUpdateMethodMessage=Update managed by container builder\nBranch=master\n" >> /opt/package_info

# Deduplicate identical files across /opt directories
COPY scripts/deduplicate.sh /deduplicate.sh
RUN bash /deduplicate.sh

# Stage 7: Final stage - minimal image with only what's needed
FROM alpine:3.24 AS final

ARG RADARR_VERSION
ARG SONARR_VERSION
ARG PROWLARR_VERSION
ARG UNPACKERR_VERSION

# Add labels with service versions (same as ubi)
LABEL org.opencontainers.image.title="Starr Stack" \
      org.opencontainers.image.description="Unified container with Radarr, Sonarr, Prowlarr, and Unpackerr" \
      org.opencontainers.image.vendor="Alexandre Foley" \
      org.opencontainers.image.source="https://github.com/AlexandreFoley/StarrStack" \
      org.opencontainers.image.documentation="https://github.com/AlexandreFoley/StarrStack" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.url="https://github.com/AlexandreFoley/StarrStack" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.authors="Alexandre Foley" \
      radarr.version="${RADARR_VERSION}" \
      sonarr.version="${SONARR_VERSION}" \
      prowlarr.version="${PROWLARR_VERSION}" \
      unpackerr.version="${UNPACKERR_VERSION}"

# icu-libs/sqlite-libs: musl .NET needs them (same as linuxserver's arr images).
# runuser: initialize.sh probes /media as a service user.
# busybox-openrc wires /etc/inittab-style openrc boot for openrc-init.
# openrc strips the container environment by default (env_filter in
# src/shared/misc.c); the runtime env (API keys etc.) reaches each service
# per-service via /etc/conf.d/<service> files written by container-init.sh's
# harvest — no rc_env_allow needed (and no cross-service leakage).
RUN apk add --no-cache openrc busybox-openrc bash curl jq icu-libs sqlite-libs runuser ca-certificates && \
    for u in radarr sonarr prowlarr unpackerr; do \
        addgroup -S "$u" && adduser -S -H -G "$u" "$u"; \
    done && \
    mkdir -p /run/openrc

# Copy consolidated applications from consolidator stage
COPY --from=consolidator /opt /opt
# Services only need read+execute here (updates are UpdateMethod=External).
# Normalize explicitly: buildah root-owns COPY --from output, but BuildKit
# preserves builder ownership. go-w also matters because services run with
# Group=root for /media sharing.
RUN chown -R root:root /opt && chmod -R u=rwX,go=rX /opt
COPY --from=consolidator /usr/bin/unpackerr /usr/bin/unpackerr
COPY config/unpackerr.conf /opt/unpackerr.conf

# Copy configuration scripts (unchanged from the ubi path)
COPY scripts/initialize.sh /usr/local/bin/initialize.sh
COPY scripts/configure-indexers.sh /usr/local/bin/configure-indexers.sh
COPY scripts/configure-downloadclients.sh /usr/local/bin/configure-downloadclients.sh
RUN chmod +x /usr/local/bin/initialize.sh /usr/local/bin/configure-indexers.sh /usr/local/bin/configure-downloadclients.sh

# Container init (PID 1): runs the same OpenRC runlevels as openrc-init but
# exits when a required oneshot fails (openrc-init cannot terminate a rootless
# container - its reboot(2) shutdown path needs init-userns CAP_SYS_BOOT, and
# PID 1 is SIGKILL-immune in rootless runtimes, verified empirically).
# rm the base's /sbin/init busybox symlink first: buildkit's overlay copy-up
# fails to exec /bin/sh in the step after COPYing over a base symlink
# (works fine under buildah; breaks under GitHub's docker buildx, verified).
RUN rm -f /sbin/init
COPY scripts/container-init.sh /sbin/init
RUN chmod +x /sbin/init

# OpenRC init scripts: OpenRC equivalents of the systemd units. Copied as a
# directory; OpenRC names services by filename, so repo names = service names.
COPY services/openrc/ /etc/init.d/
RUN chmod +x /etc/init.d/* && \
    rc-update add initialize default && \
    rc-update add radarr default && \
    rc-update add sonarr default && \
    rc-update add prowlarr default && \
    rc-update add unpackerr default && \
    rc-update add configure-indexers default && \
    rc-update add configure-downloadclients default

VOLUME ["/config","/media"]

EXPOSE 7878 8989 9696

# Environment variables for arr services (same defaults as ubi)
ENV RADARR__AUTH__APIKEY="c59b53c7cb39521ead0c0dbc1a61a401" \
    RADARR__AUTH__ENABLED="true" \
    RADARR__SERVER__URLBASE="" \
    RADARR__SERVER__PORT="7878" \
    RADARR__AUTH__METHOD="Forms" \
    SONARR__AUTH__APIKEY="c59b53c7cb39521ead0c0dbc1a61a401" \
    SONARR__AUTH__ENABLED="true" \
    SONARR__SERVER__URLBASE="" \
    SONARR__SERVER__PORT="8989" \
    SONARR__AUTH__METHOD="Forms" \
    PROWLARR__AUTH__APIKEY="c59b53c7cb39521ead0c0dbc1a61a401" \
    PROWLARR__AUTH__ENABLED="true" \
    PROWLARR__SERVER__URLBASE="" \
    PROWLARR__SERVER__PORT="9696" \
    PROWLARR__AUTH__METHOD="Forms"

# sbin/init wrapper: openrc sysinit + boot + default, exits on oneshot failure
# (FailureAction=exit parity; see scripts/container-init.sh).
CMD ["/sbin/init"]