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
# <refs-before-file> is the output of `git rev-list --all | sort -u`,
# captured BEFORE the session ran (an earlier step in the same job).
#
# Diffing against a pre-session snapshot — not `git rev-list --all --not
# <base-sha>` — is required: CI checks out with fetch-depth:0, so the
# workspace already holds every open PR/bot branch at job start. Comparing
# against the dispatch SHA counts ALL of that pre-existing unrelated history
# as "new" and the gate never fires (reproduced live: 38 unrelated commits
# from qa nightlies/release-please/other bots vs the 1 the session itself
# made). Diffing before/after the session step only counts commits created
# during THIS run, regardless of how much unrelated history was already
# fetched.
set -euo pipefail

before="$1"
if [ ! -s "$before" ]; then
  echo "::error::require-deliverable.sh: missing or empty pre-session ref snapshot at $before" >&2
  exit 1
fi

new_commits="$(comm -13 "$before" <(git rev-list --all | sort -u))"

if [ -z "$new_commits" ]; then
  echo "::error::factory-run session reported success but created no new commit anywhere in the workspace this run — no PR, no checkpoint update, nothing landed. Producing only a status report is a FAILURE per the conductor's mandate."
  exit 1
fi

touched_checkpoint=0
for c in $new_commits; do
  if git show --no-patch --name-only --pretty=format: "$c" | grep -qx 'factory-ops/state/checkpoint.json'; then
    touched_checkpoint=1
    break
  fi
done

count="$(printf '%s\n' "$new_commits" | grep -c .)"
if [ "$touched_checkpoint" = "1" ]; then
  echo "checkpoint.json changed in a new commit ($count new commit(s) this run) — real deliverable confirmed."
else
  echo "$count new commit(s) landed this run — real deliverable confirmed."
fi
