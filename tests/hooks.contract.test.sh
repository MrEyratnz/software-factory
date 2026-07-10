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
  "testCommandRegex": "(npm ((run|-s) )?test|node --test)", "testCommand": "npm test",
  "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [] }
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
# fail-conservative commit detection: forms that evade the old loose-adjacency
# regex (git alias, and git/commit split across a line-continuation newline)
# must still engage the gate — no green receipt is present in $R at this point.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"git ci -m \"feat: add a\""}')"; assert_exit 2 "commit via unknown/alias subcommand (git ci) blocked (evasion)"
EVENT="$(evt "$R" Bash '{"command":"git \\\ncommit -m \"feat: add a\""}')"; assert_exit 2 "commit split across a line-continuation newline blocked (evasion)"
# and clearly-non-commit git subcommands must still be allowed even when split
# across a newline, so the fail-conservative fix doesn't break the workflow.
EVENT="$(evt "$R" Bash '{"command":"git \\\nstatus"}')"; assert_exit 0 "git status split across newline still allowed"
EVENT="$(evt "$R" Bash '{"command":"git status"}')"; assert_exit 0 "git status allowed"
EVENT="$(evt "$R" Bash '{"command":"git diff"}')"; assert_exit 0 "git diff allowed"
EVENT="$(evt "$R" Bash '{"command":"git log"}')"; assert_exit 0 "git log allowed"
EVENT="$(evt "$R" Bash '{"command":"git add ."}')"; assert_exit 0 "git add allowed"
# fail-conservative on bare/indirect git invocations (#6 round 2): a bare
# `git` whose subcommand is supplied indirectly (xargs feeding the final
# arg, or the whole invocation hidden inside a `sh -c`/`bash -c` string)
# cannot be confidently parsed as non-commit, so it must still engage the
# gate even though no literal "commit" token sits next to the "git" token.
EVENT="$(evt "$R" Bash '{"command":"printf \"%s\" \"commit -am x\" | xargs git"}')"; assert_exit 2 "commit via xargs-supplied subcommand blocked (evasion)"
EVENT="$(evt "$R" Bash '{"command":"sh -c '"'"'git commit -m \"feat: x\"'"'"'"}')"; assert_exit 2 "commit hidden inside sh -c string blocked (evasion)"
# guard-rail: a genuinely safe indirect command (no commit anywhere) must not
# be over-blocked just because it mentions xargs alongside git.
EVENT="$(evt "$R" Bash '{"command":"echo hello | xargs git status"}')"; assert_exit 0 "safe indirect git status via xargs still allowed"
# #26: a `git` substring inside a filesystem PATH or a hyphenated filename is
# not a command — these path mentions must NOT engage the commit gate (no
# receipt is present in $R, so a false positive would deny with exit 2).
EVENT="$(evt "$R" Bash '{"command":"find /home/user/git/software-factory -iname parse-git-commit.mjs"}')"; assert_exit 0 "#26: git inside a path/hyphenated filename is not a commit (allowed)"
EVENT="$(evt "$R" Bash '{"command":"cat .git/config"}')"; assert_exit 0 "#26: .git/ path mention allowed"
EVENT="$(evt "$R" Bash '{"command":"grep -r foo /srv/git/mirrors"}')"; assert_exit 0 "#26: /git/ path mention allowed"
# but a real git commit sitting alongside a path mention is still caught.
EVENT="$(evt "$R" Bash '{"command":"cd /home/user/git/foo && git commit -m \"feat: x\""}')"; assert_exit 2 "#26: real git commit alongside a path mention still blocked"

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
echo release-captain > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":"src/x.ts"}')"; assert_exit 2 "release-captain cannot write src"
EVENT="$(evt "$R" Write '{"file_path":"docs/x.md"}')"; assert_exit 0 "release-captain can write docs"
echo tech-debt-clerk > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":"src/x.ts"}')"; assert_exit 2 "tech-debt-clerk cannot write src"
EVENT="$(evt "$R" Write '{"file_path":".factory/review/x.json"}')"; assert_exit 0 "tech-debt-clerk can write its review status"
# #31: the editor-tool out-of-project ban carves out ~/.claude (memory feature).
echo implementer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":"'"$HOME"'/.claude/projects/p/memory/note.md"}')"; assert_exit 0 "#31: editor write to ~/.claude memory carve-out allowed"
EVENT="$(evt "$R" Write '{"file_path":"/etc/evil.conf"}')"; assert_exit 2 "#31: editor write to a stray absolute path still blocked"
rm -f "$R/.factory/active-agent"

echo "# guard-roadmap"
SCRIPT="$S/guard-roadmap.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Edit '{"file_path":"docs/ROADMAP.md","old_string":"- [ ] build the thing","new_string":"- [x] build the thing"}')"
assert_exit 2 "checkbox flip blocked without merged-green proof"
printf '{"mergedGreenSha":"a1b2c3d4e5f6"}' > "$R/.factory/state/roadmap-proof.json"
assert_exit 2 "checkbox flip still blocked with an item-unbound proof (skeleton key)"
printf '{"mergedGreenSha":"a1b2c3d4e5f6","item":"build the thing"}' > "$R/.factory/state/roadmap-proof.json"
assert_exit 0 "checkbox flip allowed with an item-bound proof"
EVENT="$(evt "$R" Edit '{"file_path":"docs/ROADMAP.md","old_string":"some text","new_string":"other text"}')"
assert_exit 0 "non-flip roadmap edit allowed"
# MultiEdit carrying a flip must also be gated (findings: MultiEdit bypass)
rm -f "$R/.factory/state/roadmap-proof.json"
EVENT="$(evt "$R" MultiEdit '{"file_path":"docs/ROADMAP.md","edits":[{"old_string":"- [ ] a","new_string":"- [x] a"}]}')"
assert_exit 2 "MultiEdit checkbox flip blocked without proof"

echo "# guard-release"
SCRIPT="$S/guard-release.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"echo hi"}')"; assert_exit 0 "non-release bash allowed"
EVENT="$(evt "$R" Bash '{"command":"git tag v1.0.0"}')"; assert_exit 2 "release verb blocked without proof"
printf '{"ok":true}' > "$R/.factory/state/release-proof.json"
EVENT="$(evt "$R" Bash '{"command":"git tag v1.0.0"}')"; assert_exit 2 "release still blocked without a fresh green gate-receipt"
THrel="$(repo_tree_hash "$R")"; printf '{"tree":"%s","ok":true}' "$THrel" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"git tag v1.0.0"}')"; assert_exit 0 "release allowed with proof + fresh green receipt on release branch"

echo "# guard-mcp-commit"
SCRIPT="$S/guard-mcp-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" mcp__github__create_or_update_file '{"owner":"o","repo":"r","path":"a.ts","content":"x","message":"feat: a"}')"
assert_exit 2 "create_or_update_file denied with no release intent"
EVENT="$(evt "$R" mcp__github__push_files '{"owner":"o","repo":"r","branch":"main","files":[]}')"
assert_exit 2 "push_files denied with no release intent"
EVENT="$(evt "$R" mcp__github__delete_file '{"owner":"o","repo":"r","path":"a.ts","message":"fix: remove a","branch":"main"}')"
assert_exit 2 "delete_file denied with no release intent"
printf '{"active":true}' > "$R/.factory/state/release-intent.json"
EVENT="$(evt "$R" mcp__github__create_or_update_file '{"owner":"o","repo":"r","path":"a.ts","content":"x","message":"feat: a"}')"
assert_exit 0 "create_or_update_file allowed under release intent (guard-release owns it)"
EVENT="$(evt "$R" mcp__github__push_files '{"owner":"o","repo":"r","branch":"main","files":[]}')"
assert_exit 0 "push_files allowed under release intent (guard-release owns it)"
EVENT="$(evt "$R" mcp__github__delete_file '{"owner":"o","repo":"r","path":"a.ts","message":"fix: remove a","branch":"main"}')"
assert_exit 0 "delete_file allowed under release intent (guard-release owns it)"
rm -f "$R/.factory/state/release-intent.json"
EVENT="$(evt "$R" Bash '{"command":"echo hi"}')"; assert_exit 0 "unrelated Bash tool allowed"
EVENT="$(evt "$R" mcp__github__merge_pull_request '{"owner":"o","repo":"r","pullNumber":1}')"; assert_exit 0 "other mcp tool (merge) unaffected"

