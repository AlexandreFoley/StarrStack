FROM registry.access.redhat.com/ubi9/ubi-init as builder

# Install any required packages
RUN yum update -y && \
    yum clean all

COPY repo.sh repo.sh
RUN yes | bash repo.sh unpackerr

RUN groupadd sonarr
RUN groupadd radarr
RUN groupadd prowlarr
RUN mkdir configs

RUN dnf install -y --nodocs wget libicu

COPY arrstack-install.sh /arrstack-install.sh
RUN bash arrstack-install.sh sonarr sonarr sonarr
RUN bash arrstack-install.sh radarr radarr radarr
RUN bash arrstack-install.sh prowlarr prowlarr prowlarr
# Set up a basic service (optional example)
RUN systemctl enable sonarr radarr prowlarr unpackerr

#Cleanup
RUN dnf clean all; rm -rf /var/cache/* /var/log/dnf* /var/log/yum.*
RUN rm *.tar.gz
RUN rm -rf /opt/Prowlarr/Prowlarr.Update
RUN rm -rf /opt/Sonarr/Sonarr.Update
RUN rm -rf /opt/Radarr/Radarr.Update
RUN echo -e "UpdateMethod=External\nUpdateMethodMessage=Update managed by container builder\nBranch=master\n" >> /opt/package_info

# Deduplicate identical files across /opt directories
COPY deduplicate.sh /deduplicate.sh
RUN bash /deduplicate.sh

# Final stage - minimal image with only what's needed
FROM registry.access.redhat.com/ubi9/ubi-init

RUN groupadd sonarr && groupadd radarr && groupadd prowlarr && groupadd unpackerr
RUN useradd --system --no-create-home --gid sonarr sonarr
RUN useradd --system --no-create-home --gid radarr radarr
RUN useradd --system --no-create-home --gid prowlarr prowlarr
RUN useradd --system --no-create-home --gid unpackerr unpackerr

# Copy only the installed applications and configs from builder
COPY --from=builder /opt /opt
COPY --from=builder /usr/bin/unpackerr /usr/bin/unpackerr
COPY --from=builder /etc/systemd/system /etc/systemd/system
COPY --from=builder /usr/lib/systemd/system/unpackerr.service /usr/lib/systemd/system/unpackerr.service
COPY unpackerr.conf /opt/unpackerr.conf

# Copy permission fix script and service
COPY initialize.sh /usr/local/bin/initialize.sh
COPY initialize.service /etc/systemd/system/initialize.service
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

RUN systemctl enable sonarr radarr prowlarr unpackerr initialize

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

CMD ["/sbin/init"]

