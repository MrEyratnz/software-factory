#!/usr/bin/env bash
# session-resume.sh — checkpoint/resume for CI station sessions (#725).
#
# A station that dies mid-run (usage limit, max-turns, runner timeout) leaves
# a transcript under ~/.claude/projects/ and a session_id in its result JSON.
# Persisting both across job attempts lets `gh run rerun --failed` resume the
# parked session with `claude -p --resume <id>` instead of re-paying the
# whole context from zero — measured waste before this: $1-12+ per killed
# session, several sessions per limit window, several windows per day.
#
# Subcommands:
#   post <state-dir> <result-json>
#     Extract .session_id from the result JSON (success or error alike — the
#     limit-park IS the case that matters) and write it to
#     <state-dir>/session-id. Tolerates a missing/unparseable result (a
#     crashed session must not poison the next attempt): exits 0 and leaves
#     no stale id.
#   pre <state-dir>
#     Print the saved session id IFF its transcript exists on disk under
#     $HOME/.claude/projects — otherwise print nothing. The caller resumes
#     only on non-empty output; a blind --resume against a lost transcript
#     would cold-fail the session.
set -uo pipefail

cmd="${1:-}"
state_dir="${2:-}"
if [ -z "$cmd" ] || [ -z "$state_dir" ]; then
  echo "usage: session-resume.sh pre <state-dir> | post <state-dir> <result-json>" >&2
  exit 2
fi

case "$cmd" in
  post)
    result_json="${3:-}"
    mkdir -p "$state_dir"
    # A fresh post must never leave a PREVIOUS attempt's id behind when the
    # current result is unusable-but-present vs absent: only a successfully
    # parsed id may (re)write the file.
    if [ -n "$result_json" ] && [ -s "$result_json" ]; then
      sid="$(node -e '
        const fs = require("fs");
        try {
          const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          if (typeof o.session_id === "string" && o.session_id) process.stdout.write(o.session_id);
        } catch (e) { /* unparseable: print nothing */ }
      ' "$result_json" 2>/dev/null || true)"
      if [ -n "$sid" ]; then
        printf '%s' "$sid" > "$state_dir/session-id"
      fi
    fi
    exit 0
    ;;
  pre)
    sid="$(cat "$state_dir/session-id" 2>/dev/null || true)"
    [ -z "$sid" ] && exit 0
    # Resume only if the transcript this id names actually survived the
    # cache round-trip; find is path-agnostic to the project-dir munging.
    if find "$HOME/.claude/projects" -name "$sid.jsonl" -type f 2>/dev/null | grep -q .; then
      printf '%s' "$sid"
    fi
    exit 0
    ;;
  *)
    echo "session-resume.sh: unknown subcommand '$cmd'" >&2
    exit 2
    ;;
esac