echo "# release lifecycle: producers + cleanup (issue #14)"
# --- record-release-proof: the sanctioned producer of release-proof.json.
SCRIPT="$S/record-release-proof.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "releaseProofCommandRegex": "(npm run build|npm run smoke)" }
JSON
# no release in progress → no proof minted even on a green build.
EVENT="$(evt "$R" Bash '{"command":"npm run build"}' ',"tool_response":{"exitCode":0}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
if [ ! -f "$R/.factory/state/release-proof.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #14: no proof minted without release-intent"; fi
# release in progress + green build on release branch → proof ok:true.
printf '{"active":true}' > "$R/.factory/state/release-intent.json"
EVENT="$(evt "$R" Bash '{"command":"npm run build"}' ',"tool_response":{"exitCode":0}')"
assert_exit 0 "#14: record-release-proof exits 0"
POK="$(REC="$R/.factory/state/release-proof.json" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("missing")}')"
if [ "$POK" = "true" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #14: green build mints release-proof ok=true (got $POK)"; fi
# a failing build must not mint a proof.
rm -f "$R/.factory/state/release-proof.json"
EVENT="$(evt "$R" Bash '{"command":"npm run build"}' ',"tool_response":{"exitCode":1}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
if [ ! -f "$R/.factory/state/release-proof.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #14: failing build must not mint proof"; fi
# the minted proof is exactly what guard-release needs.
EVENT="$(evt "$R" Bash '{"command":"npm run build"}' ',"tool_response":{"exitCode":0}')"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
THrel="$(repo_tree_hash "$R")"; printf '{"tree":"%s","ok":true}' "$THrel" > "$R/.factory/state/gate-receipt.json"
SCRIPT="$S/guard-release.sh"; EVENT="$(evt "$R" Bash '{"command":"git tag v1.0.0"}')"; assert_exit 0 "#14: minted proof + fresh receipt lets guard-release allow the tag"
# --- release-cleanup: clears intent+proof at Stop.
SCRIPT="$S/release-cleanup.sh"
printf '{"active":true}' > "$R/.factory/state/release-intent.json"
printf '{"ok":true}' > "$R/.factory/state/release-proof.json"
EVENT='{"hook_event_name":"Stop","cwd":"'"$R"'"}'
assert_exit 0 "#14: release-cleanup exits 0"
if [ ! -f "$R/.factory/state/release-intent.json" ] && [ ! -f "$R/.factory/state/release-proof.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #14: cleanup removes intent+proof at Stop"; fi
# --- sanctioned intent producer: only the release-captain writes release-intent.
SCRIPT="$S/guard-scope.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
echo release-captain > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":".factory/state/release-intent.json"}')"; assert_exit 0 "#14: release-captain can write release-intent.json"
EVENT="$(evt "$R" Write '{"file_path":".factory/state/gate-receipt.json"}')"; assert_exit 2 "#14: release-captain cannot write other trust-root state"
echo implementer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":".factory/state/release-intent.json"}')"; assert_exit 2 "#14: a non-release-captain cannot write release-intent.json"
SCRIPT="$S/guard-bash-writes.sh"
echo release-captain > "$R/.factory/active-agent"
EVENT="$(evt "$R" Bash '{"command":"echo x > .factory/state/release-intent.json"}')"; assert_exit 0 "#14: release-captain may shell-write release-intent.json"
EVENT="$(evt "$R" Bash '{"command":"echo x > .factory/state/gate-receipt.json"}')"; assert_exit 2 "#14: release-captain still cannot shell-write the receipt"
rm -f "$R/.factory/active-agent"

echo "# guard-bash-writes"
SCRIPT="$S/guard-bash-writes.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"printf x > .factory/state/gate-receipt.json"}')"; assert_exit 2 "shell write to gate-receipt blocked"
EVENT="$(evt "$R" Bash '{"command":"sed -i s/a/b/ .factory/config.json"}')"; assert_exit 2 "shell sed -i of config blocked"
EVENT="$(evt "$R" Bash '{"command":"echo hi > .factory/review/x.json"}')"; assert_exit 2 "shell write to review dir blocked"
EVENT="$(evt "$R" Bash '{"command":"cat .factory/config.json"}')"; assert_exit 0 "reading config is fine"
EVENT="$(evt "$R" Bash '{"command":"echo hi > src/a.ts"}')"; assert_exit 0 "writing normal source is fine"
# read-only role (reviewer): ANY tree-mutating bash write is denied, regardless
# of target path — this is what makes "read-only by construction" true for
# Bash, not just prose.
echo reviewer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Bash '{"command":"echo x > src/evil.ts"}')"; assert_exit 2 "reviewer: bash write to arbitrary source blocked"
EVENT="$(evt "$R" Bash '{"command":"sed -i s/a/b/ src/a.ts"}')"; assert_exit 2 "reviewer: sed -i blocked"
EVENT="$(evt "$R" Bash '{"command":"git checkout -- ."}')"; assert_exit 2 "reviewer: git checkout blocked"
# guard-rails: read-only inspection commands must still pass for the reviewer.
EVENT="$(evt "$R" Bash '{"command":"git diff"}')"; assert_exit 0 "reviewer: git diff allowed"
EVENT="$(evt "$R" Bash '{"command":"node --test \"test/**/*.test.mjs\""}')"; assert_exit 0 "reviewer: node --test allowed"
EVENT="$(evt "$R" Bash '{"command":"grep -r foo ."}')"; assert_exit 0 "reviewer: grep allowed"
# regression: a mutator verb at the very START of the command (no leading
# whitespace to anchor on) must still be caught — this is the under-block bug.
EVENT="$(evt "$R" Bash '{"command":"rm -rf src/evil"}')"; assert_exit 2 "reviewer: leading rm blocked"
EVENT="$(evt "$R" Bash '{"command":"tee .factory/active-agent <<< implementer"}')"; assert_exit 2 "reviewer: leading tee (role self-escalation) blocked"
EVENT="$(evt "$R" Bash '{"command":"cp a b"}')"; assert_exit 2 "reviewer: leading cp blocked"
EVENT="$(evt "$R" Bash '{"command":"git clean -fd"}')"; assert_exit 2 "reviewer: git clean blocked"
EVENT="$(evt "$R" Bash '{"command":"echo x >> src/evil.ts"}')"; assert_exit 2 "reviewer: append redirect blocked"
EVENT="$(evt "$R" Bash '{"command":"sed -i s/a/b/ hooks/lib/common.sh"}')"; assert_exit 2 "reviewer: sed -i of arbitrary file blocked"
# regression: a bare `>` inside a quoted argument (not an actual redirect) must
# NOT be denied — this is the over-block bug (grep for arrow functions, common
# in this JS/TS repo).
EVENT="$(evt "$R" Bash '{"command":"grep -rn \"=>\" src/"}')"; assert_exit 0 "reviewer: grep for => (quoted, not a redirect) allowed"
EVENT="$(evt "$R" Bash '{"command":"git log --stat"}')"; assert_exit 0 "reviewer: git log --stat allowed"
EVENT="$(evt "$R" Bash '{"command":"grep -rn foo ."}')"; assert_exit 0 "reviewer: grep -rn allowed"
EVENT="$(evt "$R" Bash '{"command":"cat hooks/lib/common.sh"}')"; assert_exit 0 "reviewer: cat allowed"
EVENT="$(evt "$R" Bash '{"command":"ls -la"}')"; assert_exit 0 "reviewer: ls allowed"
# a non-read-only role (implementer) is unaffected: it may still write source,
# but the trust-root protection is unchanged.
echo implementer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Bash '{"command":"echo x > src/ok.ts"}')"; assert_exit 0 "implementer: bash write to source still allowed"
EVENT="$(evt "$R" Bash '{"command":"printf x > .factory/state/gate-receipt.json"}')"; assert_exit 2 "implementer: trust-root write still blocked"
EVENT="$(evt "$R" Bash '{"command":"echo x > .factory/state/gate-receipt.json"}')"; assert_exit 2 "implementer: trust-root write (echo) still blocked"
rm -f "$R/.factory/active-agent"
# #31: out-of-project Bash writes are denied (parity with guard-scope), with
# carve-outs for ~/.claude (incl. the memory feature), temp dirs, and /dev.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"cat > /some/other/path/file"}')"; assert_exit 2 "#31: redirect to an out-of-project path blocked"
EVENT="$(evt "$R" Bash '{"command":"tee /etc/evil.conf"}')"; assert_exit 2 "#31: tee to an out-of-project path blocked"
EVENT="$(evt "$R" Bash '{"command":"echo x > src/ok.ts"}')"; assert_exit 0 "#31: in-project redirect still allowed"
EVENT="$(evt "$R" Bash '{"command":"echo x > '"$HOME"'/.claude/projects/p/memory/note.md"}')"; assert_exit 0 "#31: bash write to ~/.claude memory carve-out allowed"
EVENT="$(evt "$R" Bash '{"command":"npm test 2>/dev/null"}')"; assert_exit 0 "#31: redirect to /dev/null allowed"
EVENT="$(evt "$R" Bash '{"command":"grep -rn \"=>\" src/"}')"; assert_exit 0 "#31: quoted => is not a redirect (no false positive)"
cat > "$R/.factory/config.json" <<'JSON'
{ "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "enforcement": { "enforceProjectDirScope": false } }
JSON
EVENT="$(evt "$R" Bash '{"command":"cat > /some/other/path/file"}')"; assert_exit 0 "#31: enforceProjectDirScope=false allows out-of-project write"

echo "# record-green"
SCRIPT="$S/record-green.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"npm test"}' ',"tool_response":{"exitCode":0}')"
assert_exit 0 "record-green exits 0"
if [ -f "$R/.factory/state/gate-receipt.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - record-green wrote a receipt"; fi
ROK="$(REC="$R/.factory/state/gate-receipt.json" node -e 'const fs=require("fs");process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))')"
if [ "$ROK" = "true" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - receipt ok=true"; fi
# Hardening: a forged/neutralized "suite" must NOT mint a receipt.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"echo npm test"}' ',"tool_response":{"exitCode":0}')"; assert_exit 0 "record-green tolerant of echo"
if [ ! -f "$R/.factory/state/gate-receipt.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - 'echo npm test' must NOT mint a receipt"; fi
EVENT="$(evt "$R" Bash '{"command":"npm test || true"}' ',"tool_response":{"exitCode":0}')"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
if [ ! -f "$R/.factory/state/gate-receipt.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - 'npm test || true' must NOT mint a receipt"; fi
# #22/#27: when the harness omits tool_response.exitCode, invoke the repo's
# allowlisted `testCommand` (NOT the arbitrary matched command) to get its REAL
# status instead of silently skipping the receipt (which would fail-close every
# commit). A passing invoker mints a green receipt.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
printf '%s' '{"name":"t","version":"1.0.0","scripts":{"test":"exit 0"}}' > "$R/package.json"
EVENT="$(evt "$R" Bash '{"command":"npm test"}')"
assert_exit 0 "record-green (no exitCode) re-execs the suite and exits 0"
if [ -f "$R/.factory/state/gate-receipt.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - re-exec of a passing suite mints a receipt"; fi
ROK="$(REC="$R/.factory/state/gate-receipt.json" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("missing")}')"
if [ "$ROK" = "true" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - re-exec green receipt ok=true (got $ROK)"; fi
# A FAILING re-run must NOT yield a green receipt.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
printf '%s' '{"name":"t","version":"1.0.0","scripts":{"test":"exit 1"}}' > "$R/package.json"
EVENT="$(evt "$R" Bash '{"command":"npm test"}')"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
ROK="$(REC="$R/.factory/state/gate-receipt.json" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("missing")}')"
if [ "$ROK" != "true" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - re-exec of a FAILING suite must not mint green (got $ROK)"; fi
# #27: never re-execute the ARBITRARY matched command to recover a missing exit
# code. A command that only *matches* testCommandRegex but is not the suite
# (here it would also touch a sentinel) must NOT be re-run; with no configured
# testCommand no receipt is minted (fail safe).
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.)", "testCommandRegex": "(npm test)",
  "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [] }
JSON
EVENT="$(evt "$R" Bash '{"command":"npm test; touch '"$R"'/ARBITRARY_RAN"}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
if [ ! -e "$R/ARBITRARY_RAN" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #27: arbitrary matched command must NOT be re-executed"; fi
if [ ! -f "$R/.factory/state/gate-receipt.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #27: no testCommand + no exitCode must not mint a receipt"; fi
# with an allowlisted testCommand configured, THAT is invoked (not the arbitrary
# command) to get a real exit code deterministically.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.)", "testCommandRegex": "(npm test)",
  "testCommand": "true", "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [] }
JSON
EVENT="$(evt "$R" Bash '{"command":"npm test; touch '"$R"'/ARBITRARY_RAN"}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
if [ ! -e "$R/ARBITRARY_RAN" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #27: configured testCommand invoked, not the arbitrary command"; fi
ROK="$(REC="$R/.factory/state/gate-receipt.json" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("missing")}')"
if [ "$ROK" = "true" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #27: configured testCommand (true) mints green (got $ROK)"; fi

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

echo "# otel (opt-in metrics: off by default, never blocks/changes a gate decision when on)"
# assert_exit_fast <expected> <label> [maxMs] — like assert_exit, but also
# asserts the hook returned within maxMs. Used to prove that an ENABLED emit
# against an unreachable collector cannot block a gate: the emit is
# backgrounded+disowned with its own hard timeout in otel-emit.mjs, so the
# hook itself must return promptly regardless of that timeout.
assert_exit_fast() {
  local expected="$1" label="$2" maxms="${3:-3000}" got start end elapsed
  start="$(date +%s%N)"
  printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
  got=$?
  end="$(date +%s%N)"
  elapsed=$(( (end - start) / 1000000 ))
  if [ "$got" = "$expected" ] && [ "$elapsed" -le "$maxms" ]; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL - $label (expected exit $expected within ${maxms}ms, got exit $got in ${elapsed}ms)"; fi
}

# Disabled (the default): otel_emit must return before forking anything at
# all, not merely "fast" — proven directly by an empty job table right after
# calling it (no `&`), sourcing common.sh the same way every hook does.
cat > "$TMPROOT/otel-harness.sh" <<EOF
#!/usr/bin/env bash
. "$ROOT/hooks/lib/common.sh"
otel_emit test.metric sum 1 '{}'
rc=\$?
echo "JOBS:\$(jobs -p | wc -l) RC:\$rc"
exit 0
EOF
chmod +x "$TMPROOT/otel-harness.sh"
R="$(mkrepo)"
out="$(printf '{}' | HOOK_INPUT="" CLAUDE_PROJECT_DIR="$R" bash "$TMPROOT/otel-harness.sh" 2>/dev/null)"
if [ "$out" = "JOBS:0 RC:0" ]; then PASS=$((PASS+1));
else FAIL=$((FAIL+1)); echo "FAIL - otel_emit disabled (no otel block): expected a clean, non-forking return (got: $out)"; fi

# Disabled must be transparent to gate behavior: a hook's decision is
# identical whether the config carries no otel block at all, or an explicit
# otel.enabled=false (both are "the default").
SCRIPT="$S/guard-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"git commit --no-verify -m \"feat: x\""}')"
assert_exit 2 "otel: no otel block in config — bypass flag still blocked (baseline)"

R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.|\\.spec\\.|/tests?/|\\.feature$)",
  "testCommandRegex": "(npm ((run|-s) )?test|node --test)", "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main", "generators": [], "otel": { "enabled": false } }
JSON
EVENT="$(evt "$R" Bash '{"command":"git commit --no-verify -m \"feat: x\""}')"
out="$(printf '{}' | HOOK_INPUT="" CLAUDE_PROJECT_DIR="$R" bash "$TMPROOT/otel-harness.sh" 2>/dev/null)"
if [ "$out" = "JOBS:0 RC:0" ]; then PASS=$((PASS+1));
else FAIL=$((FAIL+1)); echo "FAIL - otel_emit disabled (otel.enabled=false): expected a clean, non-forking return (got: $out)"; fi
assert_exit 2 "otel: otel.enabled=false explicit — bypass flag still blocked (unchanged)"

# Enabled but the collector is unreachable (bogus endpoint, nothing
# listening): the gating hook must STILL return the correct exit code
# promptly, for both a deny and an allow decision — proving the backgrounded
# emit + its hard client-side timeout never blocks or changes the gate.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.|\\.spec\\.|/tests?/|\\.feature$)",
  "testCommandRegex": "(npm ((run|-s) )?test|node --test)", "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main", "generators": [],
  "otel": { "enabled": true, "endpoint": "http://127.0.0.1:1" } }
JSON
EVENT="$(evt "$R" Bash '{"command":"git commit --no-verify -m \"feat: x\""}')"
assert_exit_fast 2 "otel enabled + unreachable endpoint: deny still returns exit 2 promptly" 3000
echo x > "$R/src/a.ts"; echo x > "$R/src/a.test.ts"; ( cd "$R" && git add -A )
TH="$(repo_tree_hash "$R")"
printf '{"tree":"%s","ok":true,"stages":[{"name":"suite","ok":true}]}' "$TH" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: add a\""}')"
assert_exit_fast 0 "otel enabled + unreachable endpoint: allow still returns exit 0 promptly" 3000

echo "# enforcement toggles + pause (issues #29, #30)"
# --- session-local pause: every hard gate steps aside when the marker exists.
SCRIPT="$S/guard-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
echo x > "$R/src/a.ts"; echo x > "$R/src/a.test.ts"; ( cd "$R" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: add a\""}')"
assert_exit 2 "pause: commit denied without receipt (baseline)"
touch "$R/.factory/state/paused"
assert_exit 0 "pause: marker lets the otherwise-denied commit through"
rm -f "$R/.factory/state/paused"
SCRIPT="$S/guard-bash-writes.sh"
EVENT="$(evt "$R" Bash '{"command":"printf x > .factory/state/gate-receipt.json"}')"
assert_exit 2 "pause: trust-root write denied (baseline)"
touch "$R/.factory/state/paused"
assert_exit 0 "pause: trust-root write allowed while paused"
rm -f "$R/.factory/state/paused"

# --- per-gate enforcement toggles (default ON; a repo opts out visibly).
SCRIPT="$S/guard-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.|/tests?/)",
  "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "enforcement": { "requireGreenReceiptOnCommit": false } }
JSON
echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"chore: no receipt needed\""}')"
assert_exit 0 "enforcement: requireGreenReceiptOnCommit=false allows commit with no receipt"

R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.|/tests?/)",
  "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "enforcement": { "conventionalCommitLint": false, "requireGreenReceiptOnCommit": false } }
JSON
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"totally not conventional\""}')"
assert_exit 0 "enforcement: conventionalCommitLint=false allows a non-conventional message"

R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.|/tests?/)",
  "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "enforcement": { "requireTestsFirst": false, "requireGreenReceiptOnCommit": false } }
