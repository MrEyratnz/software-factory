#!/usr/bin/env bash
# guard-bash-writes — the factory's trust roots (.factory/state/**,
# .factory/config.json, .factory/review/**) are guarded against the editor
# tools by guard-scope, but the agent also has Bash. This hook denies a Bash
# command that WRITES into those paths via a redirect/tee/cp/mv/sed -i/dd/etc.,
# closing the "printf > gate-receipt.json" receipt-forgery and config-poison
# path. Best-effort (a determined agent can still obfuscate) — which is exactly
# why CI, not any local hook, is the authoritative boundary.
. "$(dirname "$0")/../lib/common.sh"

[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
[ -n "$cmd" ] || allow

# Does the command reference a protected trust-root path at all?
printf '%s' "$cmd" | grep -Eq '\.factory/(state|review)/|\.factory/config\.json' || allow

# Is it a write construct (redirect, or a mutating command targeting the path)?
if printf '%s' "$cmd" | grep -Eq '(>>?|[[:space:]]tee([[:space:]]|$)|[[:space:]](cp|mv|dd|install|ln|truncate|rm)[[:space:]]|sed[[:space:]]+-i|git[[:space:]]+checkout|>\|)'; then
  deny "writing to the factory's trust roots (.factory/state, .factory/config.json, .factory/review) via the shell is not allowed — these are hook-managed. (The green receipt, release/roadmap proofs, and config cannot be hand-forged.)"
fi
allow
