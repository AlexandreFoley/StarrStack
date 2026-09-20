# OpenRC reproducer

This reproduces startup and cgroup behavior of the Alpine OpenRC image. It
does not use credentials or a download client. The default runtime is a local
Lima Docker VM; CI uses the host Docker daemon directly through
`REPRODUCER_RUNTIME=docker`.

Local requirements: [Lima](https://lima-vm.io/) and a host with enough disk
space for the image's build-time downloads. The script creates a Docker Lima
VM, builds `alpine.dockerfile` inside it, starts one Starr container, and
writes diagnostics to `tests/lima/results/`.

CI requirements: a Docker daemon. On `ubuntu-latest` the same script builds
`alpine.dockerfile`, starts the same container, and writes the same
diagnostics.

```sh
tests/lima/run.sh up       # create/start VM, build, run, and collect
tests/lima/run.sh collect  # collect diagnostics again
tests/lima/run.sh down     # collect, remove container, stop VM
tests/lima/run.sh reset    # remove the VM and local results
```

`up` waits 90 seconds for initialization, captures diagnostics, and fails if
the container has stopped. Override the wait with `LIMA_SETTLE_SECONDS`.
Override the runtime with `REPRODUCER_RUNTIME=docker` to use the host Docker
daemon instead of Lima.

The default VM is named `starr-openrc`; override it with `LIMA_VM`. The VM
gets a writable mount of this repository so the Docker build context is
available inside the VM. `reset` is the destructive operation: it removes the
VM and the captured results, but does not touch any other Lima VM.

The container has authentication disabled and no torrent client configured.
The test also supplies `/run` as a container tmpfs, matching the deployment
setting needed by OpenRC's sysinit.
For the cgroup failure, inspect `docker-info.txt`, `vm-cgroup.txt`,
`container-inspect.txt`, `container-cgroup.txt`, `container-mounts.txt`, and
`container-logs.txt`.