JSON
echo x > "$R/src/b.ts"; ( cd "$R" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: b with no test\""}')"
assert_exit 0 "enforcement: requireTestsFirst=false allows feat staging source but no test"

SCRIPT="$S/guard-scope.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo implementer > "$R/.factory/active-agent"
cat > "$R/.factory/config.json" <<'JSON'
{ "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "enforcement": { "protectTrustRoots": false } }
JSON
EVENT="$(evt "$R" Write '{"file_path":".factory/config.json"}')"
assert_exit 0 "enforcement: protectTrustRoots=false lets the editor write factory config"

SCRIPT="$S/guard-bash-writes.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "enforcement": { "protectTrustRoots": false } }
JSON
EVENT="$(evt "$R" Bash '{"command":"printf x > .factory/state/gate-receipt.json"}')"
assert_exit 0 "enforcement: protectTrustRoots=false lets bash write the receipt"

SCRIPT="$S/guard-release.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "releaseVerbRegex": "(git tag|npm publish)",
  "enforcement": { "requireReleaseProof": false } }
JSON
THrel="$(repo_tree_hash "$R")"; printf '{"tree":"%s","ok":true}' "$THrel" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"git tag v1.0.0"}')"
assert_exit 0 "enforcement: requireReleaseProof=false releases with only a fresh green receipt"

