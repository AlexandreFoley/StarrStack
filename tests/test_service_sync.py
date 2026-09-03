"""Static drift guards: repo-level units vs their OpenRC mirrors.

Pure stdlib, no podman: must keep running in the plain test suite, including
when the suite is later extended to execute checks inside the alpine image
(see service_sync.check_one — it takes text, works on in-image files too).
"""
import re

import pytest

from service_sync import (
    DAEMONS,
    ONESHOOTS,
    OPENRC_DIR,
    REPO_ROOT,
    SERVICES_DIR,
    check_one,
    parse_initd,
    parse_unit,
)


def _pair(name: str) -> tuple[str, str]:
    unit = SERVICES_DIR / f"{name}.service"
    initd = OPENRC_DIR / name
    assert unit.is_file(), f"missing {unit.relative_to(REPO_ROOT)}"
    assert initd.is_file(), f"missing mirror {initd.relative_to(REPO_ROOT)}"
    return unit.read_text(), initd.read_text()


# ── Repo-level units vs mirrors ─────────────────────────────────────

@pytest.mark.parametrize("name", ONESHOOTS)
def test_oneshot_mirror_in_sync(name):
    unit_text, initd_text = _pair(name)
    assert check_one(unit_text, initd_text, name) == []


@pytest.mark.parametrize("name, binary", DAEMONS.items())
def test_daemon_initd_invariants(name, binary):
    """Daemon .service files are generated at build time, so pin the mirror
    against the two in-repo sources of truth: initialize.service's ordering
    and arrstack-install.sh's unit template."""
    initd = parse_initd((OPENRC_DIR / name).read_text())
    assert initd["command"] == binary, name
    assert initd["command_user"] == f"{name}:root", name
    assert initd["supervisor"] == "supervise-daemon", name  # Restart=on-failure/always
    assert initd["respawn_max"] == "0", name  # RespawnMax=0: never give up
    assert initd["umask"] == "0002", name  # UMask=0002: /media group-writable scheme
    # MUST be the initd-variable form: supervise-daemon does umask(022) itself
    # and clobbers a start_pre `umask 0002` builtin before forking the daemon.
    assert re.search(r'^umask="0002"$', (OPENRC_DIR / name).read_text(), re.M), \
        f"{name}: umask must be set as an initd VARIABLE, not a start_pre builtin"
    assert initd["need"] == {"initialize"}, name  # initialize.service's Before=


def test_initialize_before_covers_every_daemon():
    """initialize.service [Unit] Before= list and the daemons' `need
    initialize` must name the same services."""
    unit_text, _ = _pair("initialize")
    before = {b.removesuffix(".service") for b in parse_unit(unit_text)["unit"]["before"].split()}
    assert before == set(DAEMONS), f"initialize Before={sorted(before)}"


def test_generated_unit_template_still_matches_mirrors():
    """The daemon units are rendered from arrstack-install.sh's heredoc; assert
    the load-bearing values the initd mirrors still exist in the template."""
    script = (REPO_ROOT / "scripts" / "arrstack-install.sh").read_text()
    for needle in (
        'Group=$app_guid',        # command_user="<svc>:root"
        'UMask=$app_umask',       # umask 0002 in start_pre
        'app_umask="0002"',       # ... with 0002 for every app
        "Restart=on-failure",     # supervise-daemon respawn
        'ExecStart=$bindir/$app_bin -nobrowser -data=$datadir',
    ):
        assert needle in script, f"arrstack-install.sh no longer emits: {needle}"


# ── Build wiring: every mirror must reach the alpine image ──────────

def test_alpine_dockerfile_copies_init_dir_wholesale():
    """Init scripts are copied as a directory (OpenRC names services by
    filename, so repo names = service names). Exact file-set parity is
    enforced by test_no_orphan_initd_scripts."""
    dockerfile = (REPO_ROOT / "alpine.dockerfile").read_text()
    assert "COPY services/openrc/ /etc/init.d/" in dockerfile


@pytest.mark.parametrize("name", ONESHOOTS + tuple(DAEMONS))
def test_alpine_dockerfile_enables_each_service(name):
    dockerfile = (REPO_ROOT / "alpine.dockerfile").read_text()
    assert f"rc-update add {name} default" in dockerfile, (
        f"alpine.dockerfile does not rc-update add {name}"
    )


def test_no_orphan_initd_scripts():
    fles = {p.name: p for p in OPENRC_DIR.iterdir()}
    expected = set(ONESHOOTS) | set(DAEMONS)
    assert set(fles) == expected, f"unexpected/missing initd: {sorted(fles ^ expected)}"


# ── Unpackerr drop-in: initialize.sh writer vs initd reader ─────────

