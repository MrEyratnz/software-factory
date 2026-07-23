#!/usr/bin/env bash
# Adds labels to the issue currently being triaged — and can do nothing else.
#
# The target issue is pinned by the TRIAGE_ISSUE env var, which the Issue
# Triage workflow sets from its matrix; it is deliberately NOT an argument,
# so a prompt-injected triage session cannot retarget another issue or PR,
# edit titles/bodies, or remove labels. Only --add-label is accepted, and
# the queue-control labels owned by the pickup automation (`ready`,
# `in-progress` — see project-pickup.yml) are rejected so a triage session
# can never move an issue through the pickup pipeline.
#
# Usage: ./scripts/triage-add-labels.sh --add-label "name" [--add-label "name" ...]
set -euo pipefail

usage() {
  echo "usage: $0 --add-label \"name\" [--add-label \"name\" ...]" >&2
  exit 2
}

ISSUE="${TRIAGE_ISSUE:?TRIAGE_ISSUE env var must be set (the Issue Triage workflow sets it)}"

check_label() {
  case "$1" in
    ready|in-progress)
      echo "error: '$1' is a queue-control label owned by the pickup automation; triage may not apply it" >&2
      exit 2
      ;;
  esac
}

args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --add-label)
      [ $# -ge 2 ] || usage
      check_label "$2"
      args+=(--add-label "$2")
      shift 2
      ;;
    --add-label=*)
      check_label "${1#--add-label=}"
      args+=(--add-label "${1#--add-label=}")
      shift
      ;;
    *)
      echo "error: only --add-label arguments are accepted (got: $1)" >&2
      usage
      ;;
  esac
done
[ "${#args[@]}" -gt 0 ] || usage

exec gh issue edit "$ISSUE" "${args[@]}"
