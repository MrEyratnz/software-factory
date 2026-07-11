#!/usr/bin/env bash
# guard-roadmap — "a roadmap box is checked off only when merged with green
# tests." Blocks an Edit that flips a `- [ ]` to `- [x]` in the roadmap unless
# the connector's roadmap_check verdict has a merged-green SHA proof (which
# comes from CI, not the local tree). Makes checkbox honesty structural.
. "$(dirname "$0")/../lib/common.sh"

respect_pause guard-roadmap
require_initialized guard-roadmap
# issue #52: degrade LOUDLY (never silently) when node is unavailable.
node_guard guard-roadmap || allow
case "$(field tool_name)" in Edit|MultiEdit|Write) ;; *) allow ;; esac
fp="$(field tool_input.file_path)"
roadmap="$(config_get roadmapPath 'docs/ROADMAP.md')"
case "$fp" in
  *"$roadmap"|*/ROADMAP.md|ROADMAP.md) ;;
  *) allow ;;
esac

# Extract old/new text across Edit (new_string/old_string), MultiEdit
# (edits[].new_string / old_string), AND Write (the whole `content` replaces the
# file, so there is no old_string — compare against the CURRENT on-disk roadmap).
# Without the Write branch an agent could Read the roadmap and Write it back with
# a box flipped, bypassing the gate entirely (the hook now also matches Write).
# Event JSON is piped on stdin (never env) to avoid E2BIG on a large file body.
tool_name="$(field tool_name)"
new="$(printf '%s' "$HOOK_INPUT" | node -e '
  let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{
    const ti=((()=>{try{return JSON.parse(s)}catch(e){return {}}})().tool_input)||{};
    if(Array.isArray(ti.edits)) process.stdout.write(ti.edits.map(e=>e.new_string||"").join("\n"));
    else if(typeof ti.content==="string") process.stdout.write(ti.content);
    else process.stdout.write(ti.new_string||"");
  });' 2>/dev/null)"
if [ "$tool_name" = "Write" ]; then
  # Resolve the roadmap file the Write targets and read its current contents.
  ondisk="$fp"
  case "$fp" in /*) ;; *) ondisk="$PROJECT_DIR/$fp" ;; esac
  old="$(cat "$ondisk" 2>/dev/null)"
else
  old="$(printf '%s' "$HOOK_INPUT" | node -e '
    let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{
      const ti=((()=>{try{return JSON.parse(s)}catch(e){return {}}})().tool_input)||{};
      if(Array.isArray(ti.edits)) process.stdout.write(ti.edits.map(e=>e.old_string||"").join("\n"));
      else process.stdout.write(ti.old_string||"");
    });' 2>/dev/null)"
fi
newx="$(printf '%s' "$new" | grep -oiE '\[x\]' | wc -l | tr -d ' ')"
oldx="$(printf '%s' "$old" | grep -oiE '\[x\]' | wc -l | tr -d ' ')"

# No newly-checked box → nothing to gate.
[ "${newx:-0}" -gt "${oldx:-0}" ] 2>/dev/null || allow

proof_file="$STATE_DIR/roadmap-proof.json"
[ -f "$proof_file" ] || deny "cannot check off a roadmap item without a merged-green proof (run mint-roadmap-proof.sh after the item's PR merges green)"
# When a runner-only signing key is configured, a hand-written proof (missing/
# invalid signature) cannot certify the merge — a hard boundary mirroring
# guard-commit's receipt check (issue #51). No key → nothing to verify.
roadmap_proof_verify "$proof_file" || deny "the roadmap proof's signature is missing or invalid — it was not minted by the sanctioned producer (mint-roadmap-proof.sh)"

item="$(printf '%s' "$new" | grep -iE '^\s*[-*]\s+\[x\]' | head -1 | sed -E 's/^\s*[-*]\s+\[[xX]\]\s*//')"
proof_json="$(cat "$proof_file" 2>/dev/null)"
[ -n "$proof_json" ] || proof_json='{}'
verdict="$(printf '{"item":%s,"proof":%s}' "$(json_str "$item")" "$proof_json" | fc roadmap-check)"
mayflip="$(printf '%s' "$verdict" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).mayFlip))}catch(e){process.stdout.write("false")}})')"
[ "$mayflip" = "true" ] || deny "roadmap check refused: no merged-green proof for \"$item\""
allow
