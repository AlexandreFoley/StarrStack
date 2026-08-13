"""Static validation tests for quadlet files.

Parses quadlet files with a custom parser (quadlet allows duplicate keys
which stdlib configparser does not), validates required sections/keys,
and checks cross-references between files.
"""
import re
from pathlib import Path

import pytest

QUADLET_DIR = Path(__file__).resolve().parent.parent / "quadlet" / "starrstack"

CONTAINER_FILES = sorted(QUADLET_DIR.glob("*.container"))
NETWORK_FILES = sorted(QUADLET_DIR.glob("*.network"))


def parse_quadlet(path: Path) -> dict[str, list[tuple[str, str]]]:
    """Parse a quadlet file. Returns {section: [(key, value), ...]}.

    Quadlet is INI-like but allows duplicate keys (e.g. multiple PublishPort=).
    We preserve all occurrences as a list of tuples.
    """
    sections: dict[str, list[tuple[str, str]]] = {}
    current_section = None
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", ";")):
            continue
        m = re.match(r"\[(.+)\]", stripped)
        if m:
            current_section = m.group(1)
            sections.setdefault(current_section, [])
            continue
        if current_section is None:
            continue
        if "=" in stripped:
            key, _, val = stripped.partition("=")
            sections[current_section].append((key.strip(), val.strip()))
    return sections


def _get_all(sections: dict, section: str, key: str) -> list[str]:
    """Get all values for a key that may appear multiple times."""
    return [v for k, v in sections.get(section, []) if k == key]


def _get_first(sections: dict, section: str, key: str) -> str | None:
    vals = _get_all(sections, section, key)
    return vals[0] if vals else None


# ── Structural validation ──────────────────────────────────────────

class TestQuadletStructure:
    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_container_has_required_sections(self, path):
        sections = parse_quadlet(path)
        for required in ("Container", "Service", "Install"):
            assert required in sections, f"{path.name}: missing [{required}]"

    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_container_has_image(self, path):
        sections = parse_quadlet(path)
        assert _get_first(sections, "Container", "Image"), f"{path.name}: missing Image="

    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_container_has_containername(self, path):
        sections = parse_quadlet(path)
        assert _get_first(sections, "Container", "ContainerName"), f"{path.name}: missing ContainerName="

    @pytest.mark.parametrize("path", NETWORK_FILES, ids=lambda p: p.name)
    def test_network_has_networkname(self, path):
        sections = parse_quadlet(path)
        assert _get_first(sections, "Network", "NetworkName"), f"{path.name}: missing NetworkName="

    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_container_has_network(self, path):
        sections = parse_quadlet(path)
        assert _get_first(sections, "Container", "Network"), f"{path.name}: missing Network="

    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_container_restart_always(self, path):
        sections = parse_quadlet(path)
        restart = _get_first(sections, "Service", "Restart")
        assert restart == "always", f"{path.name}: Restart should be 'always', got '{restart}'"


# ── Cross-reference validation ─────────────────────────────────────

def _container_network_names() -> dict[str, str]:
    result = {}
    for p in CONTAINER_FILES:
        sections = parse_quadlet(p)
        result[p.name] = _get_first(sections, "Container", "Network") or ""
    return result


def _network_names() -> set[str]:
    names = set()
    for p in NETWORK_FILES:
        sections = parse_quadlet(p)
        nn = _get_first(sections, "Network", "NetworkName")
        if nn:
            names.add(nn)
        # quadlet also allows referencing by filename (e.g. "starrstack.network")
        names.add(p.name)
    return names


def _container_names() -> dict[str, str]:
    result = {}
    for p in CONTAINER_FILES:
        sections = parse_quadlet(p)
        result[p.name] = _get_first(sections, "Container", "ContainerName") or ""
    return result


class TestCrossReferences:
    def test_network_references_exist(self):
        container_nets = _container_network_names()
        declared = _network_names()
        for container, net_ref in container_nets.items():
            assert net_ref in declared, (
                f"{container}: Network='{net_ref}' not in {declared}"
            )

    def test_no_duplicate_network_names(self):
        names = []
        for p in sorted(QUADLET_DIR.glob("*.network")):
            sections = parse_quadlet(p)
            nn = _get_first(sections, "Network", "NetworkName")
            if nn:
                names.append(nn)
        assert len(names) == len(set(names)), f"Duplicate NetworkName: {names}"

    def test_no_duplicate_container_names(self):
        names = list(_container_names().values())
        assert len(names) == len(set(names)), f"Duplicate ContainerName: {names}"

    def test_no_duplicate_port_mappings(self):
        seen: dict[int, str] = {}
        for p in CONTAINER_FILES:
            sections = parse_quadlet(p)
            for val in _get_all(sections, "Container", "PublishPort"):
                host_port = int(val.split(":")[0])
                assert host_port not in seen, (
                    f"Port {host_port} published by {seen[host_port]} and {p.name}"
                )
                seen[host_port] = p.name


# ── Value validation ───────────────────────────────────────────────

class TestContainerValues:
    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_publishport_format(self, path):
        sections = parse_quadlet(path)
        for val in _get_all(sections, "Container", "PublishPort"):
            for part in val.split(":"):
                assert part.isdigit(), f"{path.name}: PublishPort={val} bad segment '{part}'"

    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_volume_format(self, path):
        sections = parse_quadlet(path)
        for val in _get_all(sections, "Container", "Volume"):
            assert ":" in val, f"{path.name}: Volume={val} missing ':'"

    @pytest.mark.parametrize("path", CONTAINER_FILES, ids=lambda p: p.name)
    def test_environment_format(self, path):
        sections = parse_quadlet(path)
        for val in _get_all(sections, "Container", "Environment"):
            assert "=" in val, f"{path.name}: Environment={val} missing '='"
