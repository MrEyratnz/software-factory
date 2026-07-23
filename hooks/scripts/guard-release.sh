#!/usr/bin/env bash
# guard-release — never release from red / smoke the real artifact / no bypass.
# Gates release verbs on BOTH substrates: Bash (git tag, gh release create,
# npm publish, docker push, release-please) and the github-MCP
# push/create-or-update/delete/merge paths (while a release is in progress),
# so a release can't route around a Bash-only matcher. Requires a release-gate
# proof: green on the BUILT artifact + clean Conventional-Commit history + on
# the configured release branch.
. "$(dirname "$0")/../lib/common.sh"

respect_pause guard-release
# issue #52: degrade LOUDLY (never silently) when node is unavailable.
node_guard guard-release || allow
tn="$(field tool_name)"
cmd="$(field tool_input.command)"
# releaseVerbRegex is read fail-OPEN here (config_get returns the built-in
# default on a malformed config), and this read runs BEFORE require_config_sane
# below. That is a DELIBERATE, documented residual (issue #79): a present-but-
# corrupt .factory/config.json falls back to the default verbs, so a repo's
# CUSTOM releaseVerbRegex verb (e.g. `make deploy`) would not be detected until
# the config is fixed. It is left open because:
#   - the config is a protected trust root (guard-scope / guard-bash-writes deny
#     the policed agent any write to it, incl. a target repo's — issue #53), so
#     the corrupt-config precondition is an honest mistake, not an attacker move;
#   - the DEFAULT release verbs (git tag / gh release create / npm publish / …)
#     ARE still detected on a malformed config, and require_config_sane below
#     then fails them CLOSED — only a custom-only verb slips;
#   - closing it can't be done in this gate's role: guard-release matches EVERY
#     Bash command, so failing closed before detection would deny innocent reads
#     (ls / git status) on every command — betraying a gate that exists to gate
#     RELEASES — and it would buy nothing, because the agent can't repair a
#     corrupt config through its hooked tools anyway (guard-bash-writes already
#     denies `git checkout .factory/config.json` and guard-scope denies editing
#     it), so the fix comes out-of-band from a human regardless. guard-commit's
#     analogous check is safe only because it sits behind an is_commit gate;
#   - CI re-runs the release gate as the authoritative boundary regardless.
rel_re="$(config_get releaseVerbRegex '(git tag|gh release create|npm publish|docker push|release-please|npm version )')"

is_release=no
case "$tn" in
  Bash)
    # Command-position, quote-aware release detection: a release verb inside a
    # commit message / echo / comment is NOT a release (so `git commit -m "...npm
    # publish..."` is not false-blocked), and `git tag` counts only when it
    # CREATES a tag — never for read-only listing (`git tag -l`) (issue #52).
    [ -n "$rel_re" ] && [ "$(printf '%s' "$cmd" | node "$PLUGIN_ROOT/hooks/lib/classify-release.mjs" "$rel_re" 2>/dev/null | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).isRelease))}catch(e){process.stdout.write("false")}})')" = "true" ] && is_release=yes ;;
  mcp__github__merge_pull_request|mcp__github__push_files|mcp__github__create_or_update_file|mcp__github__delete_file)
    [ -f "$STATE_DIR/release-intent.json" ] && is_release=yes ;;
esac
[ "$is_release" = "yes" ] || allow

# The repo this release actually targets (honors `cd <dir> &&`/`git -C <dir>`),
# so the branch/receipt/tree checks bind to it, not the fixed session project
# (issue #28). For the MCP tools cmd is empty and this is the session project.
target_root="$(repo_root "$(command_target_dir "$cmd")")"

# Advisory only when NEITHER the session NOR the target repo is initialized (see
# guard-commit): enforcing on session-init keeps the issue-#28 model, and ALSO
# on target-init stops an un-inited session bypassing an initialized sibling's
# release gate. Both un-inited → step aside (no release-proof producer here).
if ! factory_initialized && [ ! -f "$target_root/.factory/config.json" ]; then
  otel_emit factory_gate_uninitialized_total sum 1 '{"hook":"guard-release"}'
  allow
fi

# The governing config must be valid JSON, or a corrupt contract would silently
# revert this repo's gates to defaults (issue #65) — fail closed here.
require_config_sane "$target_root"

# target-aware (issue #53). NOTE: releaseVerbRegex above is deliberately the
# SESSION config's — release detection runs before the target repo is known.
relb="$(config_get_for "$target_root" releaseBranch 'main')"
cur="$(cd "$target_root" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$cur" ] && [ "$cur" != "$relb" ] && { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny_soft "releases are cut only from '$relb' (currently on '$cur')"; }

if enforcement_on_for "$target_root" requireReleaseProof; then
  proof="$STATE_DIR/release-proof.json"
  [ -f "$proof" ] || { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny_soft "no release-gate proof — the full suite must be green on the BUILT artifact and history Conventional-Commit clean before releasing"; }
  receipt_verify "$proof" || { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny "the release proof's signature is missing or invalid — a hand-written proof cannot authorize a release"; }
  pok="$(REC="$proof" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("false")}')"
  [ "$pok" = "true" ] || { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny_soft "release gate not satisfied (never release from red)"; }
fi

# Also require a fresh green gate-receipt bound to the CURRENT tree, so a release
# is never cut from a tree that is not green right now (binds the proof to the
# tree, not just an ok flag). Fail closed.
receipt="$(receipt_file "$target_root")"
[ -f "$receipt" ] || { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny_soft "no green gate receipt — the suite must be green on this exact tree before releasing"; }
receipt_verify "$receipt" || { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny "the green receipt's signature is missing or invalid — a hand-written receipt cannot certify green"; }
gok="$(REC="$receipt" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("false")}')"
gtree="$(REC="$receipt" node -e 'const fs=require("fs");try{process.stdout.write(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).tree||"")}catch(e){}')"
cur="$(tree_hash "$target_root")"
[ "$gok" = "true" ] || { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny_soft "the gate is red — never release from red"; }
[ -n "$cur" ] && [ "$cur" = "$gtree" ] || { otel_emit factory_gate_release_total sum 1 '{"result":"deny"}'; deny_soft "the tree changed since the suite last passed — re-run it before releasing"; }
otel_emit factory_gate_release_total sum 1 '{"result":"allow"}'
allow
