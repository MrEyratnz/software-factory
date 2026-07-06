#!/usr/bin/env bash
# guard-bash-writes — the factory's trust roots (.factory/state/**,
# .factory/config.json, .factory/review/**) are guarded against the editor
# tools by guard-scope, but the agent also has Bash. This hook denies a Bash
# command that WRITES into those paths via a redirect/tee/cp/mv/sed -i/dd/etc.,
# closing the "printf > gate-receipt.json" receipt-forgery and config-poison
# path. It also fences read-only roles (currently: reviewer) against ANY
# tree-mutating Bash write-construct, regardless of target path — guard-scope
# only covers the Write/Edit/MultiEdit tools, so without this a "read-only by
# construction" role could still mutate the tree via Bash. Best-effort (a
# determined agent can still obfuscate) — which is exactly why CI, not any
# local hook, is the authoritative boundary.
. "$(dirname "$0")/../lib/common.sh"

[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
[ -n "$cmd" ] || allow

# Read-only roles (currently: reviewer) may not mutate the tree via Bash at
# all — this is what makes "read-only by construction" true for Bash, not
# just prose. Checked first so it fences the WHOLE tree, ahead of the
# trust-root-only check below that applies to every other role. Extends the
# base write-construct regex with the git mutators (add/commit/apply/reset/
# stash/restore/rm) that a plain redirect/tee/sed check would miss.
active="$(cat "$FACTORY_DIR/active-agent" 2>/dev/null | tr -d '[:space:]')"
case "$active" in
  reviewer)
    if printf '%s' "$cmd" | grep -Eq '(>>?|[[:space:]]tee([[:space:]]|$)|[[:space:]](cp|mv|dd|install|ln|truncate|rm)[[:space:]]|sed[[:space:]]+-i|git[[:space:]]+(checkout|add|commit|apply|reset|stash|restore|rm)|>\|)'; then
      deny "the reviewer is read-only by construction — its Bash may not mutate the tree (attempted: $cmd)"
    fi
    ;;
esac

# Does the command reference a protected trust-root path at all?
printf '%s' "$cmd" | grep -Eq '\.factory/(state|review)/|\.factory/config\.json' || allow

# Is it a write construct (redirect, or a mutating command targeting the path)?
if printf '%s' "$cmd" | grep -Eq '(>>?|[[:space:]]tee([[:space:]]|$)|[[:space:]](cp|mv|dd|install|ln|truncate|rm)[[:space:]]|sed[[:space:]]+-i|git[[:space:]]+checkout|>\|)'; then
  deny "writing to the factory's trust roots (.factory/state, .factory/config.json, .factory/review) via the shell is not allowed — these are hook-managed. (The green receipt, release/roadmap proofs, and config cannot be hand-forged.)"
fi
allow
