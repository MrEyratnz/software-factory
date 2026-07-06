#!/usr/bin/env bash
# debt-reconcile (Stop) — the crown jewel. A session cannot end while any
# adversarial-review finding is neither fixed-in-diff (status:"fixed") nor filed
# as an open `tech-debt` issue (matched by content fingerprint). Reads FILES +
# GitHub, not conversation context, so it survives compaction and fires on
# EVERY session — not only inside /factory-run.
. "$(dirname "$0")/../lib/common.sh"

review_dir="$FACTORY_DIR/review"
[ -d "$review_dir" ] || allow

findings="$(REVIEW_DIR="$review_dir" node "$PLUGIN_ROOT/hooks/lib/collect-findings.mjs" 2>/dev/null)"
[ -z "$findings" ] && allow
[ "$findings" = "[]" ] && allow

issues='[]'
if command -v gh >/dev/null 2>&1; then
  fetched="$(gh issue list --label tech-debt --state open --json title,body 2>/dev/null)"
  [ -n "$fetched" ] && issues="$fetched"
fi

audit="$(printf '{"findings":%s,"openIssues":%s}' "$findings" "$issues" | fc techdebt-audit)"
ok="$(printf '%s' "$audit" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).ok))}catch(e){process.stdout.write("true")}})')"
[ "$ok" = "true" ] && allow

n="$(printf '%s' "$audit" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).missing.length))}catch(e){process.stdout.write("?")}})')"
otel_emit factory_techdebt_missing_total gauge "$n" '{}'
block_stop "$n unfixed review finding(s) are not yet tracked — file each as a \`tech-debt\` issue (run /debt sync) or mark it status:\"fixed\" in .factory/review before ending. (course-creator convention: unfixed findings become tracked tech-debt.)"
