#!/usr/bin/env bash
# require-deliverable.sh — factory-run's own mandate (see factory-run.yml's
# prompt) is a commit and a PR: "producing only a status report is a
# FAILURE". `claude -p`'s is_error guard cannot see that failure mode — the
# CLI exits cleanly (end_turn) even when the session did nothing but orient
# and stop (observed live: GH Actions run 30490944976, 2026-07-29 — oriented,
# hit a couple of Bash permission_denials on raw plumbing commands, answered
# with a status dashboard, quit; no commit, no PR, no checkpoint update, four
# days stale while cron re-dispatched hourly).
#
# Usage: require-deliverable.sh <refs-before-file>
# Must run from the git workspace the session ran in, AFTER the session step.
# <refs-before-file> is the output of `git rev-list --branches HEAD | sort -u`,
# captured BEFORE the session ran (an earlier step in the same job).
#
# What counts as a real deliverable, enforced in three layers (each one is a
# reviewed failure mode of an earlier, weaker version of this gate):
#
#   1. The session created at least one commit of its own. Measured as new
#      commits reachable from LOCAL heads (--branches HEAD) versus the
#      pre-session snapshot — not `--all`, and not `--not <dispatch-sha>`:
#      fetch-depth:0 already holds every open PR/bot branch at job start
#      (the SHA comparison never fired — 38 unrelated commits vs the 1 a
#      session makes), and a mid-session `git fetch` of a concurrent bot
#      push lands in refs/remotes only, so scoping to local heads keeps
#      other actors' work from counting as this session's (#486).
#
#   2. At least one of those commits actually reached GitHub. A local-only
#      commit whose push/PR step then failed (the cited incident hit
#      permission_denials on exactly such plumbing) advances nothing — the
#      loop is still stalled, just with a prettier workspace (#484).
#      Measured as membership in the origin remote-ref set: a session's own
#      pushed commits appear there via the updated remote-tracking ref,
#      while concurrent bot commits are not in the session-commit set from
#      layer 1, so neither false-negative nor false-positive.
#
#   3. The pushed work is more than the mandatory end-of-run checkpoint
#      bump. The mandate's step 4 requires a `chore:` checkpoint commit on
#      EVERY run, so "committed only checkpoint.json" is the incident
#      behavior plus one commit — not roadmap progress — and must not be
#      reported to the operator as "real deliverable confirmed" (#485).
set -euo pipefail

before="$1"
if [ ! -s "$before" ]; then
  echo "::error::require-deliverable.sh: missing or empty pre-session ref snapshot at $before" >&2
  exit 1
fi

CHECKPOINT_PATH="factory-ops/state/checkpoint.json"

session_commits="$(comm -13 "$before" <(git rev-list --branches HEAD | sort -u))"

if [ -z "$session_commits" ]; then
  echo "::error::factory-run session reported success but created no commit this run — no PR, no checkpoint update, nothing landed. Producing only a status report is a FAILURE per the conductor's mandate. Next: read the session transcript artifact for why it stopped; the hourly cron will re-dispatch."
  exit 1
fi

remote_commits="$(git rev-list --remotes=origin 2>/dev/null | sort -u)"
pushed="$(comm -12 <(printf '%s\n' "$session_commits") <(printf '%s\n' "$remote_commits"))"

if [ -z "$pushed" ]; then
  echo "::error::factory-run session committed locally but nothing reached origin — the push (or PR creation) failed, so the loop has not advanced. Check the session transcript for push/auth errors (the cited incident hit permission_denials on exactly this plumbing)."
  exit 1
fi

work=0
touched_checkpoint=0
for c in $pushed; do
  files="$(git diff-tree --no-commit-id --name-only -r "$c")"
  if printf '%s\n' "$files" | grep -qxF "$CHECKPOINT_PATH"; then
    touched_checkpoint=1
  fi
  if printf '%s\n' "$files" | grep -qvxF "$CHECKPOINT_PATH"; then
    work=1
  fi
done

if [ "$work" = "0" ]; then
  echo "::error::factory-run session pushed only a checkpoint.json bump — the mandatory end-of-run bookkeeping, not roadmap work. The loop has not advanced. (If this run legitimately parked on a usage limit, that exemption is tracked as #487.)"
  exit 1
fi

count="$(printf '%s\n' "$pushed" | grep -c .)"
if [ "$touched_checkpoint" = "1" ]; then
  echo "$count pushed commit(s) with roadmap work + checkpoint updated — real deliverable confirmed."
else
  echo "$count pushed commit(s) with roadmap work landed (checkpoint.json not updated — the mandate's step 4 wants it; not blocking)."
fi
