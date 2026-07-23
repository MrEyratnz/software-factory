#!/usr/bin/env bash
# Posts ONE comment on the issue currently being triaged — nothing else.
#
# The target issue is pinned by the TRIAGE_ISSUE env var, which the Issue
# Triage workflow sets from its matrix (see triage-add-labels.sh for the
# full rationale). Only --body is accepted.
#
# Usage: ./scripts/triage-comment.sh --body "comment text"
set -euo pipefail

ISSUE="${TRIAGE_ISSUE:?TRIAGE_ISSUE env var must be set (the Issue Triage workflow sets it)}"

if [ "$#" -eq 2 ] && [ "$1" = "--body" ]; then
  body="$2"
elif [ "$#" -eq 1 ] && [[ "$1" == --body=* ]]; then
  body="${1#--body=}"
else
  echo "usage: $0 --body \"comment text\"" >&2
  exit 2
fi

# Reject an empty body at the contract layer — gh would only fail later with
# an opaque API 422, which reads as "commenting is broken" to a session.
if [ -z "$body" ]; then
  echo "error: --body must be non-empty" >&2
  exit 2
fi

exec gh issue comment "$ISSUE" --body "$body"
