#!/usr/bin/env bash
# bootstrap (SessionStart) — drop-into-ANY-repo orientation. Ensures the
# .factory runtime dirs exist and injects the assembly-line status as context.
# Idempotent and advisory (exit 0). Label creation and the full docs spine are
# the job of /factory-init (which the injected context hints at when the repo
# is uninitialized) — SessionStart never makes surprise network calls.
. "$(dirname "$0")/../lib/common.sh"

# An un-inited repo (no .factory/config.json) has not opted into the factory.
# Do NOT create .factory/ runtime dirs there — that dirties `git status` with
# untracked state the agent is then forbidden to remove, in every repo merely
# opened with the plugin enabled. Just point the user at /factory-init, and make
# no network calls (status_text may query `gh` for the debt count).
if ! factory_initialized; then
  inject_context "This repo is not factory-initialized yet — run /factory-init to stamp the docs spine, config, CI, and labels. (The factory's workflow gates stay advisory until then.)"
fi

mkdir -p "$STATE_DIR" "$FACTORY_DIR/review" "$FACTORY_DIR/panel" 2>/dev/null

# Prime the inject-status throttle (issue #34) so the first UserPromptSubmit
# doesn't immediately re-inject the same line we're about to show here.
status="$(status_text)"
printf '%s' "$status" > "$STATE_DIR/last-status" 2>/dev/null || true
inject_context "$status"
