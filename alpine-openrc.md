# Alpine + OpenRC image plan (Starr Stack) — implemented

Status: implemented, built and smoke-tested (see Verification results).

Goal: an Alpine-based variant of the ubi9-init image (`ubi.dockerfile`) that

- reuses the **same scripts** (`scripts/*.sh`) and **same service files**
  (`services/*.service`) as the ubi9 build, with **no modifications to them**
  except the single parameterization in `arrstack-install.sh` (below), which
  leaves the ubi9 build byte-identical;
- uses multi-stage builds like the ubi9 image;
- runs on Alpine 3.24 + OpenRC.

## Decisions (locked in)

| Decision | Choice | Why |
|---|---|---|
| Base image | `alpine:3.24` | pinned; matches linuxserver's arr images |
| Glibc vs musl app builds | `os=linuxmusl` (`ARR_OS=linuxmusl`) | the ubi `os=linux` (glibc) tarballs do not run on musl. Verified: all three APIs serve musl tarballs (`Radarr...linux-musl-core-x64.tar.gz`, `Prowlarr...linux-musl-core-x64.tar.gz`, `Sonarr.main...linux-musl-x64.tar.gz`) |
| Init (PID 1) | small wrapper `scripts/container-init.sh` as `/sbin/init` | `openrc-init` was the original choice, but it **cannot terminate a rootless container, verified empirically**: its shutdown path ends in `reboot(2)` which the kernel denies without init-userns `CAP_SYS_BOOT`, and PID 1 is SIGKILL-immune in rootless runtimes (SIGKILL/SIGTERM/pkill from inside are all no-ops). The wrapper runs exactly the runlevels openrc-init would (`openrc sysinit`, `openrc boot`, `openrc default`), reaps children, handles SIGTERM via `openrc shutdown`, and **exits when a required oneshot fails** → container stops |
| Oneshot failure (`FailureAction=exit` parity) | failed `initialize`/`configure-*` touches `/run/starr-failed`; the init wrapper exits after the runlevel | `openrc default` exits 0 even when services fail (verified), so the exit code is unusable; the marker file is the reliable signal. No dependency on `openrc-shutdown`/reboot(), which cannot work rootless |
| Container env → services | per-service `/etc/conf.d/<service>` files, written by a harvest in `scripts/container-init.sh` (PID 1 is the only process with the unfiltered env), root-only (0600) | OpenRC's runlevel runner (`src/openrc/rc.c`) calls `env_filter()`, which **strips the entire environment** except a static whitelist. Replaces the initial `rc_env_allow="*"` (passes everything to every service); now each daemon/oneshot sees only its own vars, like systemd's per-unit `PassEnvironment`. Daemons receive values via their process env, never by reading the files |
| service file → OpenRC conversion | **hand-written** init scripts mirroring the units | mobydeck `systemctl-alpine`'s converter (beta) drops `[Unit]` ordering, `UMask`, `PassEnvironment`, `FailureAction`; those matter here (ordering + umask-002 /media scheme). The `.service` files are **not** shipped in the image; the repo-level units remain the reference (enforced by `tests/test_service_sync.py`) |
| `systemctl-alpine` | **not installed** | initialize.sh's `systemctl daemon-reload` is guarded to the systemd build (`/run/systemd/system`), so the OpenRC build never calls systemctl; keeping a root-run third-party binary for interactive shells was dead supply-chain weight |
| Unpackerr install | static binary from GitHub releases (`unpackerr_<ver>_linux_<arch>.tar.gz`), verified against the release's `checksums.sha256.txt` | no `unpackerr` apk exists in Alpine main/community (verified in APKINDEX); asset naming changed at v0.16 (old `unpackerr.<arch>.linux.gz` only existed up to 0.15.x) |
| `runuser` (used by `initialize.sh`) | `apk add runuser` | util-linux ships it as its own Alpine subpackage (`--enable-runuser`) |
| `getent` (used by `arrstack-install.sh`) | 10-line shim | Alpine busybox (main + extras) has no `getent` applet |
| package manager (used by `arrstack-install.sh`) | `dnf` → `apk` shim | the only dnf calls are `dnf update -y` and `dnf install -y --skip-broken PKGS` |
| Daemon restart | `supervisor=supervise-daemon`, `respawn_max=0` (unlimited), `respawn_delay=2` | ubi `Restart=on-failure` parity |

## Verified facts (source)