def test_unpackerr_env_segregation():
    """Unpackerr's UN_* env must come from /etc/conf.d/unpackerr (written by
    the PID-1 harvest), not from initialize.sh's systemd drop-in + sed/eval.
    The systemd drop-in path survives in initialize.sh only for the ubi build
    and must be guarded by the /run/systemd/system check."""
    init_sh = (REPO_ROOT / "scripts" / "initialize.sh").read_text()
    initd = (OPENRC_DIR / "unpackerr").read_text()
    cinit = (REPO_ROOT / "scripts" / "container-init.sh").read_text()
    dockerfile = (REPO_ROOT / "alpine.dockerfile").read_text()

    # ubi/systemd path stays intact, but only under the systemd guard
    assert "/run/systemd/system" in init_sh
    assert 'Environment="' in init_sh
    assert "systemctl daemon-reload" in init_sh

    # alpine path must not eval anything, must not read the drop-in
    assert "eval" not in initd
    assert "environment.conf" not in initd
    assert "/etc/conf.d/unpackerr" in initd

    # PID-1 harvest covers every service's prefix
    for svc in ("radarr", "sonarr", "prowlarr", "unpackerr",
                "initialize", "configure-indexers", "configure-downloadclients"):
        assert f"/etc/conf.d/{svc}" in cinit, f"harvest misses {svc}"
    for pat in ("RADARR__*", "SONARR__*", "PROWLARR__*", "UN_*", "TORRENT_*",
                "RADARR_ROOT_DIR", "SONARR_ROOT_DIR"):
        assert pat in cinit, f"harvest misses prefix {pat}"
    # ubi parity: UN_RADARR_0_*/UN_SONARR_0_* are derived from the arr keys
    # (initialize.sh's drop-in on ubi); the harvest must do the same or
    # unpackerr gets no arr credentials in real deployments.
    for derived in ("UN_RADARR_0_API_KEY", "UN_RADARR_0_URL",
                    "UN_SONARR_0_API_KEY", "UN_SONARR_0_URL"):
        assert derived in cinit, f"harvest no longer derives {derived}"
    assert "${RADARR__SERVER__PORT}${RADARR__SERVER__URLBASE}" in cinit
    assert "${SONARR__SERVER__PORT}${SONARR__SERVER__URLBASE}" in cinit
    # write_env must drop non-identifier keys: a malformed env NAME would be
    # written unquoted and executed when openrc-run sources the file
    assert "[!A-Za-z0-9_]" in cinit, "harvest lost the key-name guard"

    # no global passthrough configured, no stale drop-in dir in the alpine image
    assert ">> /etc/rc.conf" not in dockerfile
    assert "unpackerr.service.d" not in dockerfile


def test_no_systemd_parity_cargo_in_alpine_image():
    """The OpenRC image must not ship systemd leftovers: initialize.sh's
    daemon-reload is guarded to systemd builds, so no systemctl shim is ever
    called (and a root-run third-party binary is supply-chain weight), and the
    unit files are inert (init scripts are the live config; the repo-level
    services/*.service remain the reference, checked elsewhere in this file)."""
    dockerfile = (REPO_ROOT / "alpine.dockerfile").read_text()
    assert "systemctl-alpine" not in dockerfile
    assert "/usr/bin/systemctl" not in dockerfile
    assert "COPY --from=consolidator /etc/systemd/system" not in dockerfile


# ── Self-checks: the checker itself must catch drift ────────────────

_GOOD_UNIT = """\
[Unit]
Description=the service
Requires=radarr.service sonarr.service

[Service]
Type=oneshot
FailureAction=exit
ExecStart=/opt/TheSvc/TheSvc -a -b
UMask=0002
"""

_GOOD_INITD = """\
#!/sbin/openrc-run
command="/opt/TheSvc/TheSvc"
command_args="-a -b"

depend() {
    need radarr sonarr
}

start() {
    ebegin "Starting $RC_SVCNAME"
    "$command"
    rc=$?
    if [ $rc -ne 0 ]; then
        eend 1 "fatal; stopping container"
        touch /run/starr-failed
        return $rc
    fi
    eend 0
}

start_pre() {
    umask 0002
}
"""


def test_checker_accepts_matching_pair():
    assert check_one(_GOOD_UNIT, _GOOD_INITD, "thesvc") == []


@pytest.mark.parametrize(
    "unit, initd, needle",
    [
        (_GOOD_UNIT, _GOOD_INITD.replace("touch /run/starr-failed", ""),
         "lacks the starr-failed"),
        (_GOOD_UNIT, _GOOD_INITD.replace("umask 0002", "umask 0022"),
         "UMask=0002"),
        (_GOOD_UNIT, _GOOD_INITD.replace("need radarr sonarr", "need radarr"),
         "Requires="),
        (_GOOD_UNIT, _GOOD_INITD.replace('command_args="-a -b"',
         'command_args="-a"'), "command_args"),
        (_GOOD_UNIT.replace("ExecStart=/opt/TheSvc/TheSvc",
         "ExecStart=/opt/Other/Other"), _GOOD_INITD, "ExecStart first token"),
        (_GOOD_UNIT, _GOOD_INITD
         + '\nsupervisor="supervise-daemon"\nrespawn_max="0"',
         "uses supervise-daemon"),
        (_GOOD_UNIT, _GOOD_INITD + '\ncommand_user="thesvc:root"',
         "runs as root"),
    ],
)
def test_checker_flags_drift(unit, initd, needle):
    assert any(needle in msg for msg in check_one(unit, initd, "thesvc")), (
        f"expected violation mentioning '{needle}' in {check_one(unit, initd, 'thesvc')}"
    )