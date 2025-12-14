FROM docker.io/archlinux/archlinux

# Need to create a non-root user
RUN useradd -m nonroot
RUN echo "nonroot:nonroot" | chpasswd


STOPSIGNAL SIGRTMIN+3

# make that user sudoer
# COPY systemctl.py /usr/bin/systemctl
RUN pacman -Sy
# COPY systemctl.py /usr/bin/systemctl
RUN pacman -S --noconfirm sudo
# COPY systemctl.py /usr/bin/systemctl
RUN echo -n "nonroot ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers
# Delete the preset except for the base default that contain only "disable"

# RUN pacman -S --noconfirm python
# COPY systemctl.py /usr/bin/systemctl
# #Do stuff that must be done with lower privilege
COPY install_yay.sh install_yay.sh

# # USER runs the next command as the specified user.
USER nonroot 
RUN bash ./install_yay.sh
# COPY systemctl.py /usr/bin/systemctl
# # using yay, install radarr sonarr
USER nonroot 
RUN yes | yay --answerdiff None --answerclean None -S radarr-bin
# COPY systemctl.py /usr/bin/systemctl
USER nonroot 
RUN yes | yay --answerdiff None --answerclean None -S sonarr-bin
# COPY systemctl.py /usr/bin/systemctl
USER nonroot 
RUN yes | yay --answerdiff None --answerclean None -S prowlarr-bin
# COPY systemctl.py /usr/bin/systemctl
USER nonroot 
RUN yes | yay --answerdiff None --answerclean None -S unpackerr
# COPY systemctl.py /usr/bin/systemctl
USER root
RUN sudo rm ./install_yay.sh
# COPY systemctl.py /usr/bin/systemctl
# RUN chmod +x /usr/bin/systemctl
# # # Enable the services
# RUN systemctl enable radarr sonarr prowlarr unpackerr

# # cleanup: sudo pacman -Rs package_name
RUN yes | pacman -Rns --recursive yay-bin yay-bin-debug 
RUN yes | pacman -Rns --recursive git base-devel
RUN yes | pacman -Scc
RUN userdel -r nonroot

#Disable all the userspace stuff.
RUN find /usr /run /etc -name "*.preset" 2>/dev/null ! -name "99-default.preset" -delete
RUN cd /lib/systemd/system/sysinit.target.wants/; ls | grep -v systemd-tmpfiles-setup | xargs rm -f $1 \
rm -f /lib/systemd/system/multi-user.target.wants/*;\
rm -f /etc/systemd/system/*.wants/*;\
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*;\
rm -f /lib/systemd/system/anaconda.target.wants/*; \
rm -f /lib/systemd/system/plymouth*; \
rm -f /lib/systemd/system/systemd-update-utmp*;
RUN systemctl mask systemd-userdb.sercice systemd-remount-fs.service dev-hugepages.mount sys-fs-fuse-connections.mount systemd-logind.service getty.target console-getty.service systemd-udev-trigger.service systemd-udevd.service systemd-random-seed.service systemd-machine-id-commit.service

# # Use systemctl as entrypoint to manage services
ENTRYPOINT ["/sbin/init"]

