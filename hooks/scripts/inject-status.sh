#!/usr/bin/env bash
# inject-status (UserPromptSubmit) — every command is aware of its position on
# the line. Prepends the assembly-line status (next roadmap item, local gate
# state, open tech-debt count) as additionalContext. Exit 0.
#
# Throttled so it isn't identical low-information noise every turn (issue #34):
#   - a repo that never opted into the factory (no .factory/config.json) gets
#     nothing — bootstrap already hinted "run /factory-init" once at
#     SessionStart; repeating it every turn just burns context.
#   - a paused factory (see respect_pause) stays silent.
#   - otherwise the banner is injected only when it actually CHANGED since the
#     last turn, tracked in .factory/state/last-status.
. "$(dirname "$0")/../lib/common.sh"

[ -f "$CONFIG_FILE" ] || exit 0
factory_paused && exit 0

status="$(status_text)"
last_file="$STATE_DIR/last-status"
if [ -f "$last_file" ] && [ "$(cat "$last_file" 2>/dev/null)" = "$status" ]; then
  exit 0
fi
mkdir -p "$STATE_DIR" 2>/dev/null
printf '%s' "$status" > "$last_file" 2>/dev/null || true
inject_context "$status"
