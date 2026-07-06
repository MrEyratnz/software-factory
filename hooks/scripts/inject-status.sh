#!/usr/bin/env bash
# inject-status (UserPromptSubmit) — every command is aware of its position on
# the line. Prepends the assembly-line status (next roadmap item, local gate
# state, open tech-debt count) as additionalContext. Exit 0.
. "$(dirname "$0")/../lib/common.sh"

inject_context "$(status_text)"
