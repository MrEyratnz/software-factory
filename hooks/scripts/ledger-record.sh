#!/usr/bin/env bash
# ledger-record (PostToolUse Bash) — durable audit trail that survives
# compaction. After a successful `git commit`, append one line to
# .factory/ledger.jsonl. Non-blocking: always exit 0.
. "$(dirname "$0")/../lib/common.sh"

[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
printf '%s' "$cmd" | grep -Eq '\bgit\b[^|&;]*\bcommit\b' || allow

ec="$(field tool_response.exitCode)"; [ -n "$ec" ] || ec="$(field tool_response.exit_code)"
[ -n "$ec" ] && [ "$ec" != "0" ] && allow   # failed commit → nothing to log

sha="$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null)"
[ -n "$sha" ] || allow
station="$(cat "$FACTORY_DIR/active-agent" 2>/dev/null | tr -d '[:space:]')"; [ -n "$station" ] || station="commit"
subject="$(cd "$PROJECT_DIR" 2>/dev/null && git log -1 --pretty=%s 2>/dev/null)"

mkdir -p "$FACTORY_DIR"
line="$(SHA="$sha" ST="$station" SUB="$subject" node -e 'process.stdout.write(JSON.stringify({station:process.env.ST,sha:process.env.SHA,subject:process.env.SUB}))')"
printf '%s\n' "$line" >> "$FACTORY_DIR/ledger.jsonl"
allow
