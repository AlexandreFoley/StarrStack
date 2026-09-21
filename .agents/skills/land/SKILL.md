---
name: land
description: >-
  Land the current StarrStack change to main: push the branch, open the pull
  request, verify CI, then hand the PR to the user to merge. Only invoke this
  skill when the user has explicitly requested landing (for example by
  choosing Land Changes or asking to merge the current change); do not use it
  for review, preparation, passing checks, or skill installation alone.
metadata:
  delta-action: land
---

# Land the current change on main

This skill is already running because the user requested landing. Do not ask
again whether they want to land the change. Carry out the workflow below and
report the verified outcome. Stop for genuine blockers or unsafe state; do not
bypass failing checks, branch rules, or required reviews, and do not overwrite
unrelated work. The merge itself is the user's action: this workflow ends with
a verified, merge-ready pull request.

## Scope

- Repository: `AlexandreFoley/StarrStack` (GitHub, public, default branch `main`).
- Land the currently checked-out change through a GitHub pull request: push the
  branch, open (or reuse) the PR, verify CI, and hand the PR to the user.
- Merge strategy: the user merges with a regular merge commit, matching recent
  repository history (`Merge pull request #N ...`). The agent never merges.
- Never bypass branch rules: no `gh pr merge`, no `--admin`, no `--auto`, no
  changing branch protections or rulesets, no pushing past a required review.
  A `BLOCKED` merge state with `REVIEW_REQUIRED` while every check passes is
  the expected hand-off state, not a failure.
- Conflict preference: resolve automatically only when the intended result is
  clear and unrelated work is preserved. On any ambiguous or unsafe conflict,
  stop and report without resolving.

## Preflight

1. Confirm the working tree matches the intended change: run
   `git --no-pager status --short --branch`. If unrelated uncommitted changes
   are present, stop and ask how to handle them.
2. Confirm the current branch and its commits versus `main`: `git fetch origin
   main`, then `git log --oneline origin/main..HEAD` (the local `main` ref is
   not always current). If HEAD is on `main` or there is nothing to land, stop
   and report that.
3. Do not open editors, run interactive rebases, or change branch protections
   or rulesets. All commands must be non-interactive.

## Local verification

Run the repository's full test suite before publishing:

- `just test` (source: `Justfile` `test` target runs `.venv/bin/pytest tests/
  -v -ra -s` against both UBI and Alpine variants).

A passing local run is a preflight gate, not a substitute for remote CI.
If `just test` fails, stop and report; do not publish or land.

## Publish and open the pull request

1. Push the branch: `git push -u origin HEAD`.
2. If a PR already exists for the branch, reuse it; otherwise create one with
   `gh pr create --base main`, using a title and summary derived from the
   branch commits. Keep the description factual and human-reviewable.
3. Record the PR number and URL from `gh pr view --json number,url`.

## Required remote verification

The repository's CI runs on pull requests: the `Test` workflow (source:
`.github/workflows/test.yml`) runs `test-ubi` via `just test-ubi` (source:
`Justfile` `test-ubi` target), `test-alpine` via `just test-alpine` (source:
`Justfile` `test-alpine` target), `test-openrc-docker`, and a `changes` gate,
alongside the lint/security workflows (`actionlint`, `zizmor`).

1. Watch the PR checks to completion: `gh pr checks <PR> --watch`. If the
   watch mode is unavailable, poll `gh pr view --json statusCheckRollup` and
   `gh pr checks` until every check settles.
2. Require every check on the PR head to pass. Pending, failing, missing, or
   unverifiable required checks are blockers: stop and report, never hand off
   or merge. Starting checks or seeing only some checks pass is not success.
3. If checks fail, stop and report the failing check and run links. Fix and
   re-verify only if the user asks for another landing attempt.

## Hand off the verified pull request, do not merge

1. Confirm the PR head is the commit whose checks passed: `gh pr view <PR>
   --json headRefOid` must equal the local `git rev-parse HEAD`.
2. Confirm the PR is mergeable (`gh pr view <PR> --json
   mergeable,mergeStateStatus`). `BLOCKED` from a required review is expected:
   the user resolves it when they press merge. Only a real conflict or an
   unmergeable PR is a problem; if a conflict is not obviously resolvable, stop
   and report it.
3. Never merge and never bypass: no `gh pr merge`, no `--admin`, no `--auto`,
   no approving the PR, no changing branch protections or rulesets. The user
   presses the merge button.
4. Report the PR as ready to merge — number, URL, head commit, check results —
   and state plainly that the merge is the user's action.

## Outcome reporting

- When running in a subthread and `report_subthread_status` is available, use
  it to report to the parent; otherwise report directly in the current
  conversation.
- Use `status: "success"` when every step this skill permits is verified: the
  branch is pushed, the PR is open, and every check passes on the verified
  head. Say that the PR is ready to merge; do not claim the change landed on
  `main` — the user merges after the hand-off.
- Use `status: "failure"` for failed checks, a denied push, unresolvable
  conflicts, or any state that needs the user to decide.
- Keep `title` to a few sentence-case words and `description` to one short
  line. Link the PR and the CI run with verified URLs from the PR/checks
  output and note that the merge is pending on the user; omit links that
  cannot be verified. Example: `PR ready to merge` / `[#22](<pr-url>) · [CI
  passed](<ci-run-url>) · merge button is the user's.`
- Keep questions in the conversation, not the status event. Failure is not
  terminal: continue safe recovery when permitted, within the rules above, and
  report the updated outcome after verification.