- musl downloads: `radarr.servarr.com/v1/update/master/updatefile?os=linuxmusl&runtime=netcore&arch=x64` → 200 (110MB), same for prowlarr (112MB) and `services.sonarr.tv/v1/download/main/latest?version=4&os=linuxmusl&arch=x64` → 200 (101MB).
- linuxserver's Alpine arr images install `icu-libs sqlite-libs` and download `os=linuxmusl` — the runtime deps for musl .NET.
- `unpackerr` not in `edge/main` or `edge/community` APKINDEX. Assets (since v0.16): `unpackerr_<ver>_linux_<amd64|arm64|armv7|386>.tar.gz` + `checksums.sha256.txt`.
- `runuser` exists: `aports main/util-linux/APKBUILD` → `runuser:_mv_bin`, `--enable-runuser`.
- busybox configs (`busyboxconfig`, `busyboxconfig-extras`) have no `CONFIG_GETENT`; they do have `SHA256SUM`, `STAT`, `WGET` (but busybox wget lacks `--content-disposition` → GNU wget in builder).
- OpenRC env stripping: `src/openrc/rc.c` calls `env_filter()` (defined in `src/shared/misc.c`); entries in `rc_env_allow` are matched with `fnmatch`, so globs work but the filter is global, never per-service — hence the per-service `/etc/conf.d` harvest (see `scripts/container-init.sh`).
- `openrc default` exits 0 even when services fail to start (verified in the built image).
- Rootless container init can't be stopped from inside: PID 1 is SIGKILL/SIGTERM-immune (verified: `kill -9 1` from a service returns 0, no effect), and `reboot(2)` requires init-userns caps.

## Existing-file modifications

`scripts/arrstack-install.sh`, two lines (ubi9 default preserved):

```diff
-dlbase="https://$app.servarr.com/v1/update/$branch/updatefile?os=linux&runtime=netcore"
+dlbase="https://$app.servarr.com/v1/update/$branch/updatefile?os=${ARR_OS:-linux}&runtime=netcore"
...
-dlbase="https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux"
+dlbase="https://services.sonarr.tv/v1/download/main/latest?version=4&os=${ARR_OS:-linux}"
```

Builders run `ARR_OS=linuxmusl`; the ubi9 build never sets it → identical URLs.

`scripts/initialize.sh`: the unpackerr drop-in write + `systemctl daemon-reload` are now guarded by `[ -d /run/systemd/system ]`, so the systemd build behaves identically while the OpenRC build skips them (its env comes from the per-service harvest instead).

## New files

| File | Purpose |
|---|---|
| `alpine.dockerfile` | multi-stage build (mirrors ubi.dockerfile stages) |
| `scripts/container-init.sh` | PID 1: OpenRC runlevels + exit-on-oneshot-failure + reaping + per-service env harvest (writes `/etc/conf.d/<service>`) |
| `scripts/alpine/bin/dnf` | `dnf update/install` → `apk update/add` (build stages only) |
| `scripts/alpine/bin/getent` | passwd/group lookup shim (awk over /etc/passwd, /etc/group) |
| `scripts/alpine/bin/adduser` | GNU long options → busybox `adduser -S -H -G -D` |
| `scripts/alpine/bin/groupadd` | → `addgroup -S` |
| `scripts/alpine/bin/usermod` | `-a -G GROUP USER` → `addgroup USER GROUP` |
| `services/openrc/` (7 files, named = service name) | OpenRC equivalents of the systemd units; copied wholesale into `/etc/init.d/` (OpenRC names services by filename, so repo names = service names) |

## Stage architecture (mirror of ubi.dockerfile)

```
builder-base (alpine:3.24 + bash, GNU wget, GNU-user-tool shims, mkdir /etc/systemd/system)
 ├─ radarr-builder            bash arrstack-install.sh radarr   radarr root   (ARR_OS=linuxmusl)
 ├─ sonarr-builder            bash arrstack-install.sh sonarr   sonarr root
 ├─ prowlarr-builder          bash arrstack-install.sh prowlarr prowlarr root
 ├─ unpackerr-builder         curl unpackerr_<ver>_linux_<arch>.tar.gz + sha256 check → /usr/bin/unpackerr
 └─ consolidator              merges /opt + units, package_info, deduplicate.sh
final (alpine:3.24 + openrc/busybox-openrc/bash/curl/jq/icu-libs/sqlite-libs/runuser
        + init wrapper + init scripts)   CMD ["/sbin/init"]
```

## systemd → OpenRC mapping

