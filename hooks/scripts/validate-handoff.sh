#!/usr/bin/env bash
# validate-handoff (SubagentStop) — the conductor-as-message-bus never relays
# garbage. When a reviewer / proposer / panelist finishes, require that it left
# a schema-valid artifact file behind; otherwise block its stop so it must emit
# a valid handoff. This is what makes the file-based handoffs reliable across
# isolated subagent contexts.
. "$(dirname "$0")/../lib/common.sh"

role="$(field agent_type)"
[ -n "$role" ] || role="$(cat "$FACTORY_DIR/active-agent" 2>/dev/null | tr -d '[:space:]')"

case "$role" in
  reviewer)  dir="$FACTORY_DIR/review"; required="location,impact,provenance,suggestedFix,severity" ;;
  proposer)  dir="$FACTORY_DIR/panel";  required="stance,proposal" ;;
  panelist)  dir="$FACTORY_DIR/panel";  required="verdicts" ;;
  *) allow ;;
esac

valid="$(DIR="$dir" REQ="$required" node -e '
  const fs=require("fs"),path=require("path");
  const dir=process.env.DIR, req=process.env.REQ.split(",");
  let ok=false;
  try {
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith(".json")) continue;
      let d; try { d=JSON.parse(fs.readFileSync(path.join(dir,f),"utf8")); } catch { continue; }
      const items = Array.isArray(d) ? d : (Array.isArray(d.findings)? d.findings : [d]);
      // At least one item in at least one file must carry every required field.
      if (items.some(it => it && typeof it==="object" && req.every(k => it[k]!=null && it[k]!==""))) { ok=true; break; }
    }
  } catch {}
  process.stdout.write(ok?"yes":"no");
' 2>/dev/null)"

[ "$valid" = "yes" ] && allow
block_stop "the $role produced no schema-valid handoff artifact in ${dir#$PROJECT_DIR/} (needs fields: $required). Emit it before finishing."
