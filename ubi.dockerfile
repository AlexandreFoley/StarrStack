# Stage 1: Base builder with common tools
FROM registry.access.redhat.com/ubi9/ubi-init as builder-base

# Declare build arguments for version tracking
ARG RADARR_VERSION
ARG SONARR_VERSION
ARG PROWLARR_VERSION
ARG UNPACKERR_VERSION

RUN dnf update -y && \
    dnf install -y --nodocs wget libicu && \
    dnf clean all
COPY arrstack-install.sh /arrstack-install.sh

# Stage 2: Download and build Radarr
FROM builder-base as radarr-builder
ARG RADARR_VERSION
RUN echo "Building Radarr ${RADARR_VERSION}"
RUN groupadd radarr
RUN bash arrstack-install.sh radarr radarr radarr
RUN rm -rf /opt/Radarr/Radarr.Update

# Stage 3: Download and build Sonarr
FROM builder-base as sonarr-builder
ARG SONARR_VERSION
RUN echo "Building Sonarr ${SONARR_VERSION}"
RUN groupadd sonarr
RUN bash arrstack-install.sh sonarr sonarr sonarr
RUN rm -rf /opt/Sonarr/Sonarr.Update

# Stage 4: Download and build Prowlarr
FROM builder-base as prowlarr-builder
ARG PROWLARR_VERSION
RUN echo "Building Prowlarr ${PROWLARR_VERSION}"
RUN groupadd prowlarr
RUN bash arrstack-install.sh prowlarr prowlarr prowlarr
RUN rm -rf /opt/Prowlarr/Prowlarr.Update

# Stage 5: Download and build Unpackerr
FROM builder-base as unpackerr-builder
ARG UNPACKERR_VERSION
RUN echo "Building Unpackerr ${UNPACKERR_VERSION}"
COPY repo.sh repo.sh
RUN yes | bash repo.sh unpackerr

# Stage 6: Consolidation - combine all services and deduplicate
FROM builder-base as consolidator
# Copy all services from their respective builders
COPY --from=radarr-builder /opt/Radarr /opt/Radarr
COPY --from=radarr-builder /etc/systemd/system/radarr.service /etc/systemd/system/radarr.service
COPY --from=sonarr-builder /opt/Sonarr /opt/Sonarr
COPY --from=sonarr-builder /etc/systemd/system/sonarr.service /etc/systemd/system/sonarr.service
COPY --from=prowlarr-builder /opt/Prowlarr /opt/Prowlarr
COPY --from=prowlarr-builder /etc/systemd/system/prowlarr.service /etc/systemd/system/prowlarr.service
COPY --from=unpackerr-builder /usr/bin/unpackerr /usr/bin/unpackerr
COPY --from=unpackerr-builder /usr/lib/systemd/system/unpackerr.service /usr/lib/systemd/system/unpackerr.service

# Add update method info
RUN echo -e "UpdateMethod=External\nUpdateMethodMessage=Update managed by container builder\nBranch=master\n" >> /opt/package_info

# Deduplicate identical files across /opt directories
COPY deduplicate.sh /deduplicate.sh
RUN bash /deduplicate.sh

# Stage 7: Final stage - minimal image with only what's needed
FROM registry.access.redhat.com/ubi9/ubi-init as final

# Declare build arguments for labels
ARG RADARR_VERSION
ARG SONARR_VERSION
ARG PROWLARR_VERSION
ARG UNPACKERR_VERSION

# Add labels with service versions
LABEL org.opencontainers.image.title="Starr Stack" \
      org.opencontainers.image.description="Unified container with Radarr, Sonarr, Prowlarr, and Unpackerr" \
      org.opencontainers.image.vendor="Alexandre Foley" \
      org.opencontainers.image.source="https://github.com/AlexandreFoley/StarrStack" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      radarr.version="${RADARR_VERSION}" \
      sonarr.version="${SONARR_VERSION}" \
      prowlarr.version="${PROWLARR_VERSION}" \
      unpackerr.version="${UNPACKERR_VERSION}"

RUN groupadd sonarr && groupadd radarr && groupadd prowlarr && groupadd unpackerr
RUN useradd --system --no-create-home --gid sonarr sonarr
RUN useradd --system --no-create-home --gid radarr radarr
RUN useradd --system --no-create-home --gid prowlarr prowlarr
RUN useradd --system --no-create-home --gid unpackerr unpackerr

# Copy consolidated applications from consolidator stage
COPY --from=consolidator /opt /opt
COPY --from=consolidator /usr/bin/unpackerr /usr/bin/unpackerr
COPY --from=consolidator /etc/systemd/system /etc/systemd/system
COPY --from=consolidator /usr/lib/systemd/system/unpackerr.service /usr/lib/systemd/system/unpackerr.service
COPY unpackerr.conf /opt/unpackerr.conf

# Copy permission fix script and service
COPY initialize.sh /usr/local/bin/initialize.sh
COPY initialize.service /etc/systemd/system/initialize.service
COPY logging.service /etc/systemd/system/logging.service
RUN chmod +x /usr/local/bin/initialize.sh

# Override Unpackerr service with PassEnvironment directives
RUN mkdir -p /etc/systemd/system/unpackerr.service.d && \
    cat > /etc/systemd/system/unpackerr.service.d/override.conf <<'EOF'
[Service]
PassEnvironment=UN_RADARR_0_API_KEY UN_RADARR_0_URL UN_SONARR_0_API_KEY UN_SONARR_0_URL UN_DEBUG UN_LOG_FILE UN_LOG_LEVEL UN_CHECK_RESTART UN_CHECK_UPDATE UN_START_DELAY UN_STOP_TIMEOUT
EOF

# Install runtime dependencies and cleanup
RUN dnf install -y --nodocs libicu sqlite && \
    dnf clean all && \
    rm -rf /var/cache/* /var/log/dnf* /var/log/yum.*

RUN systemctl enable sonarr radarr prowlarr unpackerr initialize logging

VOLUME ["/config","/media"]

EXPOSE 7878 8989 9696

# Environment variables for arr services
ENV RADARR__AUTH__APIKEY="c59b53c7cb39521ead0c0dbc1a61a401" \
    RADARR__AUTH__ENABLED="false" \
    RADARR__SERVER__URLBASE="" \
    RADARR__SERVER__PORT="7878" \
    RADARR__AUTH__METHOD="External" \
    SONARR__AUTH__APIKEY="c59b53c7cb39521ead0c0dbc1a61a401" \
    SONARR__AUTH__ENABLED="false" \
    SONARR__SERVER__URLBASE="" \
    SONARR__SERVER__PORT="8989" \
    SONARR__AUTH__METHOD="External" \
    PROWLARR__AUTH__APIKEY="c59b53c7cb39521ead0c0dbc1a61a401" \
    PROWLARR__AUTH__ENABLED="false" \
    PROWLARR__SERVER__URLBASE="" \
    PROWLARR__AUTH__METHOD="External"

# Environment variables for Unpackerr - keep in sync with arr services
ENV UN_RADARR_0_API_KEY="${RADARR__AUTH__APIKEY}" \
    UN_RADARR_0_URL="http://127.0.0.1:${RADARR__SERVER__PORT}${RADARR__SERVER__URLBASE}" \
    UN_SONARR_0_API_KEY="${SONARR__AUTH__APIKEY}" \
    UN_SONARR_0_URL="http://127.0.0.1:${SONARR__SERVER__PORT}${SONARR__SERVER__URLBASE}"

# Configure systemd to not redirect stdout/stderr to /dev/null
# This allows systemd and service messages to be captured by podman logs
CMD ["/sbin/init"]


