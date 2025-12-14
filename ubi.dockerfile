FROM registry.access.redhat.com/ubi9/ubi-init

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


CMD ["/sbin/init"]