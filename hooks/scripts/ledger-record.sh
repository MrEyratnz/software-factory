#!/usr/bin/env bash
# ledger-record (PostToolUse Bash) — durable audit trail that survives
# compaction. After a successful `git commit`, append one line to
# .factory/ledger.jsonl. Non-blocking: always exit 0.
. "$(dirname "$0")/../lib/common.sh"

# Un-inited repo → no ledger (the factory is advisory here).
factory_initialized || allow

[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
printf '%s' "$cmd" | grep -Eq '\bgit\b[^|&;]*\bcommit\b' || allow

# Check every exit-code field name record-green uses; a PRESENT nonzero code is a
# failed commit → nothing to log. A MISSING code is not proof of success, so we
# additionally de-dup by SHA below (a failed 'nothing to commit' leaves HEAD
# unchanged and would otherwise re-log the previous commit).
ec="$(field tool_response.exitCode)"
[ -n "$ec" ] || ec="$(field tool_response.exit_code)"
[ -n "$ec" ] || ec="$(field tool_response.code)"
[ -n "$ec" ] || ec="$(field tool_response.returnCode)"
case "$ec" in ''|*[!0-9]*) ec="" ;; esac
[ -n "$ec" ] && [ "$ec" != "0" ] && allow

# Read the sha/subject from the repo the commit actually targeted (honors
# `cd <dir>`/`git -C <dir>`), not the fixed session project (issue #28), so a
# sibling-repo commit is logged with the right sha, not the session HEAD.
target_root="$(repo_root "$(command_target_dir "$cmd")")"
sha="$(cd "$target_root" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null)"
[ -n "$sha" ] || allow
station="$(cat "$FACTORY_DIR/active-agent" 2>/dev/null | tr -d '[:space:]')"; [ -n "$station" ] || station="commit"
subject="$(cd "$target_root" 2>/dev/null && git log -1 --pretty=%s 2>/dev/null)"
repo="$(basename "$target_root")"

mkdir -p "$FACTORY_DIR"
# De-dup: if the last ledger entry already records this sha, the "commit" did not
# advance HEAD (nothing to commit / pre-commit failure) — do not append a
# duplicate, even when no exit code was available to catch the failure.
last_sha="$(tail -n 1 "$FACTORY_DIR/ledger.jsonl" 2>/dev/null | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).sha||""))}catch(e){}})' 2>/dev/null)"
[ "$last_sha" = "$sha" ] && allow

line="$(SHA="$sha" ST="$station" SUB="$subject" REPO="$repo" node -e 'process.stdout.write(JSON.stringify({station:process.env.ST,sha:process.env.SHA,subject:process.env.SUB,repo:process.env.REPO}))')"
printf '%s\n' "$line" >> "$FACTORY_DIR/ledger.jsonl"
otel_emit factory_commits_total sum 1 "$(printf '{"station":%s}' "$(json_str "$station")")"
allow