echo "# denial signalling: heuristic vs hard-boundary (issues #32, #33)"
SCRIPT="$S/guard-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
echo x > "$R/src/a.ts"; echo x > "$R/src/a.test.ts"; ( cd "$R" && git add -A )
# a commit-gate denial (engaged via the best-effort commit heuristic) is tagged
# [heuristic] and says a retry/rephrase is expected — so a classifier reading
# the transcript does not treat the recovery as evasion.
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: add a\""}')"
ERR="$(printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" 2>&1 >/dev/null)"
case "$ERR" in *"[heuristic]"*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); echo "FAIL - commit-gate denial tagged [heuristic] (got: $ERR)";; esac
# a bypass-flag denial is a real boundary — tagged [hard-boundary], no
# "rephrasing is fine" invitation.
EVENT="$(evt "$R" Bash '{"command":"git commit --no-verify -m \"feat: add a\""}')"
ERR="$(printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" 2>&1 >/dev/null)"
case "$ERR" in *"[hard-boundary]"*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); echo "FAIL - bypass-flag denial tagged [hard-boundary] (got: $ERR)";; esac
# a trust-root write is a hard boundary on the Bash surface too.
SCRIPT="$S/guard-bash-writes.sh"
EVENT="$(evt "$R" Bash '{"command":"printf x > .factory/state/gate-receipt.json"}')"
ERR="$(printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" 2>&1 >/dev/null)"
case "$ERR" in *"[hard-boundary]"*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); echo "FAIL - trust-root write tagged [hard-boundary] (got: $ERR)";; esac

echo "# HMAC-signed receipts (issue #2): forged proofs rejected when a key is set"
export FACTORY_RECEIPT_KEY="test-secret-xyz"
SCRIPT="$S/guard-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
echo x > "$R/src/a.ts"; echo x > "$R/src/a.test.ts"; ( cd "$R" && git add -A )
TH="$(repo_tree_hash "$R")"
# a hand-written (unsigned) receipt must NOT certify green when a key is set.
printf '{"tree":"%s","ok":true}' "$TH" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: a\""}')"
assert_exit 2 "#2: unsigned hand-written receipt rejected when a signing key is set"
# a correctly signed receipt is accepted.
SIG="$(PAYLOAD="true:$TH" SECRET="$FACTORY_RECEIPT_KEY" node -e 'const c=require("crypto");process.stdout.write(c.createHmac("sha256",process.env.SECRET).update(process.env.PAYLOAD).digest("hex"))')"
printf '{"tree":"%s","ok":true,"sig":"%s"}' "$TH" "$SIG" > "$R/.factory/state/gate-receipt.json"
assert_exit 0 "#2: correctly signed receipt accepted"
# a receipt signed with the WRONG key is rejected.
BADSIG="$(PAYLOAD="true:$TH" SECRET="wrong-key" node -e 'const c=require("crypto");process.stdout.write(c.createHmac("sha256",process.env.SECRET).update(process.env.PAYLOAD).digest("hex"))')"
printf '{"tree":"%s","ok":true,"sig":"%s"}' "$TH" "$BADSIG" > "$R/.factory/state/gate-receipt.json"
assert_exit 2 "#2: receipt signed with the wrong key rejected"
# record-green mints a receipt that guard-commit accepts end-to-end under a key.
SCRIPT="$S/record-green.sh"; rm -f "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"npm test"}' ',"tool_response":{"exitCode":0}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
SCRIPT="$S/guard-commit.sh"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: a\""}')"
assert_exit 0 "#2: record-green mints a signed receipt that guard-commit accepts"
unset FACTORY_RECEIPT_KEY
# without a key, an unsigned receipt is accepted exactly as before.
printf '{"tree":"%s","ok":true}' "$TH" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: a\""}')"
assert_exit 0 "#2: no key configured → unsigned receipt accepted (backward compatible)"

