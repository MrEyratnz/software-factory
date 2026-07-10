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

factory_initialized || allow
[ "$(field tool_name)" = "Bash" ] || allow
# Only while a release is in progress.
[ -f "$STATE_DIR/release-intent.json" ] || allow

cmd="$(field tool_input.command)"
proof_re="$(config_get releaseProofCommandRegex '')"
# No configured build+smoke command → nothing to key the proof on (fail safe).
# An explicitly-blanked regex must not match everything either.
[ -n "$proof_re" ] || allow

# Command-position, quote-aware classification (shared with record-green): the
# build must be a real command, not the pattern used as data ('grep "npm run
# build" …'), and its exit code certifies the build only if it is the last
# simple command (not masked by a pipe/`|| true`/`; echo`). This replaces the
# old blanket '#'/'|| true'/echo guards, which also refused a legitimate green
# build whose command merely contained a '#'.
cls="$(printf '%s' "$cmd" | node "$PLUGIN_ROOT/hooks/lib/classify-test-run.mjs" "$proof_re" 2>/dev/null)"
is_build="$(printf '%s' "$cls" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).testCommand))}catch(e){process.stdout.write("false")}})')"
[ "$is_build" = "true" ] || allow
clean="$(printf '%s' "$cls" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).cleanInvocation))}catch(e){process.stdout.write("false")}})')"

# The repo this build actually targets (issue #28), for the branch + tree.
target_root="$(repo_root "$(command_target_dir "$cmd")")"

# Only on the configured release branch.
relb="$(config_get releaseBranch 'main')"
cur_branch="$(cd "$target_root" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$cur_branch" ] && [ "$cur_branch" = "$relb" ] || allow

# Read the build+smoke exit status (numeric only). No exit-code evidence, or a
# masked pipeline the exit code doesn't certify → do not fabricate a proof (fail
# safe); we never re-execute an arbitrary build command.
ec="$(field tool_response.exitCode)"
[ -n "$ec" ] || ec="$(field tool_response.exit_code)"
[ -n "$ec" ] || ec="$(field tool_response.code)"
[ -n "$ec" ] || ec="$(field tool_response.returnCode)"
case "$ec" in ''|*[!0-9]*) allow ;; esac
[ "$ec" = "0" ] || allow
[ "$clean" = "true" ] || allow

tree="$(tree_hash "$target_root")"
[ -n "$tree" ] || allow

otel_emit factory_release_proof_total sum 1 '{"result":"mint"}'
mkdir -p "$STATE_DIR"
# Sign when a runner-only key is configured (issue #2); no-op passthrough else.
printf '{"ok":true,"tree":%s,"branch":%s}' "$(json_str "$tree")" "$(json_str "$relb")" \
  | receipt_embed_sig > "$STATE_DIR/release-proof.json"
allow
