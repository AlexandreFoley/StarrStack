"""Drift guard: systemd .service units vs their OpenRC init-script mirrors.

The alpine image boots off hand-written OpenRC init scripts
(services/openrc/) that mirror what the systemd units declare. If one side
changes and the mirror doesn't follow, the alpine image silently diverges
from the ubi image.

check_one() is the whole contract; it is store-agnostic (takes text, not
paths) so it stays usable when the test suite is later extended to run
*inside* the alpine image: there the generated daemon units live at
/etc/systemd/system/*.service and the mirrors at /etc/init.d/* — feed both
texts to check_one() and get the same guarantees.
"""

import configparser
import re
import shlex
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SERVICES_DIR = REPO_ROOT / "services"
OPENRC_DIR = SERVICES_DIR / "openrc"

# Repo-level units (present as files). The daemon units (radarr/sonarr/
# prowlarr/unpackerr) are generated at build time by arrstack-install.sh and
# are checked indirectly: the daemon initd invariants + the generated-unit
# source-of-truth strings in arrstack-install.sh.
ONESHOOTS = ("initialize", "configure-indexers", "configure-downloadclients")

DAEMONS = {
    "radarr": "/opt/Radarr/Radarr",
    "sonarr": "/opt/Sonarr/Sonarr",
    "prowlarr": "/opt/Prowlarr/Prowlarr",
    "unpackerr": "/usr/bin/unpackerr",
}

# The mapping pinned here is the md's "systemd -> OpenRC mapping" table
# (alpine-openrc.md). Extend deliberately, never silently.


def parse_unit(text: str) -> dict:
    """Parse a .service file into {section: {lowercase_key: value}}."""
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str.lower
    cp.read_string(text)
    return {s.lower(): dict(cp.items(s)) for s in cp.sections()}


_KV_RE = re.compile(
    r'^(command_args|command_user|respawn_max|respawn_delay|supervisor|command)="?([^"]*)"?$',
    re.M,
)
_DEPS_RE = re.compile(r"depend\(\)\s*\{[^}]*\}")
_NEED_LINE_RE = re.compile(r"^\s*need\s+(\S.*)$", re.M)
_UMASK_RE = re.compile(r"\bumask[=\s]\s*\"?(\d{4})\"?")


def parse_initd(text: str) -> dict:
    """Extract the OpenRC fields the init scripts set."""
    info = {
        "text": text,
        "command": None,
        "command_args": None,
        "command_user": None,
        "supervisor": None,
        "respawn_max": None,
        "need": set(),
        "umask": None,
    }
    for key, value in _KV_RE.findall(text):
        info[key] = value
    depend = _DEPS_RE.search(text)
    if depend:
        for line in depend.group(0).splitlines():
            m = _NEED_LINE_RE.match(line)
            if m:
                info["need"].update(m.group(1).split())
    umask = _UMASK_RE.search(text)
    if umask:
        info["umask"] = umask.group(1)
    return info


def check_one(unit_text: str, initd_text: str, name: str) -> list[str]:
    """Compare one unit against its mirror; return human-readable violations."""
    units = parse_unit(unit_text)
    svc = units.get("service", {})
    initd = parse_initd(initd_text)
    issues = []

    def flag(msg: str):
        issues.append(f"{name}: {msg}")

    cmd = initd["command"]
    execstart = svc.get("execstart")
    if execstart:
        parts = shlex.split(execstart)
        if parts[0] != cmd:
            flag(f"ExecStart first token '{parts[0]}' != initd command '{cmd}'")
        if parts[1:] != shlex.split(initd["command_args"] or ""):
            flag(f"ExecStart args {parts[1:]} != initd command_args '{initd['command_args']}'")
    elif cmd:
        flag(f"unit has no ExecStart but initd sets command '{cmd}'")

    user, group = svc.get("user"), svc.get("group")
    want_user = f"{user}:{group}" if group else user
    if user and initd["command_user"] != want_user:
        flag(f"unit User/Group '{want_user}' != initd command_user '{initd['command_user']}'")
    elif not user and initd["command_user"]:
        flag(f"unit runs as root but initd sets command_user '{initd['command_user']}'")

    umask = svc.get("umask")
    if (umask or initd["umask"]) and umask != initd["umask"]:
        flag(f"unit UMask={umask} != initd umask {initd['umask']}")

    restart = svc.get("restart")
    if restart and initd["supervisor"] != "supervise-daemon":
        flag(f"unit Restart={restart} but initd has no supervise-daemon")
    if not restart and initd["supervisor"]:
        flag("unit has no Restart but initd uses supervise-daemon")

    if svc.get("type") == "oneshot":
        if '"$command"' not in initd_text:
            flag("unit Type=oneshot but initd does not run the command in the foreground")
    elif '"start()"' in initd_text:
        # "start()" is a substring of "start_pre()"; use word boundary
        if re.search(r"^start\(\)", initd_text, re.M):
            flag("unit is a daemon but initd overrides start()")

    # Requires lives in the [Unit] section, not [Service]. The inverse of the
    # mapping (initd `need initialize` without a unit Requires) is the
    # cross-file contract initialize.service's Before= states, checked at the
    # repo level in test_initialize_before_covers_every_daemon.
    unit_sec = units.get("unit", {})
    req = {r.removesuffix(".service") for r in (unit_sec.get("requires") or "").split()}
    if req and req != initd["need"]:
        flag(f"unit Requires={sorted(req)} != initd need {sorted(initd['need'])}")

    marker = "touch /run/starr-failed"
    has_marker = marker in initd_text
    if svc.get("failureaction") == "exit" and not has_marker:
        flag("unit FailureAction=exit but initd lacks the starr-failed marker")
    if svc.get("failureaction") != "exit" and has_marker:
        flag("initd touches starr-failed marker but unit has no FailureAction=exit")

    return issues