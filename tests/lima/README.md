# Lima/OpenRC reproducer

This is a local-only reproducer for startup and cgroup behavior of the Alpine
OpenRC image. It does not use CI, credentials, or a download client.

Requirements: [Lima](https://lima-vm.io/) and a host with enough disk space
for the image's build-time downloads. The script creates a Docker Lima VM,
builds `alpine.dockerfile` inside it, starts one Starr container, and writes
diagnostics to `tests/lima/results/`.

```sh
tests/lima/run.sh up       # create/start VM, build, run, and collect
tests/lima/run.sh collect  # collect diagnostics again
tests/lima/run.sh down     # collect, remove container, stop VM
tests/lima/run.sh reset    # remove the VM and local results
```

`up` waits 90 seconds for initialization, captures diagnostics, and fails if
the container has stopped. Override the wait with `LIMA_SETTLE_SECONDS`.

The default VM is named `starr-openrc`; override it with `LIMA_VM`. The VM
gets a writable mount of this repository so the Docker build context is
available inside the VM. `reset` is the destructive operation: it removes the
VM and the captured results, but does not touch any other Lima VM.

The container has authentication disabled and no torrent client configured.
For the cgroup failure, inspect `docker-info.txt`, `vm-cgroup.txt`,
`container-inspect.txt`, `container-cgroup.txt`, `container-mounts.txt`, and
`container-logs.txt`.

