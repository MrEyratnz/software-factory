#!/usr/bin/env bash
# Posts ONE comment on the PR currently under review — nothing else.
#
# The target PR is pinned by the REVIEW_PR env var, which the Claude Code
# Review workflow sets from its triggering event (see triage-add-labels.sh
# for the full rationale behind env-var pinning: the target lives at the
# tool layer, out of the model's hands, so a prompt-injected review session
# cannot retarget another PR or issue). Only --body is accepted.
#
# Usage: ./scripts/review-comment.sh --body "review text"
set -euo pipefail

PR="${REVIEW_PR:?REVIEW_PR env var must be set (the Claude Code Review workflow sets it)}"

if [ "$#" -eq 2 ] && [ "$1" = "--body" ]; then
  body="$2"
elif [ "$#" -eq 1 ] && [[ "$1" == --body=* ]]; then
  body="${1#--body=}"
else
  echo "usage: $0 --body \"review text\"" >&2
  exit 2
fi

# Reject an empty body at the contract layer — gh would only fail later with
# an opaque API 422, which reads as "commenting is broken" to a session.
if [ -z "$body" ]; then
  echo "error: --body must be non-empty" >&2
  exit 2
fi

exec gh pr comment "$PR" --body "$body"