| ubi construct | Alpine replacement | Note |
|---|---|---|
| `Type=simple`, `User`, `Group` | `command`, `command_args`, `command_user` | |
| `UMask=0002` | initd variable `umask="0002"` (forwarded by openrc-run to supervise-daemon as `--umask`) | a `start_pre` `umask 0002` builtin is NOT enough: supervise-daemon calls `umask(022)` itself (default in `supervise-daemon.c`), clobbering the inherited value. Found empirically via `/proc/<pid>/status` during the env-segregation verification; the md's original mapping was wrong here |
| `Restart=on-failure` | `supervisor=supervise-daemon`, `respawn_max=0` (unlimited), `respawn_delay=2` | supervise-daemon respawns on any exit, systemd only on unclean exit — accepted drift |
| `Type=oneshot` + `RemainAfterExit=yes` | custom `start()` running the command in the foreground | service is "started" after the command exits |
| `FailureAction=exit` | failed oneshot touches `/run/starr-failed`; init wrapper exits → container stops | |
| `Before=` / `Requires=` / `Wants=` | `depend() { need initialize }` / `need radarr sonarr prowlarr` / `need radarr sonarr` | |
| `PassEnvironment=RADARR__*` | per-service `/etc/conf.d/{radarr,sonarr,prowlarr,initialize,configure-*}` (harvested by PID 1) | |
| `PassEnvironment=UN_RADARR_0_*` (unpackerr) | `/etc/conf.d/unpackerr` (harvested) — no drop-in, no eval | verified: the UN_ vars reach the daemon |
| `StandardOutput=journal+console` | inherited console fd → `podman logs` (quadlet runs with `--tty`) | unpackerr logs to stdout (deliberate drift: ubi's unit set `UN_LOG_FILE` to a file; console is better for containers) |
| `systemctl daemon-reload` (initialize.sh) | not called on the OpenRC build (guarded by `/run/systemd/system` in initialize.sh) | |

## Oneshot failure → container stop

Oneshot init scripts (`initialize`, `configure-indexers`, `configure-downloadclients`):

```sh
start() {
    ebegin "Starting $RC_SVCNAME"
    "$command"
    rc=$?
    if [ $rc -ne 0 ]; then
        eend 1 "fatal: $RC_SVCNAME failed; stopping container (FailureAction=exit parity)"
        touch /run/starr-failed
        return $rc
    fi
    eend 0
}
```

`scripts/container-init.sh`:

```sh
openrc sysinit
openrc boot
openrc default
if [ -e /run/starr-failed ]; then echo "ERROR: ...; stopping container"; exit 1; fi
trap 'openrc shutdown 2>/dev/null; exit 143' TERM INT
while :; do wait; done
```

API keys are optional: an empty `RADARR__AUTH__APIKEY` is replaced with a
runtime-generated key.

## Build & smoke test

```sh
podman build --build-arg UNPACKERR_VERSION=0.15.2 -f alpine.dockerfile -t localhost/starr-alpine:test .
podman run -d --name starr-alpine-test -p 7878:7878 -p 8989:8989 -p 9696:9696 \
    localhost/starr-alpine:test
podman exec starr-alpine-test rc-status --all
podman logs -f starr-alpine-test
```

## Verification results

| Check | Result |
|---|---|
| image size | **809 MB** alpine vs **1.08 GB** ubi9 (`localhost/starr-ubi:test`, same machine) → **~270 MB (~25%) smaller**, matching the ~250MB estimate in notes.md (ubi-init base alone is 257MB vs ~8MB alpine) |
| PID 1 | wrapper init (`/sbin/init`); `openrc sysinit/boot/default` run |
| 7 services | all `[ started ]` (`rc-status`); daemons run as `user:group` (`--user radarr root` etc.) |
| Radarr/Sonarr/Prowlarr UIs | HTTP 200 on 7878/8989/9696 |
| `initialize` (boot log) | /config per-service 700 (radarr/sonarr/prowlarr/unpackerr), unpackerr drop-in written on systemd builds, `runuser` /media probe ran, `systemctl daemon-reload` skipped on OpenRC | |
| configure-downloadclients | skips cleanly with no `TORRENT_*` env (matches design, no failure) |
| configure-indexers | full success: connected to all three apps, added Radarr-autoconf + Sonarr-autoconf to Prowlarr, triggered sync |
| unpackerr env | `UN_RADARR_0_URL`, `UN_RADARR_0_API_KEY`, `UN_SONARR_0_*` present in the daemon's environment (drop-in eval works) |
| unpackerr connectivity | ESTABLISHED connection to Radarr on :7878 observed |
| failure-stop | required startup failures self-exit `Exited (1)` with the "stopping container" message |
| ubi size comparison | done: 809 MB (alpine) vs 1.08 GB (ubi9) |