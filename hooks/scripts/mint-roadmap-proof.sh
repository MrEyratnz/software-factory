#!/usr/bin/env bash
# mint-roadmap-proof — the sanctioned producer of .factory/state/roadmap-proof.json
# (issue #51). Before this, NOTHING wrote that file outside the contract tests,
# so guard-roadmap's merged-green requirement could never be satisfied by a real
# workflow — `/roadmap check` had no in-repo path to succeed.
#
# This is NOT a hook: it is a CLI the RUNNER / CI invokes (the same trust model
# as FACTORY_RECEIPT_KEY — direct filesystem access, not gated). It refuses to
# mint unless GITHUB confirms the facts, so the trust anchor is the GitHub API,
# not the caller's claims:
#   1. the named roadmap item exists in the roadmap file,
#   2. the PR is MERGED into the configured release branch,
#   3. every check run on the merge commit completed green (success/neutral/
#      skipped) — and at least one check run exists.
# When a receipt key is configured the proof is HMAC-signed over its OWN payload
# (mergedGreenSha:item — receipt_embed_sig's ok+tree fields would degenerate to
# a constant here, making one old signature a skeleton key), and guard-roadmap
# rejects an unsigned/invalid proof. With the key kept runner-private, a policed
# agent invoking this script cannot mint a proof the gate will accept unless
# GitHub really confirms the merge — and cannot hand-write one at all.
#
# Usage: mint-roadmap-proof.sh [--repo <dir>] [--pr <number>] <exact item text>
#   --repo  repo to mint for (default: $CLAUDE_PROJECT_DIR or the cwd)
#   --pr    the PR that shipped the item; when omitted, derived from the item's
#           "(#N)" issue reference via GitHub's linked-issue data (the most
#           recently merged PR that GitHub records as closing issue N)
# Exit: 0 minted · 2 refused (reason on stderr).
set -u

die() { printf 'mint-roadmap-proof: %s\n' "$1" >&2; exit 2; }

pr=""
repo_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr) [ "$#" -ge 2 ] || die "--pr needs a value"; pr="$2"; shift 2 ;;
    --pr=*) pr="${1#--pr=}"; shift ;;
    --repo) [ "$#" -ge 2 ] || die "--repo needs a value"; repo_dir="$2"; shift 2 ;;
    --repo=*) repo_dir="${1#--repo=}"; shift ;;
    --) shift; break ;;
    -*) die "unknown flag: $1" ;;
    *) break ;;
  esac
done
item="$*"
[ -n "$item" ] || die "usage: mint-roadmap-proof.sh [--repo <dir>] [--pr <number>] <exact item text>"
case "$pr" in ''|*[!0-9]*) [ -z "$pr" ] || die "--pr must be a number" ;; esac

if [ -n "$repo_dir" ]; then
  cd "$repo_dir" 2>/dev/null || die "cannot cd to --repo $repo_dir"
  CLAUDE_PROJECT_DIR="$PWD"; export CLAUDE_PROJECT_DIR
else
  CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"; export CLAUDE_PROJECT_DIR
fi

# A CLI, not a hook: pre-seed HOOK_INPUT so common.sh does not block on stdin.
# (shellcheck sees it as unused, but common.sh reads it after the source.)
# shellcheck disable=SC2034
HOOK_INPUT='{}'
. "$(dirname "$0")/../lib/common.sh"

command -v gh >/dev/null 2>&1 || die "gh is required (the proof is verified against GitHub)"
command -v node >/dev/null 2>&1 || die "node is required"
factory_initialized || die "this repo is not factory-initialized (no .factory/config.json)"

# 1. The item must exist in the roadmap AS A CHECKBOX ITEM — a raw substring
#    match could hit a heading or another item's prose; anchor to checkbox
#    lines (the same shape guard-roadmap extracts) and exact-match the text.
roadmap="$PROJECT_DIR/$(config_get roadmapPath 'docs/ROADMAP.md')"
[ -f "$roadmap" ] || die "no roadmap at $roadmap"
grep -E '^[[:space:]]*[-*][[:space:]]+\[[ xX]\]' "$roadmap" \
  | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[[ xX]\][[:space:]]*//' \
  | grep -qFx -- "$item" || die "no checkbox item with this exact text in $roadmap: $item"

