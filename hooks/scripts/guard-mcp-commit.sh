#!/usr/bin/env bash
# guard-mcp-commit — never commit red, closed on the github-MCP write path too.
#
# guard-commit only matches the Bash tool, so a server-side content write via
# mcp__github__create_or_update_file / mcp__github__push_files / mcp__github__
# delete_file (a delete is a commit too — it changes tree content) never sees
# the tests-first / green-receipt / conventional-commit-lint gate: those tools
# write server-side, with no local working tree to bind a `git write-tree`
# receipt to, so the check cannot be retrofitted onto them. Rather than compose
# a check that doesn't hold, this hook owns the NON-release regime: it DENIES
# all three content-write tools and tells the agent to use local `git commit`
# (which guard-commit gates).
#
# Two regimes, one arbiter each: while a release is in progress
# (.factory/state/release-intent.json present), guard-release is the SOLE
# arbiter for these same three tools — it enforces branch==release-branch,
# a release-gate proof, and a fresh tree-bound gate-receipt. This hook simply
# steps aside (allow) whenever release-intent exists, purely on the file's
# existence; it does not itself check branch or freshness, since guard-release
# already does and duplicating it here would just be two places to keep in
# sync. Outside a release, this hook is the sole arbiter and denies.
# The lifecycle of release-intent.json (who creates/clears it, and when) is a
# guard-release/ship concern tracked separately — this hook only reacts to
# whether the file is present right now.
. "$(dirname "$0")/../lib/common.sh"

respect_pause guard-mcp-commit
require_initialized guard-mcp-commit
tn="$(field tool_name)"
case "$tn" in
  mcp__github__create_or_update_file|mcp__github__push_files|mcp__github__delete_file) ;;
  *) allow ;;
esac

[ -f "$STATE_DIR/release-intent.json" ] && allow

deny "commits must go through local 'git commit' so the factory gate (tests-first + green receipt + conventional-commit lint) applies — the github-MCP file-write path bypasses it; use git, or a release verb under guard-release"
