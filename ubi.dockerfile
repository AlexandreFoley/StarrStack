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

# Final stage - minimal image with only what's needed
FROM registry.access.redhat.com/ubi9/ubi-init

RUN groupadd sonarr && groupadd radarr && groupadd prowlarr && groupadd unpackerr
RUN useradd --system --no-create-home --gid sonarr sonarr
RUN useradd --system --no-create-home --gid radarr radarr
RUN useradd --system --no-create-home --gid prowlarr prowlarr
RUN useradd --system --no-create-home --gid unpackerr unpackerr

# Copy only the installed applications and configs from builder
COPY --from=builder /opt /opt
COPY --from=builder /configs /configs
COPY --from=builder /usr/bin/unpackerr /usr/bin/unpackerr
COPY --from=builder /etc/systemd/system /etc/systemd/system
COPY --from=builder /usr/lib/systemd/system/unpackerr.service /usr/lib/systemd/system/unpackerr.service

# Install runtime dependencies and cleanup
RUN dnf install -y --nodocs libicu sqlite && \
    dnf clean all && \
    rm -rf /var/cache/* /var/log/dnf* /var/log/yum.*

RUN systemctl enable sonarr radarr prowlarr unpackerr

CMD ["/sbin/init"]