echo "# multi-repo receipt binding (issue #28)"
SCRIPT="$S/guard-commit.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
# a sibling repo B (its own git repo) committed to from the SAME session.
B="$(mktemp -d "$TMPROOT/repoB.XXXXXX")"
( cd "$B" && git init -q && git symbolic-ref HEAD refs/heads/main 2>/dev/null; git config user.email t@t && git config user.name t && git commit --allow-empty -q -m init )
mkdir -p "$B/src"; echo x > "$B/src/b.ts"; ( cd "$B" && git add -A )
# the session repo R being green must NOT certify a commit to B (the bug).
TH="$(repo_tree_hash "$R")"; printf '{"tree":"%s","ok":true}' "$TH" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"cd '"$B"' && git commit -m \"chore: b\""}')"
assert_exit 2 "#28: commit to sibling repo B not certified by R's own receipt"
# mint B's receipt via record-green targeting B (cd into B).
SCRIPT="$S/record-green.sh"
EVENT="$(evt "$R" Bash '{"command":"cd '"$B"' && npm test"}' ',"tool_response":{"exitCode":0}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
BKEY="$(printf '%s' "$B" | cksum | cut -d' ' -f1)"
if [ -f "$R/.factory/state/gate-receipt-$BKEY.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #28: record-green mints a per-repo keyed receipt for B"; fi
# and the session repo's own default receipt is untouched by B's run.
SCRIPT="$S/guard-commit.sh"
EVENT="$(evt "$R" Bash '{"command":"cd '"$B"' && git commit -m \"chore: b\""}')"
assert_exit 0 "#28: commit to B allowed once B has its own green receipt"
# a plain in-session commit still uses the canonical gate-receipt.json.
echo x > "$R/src/a.ts"; echo x > "$R/src/a.test.ts"; ( cd "$R" && git add -A )
THr="$(repo_tree_hash "$R")"; printf '{"tree":"%s","ok":true}' "$THr" > "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: a\""}')"
assert_exit 0 "#28: in-session commit still uses the canonical receipt (backward compatible)"

echo "# status banner throttle (issue #34)"
SCRIPT="$S/inject-status.sh"
# uninitialized repo (no .factory/config.json): inject nothing at all.
D="$(mktemp -d "$TMPROOT/uninit.XXXXXX")"; ( cd "$D" && git init -q && git commit --allow-empty -q -m init 2>/dev/null ); mkdir -p "$D/.factory/state"
export CLAUDE_PROJECT_DIR="$D"
EVENT='{"hook_event_name":"UserPromptSubmit","cwd":"'"$D"'"}'
OUT="$(printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" 2>/dev/null)"
if [ -z "$OUT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #34: uninitialized repo injects nothing (got: $OUT)"; fi
# initialized repo: first turn injects the banner, an identical next turn is suppressed.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT='{"hook_event_name":"UserPromptSubmit","cwd":"'"$R"'"}'
OUT1="$(printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" 2>/dev/null)"
case "$OUT1" in *additionalContext*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); echo "FAIL - #34: first turn injects the banner (got: $OUT1)";; esac
OUT2="$(printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" 2>/dev/null)"
if [ -z "$OUT2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #34: unchanged banner suppressed on next turn (got: $OUT2)"; fi
# paused → silent.
touch "$R/.factory/state/paused"
OUT3="$(printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" 2>/dev/null)"
if [ -z "$OUT3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #34: paused suppresses the banner (got: $OUT3)"; fi
rm -f "$R/.factory/state/paused"

echo "# adversarial self-review regressions (findings #1-#6)"
# #2: `git -C <dir>` overrides `cd` — the gate must bind to the repo git actually
# targets, so a red commit can't be certified by a cd'd green sibling.
SCRIPT="$S/record-green.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"   # session repo, RED (no receipt)
G="$(mktemp -d "$TMPROOT/repoG.XXXXXX")"
( cd "$G" && git init -q && git symbolic-ref HEAD refs/heads/main 2>/dev/null; git config user.email t@t && git config user.name t && git commit --allow-empty -q -m init )
mkdir -p "$G/src"; echo x > "$G/src/g.ts"; ( cd "$G" && git add -A )
EVENT="$(evt "$R" Bash '{"command":"cd '"$G"' && npm test"}' ',"tool_response":{"exitCode":0}')"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
SCRIPT="$S/guard-commit.sh"
EVENT="$(evt "$R" Bash '{"command":"cd '"$G"' && git -C '"$R"' commit -m \"chore: x\""}')"
assert_exit 2 "#2: git -C target (red session repo) not certified by a cd'd green sibling"
EVENT="$(evt "$R" Bash '{"command":"cd '"$G"' && git commit -m \"chore: g\""}')"
assert_exit 0 "#2: commit to the cd'd green repo still allowed"
# #2 (message-injection variant): a `git -C <green>` mentioned INSIDE the commit
# message is not a git option — the red session commit must still be denied.
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"chore: git -C '"$G"' note\""}')"
assert_exit 2 "#2: git -C inside the -m message does not bind the gate to a sibling"
# #3: a `cd` into a trust root then a redirect must be caught (pause/receipt forge).
SCRIPT="$S/guard-bash-writes.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"cd .factory/state && printf {} > paused"}')"; assert_exit 2 "#3: cd into trust root then redirect (pause forge) blocked"
EVENT="$(evt "$R" Bash '{"command":"cd .factory/state && printf x > gate-receipt.json"}')"; assert_exit 2 "#3: cd into trust root then redirect (receipt forge) blocked"
# #4: a `cd` outside the tree then a redirect is an out-of-project write.
EVENT="$(evt "$R" Bash '{"command":"cd /etc && printf x >> hosts"}')"; assert_exit 2 "#4: cd outside then redirect (out-of-project) blocked"
# #1/#6: a `>` or `tee` that is quoted / an argument is not a write construct.
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"docs: logs cmd > /var/log/app.log\""}')"; assert_exit 0 "#1: > inside a commit message is not an out-of-project write"
EVENT="$(evt "$R" Bash '{"command":"echo \"usage: mycmd > /etc/output.conf\""}')"; assert_exit 0 "#1: > inside a quoted echo is not a redirect"
EVENT="$(evt "$R" Bash '{"command":"grep tee /etc/hosts"}')"; assert_exit 0 "#6: tee as a grep argument is not a write construct"
# #5: guard-scope must fail CLOSED (deny, not abort) when HOME is unset under set -u.
SCRIPT="$S/guard-scope.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo implementer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":"/etc/x.conf"}')"
got5="$(printf '%s' "$EVENT" | HOOK_INPUT="" env -u HOME CLAUDE_PROJECT_DIR="$R" bash "$SCRIPT" >/dev/null 2>&1; echo $?)"
if [ "$got5" = "2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - #5: guard-scope with HOME unset must deny/fail-closed (got exit $got5)"; fi
rm -f "$R/.factory/active-agent"

echo "# check-drift & orientation"
SCRIPT="$S/check-drift.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Write '{"file_path":"src/a.ts"}')"; assert_exit 0 "no generators → allow"
SCRIPT="$S/bootstrap.sh"; EVENT='{"hook_event_name":"SessionStart","cwd":"'"$R"'"}'; assert_exit 0 "bootstrap exits 0"
SCRIPT="$S/inject-status.sh"; EVENT='{"hook_event_name":"UserPromptSubmit","cwd":"'"$R"'"}'; assert_exit 0 "inject-status exits 0"

# ═══════════════════════════════════════════════════════════════════════════
# Bug-hunt regressions — every case below reproduces a defect found by the
# multi-agent audit and asserts it stays fixed. Helpers: `assert_exit`, `evt`,
# `mkrepo` (a git repo WITH .factory/config.json), `repo_tree_hash`. `mkbare`
# (added here) is a git repo with NO config — an "un-initialized" repo.
# ═══════════════════════════════════════════════════════════════════════════

# mkbare — a throwaway git repo that is NOT factory-initialized (no config.json).
mkbare() {
  local d; d="$(mktemp -d "$TMPROOT/bare.XXXXXX")"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main 2>/dev/null; \
    git config user.email t@t && git config user.name t; \
    mkdir -p src && echo x > src/a.ts && echo t > src/a.test.ts && git add -A && git commit -q -m init )
  printf '%s' "$d"
}
# assert_file <exists|absent> <path> <label>
assert_file() {
  if { [ "$1" = exists ] && [ -f "$2" ]; } || { [ "$1" = absent ] && [ ! -f "$2" ]; }; then
    PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - $3 (expected $2 to be $1)"; fi
}
# mint_receipt <repo> — run record-green for a clean `npm test` with exitCode 0.
mint_receipt() {
  SCRIPT="$S/record-green.sh"
  EVENT="$(evt "$1" Bash '{"command":"npm test"}' ',"tool_response":{"exitCode":0}')"
  printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
}

