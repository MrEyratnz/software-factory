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
# <refs-before-file> is the output of
# `git rev-list --branches --remotes HEAD | sort -u`, captured BEFORE the
# session ran (an earlier step in the same job). Remotes are IN the
# snapshot deliberately: anything already on origin at session start —
# including a pre-existing bot branch the session later DWIM-checkouts, or
# history a pull fast-forwards in — must never count as this session's own
# work (#564); only commits that did not exist anywhere at snapshot time do.
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
#      EVERY run, so "committed only checkpoint.json" is not roadmap
#      progress and must not read as "real deliverable confirmed" (#485).
#      This layer WARNS rather than fails: a pushed checkpoint-only commit
#      is also exactly the mandated usage-limit / roadmap-complete park
#      ("checkpoint, commit chore:, never red on a limit" — CLAUDE.md and
#      the conductor prompt's own step 4), and the gate cannot distinguish
#      a legitimate park from a lazy run without stop-reason detection
#      (#487). Layers 1+2 still hard-fail the actual observed incident
#      (no commit at all / nothing pushed).
set -euo pipefail

before="$1"
if [ ! -s "$before" ]; then
  echo "::error::require-deliverable.sh: missing or empty pre-session ref snapshot at $before" >&2
  exit 1
fi

CHECKPOINT_PATH="factory-ops/state/checkpoint.json"

session_commits="$(comm -13 "$before" <(git rev-list --branches HEAD | sort -u))"

# Of the post-snapshot commits, only ones committed under THIS session's
# git identity count as its own work: a mid-session `git pull` absorbs
# commits other actors pushed AFTER the snapshot straight into local
# heads, and the snapshot cannot exclude what did not exist yet — the
# committer identity (set by the "session identity" step) is the property
# a foreign actor's commit cannot share. (A pull's own merge commit does
# carry our identity, but it lists no files, so it classifies as a park,
# never as roadmap work.)
me="$(git config user.email 2>/dev/null || true)"
if [ -z "$me" ]; then
  echo "::error::session git identity (user.email) is unset — commits cannot be attributed to this session, so the gate fails closed rather than crediting foreign work (#681)."
  exit 1
fi
own=""
for c in $session_commits; do
  if [ "$(git show -s --format=%ce "$c")" = "$me" ]; then
    own="${own}${c}
"
  fi
done
session_commits="$(printf '%s' "$own")"

if [ -z "$session_commits" ]; then
  echo "::error::factory-run session reported success but created no commit this run — no PR, no checkpoint update, nothing landed. Producing only a status report is a FAILURE per the conductor's mandate. Next: read the session transcript artifact for why it stopped; the hourly cron will re-dispatch."
  exit 1
fi

# Classify the session's OWN commits into roadmap work vs checkpoint-only
# BEFORE any push check (#556): CLAUDE.md's usage-limit protocol mandates
# "write checkpoint.json, commit chore:, exit 0" — with no push step — so a
# LOCAL-only checkpoint park is the documented good-citizen behavior and
# must never red. Only real work stranded unpushed is a stall.
has_work() {
  local c files
  for c in $1; do
    files="$(git diff-tree --no-commit-id --name-only -r "$c")"
    # A merge or --allow-empty commit lists no files at all; without this
    # guard the empty string reads as a phantom non-checkpoint line and
    # counts as work (#515).
    [ -z "$files" ] && continue
    if printf '%s\n' "$files" | grep -qvxF "$CHECKPOINT_PATH"; then
      return 0
    fi
  done
  return 1
}

if ! has_work "$session_commits"; then
  echo "::warning::factory-run session committed only a checkpoint.json bump (pushed or not) — the mandated park (usage limit / roadmap complete / waiting on CI), not roadmap progress. Legitimate as a park; if this repeats across consecutive wakes with no roadmap work, the loop is stalled. Stop-reason-aware enforcement is tracked as #487."
  exit 0
fi

remote_commits="$(git rev-list --remotes=origin 2>/dev/null | sort -u)"
pushed="$(comm -12 <(printf '%s\n' "$session_commits") <(printf '%s\n' "$remote_commits"))"

# Local work that never reached origin WARNS, not reds (#676): CLAUDE.md's
# park protocol is commit-then-exit with no mandated push, so this shape is
# indistinguishable from a legitimate mid-work limit park — and "never red
# on a limit" wins. The warning names both readings so the operator can
# tell them apart from the transcript; repeat-park escalation is #487.
if [ -z "$pushed" ] || ! has_work "$pushed"; then
  echo "::warning::factory-run session produced roadmap work locally but none of it reached origin — either a mid-work usage-limit park (legitimate; the hourly cron resumes it) or a failed push. Not red, per the never-red-on-a-limit law; check the session transcript to distinguish. Stop-reason-aware enforcement is tracked as #487."
  exit 0
fi

# Layer 4 (#644): the mandate is a commit AND a pull request. Pushed WORK
# commits (checkpoint bumps never vouch for stranded work — #678) count
# only if one either already landed on origin's default branch (merged or
# pushed there directly — strictly better than an open PR) or an open or
# merged PR's head branch carries it. A push that succeeded while
# `gh pr create` failed (rate limit, permission denial — the cited
# incident's exact failure class) is stranded work, not a deliverable.
# Fetch first so a PR merged while the session ran is visible (#677).
git fetch origin --quiet 2>/dev/null || true
default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
default_branch="${default_branch:-main}"
pr_ok=0
gh_failed=0
for c in $pushed; do
  has_work "$c" || continue
  if git merge-base --is-ancestor "$c" "origin/$default_branch" 2>/dev/null; then
    pr_ok=1
    break
  fi
done
if [ "$pr_ok" = "0" ]; then
  for c in $pushed; do
    has_work "$c" || continue
    for b in $(git branch --format='%(refname:short)' --contains "$c" 2>/dev/null); do
      if n="$(gh pr list --state all --head "$b" --json state --jq '[.[] | select(.state == "OPEN" or .state == "MERGED")] | length' 2>/dev/null)"; then
        if [ "${n:-0}" != "0" ]; then
          pr_ok=1
          break 2
        fi
      else
        # An API failure is inconclusive, not proof of no PR (#679) —
        # a transient rate-limit/5xx must not red a completed run.
        gh_failed=1
      fi
    done
  done
fi
if [ "$pr_ok" = "0" ]; then
  if [ "$gh_failed" = "1" ]; then
    echo "::warning::factory-run pushed roadmap work but the PR-existence check was inconclusive (GitHub API error on gh pr list) — not failing on a transient API error. Verify a PR exists for the pushed branch if this warning repeats."
  else
    echo "::error::factory-run session pushed roadmap work, but no open or merged PR carries it and it has not landed on origin/$default_branch — the mandate is a commit AND a pull request. Check the session transcript for gh pr create failures or permission denials (the cited incident's exact failure class)."
    exit 1
  fi
fi

touched_checkpoint=0
for c in $pushed; do
  if git diff-tree --no-commit-id --name-only -r "$c" | grep -qxF "$CHECKPOINT_PATH"; then
    touched_checkpoint=1
    break
  fi
done

count="$(printf '%s\n' "$pushed" | grep -c .)"
if [ "$touched_checkpoint" = "1" ]; then
  echo "$count pushed commit(s) with roadmap work + checkpoint updated — real deliverable confirmed."
else
  echo "$count pushed commit(s) with roadmap work landed (checkpoint.json not updated — the mandate's step 4 wants it; not blocking)."
fi
