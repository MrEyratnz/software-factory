#!/usr/bin/env bash
# gate-run — run a repo's allowlisted suite to completion OUT OF BAND and mint
# the tree-bound green receipt (issue #93).
#
# Why this exists: when the harness reports no exit code for the agent's own
# suite command, record-green re-runs the repo's `testCommand` to observe a real
# status. Bounded inside the hook's timeout budget, any suite slower than ~20s
# produced NO receipt at all — so guard-commit denied every commit forever and
# the factory could not commit its own work. record-green now hands the slow case
# here, and this runner mints when the suite actually finishes.
#
# The trust properties are exactly those of the in-hook path:
#   * the command comes ONLY from the target repo's committed .factory/config.json
#     (never from the agent's command string — issue #27's allowlist rule),
#   * the exit code is a real suite exit code, not an inference, and
#   * the receipt is bound to the write-tree, recomputed at completion, so a tree
#     that moved while the suite ran mints nothing rather than certifying work
#     that was never tested.
#
# Invoked detached by record-green, or directly as `gate-run.sh <repo-root>`.
# Always exits 0-ish: it is a producer, never a gate.

# common.sh reads the hook event from stdin when HOOK_INPUT is unset; this script
# is not stdin-driven (it runs detached, and directly in tests), so declare an
# empty event rather than blocking on a `cat` that will never see input.
HOOK_INPUT='{}'
export HOOK_INPUT
. "$(dirname "$0")/../lib/common.sh"

root="${1:-$PROJECT_DIR}"
[ -n "$root" ] || exit 0

# Never create factory state in a repo that did not opt in, and never try to
# classify a receipt without node (issue #52's path).
factory_initialized || exit 0
command -v node >/dev/null 2>&1 || exit 0

tc="$(config_get_for "$root" testCommand '')"
[ -n "$tc" ] || exit 0

mkdir -p "$STATE_DIR"
lock="$(gate_lock)"
marker="$(gate_marker)"

# One gate run at a time: mkdir is the atomic test-and-set. A second runner
# declines rather than doubling the machine's load and racing the mint.
mkdir "$lock" 2>/dev/null || exit 0
trap 'rm -rf "$lock"; rm -f "$marker"' EXIT INT TERM

start_tree="$(tree_hash "$root")"
[ -n "$start_tree" ] || exit 0

# The in-flight marker is what lets guard-commit say "the gate run is in flight,
# wait" instead of the misleading "the last gate run was red".
printf '{"tree":%s,"root":%s}' "$(json_str "$start_tree")" "$(json_str "$root")" > "$marker"

# Cap the run so a hung suite cannot hold the lock forever. Generous by design:
# this is the path for suites too slow for the hook, and the cap only has to beat
# "wedged", not "slow".
if command -v timeout >/dev/null 2>&1; then
  ( cd "$root" 2>/dev/null && timeout "${FACTORY_GATE_MAX_SECONDS:-1800}" sh -c "$tc" ) >/dev/null 2>&1
  ec=$?
else
  ( cd "$root" 2>/dev/null && sh -c "$tc" ) >/dev/null 2>&1
  ec=$?
fi

# Timed out (124) or the invoker could not start (126/127): that is "no
# evidence", not a red suite — mint nothing rather than a misleading red receipt.
case "$ec" in 124|126|127) exit 0 ;; esac

# Tree-bound: if the working tree moved while the suite ran, this exit code
# certifies a tree that no longer exists. Mint nothing; the next run will bind
# to the tree that was actually tested.
[ "$(tree_hash "$root")" = "$start_tree" ] || exit 0

mint_receipt "$root" "$ec"