# 2. Resolve the PR. --pr is the explicit, deterministic path (CI knows its own
#    PR number). Without it, the item's "(#N)" issue reference is resolved via
#    GitHub's LINKED-ISSUE data (closedByPullRequestsReferences) — not a
#    free-text body search, which would bind the proof to any merged PR that
#    merely mentions #N (a follow-up, a revert, a "see #N for context").
if [ -z "$pr" ]; then
  num="$(printf '%s' "$item" | grep -oE '\(#[0-9]+\)' | head -1 | tr -dc '0-9')"
  [ -n "$num" ] || die "no --pr given and the item carries no (#N) issue reference to derive one"
  nwo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
  [ -n "$nwo" ] || die "cannot resolve the repository (gh repo view failed)"
  pr="$(gh api graphql \
        -f query='query($owner:String!,$name:String!,$num:Int!){repository(owner:$owner,name:$name){issue(number:$num){closedByPullRequestsReferences(first:100,includeClosedPrs:true){nodes{number merged mergedAt}}}}}' \
        -f owner="${nwo%%/*}" -f name="${nwo##*/}" -F num="$num" \
        --jq '[.data.repository.issue.closedByPullRequestsReferences.nodes[] | select(.merged)] | sort_by(.mergedAt) | reverse | .[0].number // empty' 2>/dev/null)"
  [ -n "$pr" ] || die "no merged PR is linked as closing #$num — pass --pr explicitly"
fi

# 3. GitHub facts: merged, into the release branch, with a merge commit.
relb="$(config_get releaseBranch 'main')"
facts="$(gh pr view "$pr" --json state,baseRefName,mergeCommit \
         --jq '[.state, .baseRefName, (.mergeCommit.oid // "")] | join(" ")' 2>/dev/null)"
[ -n "$facts" ] || die "gh pr view $pr failed"
state="$(printf '%s' "$facts" | cut -d' ' -f1)"
base="$(printf '%s' "$facts" | cut -d' ' -f2)"
sha="$(printf '%s' "$facts" | cut -d' ' -f3)"
[ "$state" = "MERGED" ] || die "PR #$pr is not merged (state: $state)"
[ "$base" = "$relb" ] || die "PR #$pr merged into '$base', not the release branch '$relb'"
case "$sha" in
  *[!0-9a-f]*|'') die "PR #$pr has no usable merge commit SHA ('$sha')" ;;
esac
[ "${#sha}" -ge 7 ] || die "PR #$pr merge commit SHA too short ('$sha')"

# 4. Every check run on the merge commit is green; zero check runs is NOT green
#    (a repo with CI configured but not yet reported must not mint).
checks="$(gh api "repos/{owner}/{repo}/commits/$sha/check-runs" --paginate \
          --jq '.check_runs[] | .status + ":" + (.conclusion // "")' 2>/dev/null)"
[ -n "$checks" ] || die "no check runs found on $sha — cannot certify merged-green"
bad="$(printf '%s\n' "$checks" | grep -vE '^completed:(success|neutral|skipped)$' || true)"
[ -z "$bad" ] || die "check runs on $sha are not all green: $(printf '%s' "$bad" | tr '\n' ' ')"

# 5. Mint the item-bound proof (signed over mergedGreenSha:item when a
#    runner-only key is configured — see roadmap_proof_embed_sig).
mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
printf '{"mergedGreenSha":%s,"item":%s}' "$(json_str "$sha")" "$(json_str "$item")" \
  | roadmap_proof_embed_sig > "$STATE_DIR/roadmap-proof.json"
# Never report "minted" on a write that produced nothing (a future change to
# the sig helper must not be able to turn this into a silent success).
grep -q '"mergedGreenSha"' "$STATE_DIR/roadmap-proof.json" 2>/dev/null \
  || die "proof write failed — $STATE_DIR/roadmap-proof.json is empty or malformed"
printf 'minted roadmap proof: %s ← PR #%s (%s)\n' "$sha" "$pr" "$item"
exit 0
