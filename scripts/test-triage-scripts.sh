#!/usr/bin/env bash
# Regression tests for the vendored wrapper scripts (triage-add-labels.sh,
# triage-comment.sh, review-comment.sh). Those scripts are the tool-layer
# enforcement boundary for the Issue Triage and Claude Code Review
# workflows — the only thing preventing a prompt-injected session from
# retargeting another issue/PR, editing titles/bodies, or removing labels —
# so their argument contract is CI-gated here: a stub `gh` on PATH records
# what would be executed, and each case asserts pass-through or rejection.
# Dependency-free, mirrors tests/hooks.contract.test.sh in spirit
# (hermetic, stubbed gh, no network).
set -euo pipefail

cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Stub gh: records its argv — one arg per line, so a quoting or
# word-splitting regression in a wrapper changes the recording and fails
# the assertion — instead of calling GitHub.
cat > "$tmp/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${GH_STUB_OUT:?}"
EOF
chmod +x "$tmp/gh"
export PATH="$tmp:$PATH"
export GH_STUB_OUT="$tmp/out"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

run() { # run <expected-exit> <description> -- <cmd...>
  local expected="$1" desc="$2"
  shift 3
  : > "$GH_STUB_OUT"
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq "$expected" ] || fail "$desc: expected exit $expected, got $rc"
}

assert_argv() { # assert_argv <description> <expected-arg...>
  local desc="$1"
  shift
  printf '%s\n' "$@" | cmp -s - "$GH_STUB_OUT" ||
    fail "$desc argv mismatch: $(tr '\n' ' ' < "$GH_STUB_OUT")"
}

export TRIAGE_ISSUE=155

# --- triage-add-labels.sh ---
run 0 "multi --add-label passes through" -- \
  ./scripts/triage-add-labels.sh --add-label tech-debt --add-label "priority:low"
assert_argv "multi-label" issue edit 155 --add-label tech-debt --add-label "priority:low"

run 0 "--add-label= form passes through" -- \
  ./scripts/triage-add-labels.sh --add-label=triaged
assert_argv "=-form" issue edit 155 --add-label triaged

run 2 "--remove-label rejected" -- ./scripts/triage-add-labels.sh --remove-label bug
run 2 "no arguments rejected" -- ./scripts/triage-add-labels.sh
run 2 "positional issue number rejected" -- ./scripts/triage-add-labels.sh 161 --add-label bug
run 2 "--title rejected even after a valid flag" -- \
  ./scripts/triage-add-labels.sh --add-label bug --title pwned
run 2 "dangling --add-label without value rejected" -- ./scripts/triage-add-labels.sh --add-label

# Queue-control labels are owned by the pickup automation
# (project-pickup.yml): a triage session must not be able to drive it.
run 2 "queue-control label in-progress rejected" -- \
  ./scripts/triage-add-labels.sh --add-label in-progress
run 2 "queue-control label ready rejected (= form)" -- \
  ./scripts/triage-add-labels.sh --add-label=ready
run 2 "queue-control label rejected even after a valid label" -- \
  ./scripts/triage-add-labels.sh --add-label bug --add-label in-progress
[ ! -s "$GH_STUB_OUT" ] || fail "gh was invoked despite a rejected queue-control label"

# --- triage-comment.sh ---
run 0 "--body passes through" -- ./scripts/triage-comment.sh --body "duplicate of #142"
assert_argv "comment" issue comment 155 --body "duplicate of #142"

run 0 "--body= form passes through" -- ./scripts/triage-comment.sh --body="see #142"
assert_argv "comment =-form" issue comment 155 --body "see #142"

run 2 "positional issue number rejected (comment)" -- ./scripts/triage-comment.sh 161 --body hi
run 2 "no arguments rejected (comment)" -- ./scripts/triage-comment.sh
run 2 "second comment flag rejected" -- ./scripts/triage-comment.sh --body hi --body again
run 2 "empty body rejected (comment)" -- ./scripts/triage-comment.sh --body ""
run 2 "empty body rejected (= form, comment)" -- ./scripts/triage-comment.sh --body=
[ ! -s "$GH_STUB_OUT" ] || fail "gh was invoked despite an empty triage-comment body"

# A dash-leading body is DATA, not a flag: gh (pflag) consumes the next argv
# element as --body's value unconditionally, so this must pass through as
# literal comment text — a rewrite that treats it as an option (e.g. getopts)
# would silently change the wrapper's contract.
run 0 "dash-leading body passes through as data (comment)" -- \
  ./scripts/triage-comment.sh --body --edit-last
assert_argv "comment dash-leading body" issue comment 155 --body --edit-last

# --- missing TRIAGE_ISSUE fails loudly, gh never invoked ---
: > "$GH_STUB_OUT"
if (unset TRIAGE_ISSUE && ./scripts/triage-add-labels.sh --add-label bug) >/dev/null 2>&1; then
  fail "missing TRIAGE_ISSUE should fail (add-labels)"
fi
if (unset TRIAGE_ISSUE && ./scripts/triage-comment.sh --body hi) >/dev/null 2>&1; then
  fail "missing TRIAGE_ISSUE should fail (comment)"
fi
[ ! -s "$GH_STUB_OUT" ] || fail "gh was invoked despite missing TRIAGE_ISSUE"

# --- review-comment.sh (Claude Code Review workflow; pinned by REVIEW_PR) ---
export REVIEW_PR=62

run 0 "--body passes through (review)" -- ./scripts/review-comment.sh --body "LGTM with nits"
assert_argv "review comment" pr comment 62 --body "LGTM with nits"

run 0 "--body= form passes through (review)" -- ./scripts/review-comment.sh --body="see inline"
assert_argv "review comment =-form" pr comment 62 --body "see inline"

run 2 "positional PR number rejected (review)" -- ./scripts/review-comment.sh 61 --body hi
run 2 "no arguments rejected (review)" -- ./scripts/review-comment.sh
run 2 "second flag rejected (review)" -- ./scripts/review-comment.sh --body hi --body again
run 2 "--edit-last rejected (review)" -- ./scripts/review-comment.sh --body hi --edit-last
run 2 "empty body rejected (review)" -- ./scripts/review-comment.sh --body ""
run 2 "empty body rejected (= form, review)" -- ./scripts/review-comment.sh --body=
[ ! -s "$GH_STUB_OUT" ] || fail "gh was invoked despite a rejected review-comment invocation"

# Dash-leading body is data, not a flag (see the triage-comment case above).
run 0 "dash-leading body passes through as data (review)" -- \
  ./scripts/review-comment.sh --body --edit-last
assert_argv "review dash-leading body" pr comment 62 --body --edit-last

# --- missing REVIEW_PR fails loudly, gh never invoked ---
: > "$GH_STUB_OUT"
if (unset REVIEW_PR && ./scripts/review-comment.sh --body hi) >/dev/null 2>&1; then
  fail "missing REVIEW_PR should fail (review comment)"
fi
[ ! -s "$GH_STUB_OUT" ] || fail "gh was invoked despite missing REVIEW_PR"

echo "triage wrapper script tests: OK"
