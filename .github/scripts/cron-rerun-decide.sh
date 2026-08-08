#!/usr/bin/env bash
# cron-rerun-decide.sh — the decision predicates behind cron-rerun.yml,
# extracted so the contract tests run the ACTUAL logic against fixtures
# instead of grepping the workflow for tokens it also carries in its own
# comments (#1276/#1277 — the shape-only-no-op defect class #421/#98
# documents for require-deliverable.sh).
#
#   signature <log-file>
#     exit 0 iff the file carries the structured limit-kill signature:
#     the CLI result JSON on the failed step ("is_error": true on the
#     same line as a session/weekly-limit phrase, rate_limit_error, or
#     "api_error_status": 429) or claude-session's error guard as stored
#     logs actually render it (##[error]Station failed: ..., never the
#     ::error:: source form). Whitespace after JSON colons is tolerated
#     (#1285). Limit phrases WITHOUT one of the two anchors — quoted in
#     an issue body, a reviewed diff, an echo — are not a limit kill
#     (#1233).
#
#   decide <attempt> <updated-at-iso> <max-attempts> <backoff-hours> <now-iso>
#     prints exactly one verdict:
#       park  — attempt cap reached; leave the run for a human
#       due   — rerun now. The FIRST rerun is never delayed: a session
#               limit resets within hours and the checkpoint machinery
#               makes the retry near-free, so pacing it would only slow
#               recovery (#1281). Later attempts are due once the last
#               attempt is older than the backoff.
#       young — a later attempt inside the backoff window; wait, so the
#               cap outlasts a multi-day weekly limit instead of being
#               exhausted by hourly hammering (#1235).
set -euo pipefail

cmd="${1:-}"
case "$cmd" in
  signature)
    [ -r "${2:-}" ] || exit 2
    grep -qiE '("is_error":[[:space:]]*true|##\[error\]Station failed:).*((hit your (session|weekly) limit)|rate_limit_error|"api_error_status":[[:space:]]*429)' "$2"
    ;;
  decide)
    attempt="${2:-1}" updated_at="${3:?updatedAt required}" max="${4:?max required}" backoff_h="${5:?backoff required}" now="${6:?now required}"
    case "$attempt" in ''|*[!0-9]*) attempt=1 ;; esac
    if [ "$attempt" -ge "$max" ]; then
      echo park
    elif [ "$attempt" -le 1 ]; then
      echo due
    else
      upd_s="$(date -u -d "$updated_at" +%s)"
      now_s="$(date -u -d "$now" +%s)"
      if [ $((now_s - upd_s)) -lt $((backoff_h * 3600)) ]; then
        echo young
      else
        echo due
      fi
    fi
    ;;
  *)
    echo "usage: cron-rerun-decide.sh signature <log-file> | decide <attempt> <updatedAt> <max> <backoffH> <now>" >&2
    exit 64
    ;;
esac
