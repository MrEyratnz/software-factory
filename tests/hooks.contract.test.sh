#!/usr/bin/env bash
# Hermetic contract tests for every hook: feed each script synthetic Claude Code
# event JSON inside throwaway git repos and assert the EXACT exit code (0 =
# allow/proceed, 2 = block). No live model, no network — `gh` is replaced by a
# PATH shim. This proves the factory's laws are enforced, independent of any
# agent or command.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$ROOT"
S="$ROOT/hooks/scripts"
PASS=0; FAIL=0
TMPROOT="$(mktemp -d)"
trap 'cd /; rm -rf "$TMPROOT"' EXIT

# assert_exit <expected> <label>  (reads the hook stdin from $EVENT, env from caller)
assert_exit() {
  local expected="$1" label="$2" got
  printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$expected" ]; then PASS=$((PASS+1)); # echo "ok   - $label"
  else FAIL=$((FAIL+1)); echo "FAIL - $label (expected exit $expected, got $got)"; fi
}

# mkrepo — a throwaway git repo with a factory config; echoes its path.
mkrepo() {
  local d; d="$(mktemp -d "$TMPROOT/repo.XXXXXX")"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main 2>/dev/null; \
    git config user.email t@t && git config user.name t && git commit --allow-empty -q -m init )
  mkdir -p "$d/.factory/state" "$d/.factory/review" "$d/.factory/panel" "$d/docs" "$d/src"
  cat > "$d/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.|\\.spec\\.|/tests?/|\\.feature$)",
  "testCommandRegex": "(npm ((run|-s) )?test|node --test)", "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main", "generators": [] }
JSON
  printf '%s' "$d"
}

mk_gh_shim() { # $1 = json to echo for `gh issue list`
  local dir; dir="$(mktemp -d "$TMPROOT/ghshim.XXXXXX")"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
# minimal gh shim: 'issue list' prints canned JSON, everything else no-ops
case "\$*" in
  *"issue list"*) printf '%s' '$1' ;;
  *) : ;;
esac
EOF
  chmod +x "$dir/gh"; printf '%s' "$dir"
}

# tree_hash for a repo (mirrors common.sh) so tests can build a matching receipt.
repo_tree_hash() {
  local d="$1" idx out
  idx="$(mktemp)"; rm -f "$idx"
  out="$( cd "$d" && GIT_INDEX_FILE="$idx" git add -A -- ':(exclude).factory' >/dev/null 2>&1; GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null )"
  rm -f "$idx"; printf '%s' "$out"
}

evt() { # helper builds an event JSON: evt <tool_name> <tool_input_json> [extra]
  local cwd="$1" tn="$2" ti="$3" extra="${4:-}"
  printf '{"tool_name":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_input":%s%s}' \
    "$tn" "$cwd" "$ti" "$extra"
}

echo "# guard-commit"
SCRIPT="$S/guard-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"npm test"}')"; assert_exit 0 "non-commit bash allowed"
echo x > "$R/src/a.ts"; echo x > "$R/src/a.test.ts"; ( cd "$R" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: add a\""}')"; assert_exit 2 "commit blocked with no green receipt"
# write a matching green receipt, then it should pass
TH="$(repo_tree_hash "$R")"
printf '{"tree":"%s","ok":true,"stages":[{"name":"suite","ok":true}]}' "$TH" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: add a\""}')"; assert_exit 0 "commit allowed with matching green receipt + test staged"
EVENT="$(evt "$R" Bash '{"command":"git commit --no-verify -m \"feat: add a\""}')"; assert_exit 2 "commit --no-verify blocked"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"added a thing\""}')"; assert_exit 2 "non-conventional message blocked"
# feat staging source but no test
R2="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R2"; echo x > "$R2/src/b.ts"; ( cd "$R2" && git add -A )
TH2="$(repo_tree_hash "$R2")"; printf '{"tree":"%s","ok":true}' "$TH2" > "$R2/.factory/state/gate-receipt.json"
EVENT="$(evt "$R2" Bash '{"command":"git commit -m \"feat: b\""}')"; assert_exit 2 "tests-first: feat with source but no test blocked"

echo "# guard-scope"
SCRIPT="$S/guard-scope.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
echo reviewer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":"src/x.ts"}')"; assert_exit 2 "reviewer cannot write"
echo implementer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":"src/x.ts"}')"; assert_exit 0 "implementer can write src"
EVENT="$(evt "$R" Write '{"file_path":".factory/config.json"}')"; assert_exit 2 "implementer cannot write factory config"
EVENT="$(evt "$R" Write '{"file_path":".factory/state/gate-receipt.json"}')"; assert_exit 2 "nobody edits the receipt via tools"
echo architect > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":"docs/ADR.md"}')"; assert_exit 0 "architect can write docs"
EVENT="$(evt "$R" Write '{"file_path":"src/x.ts"}')"; assert_exit 2 "architect cannot write src"

echo "# guard-roadmap"
SCRIPT="$S/guard-roadmap.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Edit '{"file_path":"docs/ROADMAP.md","old_string":"- [ ] build the thing","new_string":"- [x] build the thing"}')"
assert_exit 2 "checkbox flip blocked without merged-green proof"
printf '{"mergedGreenSha":"a1b2c3d4e5f6"}' > "$R/.factory/state/roadmap-proof.json"
assert_exit 0 "checkbox flip allowed with proof"
EVENT="$(evt "$R" Edit '{"file_path":"docs/ROADMAP.md","old_string":"some text","new_string":"other text"}')"
assert_exit 0 "non-flip roadmap edit allowed"

