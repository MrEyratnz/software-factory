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
# issue #52: degrade LOUDLY (never silently) when node is unavailable.
node_guard guard-bash-writes || allow
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
    # Any quote-aware write target (redirect/tee/cp/mv/dd/install/ln/touch/…)
    # means a tree mutation — the parser resolves these, so a `>` inside a quoted
    # arg (`grep "a > b" f`, `awk "$1 > 5"`) is NOT a false positive (issue #39).
    rev_writes="$(printf '%s' "$cmd" | HOOK_PROJECT_DIR="$PROJECT_DIR" node "$PLUGIN_ROOT/hooks/lib/parse-bash-writes.mjs" 2>/dev/null \
      | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String((JSON.parse(s).all||[]).length))}catch(e){process.stdout.write("0")}})')"
    [ "${rev_writes:-0}" -gt 0 ] 2>/dev/null && deny "the reviewer is read-only by construction — its Bash may not mutate the tree (attempted: $cmd)"
    # Plus deleters and MUTATING git subcommands the write-target parser does not
    # model. Read-only git (`diff`/`log`/`status`/`show`/`stash list`/`stash
    # show`) must stay allowed (issue #57): `stash` matches only when bare or a
    # mutating subverb, never `stash list`/`stash show`.
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(rm|patch|shred)([[:space:]]|$)|sed[[:space:]]+-i|git[[:space:]]+((checkout|switch|add|commit|apply|reset|restore|rm|clean|mv|cherry-pick|revert|merge|rebase|am)([[:space:]]|$)|stash([[:space:]]*([;&|]|$)|[[:space:]]+(push|pop|apply|drop|clear|save|create|store)))'; then
      deny "the reviewer is read-only by construction — its Bash may not mutate the tree (attempted: $cmd)"
    fi
    ;;
esac

# Classify redirect/tee write targets once, resolved against the command's
# effective cwd (a leading `cd`), so paths reached via `cd <dir>` are judged by
# where they LAND, not by the literal text (issues #31, #3, #4). Quote-aware, so
# a `>` inside a quoted string / commit message is not a false positive (#1/#6).
pj="$(printf '%s' "$cmd" | HOOK_PROJECT_DIR="$PROJECT_DIR" node "$PLUGIN_ROOT/hooks/lib/parse-bash-writes.mjs" 2>/dev/null)"
outside="$(printf '%s' "$pj" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const a=JSON.parse(s).outside;process.stdout.write(a&&a.length?a[0]:"")}catch(e){}})')"
troot="$(printf '%s' "$pj" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const a=JSON.parse(s).trustRoot;process.stdout.write(a&&a.length?a[0]:"")}catch(e){}})')"
trootcount="$(printf '%s' "$pj" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String((JSON.parse(s).trustRoot||[]).length))}catch(e){process.stdout.write("0")}})')"

# General "no writes outside the project directory" parity with guard-scope
# (issue #31): carve-outs for ~/.claude (incl. memory), temp dirs, and /dev.
if enforcement_on enforceProjectDirScope && [ -n "$outside" ]; then
  deny_soft "writing outside the project directory is not allowed: $outside (guard-scope enforces the same rule for the editor tools; ~/.claude, temp dirs, and /dev are carved out)"
fi

# Trust-root protection can be relaxed per-repo via enforcement.protectTrustRoots.
enforcement_on protectTrustRoots || allow

# Sanctioned carve-out (issue #14): the release-captain writes the
# release-intent flag to signal a release is in progress. Only that exact path,
# only that role, and only when the command touches no other trust-root file.
if [ "$active" = "release-captain" ] \
   && printf '%s' "$cmd" | grep -Eq '\.factory/state/release-intent\.json' \
   && ! printf '%s' "$cmd" | grep -Eq '\.factory/config\.json|\.factory/review/|\.factory/state/(gate-receipt|release-proof|roadmap-proof|loop|paused)'; then
  allow
fi

# First-run /factory-init may create .factory/config.json via the shell (heredoc
# redirect). Allow it ONLY while the config does not yet exist AND config.json is
# the SOLE trust-root target — checked against the resolved trust-root LIST, not
# a literal grep, so a command that ALSO plants state (e.g.
# `cd .factory && > config.json; > state/paused`) is not smuggled through the
# carve-out (its trust-root list has 2 entries). Once created, the config is
# edited as committed source (issues #1, #54).
if [ ! -f "$CONFIG_FILE" ] \
   && [ "$trootcount" = "1" ] \
   && printf '%s' "$troot" | grep -q '/\.factory/config\.json$'; then
  allow
fi

# A redirect/tee target that RESOLVES into a trust root — even via a `cd` the
# raw-text grep below would miss (issue #3: `cd .factory/state && > paused`) — is
# a forgery attempt. Hard boundary.
[ -n "$troot" ] && deny "writing to the factory's trust roots via the shell is not allowed — these are hook-managed and cannot be hand-forged (attempted: $troot)"

# Belt-and-suspenders for literal trust-root references via a mutating construct.
# The redirect/tee/cp/mv/dd/install/ln/touch/truncate targets are already
# resolved by parse-bash-writes above; this literal-text fallback additionally
# covers sed -i / git checkout / rm and anchors every verb at command start OR
# after a separator/whitespace (not a REQUIRED leading space), so a command that
# STARTS with the verb (`cp forged .factory/state/gate-receipt.json`,
# `touch .factory/state/paused`) is caught too (issues #2, #50).
printf '%s' "$cmd" | grep -Eq '\.factory/(state|review)/|\.factory/config\.json' || allow
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:]]|[0-9]|&)>>?|(^|[;&|[:space:]])(tee|cp|mv|dd|install|ln|truncate|rm|touch)([[:space:]]|$)|sed[[:space:]]+-i|git[[:space:]]+checkout|>\|'; then
  deny "writing to the factory's trust roots (.factory/state, .factory/config.json, .factory/review) via the shell is not allowed — these are hook-managed. (The green receipt, release/roadmap proofs, and config cannot be hand-forged.)"
fi
allow
