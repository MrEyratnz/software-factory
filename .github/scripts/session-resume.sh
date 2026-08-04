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
#   arm  <state-dir> <uuid> [head-sha]
#        Record the id the session will use (rejects anything but a UUID,
#        #756) plus the checkout SHA it was armed against (#786).
#   pre  <state-dir> [head-sha]
#        Print the armed id IFF its transcript exists on disk AND, when a
#        head-sha is given, it matches the armed one — a resumed station
#        must never continue against a different checkout than it was
#        killed on (#786); on mismatch print nothing (cold start).
#   post <state-dir> <result-json>
#        Clear the id ONLY when the result parses and is_error is falsy —
#        the SAME predicate the workflow's failure guard uses (#788), so
#        "job went green" and "checkpoint cleared" can never diverge.
set -uo pipefail

cmd="${1:-}"
state_dir="${2:-}"
if [ -z "$cmd" ] || [ -z "$state_dir" ]; then
  echo "usage: session-resume.sh arm <state-dir> <uuid> | pre <state-dir> | post <state-dir> <result-json>" >&2
  exit 2
fi

case "$cmd" in
  arm)
    sid="${3:-}"
    head_sha="${4:-}"
    # Whole-string match ([[ =~ ]] anchors the full value, unlike per-line
    # grep — #791): a multi-line or embedded value must not pass the gate.
    if ! [[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
      echo "session-resume.sh: refusing to arm non-UUID session id '$sid'" >&2
      exit 2
    fi
    mkdir -p "$state_dir"
    printf '%s' "$sid" > "$state_dir/session-id"
    if [ -n "$head_sha" ]; then
      printf '%s' "$head_sha" > "$state_dir/head-sha"
    fi
    exit 0
    ;;
  pre)
    expected_sha="${3:-}"
    sid="$(cat "$state_dir/session-id" 2>/dev/null || true)"
    # A non-UUID id is never used: it cannot have come from arm, and a
    # crafted value would otherwise glob-match inside find (#756).
    [[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || exit 0
    # A resume against a DIFFERENT checkout than the session was killed on
    # would act on a stale diff (a review approving vanished code — #786):
    # when both sides have a SHA and they differ, cold-start instead.
    if [ -n "$expected_sha" ] && [ -f "$state_dir/head-sha" ]; then
      armed_sha="$(cat "$state_dir/head-sha" 2>/dev/null || true)"
      if [ -n "$armed_sha" ] && [ "$armed_sha" != "$expected_sha" ]; then
        exit 0
      fi
    fi
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
    # Clear the checkpoint ONLY on a confirmed clean completion, judged by
    # the SAME truthiness predicate as the workflow's failure guard
    # (`if (o.is_error)` — #788): a result the guard calls green must also
    # clear the checkpoint, or a later rerun resumes a finished station.
    # A missing, empty, or unparseable result means the session was killed
    # mid-run — exactly when the armed checkpoint must survive.
    if [ -n "$result_json" ] && [ -s "$result_json" ]; then
      verdict="$(node -e '
        const fs = require("fs");
        try {
          const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          process.stdout.write(o.is_error ? "parked" : "clean");
        } catch (e) { process.stdout.write("parked"); }
      ' "$result_json" 2>/dev/null || printf 'parked')"
      if [ "$verdict" = "clean" ]; then
        rm -f "$state_dir/session-id" "$state_dir/head-sha"
      fi
    fi
    exit 0
    ;;
  *)
    echo "session-resume.sh: unknown subcommand '$cmd'" >&2
    exit 2
    ;;
esac
