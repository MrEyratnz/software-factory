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

respect_pause guard-bash-writes
[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
[ -n "$cmd" ] || allow

# Read-only roles (currently: reviewer) may not mutate the tree via Bash at
# all — this is what makes "read-only by construction" true for Bash, not
# just prose. Checked first so it fences the WHOLE tree, ahead of the
# trust-root-only check below that applies to every other role. Extends the
# base write-construct regex with the git mutators (add/commit/apply/reset/
# stash/restore/rm/clean) that a plain redirect/tee/sed check would miss.
# The mutator-verb group is anchored at command-start OR after a
# separator/whitespace (not just a REQUIRED leading space), so a command that
# *starts* with a verb (e.g. "rm -rf x", "tee .factory/active-agent") is still
# caught. The redirect match requires the ">" to be preceded by
# start/whitespace/a fd digit/"&" so a real redirect (`> f`, `>> f`, `2> f`,
# `&> f`) is caught but a bare ">" inside a quoted arg (e.g. `grep "=>"`) is
# not.
active="$(cat "$FACTORY_DIR/active-agent" 2>/dev/null | tr -d '[:space:]')"
case "$active" in
  reviewer)
    if printf '%s' "$cmd" | grep -Eq '(^|[[:space:]]|[0-9]|&)>>?|(^|[;&|[:space:]])(cp|mv|dd|install|ln|truncate|rm|tee|patch)([[:space:]]|$)|sed[[:space:]]+-i|git[[:space:]]+(checkout|add|commit|apply|reset|stash|restore|rm|clean)'; then
      deny "the reviewer is read-only by construction — its Bash may not mutate the tree (attempted: $cmd)"
    fi
    ;;
esac

# General "no writes outside the project directory" parity with guard-scope
# (issue #31): guard-scope bans out-of-project writes for the editor tools, but
# the Bash surface had no equivalent, so a `cat > /elsewhere` slipped through.
# Best-effort: inspects redirect/tee targets, with carve-outs for Claude Code's
# own state (~/.claude, incl. the memory feature), temp dirs, and /dev.
if enforcement_on enforceProjectDirScope; then
  outside="$(printf '%s' "$cmd" | HOOK_PROJECT_DIR="$PROJECT_DIR" node "$PLUGIN_ROOT/hooks/lib/parse-bash-writes.mjs" 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const a=JSON.parse(s).outside;process.stdout.write(a&&a.length?a[0]:"")}catch(e){}})')"
  [ -n "$outside" ] && deny_soft "writing outside the project directory is not allowed: $outside (guard-scope enforces the same rule for the editor tools; ~/.claude, temp dirs, and /dev are carved out)"
fi

# Trust-root protection can be relaxed per-repo via enforcement.protectTrustRoots.
enforcement_on protectTrustRoots || allow

# Does the command reference a protected trust-root path at all?
printf '%s' "$cmd" | grep -Eq '\.factory/(state|review)/|\.factory/config\.json' || allow

# Is it a write construct (redirect, or a mutating command targeting the path)?
if printf '%s' "$cmd" | grep -Eq '(>>?|[[:space:]]tee([[:space:]]|$)|[[:space:]](cp|mv|dd|install|ln|truncate|rm)[[:space:]]|sed[[:space:]]+-i|git[[:space:]]+checkout|>\|)'; then
  deny "writing to the factory's trust roots (.factory/state, .factory/config.json, .factory/review) via the shell is not allowed — these are hook-managed. (The green receipt, release/roadmap proofs, and config cannot be hand-forged.)"
fi
allow
