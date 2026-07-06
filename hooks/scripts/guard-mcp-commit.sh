#!/usr/bin/env bash
# guard-mcp-commit — never commit red, closed on the github-MCP write path too.
#
# guard-commit only matches the Bash tool, so a commit made via
# mcp__github__create_or_update_file / mcp__github__push_files never sees the
# tests-first / green-receipt / conventional-commit-lint gate: those tools
# write server-side, with no local working tree to bind a `git write-tree`
# receipt to, so the check cannot be retrofitted onto them. Rather than compose
# a check that doesn't hold, this hook DENIES the MCP file-write path outright
# and tells the agent to use local `git commit` (which guard-commit gates).
#
# guard-release ALSO matches these two tools, but only while a release is in
# progress (.factory/state/release-intent.json present) — that is a distinct,
# already-gated verb (release cut via the github-MCP push/merge substrate), not
# a raw file commit. So: if release-intent exists, this hook steps aside
# (allow) and lets guard-release own the decision; otherwise it denies. Ordering
# in hooks.json doesn't matter for correctness since each hook only vetoes its
# own tool_name/state combination and any exit 2 from any hook blocks the call,
# but both are listed on the same matcher block for a single review of intent.
. "$(dirname "$0")/../lib/common.sh"

tn="$(field tool_name)"
case "$tn" in
  mcp__github__create_or_update_file|mcp__github__push_files) ;;
  *) allow ;;
esac

[ -f "$STATE_DIR/release-intent.json" ] && allow

deny "commits must go through local 'git commit' so the factory gate (tests-first + green receipt + conventional-commit lint) applies — the github-MCP file-write path bypasses it; use git, or a release verb under guard-release"
