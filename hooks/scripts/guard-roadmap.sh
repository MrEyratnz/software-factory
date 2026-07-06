#!/usr/bin/env bash
# guard-roadmap — "a roadmap box is checked off only when merged with green
# tests." Blocks an Edit that flips a `- [ ]` to `- [x]` in the roadmap unless
# the connector's roadmap_check verdict has a merged-green SHA proof (which
# comes from CI, not the local tree). Makes checkbox honesty structural.
. "$(dirname "$0")/../lib/common.sh"

case "$(field tool_name)" in Edit|MultiEdit) ;; *) allow ;; esac
fp="$(field tool_input.file_path)"
roadmap="$(config_get roadmapPath 'docs/ROADMAP.md')"
case "$fp" in
  *"$roadmap"|*/ROADMAP.md|ROADMAP.md) ;;
  *) allow ;;
esac

# Extract old/new text for BOTH Edit (new_string/old_string) and MultiEdit
# (edits[].new_string / old_string, concatenated) — else a flip inside a
# MultiEdit is invisible and slips through.
new="$(HOOK_JSON="$HOOK_INPUT" node -e '
  const ti=(JSON.parse(process.env.HOOK_JSON||"{}").tool_input)||{};
  if(Array.isArray(ti.edits)) process.stdout.write(ti.edits.map(e=>e.new_string||"").join("\n"));
  else process.stdout.write(ti.new_string||"");' 2>/dev/null)"
old="$(HOOK_JSON="$HOOK_INPUT" node -e '
  const ti=(JSON.parse(process.env.HOOK_JSON||"{}").tool_input)||{};
  if(Array.isArray(ti.edits)) process.stdout.write(ti.edits.map(e=>e.old_string||"").join("\n"));
  else process.stdout.write(ti.old_string||"");' 2>/dev/null)"
newx="$(printf '%s' "$new" | grep -oiE '\[x\]' | wc -l | tr -d ' ')"
oldx="$(printf '%s' "$old" | grep -oiE '\[x\]' | wc -l | tr -d ' ')"

# No newly-checked box → nothing to gate.
[ "${newx:-0}" -gt "${oldx:-0}" ] 2>/dev/null || allow

proof_file="$STATE_DIR/roadmap-proof.json"
[ -f "$proof_file" ] || deny "cannot check off a roadmap item without a merged-green proof (CI must be green on the merged branch first)"

item="$(printf '%s' "$new" | grep -iE '^\s*[-*]\s+\[x\]' | head -1 | sed -E 's/^\s*[-*]\s+\[[xX]\]\s*//')"
proof_json="$(cat "$proof_file" 2>/dev/null)"
[ -n "$proof_json" ] || proof_json='{}'
verdict="$(printf '{"item":%s,"proof":%s}' "$(json_str "$item")" "$proof_json" | fc roadmap-check)"
mayflip="$(printf '%s' "$verdict" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).mayFlip))}catch(e){process.stdout.write("false")}})')"
[ "$mayflip" = "true" ] || deny "roadmap check refused: no merged-green proof for \"$item\""
allow
