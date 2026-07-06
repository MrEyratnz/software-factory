#!/usr/bin/env bash
# bootstrap (SessionStart) — drop-into-ANY-repo orientation. Ensures the
# .factory runtime dirs exist and injects the assembly-line status as context.
# Idempotent and advisory (exit 0). Label creation and the full docs spine are
# the job of /factory-init (which the injected context hints at when the repo
# is uninitialized) — SessionStart never makes surprise network calls.
. "$(dirname "$0")/../lib/common.sh"

mkdir -p "$STATE_DIR" "$FACTORY_DIR/review" "$FACTORY_DIR/panel" 2>/dev/null

hint=""
if [ ! -f "$CONFIG_FILE" ]; then
  hint=" This repo is not factory-initialized yet — run /factory-init to stamp the docs spine, config, CI, and labels."
fi

inject_context "$(status_text)$hint"
