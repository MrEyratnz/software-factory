#!/usr/bin/env bash
# guard-commit — TDD is law / never commit red. Fast, fail-early UX; CI is the
# authoritative boundary that re-runs the identical gate.
#
# Denies a `git commit` unless ALL hold:
#   (a) no bypass flag (--no-verify / --no-gpg-sign)
#   (b) the message is a valid Conventional Commit (via factory-core commit_lint)
#   (c) tests-first: a feat/fix that stages source globs must also stage a test
#   (d) green: a gate receipt exists whose git-write-tree hash matches the tree
. "$(dirname "$0")/../lib/common.sh"

respect_pause guard-commit
[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
[ -n "$cmd" ] || allow

info="$(printf '%s' "$cmd" | node "$PLUGIN_ROOT/hooks/lib/parse-git-commit.mjs" 2>/dev/null)"
is_commit="$(printf '%s' "$info" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).isCommit))}catch(e){process.stdout.write("false")}})')"
[ "$is_commit" = "true" ] || allow

# The repo this commit actually targets (honors `cd <dir> &&`/`git -C <dir>`),
# so the green gate binds to it, not the fixed session project (issue #28).
target_root="$(repo_root "$(command_target_dir "$cmd")")"

# (a) bypass flags
bypass="$(printf '%s' "$info" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).bypass))}catch(e){process.stdout.write("false")}})')"
[ "$bypass" = "true" ] && { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"bypass"}'; deny "commit bypass flags (--no-verify/--no-gpg-sign) are not allowed — the gates are the point"; }

message="$(printf '%s' "$info" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).message||"")}catch(e){}})')"

# (b) conventional-commit lint (only when a -m message is visible)
ctype=""
if [ -n "$message" ]; then
  lint="$(printf '{"message":%s}' "$(json_str "$message")" | fc commit-lint)"
  ok="$(printf '%s' "$lint" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).ok))}catch(e){process.stdout.write("true")}})')"
  ctype="$(printf '%s' "$lint" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).type||"")}catch(e){}})')"
  if enforcement_on conventionalCommitLint; then
    [ "$ok" = "false" ] && { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"lint"}'; deny_soft "commit message is not a valid Conventional Commit (feat/fix/…): $message"; }
  fi
fi

# (c) tests-first for feat/fix
src_re="$(config_get sourceRegex '^src/')"
test_re="$(config_get testRegex '(\.test\.|\.spec\.|_test\.|/tests?/|\.feature$)')"
if { [ "$ctype" = "feat" ] || [ "$ctype" = "fix" ]; } && enforcement_on requireTestsFirst; then
  files="$(staged_files "$target_root")"
  # `git commit -a/-am` stages tracked modifications AT commit time, so nothing
  # is staged yet at PreToolUse — evaluate the tracked changeset instead, or the
  # TDD check would be silently skipped.
  if printf '%s' "$cmd" | grep -Eq 'commit[^|&;]*[[:space:]]-[A-Za-z]*a'; then
    files="$( cd "$target_root" 2>/dev/null && git diff --name-only HEAD 2>/dev/null )"
  fi
  if [ -n "$files" ]; then
    has_src="$(printf '%s\n' "$files" | grep -Eq "$src_re" && echo yes || echo no)"
    has_test="$(printf '%s\n' "$files" | grep -Eq "$test_re" && echo yes || echo no)"
    [ "$has_src" = "yes" ] && [ "$has_test" = "no" ] && {
      otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"tests-first"}'
      deny_soft "tests-first: this ${ctype} stages source but no test — write the failing test first (TDD)"
    }
  fi
fi

# (d) green receipt, bound to the current tree
if enforcement_on requireGreenReceiptOnCommit; then
  receipt="$(receipt_file "$target_root")"
  [ -f "$receipt" ] || { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"no-receipt"}'; deny_soft "no green gate receipt — run the full test suite; it must pass on this exact tree before committing"; }
  # When a signing key is configured, a hand-written receipt (no/invalid
  # signature) cannot certify green — this is a hard boundary, not a heuristic.
  receipt_verify "$receipt" || { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"bad-sig"}'; deny "the green receipt's signature is missing or invalid — a hand-written receipt cannot certify green (it was not minted by the gate)"; }
  rok="$(REC="$receipt" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("false")}')"
  rtree="$(REC="$receipt" node -e 'const fs=require("fs");try{process.stdout.write(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).tree||"")}catch(e){}')"
  [ "$rok" = "true" ] || { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"red"}'; deny_soft "the last gate run was red — fix it to green before committing"; }
  # Fail closed: if we cannot compute the current tree hash, we cannot certify the
  # receipt still matches, so refuse rather than allow.
  cur="$(tree_hash "$target_root")"
  [ -n "$cur" ] || { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"no-tree-hash"}'; deny "cannot compute the working-tree hash — refusing to certify green"; }
  [ "$cur" = "$rtree" ] || { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"stale-tree"}'; deny_soft "the tree changed since tests last passed — re-run the suite to refresh the green receipt"; }
fi

otel_emit factory_gate_commit_total sum 1 '{"result":"allow"}'
allow
