#!/usr/bin/env bash
# session-resume.sh — checkpoint/resume for CI station sessions (#725).
#
# A station that dies mid-run (usage limit, max-turns, runner timeout)
# leaves a transcript under ~/.claude/projects/. Persisting it plus the
# session id across job attempts lets `gh run rerun --failed` resume the
# parked session with `claude -p --resume <id>` instead of re-paying the
# whole context from zero.
#
# The id is ARMED before launch (the workflow pre-assigns it via
# `claude --session-id`), so even a hard SIGKILL that never writes a
# result JSON leaves a resumable checkpoint (#753). After the session,
# `post` CLEARS the id only on a confirmed clean completion — a
# successfully-finished station must never be resumed by a rerun of an
# unrelated failed step, which would re-drive its side effects and re-pay
# the session (#752). Any other outcome (is_error, missing or unparseable
# result) keeps the checkpoint armed.
#
# Subcommands:
#   arm  <state-dir> <uuid>          — record the id the session will use;
#                                      rejects anything but a UUID (#756)
#   pre  <state-dir>                 — print the armed id IFF its transcript
#                                      exists on disk; else print nothing
#   post <state-dir> <result-json>   — clear the id ONLY when the result
#                                      parses and is_error is false
set -uo pipefail

UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

cmd="${1:-}"
state_dir="${2:-}"
if [ -z "$cmd" ] || [ -z "$state_dir" ]; then
  echo "usage: session-resume.sh arm <state-dir> <uuid> | pre <state-dir> | post <state-dir> <result-json>" >&2
  exit 2
fi

case "$cmd" in
  arm)
    sid="${3:-}"
    if ! printf '%s' "$sid" | grep -qE "$UUID_RE"; then
      echo "session-resume.sh: refusing to arm non-UUID session id '$sid'" >&2
      exit 2
    fi
    mkdir -p "$state_dir"
    printf '%s' "$sid" > "$state_dir/session-id"
    exit 0
    ;;
  pre)
    sid="$(cat "$state_dir/session-id" 2>/dev/null || true)"
    # A non-UUID id is never used: it cannot have come from arm, and a
    # crafted value would otherwise glob-match inside find (#756).
    printf '%s' "$sid" | grep -qE "$UUID_RE" || exit 0
    # Resume only if the transcript this id names actually survived the
    # cache round-trip; find is path-agnostic to the project-dir munging,
    # and the UUID shape guarantees the -name pattern is literal.
    if find "$HOME/.claude/projects" -name "$sid.jsonl" -type f 2>/dev/null | grep -q .; then
      printf '%s' "$sid"
    fi
    exit 0
    ;;
  post)
    result_json="${3:-}"
    # Clear the checkpoint ONLY on a confirmed clean completion. A missing,
    # empty, or unparseable result means the session was killed mid-run —
    # exactly when the armed checkpoint must survive for the next attempt.
    if [ -n "$result_json" ] && [ -s "$result_json" ]; then
      verdict="$(node -e '
        const fs = require("fs");
        try {
          const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          process.stdout.write(o.is_error === false ? "clean" : "parked");
        } catch (e) { process.stdout.write("parked"); }
      ' "$result_json" 2>/dev/null || printf 'parked')"
      if [ "$verdict" = "clean" ]; then
        rm -f "$state_dir/session-id"
      fi
    fi
    exit 0
    ;;
  *)
    echo "session-resume.sh: unknown subcommand '$cmd'" >&2
    exit 2
    ;;
esac
