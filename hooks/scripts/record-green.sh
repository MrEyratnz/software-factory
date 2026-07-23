#!/usr/bin/env bash
# record-green — after a full suite command exits 0, write the tree-bound green
# receipt that guard-commit consumes. Advisory: always exit 0.
#
# The receipt is bound to `git write-tree` (not a timestamp), so any later edit
# to the source changes the tree and silently invalidates it — no separate
# invalidation hook needed.
. "$(dirname "$0")/../lib/common.sh"

# Un-inited repo → the factory is advisory here (guard-commit steps aside too),
# so do not mint receipts or create .factory state in a repo that never opted in.
factory_initialized || allow

# issue #52: without node no receipt can be classified or minted — say so
# loudly (once per session) instead of leaving "no receipt" indistinguishable
# from "tests were red".
node_guard record-green || allow

[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
[ -n "$cmd" ] || allow

# The repo the suite actually runs in (issue #28) — resolved EARLY so the
# regex/testCommand reads below can come from the TARGET repo's contract
# (issue #53), not the session's.
target_root="$(repo_root "$(command_target_dir "$cmd")")"

# Default recognizes the common runners across ecosystems (npm/yarn/pnpm/bun/npx,
# node --test, jest/vitest/mocha/ava/tap, pytest, go test, cargo test, make). An
# un-inited repo has no config to widen this, so a green `yarn test`/`bun test`
# must still be recognized or its commit would deadlock. A repo can override via
# testCommandRegex.
DEFAULT_TEST_RE='(npm ((run|-s) )?te?st|(yarn|pnpm|bun)( run)? te?st|npx (jest|vitest|mocha|ava|tap)|npx playwright test|node --test|vitest|jest|mocha|pytest|go test|cargo test|make test|python[0-9.]* -m (pytest|unittest)|py.test|(poetry|pdm|pipenv|hatch|rye) run [a-z:-]*te?st|coverage run -m (pytest|unittest|nose2)|tox( +(-[prfqv]|--parallel|--recreate))* *$)'
test_re="$(config_get_for "$target_root" testCommandRegex "$DEFAULT_TEST_RE")"
# An explicitly-blanked regex must DISABLE detection, never match every command
# (an empty ERE matches all): fail safe — mint nothing.
[ -n "$test_re" ] || allow

# Classify the command in a quote-aware, command-position-aware way:
#   testCommand    — a test invocation is in command position (so this is a real
#                    suite run, not `grep "npm test"`, `echo "npm test passed"`,
#                    or an env/cd-prefixed forgery).
#   cleanInvocation — the LAST simple command is that test, so a reported exit
#                    code actually certifies the SUITE (false for `npm test|tail`,
#                    `npm test||echo x`, `npm test; echo x` — exit-status masking).
# This replaces the old whole-line grep + first-token-only forgery guards, which
# both false-passed (masked pipelines) and false-skipped (a '#' or '||' anywhere).
cls="$(printf '%s' "$cmd" | node "$PLUGIN_ROOT/hooks/lib/classify-test-run.mjs" "$test_re" 2>/dev/null)"
is_test="$(printf '%s' "$cls" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).testCommand))}catch(e){process.stdout.write("false")}})')"
[ "$is_test" = "true" ] || allow
clean="$(printf '%s' "$cls" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).cleanInvocation))}catch(e){process.stdout.write("false")}})')"

# Read the command's exit status from the tool response (try known field names),
# and accept it only if it is a clean integer — a non-numeric value (e.g.
# code:"ENOENT" on a spawn failure) would otherwise be interpolated raw into the
# gate-evaluate JSON, making it invalid and silently aborting the mint.
ec="$(field tool_response.exitCode)"
[ -n "$ec" ] || ec="$(field tool_response.exit_code)"
[ -n "$ec" ] || ec="$(field tool_response.code)"
[ -n "$ec" ] || ec="$(field tool_response.returnCode)"
case "$ec" in ''|*[!0-9]*) ec="" ;; esac

if [ -n "$ec" ]; then
  # A reported exit code certifies the SUITE only when the suite is the last
  # simple command (issue: pipeline/list exit-status masking mints false green).
  # Otherwise decline — the exit code describes `tail`/`echo`/`true`, not tests.
  [ "$clean" = "true" ] || allow
else
  # No exit-status evidence: rather than blindly re-executing the ARBITRARY
  # already-run command (issue #27 — unsafe for anything non-idempotent), invoke
  # the repo's explicit, allowlisted `testCommand` (trust-root config only, never
  # the agent's command string) and take its real exit code (issues #27, #35).
  # With no configured invoker there is no safe way to determine green — fail
  # safe and mint nothing (the commit gate stays closed until a suite with a real
  # exit code runs). Cap the re-exec with `timeout` (when available) well under
  # the hook's own budget so a long suite fails cleanly instead of being
  # SIGKILLed mid-write.
  tc="$(config_get_for "$target_root" testCommand '')"
  [ -n "$tc" ] || allow
  if command -v timeout >/dev/null 2>&1; then
    ( cd "$target_root" 2>/dev/null && timeout "${FACTORY_GATE_SYNC_BUDGET:-20}" sh -c "$tc" ) >/dev/null 2>&1; ec=$?
    if [ "$ec" = 124 ]; then
      # The suite is slower than a hook may block for. Bounded here it would
      # mint NOTHING and deadlock every commit (issue #93), so hand it to the
      # out-of-band runner, which mints when the suite actually finishes. The
      # hook still returns immediately — it never holds up the agent's turn.
      # The in-flight marker is written HERE, before the spawn, so the wait state
      # is visible to guard-commit from the instant of hand-off rather than
      # whenever the detached process happens to get scheduled; the runner owns
      # clearing it (its EXIT trap).
      mkdir -p "$STATE_DIR"
      printf '{"tree":%s,"root":%s}' "$(json_str "$(tree_hash "$target_root")")" "$(json_str "$target_root")" > "$(gate_marker)"
      ( nohup "$PLUGIN_ROOT/hooks/scripts/gate-run.sh" "$target_root" >/dev/null 2>&1 & disown ) 2>/dev/null \
        || ( "$PLUGIN_ROOT/hooks/scripts/gate-run.sh" "$target_root" >/dev/null 2>&1 & ) 2>/dev/null
      allow
    fi
  else
    ( cd "$target_root" 2>/dev/null && eval "$tc" ) >/dev/null 2>&1; ec=$?
  fi
  # Invoker could not start (126 not-executable / 127 not-found) or timed out
  # (124): that is "no evidence", not a red suite — mint nothing rather than a
  # misleading red receipt.
  case "$ec" in 124|126|127) allow ;; esac
fi

# The mint itself lives in common.sh so this in-hook path and the out-of-band
# runner (gate-run.sh, issue #93) can never drift apart: same gate-evaluate
# verdict, same tree binding, same optional signing (issue #2).
mint_receipt "$target_root" "$ec"
allow
