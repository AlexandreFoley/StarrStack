# Test harness for podman-in-podman quadlet testing.
# Has systemd + podman so quadlet files can be processed inside a container.
FROM registry.access.redhat.com/ubi9/ubi-init

RUN dnf install -y --nodocs --allowerasing \
        podman \
        crun \
        jq \
        curl \
        skopeo \
    && dnf clean all

# Rootless podman needs a user with a home and subuids/subgids
RUN useradd -m -s /bin/bash testuser \
    && echo "testuser:100000:65536" >> /etc/subuid \
    && echo "testuser:100000:65536" >> /etc/subgid

# Quadlet files land here (copied from project root quadlet/starrstack/)
COPY quadlet/starrstack/* /etc/containers/systemd/
RUN mkdir -p /etc/containers/systemd/mounts

# Disable automatic restart on crash for testing
RUN sed -i 's/Restart=always/Restart=no/' /etc/containers/systemd/*.container

# Copy monitoring script and systemd service
COPY tests/harness/monitor-services.sh /usr/local/bin/monitor-services.sh
RUN chmod +x /usr/local/bin/monitor-services.sh

COPY tests/harness/service-monitor.service /etc/systemd/system/service-monitor.service
RUN systemctl enable service-monitor.service

COPY tests/harness/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY test_api_key /harness/test_api_key

ENTRYPOINT ["/entrypoint.sh"]
