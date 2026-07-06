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

# Read the command's exit status from the tool response (try known field names).
ec="$(field tool_response.exitCode)"
[ -n "$ec" ] || ec="$(field tool_response.exit_code)"
[ -n "$ec" ] || ec="$(field tool_response.code)"
[ -n "$ec" ] || ec="$(field tool_response.returnCode)"
# No exit-status evidence → do not fabricate a green receipt (fail safe).
[ -n "$ec" ] || allow

tree="$(tree_hash)"
[ -n "$tree" ] || allow

receipt="$(printf '{"stages":[{"name":"suite","exitCode":%s}],"treeHash":%s}' "$ec" "$(json_str "$tree")" \
  | fc gate-evaluate \
  | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const o=JSON.parse(s);process.stdout.write(JSON.stringify({...o.receipt,ts:o.receipt.tree?1:0}))}catch(e){process.stdout.write("")}})')"

[ -n "$receipt" ] || allow
mkdir -p "$STATE_DIR"
printf '%s\n' "$receipt" > "$STATE_DIR/gate-receipt.json"
allow
