#!/usr/bin/env bash
# record-green — after a full suite command exits 0, write the tree-bound green
# receipt that guard-commit consumes. Advisory: always exit 0.
#
# The receipt is bound to `git write-tree` (not a timestamp), so any later edit
# to the source changes the tree and silently invalidates it — no separate
# invalidation hook needed.
. "$(dirname "$0")/../lib/common.sh"

[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
test_re="$(config_get testCommandRegex '(npm ((run|-s) )?test|node --test|vitest|pytest|go test|cargo test|make test)')"
printf '%s' "$cmd" | grep -Eq "$test_re" || allow

# Harden against forged green: refuse to mint a receipt for a command that only
# *mentions* the suite or neutralizes its exit status. This is not airtight
# (CI is the authoritative gate) but it closes the trivial forgeries:
#   echo/printf/: /true prefix, `|| true`, `; true`, `&& true`, `# …` comment.
trimmed="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]+//')"
case "$trimmed" in
  echo\ *|printf\ *|:\ *|true\ *|:|true) allow ;;
esac
printf '%s' "$cmd" | grep -Eq '(\|\||;|&&)[[:space:]]*(true|:)([[:space:]]|$)' && allow
printf '%s' "$cmd" | grep -Eq '#' && allow

# Read the command's exit status from the tool response (try known field names).
ec="$(field tool_response.exitCode)"
[ -n "$ec" ] || ec="$(field tool_response.exit_code)"
[ -n "$ec" ] || ec="$(field tool_response.code)"
[ -n "$ec" ] || ec="$(field tool_response.returnCode)"
# No exit-status evidence: rather than blindly re-executing the ARBITRARY
# already-run command (issue #27 — unsafe for anything non-idempotent, and the
# root of the "red receipt poisoning" when a non-test command merely *matched*
# testCommandRegex), invoke the repo's explicit, allowlisted `testCommand` and
# take its real exit code (issues #27, #35). `testCommand` comes only from the
# trust-root config, never from the agent's command string. With no configured
# invoker there is no safe way to determine green here, so fail safe: decline to
# mint a receipt (the commit gate stays closed until a suite with a real exit
# code runs).
if [ -z "$ec" ]; then
  tc="$(config_get testCommand '')"
  [ -n "$tc" ] || allow
  ( cd "$PROJECT_DIR" 2>/dev/null && eval "$tc" ) >/dev/null 2>&1; ec=$?
fi

tree="$(tree_hash)"
[ -n "$tree" ] || allow

receipt="$(printf '{"stages":[{"name":"suite","exitCode":%s}],"treeHash":%s}' "$ec" "$(json_str "$tree")" \
  | fc gate-evaluate \
  | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const o=JSON.parse(s);process.stdout.write(JSON.stringify({...o.receipt,ts:o.receipt.tree?1:0}))}catch(e){process.stdout.write("")}})')"

[ -n "$receipt" ] || allow

rok="$(printf '%s' "$receipt" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).ok))}catch(e){process.stdout.write("false")}})')"
otel_emit factory_gate_suite_total sum 1 "$(printf '{"result":"%s"}' "$([ "$rok" = "true" ] && echo pass || echo fail)")"

mkdir -p "$STATE_DIR"
printf '%s\n' "$receipt" > "$STATE_DIR/gate-receipt.json"
allow
