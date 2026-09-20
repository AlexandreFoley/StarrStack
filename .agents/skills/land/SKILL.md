---
name: land
description: >-
  Land the current StarrStack change to main via pull request. Only invoke
  this skill when the user has explicitly requested landing (for example by
  choosing Land Changes or asking to merge the current change); do not use
  it for review, preparation, passing checks, or skill installation alone.
metadata:
  delta-action: land
---

# Land the current change on main

This skill is already running because the user requested landing. Do not ask
again whether they want to merge. Carry out the workflow below and report the
verified outcome. Stop for genuine blockers or unsafe state; do not bypass
failing checks or overwrite unrelated work.

## Scope

- Repository: `AlexandreFoley/StarrStack` (GitHub, public, default branch `main`).
- Land the currently checked-out change (expected: branch
  `fix/alpine-openrc-cgroups`) onto `main` through a GitHub pull request.
- Merge strategy: regular merge commit, matching recent repository history
  (recent `main` history consists of `Merge pull request #N ...` commits).
- Conflict preference: resolve automatically only when the intended result is
  clear and unrelated work is preserved. On any ambiguous or unsafe conflict,
  stop and report without resolving.

## Preflight

1. Confirm the working tree matches the intended change: run
   `git --no-pager status --short --branch`. If unrelated uncommitted changes
   are present, stop and ask how to handle them.
2. Confirm the current branch and its commits versus `main`
   (`git log --oneline main..HEAD`). If HEAD is on `main` or there is nothing
   to land, stop and report that.
3. Do not open editors, run interactive rebases, or change branch protections.
   All commands must be non-interactive.

## Local verification

Run the repository's full test suite before publishing:

- `just test` (source: `Justfile` `test` target runs `.venv/bin/pytest tests/
  -v -ra -s` against both UBI and Alpine variants).

A passing local run is a preflight gate, not a substitute for remote CI.
If `just test` fails, stop and report; do not publish or land.

## Publish and open the pull request

1. Push the branch: `git push -u origin HEAD` (use the existing
   `fix/alpine-openrc-cgroups` name when already on it).
2. If a PR already exists for the branch, reuse it; otherwise create one with
   `gh pr create --base main`, using a title and summary derived from the
   branch commits. Keep the description factual and human-reviewable.
3. Record the PR number and URL from `gh pr view --json number,url`.

## Required remote verification

The repository's CI is the `Test` workflow (source:
`.github/workflows/test.yml`), which runs `test-ubi` via `just test-ubi`
(source: `Justfile` `test-ubi` target) and `test-alpine` via
`just test-alpine` (source: `Justfile` `test-alpine` target) on pushes and
pull requests.

1. Watch the PR checks to completion: `gh pr checks <PR> --watch`. If the
   watch mode is unavailable, poll `gh pr view --json statusCheckRollup` and
   `gh pr checks` until every check settles.
2. Require all checks on the PR head to pass. Pending, failing, missing, or
   unverifiable required checks are blockers: do not merge. Starting checks or
   seeing only some checks pass is not success.
3. If checks fail, stop and report the failing check and run links. Fix and
   re-verify only if the user asks for another landing attempt.

## Merge

1. Confirm the PR is mergeable (`gh pr view --json mergeable,mergeStateStatus`)
   and that its head is the verified commit.
2. Merge with a merge commit: `gh pr merge <PR> --merge`.
3. If the merge command reports conflicts or the PR becomes unmergeable, apply
   the conflict preference: fix only obvious conflicts, otherwise stop and
   report the conflict without landing.
4. If publication or merge is denied (permissions, protections, or other
   access errors), stop and report that the changes have not landed and what
   access is required.

## Verify the landing

Landing is complete only after all of the following hold:

1. `gh pr view <PR> --json state` reports `MERGED`.
2. The change is on `main`: `git fetch origin main` and confirm `origin/main`
   contains the PR head or merge commit (for example with
   `git merge-base --is-ancestor <sha> origin/main`).
3. The local tree is clean and consistent with the landed state.

## Outcome reporting

- When running in a subthread and `report_subthread_status` is available, use
  it to report the landing result to the parent; otherwise report directly in
  the current conversation.
- Use `status: "success"` only after the verification above confirms the
  change reached `main`. Use `status: "failure"` for failed attempts or
  genuine blockers (failed checks, denied push, unresolvable conflicts).
- A prepared commit, pushed branch, opened PR, or passing local build alone is
  not landing success.
- Keep `title` to a few sentence-case words and `description` to one short
  line. Link the merged commit with its short SHA and the CI run with its
  result, using verified URLs from the PR/checks output; omit links that
  cannot be verified. Example: `Landed on main` / `[bb9dba3](<commit-url>) ·
  [CI passed](<ci-run-url>).`
- Keep questions in the conversation, not the status event. Failure is not
  terminal: continue safe recovery when permitted and report the updated
  outcome after verification.