echo "# regressions: uninitialized-repo gates are advisory (no deadlock)"
# A repo with no .factory/config.json never opted in — the workflow gates must
# step aside instead of demanding an unmintable proof.
B="$(mkbare)"; export CLAUDE_PROJECT_DIR="$B"
SCRIPT="$S/guard-commit.sh"
EVENT="$(evt "$B" Bash '{"command":"git commit -m \"feat: add a\""}')"
assert_exit 0 "uninit: commit not deadlocked without a receipt"
SCRIPT="$S/guard-release.sh"
EVENT="$(evt "$B" Bash '{"command":"git tag v1.0.0"}')"
assert_exit 0 "uninit: release verb not deadlocked without a proof"
SCRIPT="$S/guard-roadmap.sh"
EVENT="$(evt "$B" Edit '{"file_path":"docs/ROADMAP.md","old_string":"- [ ] x","new_string":"- [x] x"}')"
assert_exit 0 "uninit: roadmap flip not deadlocked without a proof"
SCRIPT="$S/record-green.sh"
EVENT="$(evt "$B" Bash '{"command":"npm test"}' ',"tool_response":{"exitCode":0}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
assert_file absent "$B/.factory/state/gate-receipt.json" "uninit: record-green does not create .factory state"
SCRIPT="$S/bootstrap.sh"
EVENT='{"hook_event_name":"SessionStart","cwd":"'"$B"'"}'
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
assert_file absent "$B/.factory/config.json" "uninit: bootstrap leaves repo clean (no .factory)"
[ ! -d "$B/.factory" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - uninit bootstrap must not create .factory dir"; }

echo "# regressions: large event payload (E2BIG) must not fail the gate open"
# A verbose tool_response once exceeded the 128KB env limit, making every node
# exec fail and every gate silently no-op. Feeding it on stdin fixes that: a big
# passing run still mints a receipt.
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
BIG="$(head -c 200000 /dev/zero | tr '\0' x)"
SCRIPT="$S/record-green.sh"
EVENT="$(printf '{"tool_name":"Bash","hook_event_name":"PostToolUse","cwd":"%s","tool_input":{"command":"npm test"},"tool_response":{"exitCode":0,"stdout":"%s"}}' "$R" "$BIG")"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
assert_file exists "$R/.factory/state/gate-receipt.json" "E2BIG: 200KB tool_response still mints a receipt"

echo "# regressions: record-green false-green vectors refuse to mint"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
SCRIPT="$S/record-green.sh"
rg_no_mint() { # <cmd-json> <label>
  rm -f "$R/.factory/state/gate-receipt.json"
  EVENT="$(evt "$R" Bash "$1" ',"tool_response":{"exitCode":0}')"
  printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
  assert_file absent "$R/.factory/state/gate-receipt.json" "$2"
}
rg_mint() { # <cmd-json> <label>
  rm -f "$R/.factory/state/gate-receipt.json"
  EVENT="$(evt "$R" Bash "$1" ',"tool_response":{"exitCode":0}')"
  printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
  assert_file exists "$R/.factory/state/gate-receipt.json" "$2"
}
rg_no_mint '{"command":"npm test 2>&1 | tail -20"}'         "pipeline (| tail) masks exit status → no receipt"
rg_no_mint '{"command":"npm test || echo failed"}'          "|| echo masks exit status → no receipt"
rg_no_mint '{"command":"npm test; echo done"}'              "; echo masks exit status → no receipt"
rg_no_mint '{"command":"grep -rn \"npm test\" README.md"}'  "test pattern as grep data → no receipt"
rg_no_mint '{"command":"echo \"npm test passed\""}'         "echo forgery → no receipt"
rg_no_mint '{"command":"FOO=1 echo \"npm test\""}'          "env-prefixed echo forgery → no receipt"
rg_mint    '{"command":"npm test -- --grep \"#42\""}'       "legit test with # in an arg → mints (not skipped by bare-# guard)"
rg_mint    '{"command":"npm test # ran the suite"}'         "trailing # comment on a real run → mints"
rg_mint    '{"command":"cd . && npm test"}'                 "cd && npm test (last cmd is the suite) → mints"
# widened default runner regex: yarn/pnpm/bun recognized (config has none set here)
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.)", "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main", "generators": [] }
JSON
rg_mint '{"command":"yarn test"}' "default regex recognizes yarn test → mints"
rg_mint '{"command":"bun test"}'  "default regex recognizes bun test → mints"
# an explicitly-empty testCommandRegex must DISABLE detection, not match-all
cat > "$R/.factory/config.json" <<'JSON'
{ "testCommandRegex": "", "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [] }
JSON
rg_no_mint '{"command":"ls -la"}' "empty testCommandRegex disables detection (no match-all) → no receipt"
# a non-numeric exit code must not corrupt the mint
cat > "$R/.factory/config.json" <<'JSON'
{ "testCommandRegex": "(npm test)", "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [] }
JSON
rm -f "$R/.factory/state/gate-receipt.json"
EVENT="$(evt "$R" Bash '{"command":"npm test"}' ',"tool_response":{"code":"ENOENT"}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
assert_file absent "$R/.factory/state/gate-receipt.json" "non-numeric exit code (ENOENT) mints nothing"

echo "# regressions: subdir session receipt does not self-invalidate"
# Session opened in a repo SUBDIR: the receipt lands under <repo>/<sub>/.factory
# but binds to the repo-root tree — tree_hash must exclude it or every commit is
# denied 'stale-tree'.
MONO="$(mktemp -d "$TMPROOT/mono.XXXXXX")"
( cd "$MONO" && git init -q && git symbolic-ref HEAD refs/heads/main 2>/dev/null; git config user.email t@t && git config user.name t; \
  mkdir -p pkg/src && echo x > pkg/src/a.ts && echo t > pkg/src/a.test.ts && git add -A && git commit -q -m init )
SUB="$MONO/pkg"; mkdir -p "$SUB/.factory/state"
cat > "$SUB/.factory/config.json" <<'JSON'
{ "testCommandRegex": "(npm test)", "sourceRegex":"^src/", "testRegex":"(\\.test\\.)",
  "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [] }
JSON
export CLAUDE_PROJECT_DIR="$SUB"
SCRIPT="$S/record-green.sh"; EVENT="$(evt "$SUB" Bash '{"command":"npm test"}' ',"tool_response":{"exitCode":0}')"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
SCRIPT="$S/guard-commit.sh"; EVENT="$(evt "$SUB" Bash '{"command":"git commit -m \"chore: x\""}')"
assert_exit 0 "subdir session: commit allowed (receipt not self-invalidated)"

echo "# regressions: receipt forgery via non-redirect write mutators"
SCRIPT="$S/guard-bash-writes.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"touch .factory/state/paused"}')"; assert_exit 2 "touch .factory/state/paused (self-pause) blocked"
EVENT="$(evt "$R" Bash '{"command":"mkdir -p .factory/state && touch .factory/state/paused"}')"; assert_exit 2 "mkdir+touch self-pause blocked"
EVENT="$(evt "$R" Bash '{"command":"cp /tmp/x .factory/state/gate-receipt.json"}')"; assert_exit 2 "cp receipt forgery (leading verb) blocked"
EVENT="$(evt "$R" Bash '{"command":"install -m644 /tmp/x .factory/state/gate-receipt.json"}')"; assert_exit 2 "install receipt forgery blocked"
EVENT="$(evt "$R" Bash '{"command":"dd if=/dev/zero of=.factory/state/paused"}')"; assert_exit 2 "dd of= self-pause blocked"
EVENT="$(evt "$R" Bash '{"command":"cp a.ts b.ts"}')"; assert_exit 0 "in-project cp allowed"
EVENT="$(evt "$R" Bash '{"command":"touch src/new.ts"}')"; assert_exit 0 "in-project touch allowed"

echo "# regressions: reviewer read-only quote/subcommand awareness"
echo reviewer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Bash '{"command":"grep \"a > b\" file.txt"}')"; assert_exit 0 "reviewer: quoted > (not a redirect) allowed"
EVENT="$(evt "$R" Bash '{"command":"git stash list"}')"; assert_exit 0 "reviewer: git stash list (read-only) allowed"
EVENT="$(evt "$R" Bash '{"command":"git stash show"}')"; assert_exit 0 "reviewer: git stash show (read-only) allowed"
EVENT="$(evt "$R" Bash '{"command":"git stash"}')"; assert_exit 2 "reviewer: bare git stash (push) blocked"
EVENT="$(evt "$R" Bash '{"command":"git stash push -m x"}')"; assert_exit 2 "reviewer: git stash push blocked"
rm -f "$R/.factory/active-agent"

echo "# regressions: reviewer can emit its findings artifact; source stays denied"
SCRIPT="$S/guard-scope.sh"; echo reviewer > "$R/.factory/active-agent"
EVENT="$(evt "$R" Write '{"file_path":".factory/review/pr.json"}')"; assert_exit 0 "reviewer: Write .factory/review/*.json allowed (handoff)"
EVENT="$(evt "$R" Write '{"file_path":"src/x.ts"}')"; assert_exit 2 "reviewer: Write source still denied"
rm -f "$R/.factory/active-agent"

echo "# regressions: /factory-init can create config; symlink evasion blocked"
SCRIPT="$S/guard-scope.sh"; B="$(mkbare)"; export CLAUDE_PROJECT_DIR="$B"
EVENT="$(evt "$B" Write '{"file_path":".factory/config.json"}')"; assert_exit 0 "init: create .factory/config.json (absent) allowed"
mkdir -p "$B/.factory"; echo '{}' > "$B/.factory/config.json"
EVENT="$(evt "$B" Write '{"file_path":".factory/config.json"}')"; assert_exit 2 "init: config.json protected once it exists"
EVENT="$(evt "$B" Write '{"file_path":".factory/state/gate-receipt.json"}')"; assert_exit 2 "init: state is never creatable via the editor"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo implementer > "$R/.factory/active-agent"
ln -s .factory/state "$R/sneak"
EVENT="$(evt "$R" Write '{"file_path":"sneak/gate-receipt.json"}')"; assert_exit 2 "symlink into trust root (sneak/) blocked"
rm -f "$R/.factory/active-agent" "$R/sneak"

echo "# regressions: guard-roadmap Write bypass; guard-release read-only tag"
SCRIPT="$S/guard-roadmap.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
printf '## M0\n- [ ] build the thing\n' > "$R/docs/ROADMAP.md"
EVENT="$(evt "$R" Write '{"file_path":"docs/ROADMAP.md","content":"## M0\n- [x] build the thing\n"}')"
assert_exit 2 "roadmap: Write-tool checkbox flip blocked without proof (bypass closed)"
SCRIPT="$S/guard-release.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT="$(evt "$R" Bash '{"command":"git tag -l"}')"; assert_exit 0 "release: read-only 'git tag -l' allowed"
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"docs: how to npm publish\""}')"; assert_exit 0 "release: verb inside a commit message not a release"
EVENT="$(evt "$R" Bash '{"command":"git tag v9.9.9"}')"; assert_exit 2 "release: 'git tag <name>' (create) still gated without proof"

