#!/usr/bin/env bash
# record-release-proof — the sanctioned producer of .factory/state/release-proof.json
# (issue #14). Before this, release-proof.json was written only by the contract
# test harness, so guard-release's `.ok==true` requirement could never be
# satisfied by a real release in prod — the MCP release path was effectively
# always denied and the intended producer was unspecified.
#
# This mirrors record-green, but mints the RELEASE gate proof: after the
# release-captain runs the build+smoke command on the BUILT artifact and it
# exits 0, on the release branch, while a release is in progress, write the
# tree-bound proof. Advisory: always exit 0. Not hand-writable by the agent
# (guard-scope/guard-bash-writes block it); best-effort like record-green, with
# CI the authoritative boundary.
. "$(dirname "$0")/../lib/common.sh"

[ "$(field tool_name)" = "Bash" ] || allow
# Only while a release is in progress.
[ -f "$STATE_DIR/release-intent.json" ] || allow

cmd="$(field tool_input.command)"
proof_re="$(config_get releaseProofCommandRegex '')"
# No configured build+smoke command → nothing to key the proof on (fail safe).
[ -n "$proof_re" ] || allow
printf '%s' "$cmd" | grep -Eq "$proof_re" || allow

# Same forgery guards as record-green: a command that only *mentions* the build
# or neutralizes its exit status must not mint a proof.
trimmed="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]+//')"
case "$trimmed" in
  echo\ *|printf\ *|:\ *|true\ *|:|true) allow ;;
esac
printf '%s' "$cmd" | grep -Eq '(\|\||;|&&)[[:space:]]*(true|:)([[:space:]]|$)' && allow
printf '%s' "$cmd" | grep -Eq '#' && allow

# The repo this build actually targets (issue #28), for the branch + tree.
target_root="$(repo_root "$(command_target_dir "$cmd")")"

# Only on the configured release branch.
relb="$(config_get releaseBranch 'main')"
cur_branch="$(cd "$target_root" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$cur_branch" ] && [ "$cur_branch" = "$relb" ] || allow

# Read the build+smoke exit status. No exit-code evidence → do not fabricate a
# proof (fail safe); we never re-execute an arbitrary build command.
ec="$(field tool_response.exitCode)"
[ -n "$ec" ] || ec="$(field tool_response.exit_code)"
[ -n "$ec" ] || ec="$(field tool_response.code)"
[ -n "$ec" ] || ec="$(field tool_response.returnCode)"
[ -n "$ec" ] || allow
[ "$ec" = "0" ] || allow

tree="$(tree_hash "$target_root")"
[ -n "$tree" ] || allow

otel_emit factory_release_proof_total sum 1 '{"result":"mint"}'
mkdir -p "$STATE_DIR"
printf '{"ok":true,"tree":%s,"branch":%s}\n' "$(json_str "$tree")" "$(json_str "$relb")" > "$STATE_DIR/release-proof.json"
allow
