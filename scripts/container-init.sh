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