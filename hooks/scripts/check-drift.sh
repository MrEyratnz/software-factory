#!/usr/bin/env bash
# check-drift (PostToolUse Edit/Write) — generated-artifact drift fails at edit
# time, not only in CI. If an edited file is a generated-artifact SOURCE (per
# .factory/config.json "generators"), regenerate and diff the output; on drift,
# block with instructions to regenerate + stage. Non-generator edits: allow.
. "$(dirname "$0")/../lib/common.sh"

case "$(field tool_name)" in Write|Edit|MultiEdit) ;; *) allow ;; esac
fp="$(field tool_input.file_path)"
[ -n "$fp" ] || allow

gens="$(config_get generators '[]')"
[ "$gens" = "[]" ] && allow

# Find a generator whose sourceRegex matches the edited path.
match="$(GENS="$gens" FP="$fp" node -e '
  let gens=[]; try{gens=JSON.parse(process.env.GENS)}catch(e){}
  const fp=process.env.FP;
  const g=gens.find(g=>{try{return new RegExp(g.sourceRegex).test(fp)}catch(e){return false}});
  process.stdout.write(g?JSON.stringify(g):"");
')"
[ -n "$match" ] || allow

cmd="$(printf '%s' "$match" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).command||"")}catch(e){}})')"
out="$(printf '%s' "$match" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).output||"")}catch(e){}})')"
[ -n "$cmd" ] || allow

( cd "$PROJECT_DIR" 2>/dev/null && sh -c "$cmd" >/dev/null 2>&1 )
if ! ( cd "$PROJECT_DIR" 2>/dev/null && git diff --quiet -- "$out" 2>/dev/null ); then
  deny "generated artifact '$out' drifted after editing its source — regenerate ('$cmd') and stage the result"
fi
allow
