#!/usr/bin/env bash
# guard-release — never release from red / smoke the real artifact / no bypass.
# Gates release verbs on BOTH substrates: Bash (git tag, gh release create,
# npm publish, docker push, release-please) and the github-MCP push/merge paths
# (while a release is in progress), so a release can't route around a Bash-only
# matcher. Requires a release-gate proof: green on the BUILT artifact + clean
# Conventional-Commit history + on the configured release branch.
. "$(dirname "$0")/../lib/common.sh"

tn="$(field tool_name)"
cmd="$(field tool_input.command)"
rel_re="$(config_get releaseVerbRegex '(git tag|gh release create|npm publish|docker push|release-please|npm version )')"

is_release=no
case "$tn" in
  Bash) printf '%s' "$cmd" | grep -Eq "$rel_re" && is_release=yes ;;
  mcp__github__merge_pull_request|mcp__github__push_files|mcp__github__create_or_update_file)
    [ -f "$STATE_DIR/release-intent.json" ] && is_release=yes ;;
esac
[ "$is_release" = "yes" ] || allow

relb="$(config_get releaseBranch 'main')"
cur="$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$cur" ] && [ "$cur" != "$relb" ] && deny "releases are cut only from '$relb' (currently on '$cur')"

proof="$STATE_DIR/release-proof.json"
[ -f "$proof" ] || deny "no release-gate proof — the full suite must be green on the BUILT artifact and history Conventional-Commit clean before releasing"
pok="$(REC="$proof" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("false")}')"
[ "$pok" = "true" ] || deny "release gate not satisfied (never release from red)"

# Also require a fresh green gate-receipt bound to the CURRENT tree, so a release
# is never cut from a tree that is not green right now (binds the proof to the
# tree, not just an ok flag). Fail closed.
receipt="$STATE_DIR/gate-receipt.json"
[ -f "$receipt" ] || deny "no green gate receipt — the suite must be green on this exact tree before releasing"
gok="$(REC="$receipt" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("false")}')"
gtree="$(REC="$receipt" node -e 'const fs=require("fs");try{process.stdout.write(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).tree||"")}catch(e){}')"
cur="$(tree_hash)"
[ "$gok" = "true" ] || deny "the gate is red — never release from red"
[ -n "$cur" ] && [ "$cur" = "$gtree" ] || deny "the tree changed since the suite last passed — re-run it before releasing"
allow
