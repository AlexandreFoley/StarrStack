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

# Quadlet files land here
COPY quadlet/* /etc/containers/systemd/
COPY ubi.dockerfile /ubi.dockerfile
RUN echo "test-api-key-quadlet" > /run/secrets/radarr_apikey
RUN echo "test-api-key-quadlet" > /run/secrets/sonarr_apikey
RUN echo "test-api-key-quadlet" > /run/secrets/prowlarr_apikey
RUN echo "testpass" > /run/secrets/webui_password

# Build starr image inside the harness with the tag quadlet expects
RUN podman build -t ghcr.io/alexandrefoley/starrstack:latest -f /ubi.dockerfile /

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/sbin/init"]
