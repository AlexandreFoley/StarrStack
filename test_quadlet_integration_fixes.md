# `test_quadlet_integration.py` — Fixes Plan

## Fix 1 — `podman load` targets host instead of harness container
**Bug — breaks image import entirely.**

Change:
```python
subprocess.Popen(["podman", "load"], stdin=subprocess.PIPE)
```
To:
```python
subprocess.Popen(["podman", "exec", "-i", container, "podman", "load"], stdin=subprocess.PIPE)
```

---

## Fix 2 — `running_harness` depends on `built_image` but never uses it

Remove `built_image` from the fixture signature. The starr image is already baked into
the harness via the `Dockerfile`'s `RUN podman build`, and the `session`-scoped `built_image`
pulling into a `module`-scoped fixture is a scope mismatch with no benefit.

---

## Fix 3 — `harness_image` mutates the committed `tests/harness/quadlet/` directory

`shutil.copytree` into `HARNESS_DIR / "quadlet"` clobbers the committed directory.
The cleanup `rmtree` at the end then deletes those committed files.

Replace with a `tempfile.TemporaryDirectory` as the build context: copy `HARNESS_DIR`
contents + quadlet files + `ubi.dockerfile` into the temp dir, build from there.

---

## Fix 4 — `harness_image` has no `try/finally` around the copy phase

If the build fails mid-copy, `quadlet_dst` is left behind dirtying the working tree.

Wrap the copy into `try/finally` so the working tree is always restored.

---

## Fix 5 — `communicate()` `TimeoutExpired` is unhandled

If the 120 s timeout fires, `communicate()` raises `TimeoutExpired` and
`qbittorrent_proc.returncode` is never checked — the fixture continues with a
partially-loaded image.

Wrap in `try/except subprocess.TimeoutExpired` → kill process + `pytest.fail(...)`.

---

## Fix 6 — Hard-coded `time.sleep(10)` / `time.sleep(20)` are fragile

Replace both sleeps with poll loops:

- After `podman run`: poll `_podman_exec(container, "systemctl", "is-system-running")`
  every 0.5 s up to ~60 s.
- After `systemctl start`: poll `_podman_exec(container, "podman", "ps", "--format",
  "{{.Names}}")` until both `starr` and `qbittorrent` appear (or deadline is hit).

---

## Fix 7 — `_wait_for_url` is an instance method that doesn't use `self`

Move to module level alongside `_run` / `_podman_exec`, and update the three call
sites inside `TestContainersFromQuadlet` from `self._wait_for_url(...)` to
`_wait_for_url(...)`.

---

## Fix 8 — Dead bash CMD passed to `podman run`

The Dockerfile sets `ENTRYPOINT ["/sbin/init"]`. The `"bash", "-c", "..."` block
passed after the image name becomes an *argument to systemd*, which ignores it.
The inline `systemctl daemon-reload` and `sleep infinity` are both dead code —
systemd keeps the container alive on its own, and daemon-reload is called again
via `_podman_exec` anyway.

Strip the bash arguments from `podman run`. The poll loop from Fix 6 replaces the
intent of the inline wait script entirely.

---

## Deferred

**Port conflicts** — `-p 7878:7878` etc. fail if those ports are already in use on
the host. Fix requires dynamic port binding (`-p 0:7878`), reading back assigned
ports with `podman port`, and threading them through the test classes. Not needed
for ephemeral per-job CI environments.