echo "# regressions: collect-findings robustness (feeds debt-reconcile)"
SCRIPT="$S/debt-reconcile.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
EVENT='{"hook_event_name":"Stop","cwd":"'"$R"'"}'
GHEMPTY="$(mk_gh_shim '[]')"
# a null file must not abort the scan and drop the real (unfiled) finding after it
printf 'null' > "$R/.factory/review/a-null.json"
printf '[{"location":"src/z.ts:1","impact":"bug","provenance":"introduced","suggestedFix":"fix","severity":"high","status":"open"}]' > "$R/.factory/review/z.json"
( export PATH="$GHEMPTY:$PATH"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1 ); [ $? = 2 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - null review file must not drop a later unfiled finding"; }
# the honest {clean:true} sentinel must NOT be counted as an unfixed finding
rm -f "$R/.factory/review/"*.json
printf '{"clean":true}' > "$R/.factory/review/clean.json"
( export PATH="$GHEMPTY:$PATH"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1 ); [ $? = 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - clean sentinel must not block Stop"; }

echo "# regressions: ledger de-dups a failed (HEAD-unchanged) commit"
SCRIPT="$S/ledger-record.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
echo x > "$R/src/a.ts"; ( cd "$R" && git add -A && git commit -q -m "feat: real" )
EVENT="$(evt "$R" Bash '{"command":"git commit -m \"feat: real\""}' ',"tool_response":{"stdout":"nothing to commit"}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
LN="$(wc -l < "$R/.factory/ledger.jsonl" 2>/dev/null | tr -d ' ')"
[ "${LN:-0}" = "1" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - ledger must not double-log a HEAD-unchanged commit (got $LN lines)"; }

echo "# regressions: commit parser (heredoc / -am / bypass-scope / quote-awareness)"
PGC="$ROOT/hooks/lib/parse-git-commit.mjs"
pgc_field() { printf '%s' "$1" | node "$PGC" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(String(JSON.parse(s)["'"$2"'"])))'; }
[ "$(pgc_field 'git commit -am "wip not conventional"' message)" = "wip not conventional" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - -am message must be extracted (lint not skipped)"; }
[ "$(pgc_field 'git commit -am "x"' all)" = "true" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - -am must set the all flag"; }
[ "$(pgc_field 'git commit -m "docs: mentions --no-verify"' bypass)" = "false" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - --no-verify inside the message is not a bypass"; }
[ "$(pgc_field 'echo "reminder: git commit --no-verify"' isCommit)" = "false" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - git commit inside a quoted echo is not a commit"; }
HEREDOC_MSG="$(printf 'git commit -m "$(cat <<%sEOF%s\nfeat: heredoc subject\n\nbody\nEOF\n)"' "'" "'" | node "$PGC" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.parse(s).message.split("\n")[0]))')"
[ "$HEREDOC_MSG" = "feat: heredoc subject" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL - heredoc commit subject must be extracted (got: $HEREDOC_MSG)"; }
# end-to-end: a heredoc commit with a green receipt + staged test is ALLOWED
SCRIPT="$S/guard-commit.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
echo x > "$R/src/a.ts"; echo x > "$R/src/a.test.ts"; ( cd "$R" && git add -A )
TH="$(repo_tree_hash "$R")"; printf '{"tree":"%s","ok":true}' "$TH" > "$R/.factory/state/gate-receipt.json"
HEREDOC_CMD='{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: add a\nEOF\n)\""}'
EVENT="$(evt "$R" Bash "$HEREDOC_CMD")"; assert_exit 0 "heredoc commit with green receipt allowed (Claude Code default commit style)"

echo "# regressions: record-release-proof mints on a build whose command contains '#'"
SCRIPT="$S/record-release-proof.sh"; R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"
cat > "$R/.factory/config.json" <<'JSON'
{ "roadmapPath": "docs/ROADMAP.md", "releaseBranch": "main", "generators": [],
  "releaseProofCommandRegex": "(npm run build)" }
JSON
printf '{"active":true}' > "$R/.factory/state/release-intent.json"
EVENT="$(evt "$R" Bash '{"command":"npm run build # release build"}' ',"tool_response":{"exitCode":0}')"
printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1
assert_file exists "$R/.factory/state/release-proof.json" "release proof mints on a green build with a trailing '#' comment"

# ═══════════════════════════════════════════════════════════════════════════
# Review-round regressions — defects the adversarial review of the fix diff
# itself surfaced (command wrappers defeating the tokenized parsers, cp -t
# forgery, cross-repo/config-delete bypasses, symlinked-root false-block).
# ═══════════════════════════════════════════════════════════════════════════
echo "# review-round: command wrappers no longer defeat the parsers"
PGC="$ROOT/hooks/lib/parse-git-commit.mjs"
CTR="$ROOT/hooks/lib/classify-test-run.mjs"
CRL="$ROOT/hooks/lib/classify-release.mjs"
DTR='(npm ((run|-s) )?te?st|(yarn|pnpm|bun)( run)? te?st|npx (jest|vitest|mocha|ava|tap)|npx playwright test|node --test|vitest|jest|mocha|pytest|go test|cargo test|make test|python[0-9.]* -m (pytest|unittest)|py.test|(poetry|pdm|pipenv|hatch|rye) run [a-z:-]*te?st|coverage run|tox)'
REL='(git tag|gh release create|npm publish|docker push|release-please|npm version )'
jf() { printf '%s' "$1" | node "$2" ${3:+"$3"} | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(String(JSON.parse(s)["'"$4"'"])))'; }
chk() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL - $3 (got '$1', want '$2')"; fi; }
# parse-git-commit: wrapped commits detected; bypass still scoped; heredoc scoped
chk "$(jf 'timeout 60 git commit --no-verify -m x' "$PGC" '' isCommit)" true "wrapper: timeout git commit is a commit"
chk "$(jf 'timeout 60 git commit --no-verify -m x' "$PGC" '' bypass)" true "wrapper: --no-verify under timeout still a bypass"
chk "$(jf 'nice -n 5 git commit -m x' "$PGC" '' isCommit)" true "wrapper: nice -n 5 git commit is a commit"
chk "$(jf 'sudo -u ci git commit -m x' "$PGC" '' isCommit)" true "wrapper: sudo -u ci git commit is a commit"
chk "$(jf 'git commit -m "feat: real" && cat <<EOF > n.txt
notes
EOF' "$PGC" '' message)" "feat: real" "heredoc: unrelated chained heredoc does not overwrite the -m message"
# classify-test-run: wrappers engage; python forms; playwright install excluded; && clean; & not clean
chk "$(jf 'timeout 300 npm test' "$CTR" "$DTR" testCommand)" true "wrapper: timeout npm test is a test run"
chk "$(jf 'python -m pytest' "$CTR" "$DTR" testCommand)" true "python -m pytest is a test run"
chk "$(jf 'coverage run -m pytest' "$CTR" "$DTR" testCommand)" true "coverage run is a test run"
chk "$(jf 'npx playwright install' "$CTR" "$DTR" testCommand)" false "npx playwright install is NOT a test run"
chk "$(jf 'npm test && npm run lint' "$CTR" "$DTR" cleanInvocation)" true "&&-chained suite: exit code is authoritative"
chk "$(jf 'npm test &' "$CTR" "$DTR" cleanInvocation)" false "backgrounded suite: exit code NOT authoritative"
# classify-release: wrapped/sh-c releases detected
chk "$(jf 'timeout 60 gh release create v1' "$CRL" "$REL" isRelease)" true "wrapper: timeout gh release create is a release"
chk "$(jf "sh -c 'gh release create v1'" "$CRL" "$REL" isRelease)" true "sh -c hidden release is a release"
chk "$(jf 'git tag -l' "$CRL" "$REL" isRelease)" false "git tag -l (read-only) still not a release"

echo "# review-round: parse-bash-writes cp -t forgery + rm trust-root deletion"
PBW="$ROOT/hooks/lib/parse-bash-writes.mjs"
tcount() { printf '%s' "$1" | HOOK_PROJECT_DIR=/proj node "$PBW" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(String((JSON.parse(s).trustRoot||[]).length)))'; }
chk "$(tcount 'cp -t .factory/state gate-receipt.json')" 1 "cp -t DIR flags the trust-root target dir"
chk "$(tcount 'cp -rt .factory/state x')" 1 "cp -rt cluster flags the trust-root dir"
chk "$(tcount 'cd .factory && rm config.json')" 1 "cd-relative rm of config flagged as trust-root delete"
chk "$(tcount 'rm src/x.ts')" 0 "rm of an in-project non-trust file is not over-flagged"

echo "# review-round: guard-bash-writes carve-out + cross-repo + nested symlink"
SCRIPT="$S/guard-bash-writes.sh"
B="$(mkbare)"; export CLAUDE_PROJECT_DIR="$B"   # uninit (no config)
EVENT="$(evt "$B" Bash '{"command":"cd .factory && mkdir -p state && printf {} > config.json; : > state/paused"}')"
assert_exit 2 "carve-out: config-create that ALSO plants state/paused is blocked"
EVENT="$(evt "$B" Bash '{"command":"mkdir -p .factory && printf {} > .factory/config.json"}')"
assert_exit 0 "carve-out: first-run config-only creation still allowed"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"    # init
EVENT="$(evt "$R" Bash '{"command":"cd .factory && rm config.json"}')"
assert_exit 2 "cd-relative rm of config in an inited repo is blocked (no kill-switch)"
# cross-repo union: uninit session A committing to inited sibling B is still gated
A2="$(mkbare)"; B2="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$A2"
SCRIPT="$S/guard-commit.sh"
EVENT="$(evt "$A2" Bash '{"command":"cd '"$B2"' && git commit -m \"feat: sneaky\""}')"
assert_exit 2 "cross-repo: uninit session cannot bypass an inited sibling's commit gate"
EVENT="$(evt "$A2" Bash '{"command":"git commit -m \"feat: local\""}')"
assert_exit 0 "cross-repo: uninit session + uninit target stays advisory (no deadlock)"
# guard-scope: a new nested file under a SYMLINKED project root is allowed
SCRIPT="$S/guard-scope.sh"
SYMBASE="$(mktemp -d "$TMPROOT/symp.XXXXXX")"; mkdir -p "$SYMBASE/real/.factory" "$SYMBASE/real/src"
printf '{}' > "$SYMBASE/real/.factory/config.json"; ( cd "$SYMBASE/real" && git init -q )
ln -s "$SYMBASE/real" "$SYMBASE/sym"; echo implementer > "$SYMBASE/real/.factory/active-agent"
export CLAUDE_PROJECT_DIR="$SYMBASE/sym"
EVENT="$(evt "$SYMBASE/sym" Write '{"file_path":"'"$SYMBASE"'/sym/src/comp/NewThing/index.tsx"}')"
assert_exit 0 "symlinked root: new file in a not-yet-created nested dir is allowed"
EVENT="$(evt "$SYMBASE/sym" Write '{"file_path":".factory/state/gate-receipt.json"}')"
assert_exit 2 "symlinked root: trust-root write still blocked"

echo "# review-round: record-green recognizes python/wrapper suites, rejects background"
SCRIPT="$S/record-green.sh"
R="$(mkrepo)"; export CLAUDE_PROJECT_DIR="$R"; echo x > "$R/src/a.ts"; ( cd "$R" && git add -A )
cat > "$R/.factory/config.json" <<'JSON'
{ "sourceRegex": "^src/", "testRegex": "(\\.test\\.)", "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main", "generators": [] }
JSON
rgm() { rm -f "$R/.factory/state/gate-receipt.json"; EVENT="$(evt "$R" Bash "$1" ',"tool_response":{"exitCode":0}')"; printf '%s' "$EVENT" | HOOK_INPUT="" bash "$SCRIPT" >/dev/null 2>&1; }
rgm '{"command":"python -m pytest"}'; assert_file exists "$R/.factory/state/gate-receipt.json" "python -m pytest mints a receipt"
rgm '{"command":"timeout 300 npm test"}'; assert_file exists "$R/.factory/state/gate-receipt.json" "timeout npm test mints a receipt"
rgm '{"command":"npm test && npm run lint"}'; assert_file exists "$R/.factory/state/gate-receipt.json" "npm test && lint mints (exit authoritative)"
rgm '{"command":"npx playwright install"}'; assert_file absent "$R/.factory/state/gate-receipt.json" "npx playwright install mints nothing"
rgm '{"command":"npm test &"}'; assert_file absent "$R/.factory/state/gate-receipt.json" "backgrounded npm test mints nothing"

echo
echo "hooks contract: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