echo "# guard-release"
SCRIPT="$S/guard-release.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"echo hi"}')"; assert_exit 0 "non-release bash allowed"
EVENT="$(evt "$R" Bash '{"command":"git tag v1.0.0"}')"; assert_exit 2 "release verb blocked without proof"
printf '{"ok":true}' > "$R/.factory/state/release-proof.json"
EVENT="$(evt "$R" Bash '{"command":"git tag v1.0.0"}')"; assert_exit 0 "release verb allowed with proof on release branch"

echo "# record-green"
SCRIPT="$S/record-green.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"npm test"}' ',"tool_response":{"exitCode":0}')"
assert_exit 0 "record-green exits 0"
if [ -f "$R/.factory/state/gate-receipt.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - record-green wrote a receipt"; fi
ROK="$(REC="$R/.factory/state/gate-receipt.json" node -e 'const fs=require("fs");process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))')"
if [ "$ROK" = "true" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - receipt ok=true"; fi

echo "# debt-reconcile"
SCRIPT="$S/debt-reconcile.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT='{"hook_event_name":"Stop","cwd":"'"$R"'"}'
GHEMPTY="$(mk_gh_shim '[]')"
( export PATH="$GHEMPTY:$PATH"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1 ); [ $? = 0 ] && { PASS=$((PASS+1)); } || { FAIL=$((FAIL+1)); echo "FAIL - no findings allows stop"; }
printf '[{"location":"src/a.ts:1","impact":"bug","provenance":"introduced","suggestedFix":"fix","severity":"high","status":"open"}]' > "$R/.factory/review/r.json"
( export PATH="$GHEMPTY:$PATH"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1 ); [ $? = 2 ] && { PASS=$((PASS+1)); } || { FAIL=$((FAIL+1)); echo "FAIL - unfiled finding blocks stop"; }
# mark fixed → allowed
printf '[{"location":"src/a.ts:1","impact":"bug","provenance":"introduced","suggestedFix":"fix","severity":"high","status":"fixed"}]' > "$R/.factory/review/r.json"
( export PATH="$GHEMPTY:$PATH"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1 ); [ $? = 0 ] && { PASS=$((PASS+1)); } || { FAIL=$((FAIL+1)); echo "FAIL - fixed finding allows stop"; }
# filed in gh → allowed
printf '[{"location":"src/a.ts:1","impact":"bug","provenance":"introduced","suggestedFix":"fix","severity":"high","status":"open"}]' > "$R/.factory/review/r.json"
FP="$(printf '{"location":"src/a.ts:1","impact":"bug"}' | node "$ROOT/connector/src/cli.mjs" fingerprint | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.parse(s).fingerprint))')"
GHFILED="$(mk_gh_shim '[{"title":"debt","body":"fingerprint: '"$FP"'"}]')"
( export PATH="$GHFILED:$PATH"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1 ); [ $? = 0 ] && { PASS=$((PASS+1)); } || { FAIL=$((FAIL+1)); echo "FAIL - filed finding allows stop"; }

echo "# loop-guard"
SCRIPT="$S/loop-guard.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT='{"hook_event_name":"Stop","cwd":"'"$R"'"}'
assert_exit 0 "no loop → allow stop"
printf '## M0\n- [ ] do the thing\n' > "$R/docs/ROADMAP.md"
printf '{"active":true,"iterations":0,"maxIterations":3}' > "$R/.factory/state/loop.json"
assert_exit 2 "active loop with work re-blocks stop"
printf '## M0\n- [x] do the thing\n' > "$R/docs/ROADMAP.md"
printf '{"active":true,"iterations":0,"maxIterations":3}' > "$R/.factory/state/loop.json"
assert_exit 0 "active loop with roadmap complete → allow"

echo "# validate-handoff"
SCRIPT="$S/validate-handoff.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT='{"hook_event_name":"SubagentStop","agent_type":"reviewer","cwd":"'"$R"'"}'
assert_exit 2 "reviewer with no artifact blocked"
printf '[{"location":"a.ts:1","impact":"x","provenance":"introduced","suggestedFix":"y","severity":"low"}]' > "$R/.factory/review/r.json"
assert_exit 0 "reviewer with valid findings allowed"

echo "# ledger-record"
SCRIPT="$S/ledger-record.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A && git commit -q -m "feat: a" )
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: a\""}' ',"tool_response":{"exitCode":0}')"
assert_exit 0 "ledger-record exits 0"
if [ -s "$R/.factory/ledger.jsonl" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - ledger line appended"; fi

echo "# check-drift & orientation"
SCRIPT="$S/check-drift.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Write '{"file_path":"src/a.ts"}')"; assert_exit 0 "no generators → allow"
SCRIPT="$S/bootstrap.sh"; EVENT='{"hook_event_name":"SessionStart","cwd":"'"$R"'"}'; assert_exit 0 "bootstrap exits 0"
SCRIPT="$S/inject-status.sh"; EVENT='{"hook_event_name":"UserPromptSubmit","cwd":"'"$R"'"}'; assert_exit 0 "inject-status exits 0"

echo
echo "hooks contract: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
