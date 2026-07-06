#!/usr/bin/env bash
# loop-guard (Stop) — bounded lights-out continuation. While a /factory-run is
# active and the roadmap still has unchecked items, re-block Stop so the loop
# advances station-to-station — hard-capped by max-iterations so it can never
# run away. Inactive (allow) outside a loop.
. "$(dirname "$0")/../lib/common.sh"

loop="$STATE_DIR/loop.json"
[ -f "$loop" ] || allow

active="$(REC="$loop" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).active))}catch(e){process.stdout.write("false")}')"
[ "$active" = "true" ] || allow

iters="$(REC="$loop" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).iterations||0))}catch(e){process.stdout.write("0")}')"
maxi="$(REC="$loop" node -e 'const fs=require("fs");try{const o=JSON.parse(fs.readFileSync(process.env.REC,"utf8"));process.stdout.write(String(o.maxIterations||10))}catch(e){process.stdout.write("10")}')"

# Roadmap complete? Then the loop is done — deactivate and allow the stop.
roadmap="$PROJECT_DIR/$(config_get roadmapPath 'docs/ROADMAP.md')"
if [ -f "$roadmap" ]; then
  md="$(cat "$roadmap")"
  nexttxt="$(printf '{"markdown":%s}' "$(json_str "$md")" | fc roadmap-next \
    | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const n=JSON.parse(s).next;process.stdout.write(n?n.text:"")}catch(e){process.stdout.write("")}})')"
  pct="$(printf '{"markdown":%s}' "$(json_str "$md")" | fc roadmap-status \
    | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).totals.percent))}catch(e){process.stdout.write("")}})')"
  otel_emit factory_roadmap_percent_complete gauge "$pct" '{}'
  if [ -z "$nexttxt" ]; then
    LOOP="$loop" node -e 'const fs=require("fs");try{const o=JSON.parse(fs.readFileSync(process.env.LOOP,"utf8"));o.active=false;fs.writeFileSync(process.env.LOOP,JSON.stringify(o))}catch(e){}'
    allow
  fi
fi

# Iteration cap reached → stop for safety.
if [ "$iters" -ge "$maxi" ] 2>/dev/null; then
  LOOP="$loop" node -e 'const fs=require("fs");try{const o=JSON.parse(fs.readFileSync(process.env.LOOP,"utf8"));o.active=false;fs.writeFileSync(process.env.LOOP,JSON.stringify(o))}catch(e){}'
  block_stop "factory-run reached its max-iterations cap ($maxi) — stopping at a safe checkpoint. Review progress, then re-run /factory-run to continue."
fi

# Otherwise advance: increment the counter and re-block the stop.
LOOP="$loop" node -e 'const fs=require("fs");try{const o=JSON.parse(fs.readFileSync(process.env.LOOP,"utf8"));o.iterations=(o.iterations||0)+1;fs.writeFileSync(process.env.LOOP,JSON.stringify(o))}catch(e){}'
otel_emit factory_loop_iterations_total sum "$((iters+1))" '{}'
block_stop "factory-run active (iteration $((iters+1))/$maxi): next roadmap item is \"${nexttxt:-unknown}\". Continue the loop: /next → /review → (file tech-debt), and /ship at each milestone close."
