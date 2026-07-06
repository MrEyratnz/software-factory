#!/usr/bin/env bash
# check-drift (PostToolUse Edit/Write) — remind the agent to regenerate a
# generated artifact when its SOURCE is edited. ADVISORY ONLY: it never executes
# a command from config (config is repo/agent content; shell-evaluating it would
# be arbitrary code execution triggered by an ordinary edit). The AUTHORITATIVE
# drift gate is CI's `git diff --exit-code` after regeneration; this hook only
# nudges so drift is noticed at edit time.
. "$(dirname "$0")/../lib/common.sh"

case "$(field tool_name)" in Write|Edit|MultiEdit) ;; *) allow ;; esac
fp="$(field tool_input.file_path)"
[ -n "$fp" ] || allow

gens="$(config_get generators '[]')"
[ "$gens" = "[]" ] && allow

# Find a generator whose sourceRegex matches the edited path (matching only —
# no command is executed here).
match="$(GENS="$gens" FP="$fp" node -e '
  let gens=[]; try{gens=JSON.parse(process.env.GENS)}catch(e){}
  const fp=process.env.FP;
  const g=gens.find(g=>{try{return new RegExp(g.sourceRegex).test(fp)}catch(e){return false}});
  process.stdout.write(g?JSON.stringify({command:g.command||"",output:g.output||""}):"");
')"
[ -n "$match" ] || allow

cmd="$(printf '%s' "$match" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).command||"")}catch(e){}})')"
out="$(printf '%s' "$match" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).output||"")}catch(e){}})')"

inject_context "You edited a generated-artifact source ($fp). Regenerate '$out' (run: $cmd) and stage the result before committing — CI enforces \`git diff --exit-code\` on it."
