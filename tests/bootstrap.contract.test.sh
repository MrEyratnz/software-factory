#!/usr/bin/env bash
# bootstrap.contract.test.sh — hermetic contract tests for bootstrap.sh, the ONE
# script a human runs once to stand up the factory. No network, no real GitHub:
# `gh`/`git`/`node`/`xdg-open` are replaced by a PATH shim of fakes under
# tests/bin that record their argv and return canned output — INCLUDING the real
# failure modes the adversarial audit found (gh writing a 404/403 error BODY to
# stdout and exiting 1; a GraphQL no-scope error document; a protected-branch
# push rejection).
#
# It pins the CORRECT post-fix behaviour for the 15 audited defects, plus the
# runner/egress-proxy failures observed on the first live bootstrap. Every
# assertion is a regression guard: green here means the defect stays fixed.
#
# Three techniques, by what each defect actually needs:
#   * full hermetic runs — copy bootstrap.sh into a temp workspace and run it end
#     to end with FACTORY_APPS_SKIP / FACTORY_RUNNER_SKIP so it reaches the repo,
#     push, secrets/vars, projects and dispatch sections; assert on the recorded
#     calls and the stdout contract.
#   * extracted-function drives — pull a single function (env_has_app,
#     ensure_issue) out of the script and call it directly under the shim.
#   * static parse assertions — for the app-flow internals and the node manifest
#     server, whose defects are not reachable without a live browser; a
#     grep/parse regression guard that would catch a re-introduction.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/bootstrap.sh"
BIN="$ROOT/tests/bin"
chmod +x "$BIN"/* 2>/dev/null || true

TMPROOT="$(mktemp -d)"
trap 'cd /; rm -rf "$TMPROOT"' EXIT

export CALL_LOG="$TMPROOT/calls.log"
export VARSET_LOG="$TMPROOT/varset.log"
export SECSET_LOG="$TMPROOT/secset.log"
OUT="$TMPROOT/stdout"; ERR="$TMPROOT/stderr"
CRA="$TMPROOT/create_role_app.snippet"

# The shim wins; the outer environment must not leak a real credential in.
export PATH="$BIN:$PATH"
unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN FACTORY_APP_PORT 2>/dev/null || true

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); [ -n "${VERBOSE:-}" ] && printf 'ok   - %s\n' "$1"; return 0; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; return 0; }
# expect "<label>" <rc>   — rc 0 means the correct behaviour held.
expect() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

# extract_func <name> — emit a single top-level `name() { ... }` block verbatim.
extract_func() {
  awk -v fn="$1" '
    index($0, fn"() {")==1 { p=1 }
    p { print }
    p && /^}/ { exit }
  ' "$BOOTSTRAP"
}

# A temp workspace that looks enough like a repo checkout for bootstrap to run:
# plugin manifest present (its root check) and LICENSE present (so it does not
# try to fetch+commit one). Every git/gh operation is intercepted by the shim.
WORK="$TMPROOT/work"
mkdir -p "$WORK/.claude-plugin"
cp "$BOOTSTRAP" "$WORK/bootstrap.sh"
printf '{}\n'        > "$WORK/.claude-plugin/plugin.json"
printf 'a license\n' > "$WORK/LICENSE"

reset_env() {
  export FACTORY_APPS_SKIP=true FACTORY_RUNNER_SKIP=true
  export FACTORY_REPO=owner/repo FAKE_OWNER=octocat
  export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-fake FACTORY_PAT=fake-pat
  export PUSH_MODE=ok GRAPHQL_EXISTING="" RUNLIST_MODE=ok
  unset HALT_STATE APP_ID_MODE ISSUE_SEARCH ISSUE_REST INSTALLATIONS_MODE REPO 2>/dev/null || true
  : > "$CALL_LOG"; : > "$VARSET_LOG"; : > "$SECSET_LOG"
}

run_bootstrap() {
  if command -v timeout >/dev/null 2>&1; then
    ( cd "$WORK" && timeout 90 bash "$WORK/bootstrap.sh" ) >"$OUT" 2>"$ERR"; RC=$?
  else
    ( cd "$WORK" && bash "$WORK/bootstrap.sh" ) >"$OUT" 2>"$ERR"; RC=$?
  fi
}

echo "# bootstrap.sh contract"

# --- sanity: the script under test parses ------------------------------------
if bash -n "$BOOTSTRAP" 2>/dev/null; then ok "bootstrap.sh parses (bash -n)"; else bad "bootstrap.sh fails bash -n"; fi

# =============================================================================
# env-has-app-404  (blocker) — a 404 variable read must read as NOT configured.
# gh writes the error body to stdout and exits 1; the guard must not mistake
# that blob for a configured app and skip every role.
# =============================================================================
# shellcheck disable=SC1090
source <(extract_func env_has_app)
export REPO=owner/repo
: > "$CALL_LOG"; export APP_ID_MODE=404
out="$(env_has_app orchestrator 2>/dev/null || true)"
if [ -z "$out" ]; then expect "[env-has-app-404] a 404 APP_ID read yields no value (role is NOT configured)" 0; else expect "[env-has-app-404] a 404 APP_ID read yields no value (role is NOT configured)" 1; fi
: > "$CALL_LOG"; export APP_ID_MODE=value
out="$(env_has_app orchestrator 2>/dev/null || true)"
if [ -n "$out" ]; then expect "[env-has-app-404] a genuinely present APP_ID still reads as configured" 0; else expect "[env-has-app-404] a genuinely present APP_ID still reads as configured" 1; fi
unset APP_ID_MODE REPO

# =============================================================================
# ensure-issue-search-lag (minor) — de-dup against the authoritative REST issue
# list, not the eventually-consistent search index. Model a just-created issue
# the search index has NOT caught up on (search empty) but REST returns it.
# =============================================================================
# shellcheck disable=SC1090
source <(extract_func ensure_issue)
export REPO=owner/repo
: > "$CALL_LOG"; export ISSUE_SEARCH="" ISSUE_REST="Epic 1: plugin test suite (tracking)"
ensure_issue "Epic 1: plugin test suite (tracking)" "P1" "body" >/dev/null 2>&1 || true
if grep -q 'issue create' "$CALL_LOG"; then rc=1; else rc=0; fi
expect "[ensure-issue-search-lag] a title present only in REST is NOT re-created (no duplicate)" "$rc"
if grep -q 'issues?state=all' "$CALL_LOG"; then rc=0; else rc=1; fi
expect "[ensure-issue-search-lag] de-dup reads the authoritative REST issue list" "$rc"
if grep -q 'issue list .*--search' "$CALL_LOG"; then rc=1; else rc=0; fi
expect "[ensure-issue-search-lag] de-dup does not depend on the lagging search index" "$rc"
unset ISSUE_SEARCH ISSUE_REST REPO

# =============================================================================
# push-protected-main (blocker) — a direct push to a protected main must not
# abort bootstrap. With a commit pending and main protected, bootstrap must
# route/​warn and CONTINUE, never die.
# =============================================================================
reset_env; export PUSH_MODE=protected
run_bootstrap
if [ "$RC" -eq 0 ]; then expect "[push-protected-main] a protected-main push rejection does not abort bootstrap" 0; else expect "[push-protected-main] a protected-main push rejection does not abort bootstrap" 1; fi
if grep -q '^Factory is live: ' "$OUT"; then rc=0; else rc=1; fi
expect "[push-protected-main] bootstrap still runs to completion (prints the live line)" "$rc"

# =============================================================================
# projects-error-body (blocker) — a Projects v2 query that errors (no scope)
# prints the GraphQL error document to stdout and exits 1. That blob must never
# be sliced into PROJECT_ID and written as a repo variable.
# =============================================================================
reset_env; export GRAPHQL_EXISTING=ERROR
run_bootstrap
pid="$(awk -F'\t' '$1=="PROJECT_ID"{v=$2} END{print v}' "$VARSET_LOG")"
case "$pid" in
  ""|PVT_*) rc=0 ;;   # unset, or a genuine Projects v2 node id
  *)        rc=1 ;;   # a JSON error blob got written
esac
expect "[projects-error-body] PROJECT_ID is never written from a GraphQL error blob" "$rc"

# =============================================================================
# project-var-names (major) + fields-only-on-create (major)
# One run with the board ALREADY present exercises both: the workflows read
# vars.TRIAGE_PROJECT_NUMBER and secrets.PROJECT_TOKEN (bootstrap must set them),
# and the board's fields must be ensured even when the board pre-exists.
# =============================================================================
reset_env; export GRAPHQL_EXISTING="PVT_exist 3"
run_bootstrap
if awk -F'\t' '$1=="TRIAGE_PROJECT_NUMBER"{f=1} END{exit f?0:1}' "$VARSET_LOG"; then rc=0; else rc=1; fi
expect "[project-var-names] TRIAGE_PROJECT_NUMBER variable is set (project-pickup/triage read it)" "$rc"
if grep -qx 'PROJECT_TOKEN' "$SECSET_LOG"; then rc=0; else rc=1; fi
expect "[project-var-names] PROJECT_TOKEN secret is set when a PAT is provided" "$rc"
if grep -q 'createProjectV2Field' "$CALL_LOG"; then rc=0; else rc=1; fi
expect "[fields-only-on-create] board fields are ensured even when the board already exists" "$rc"

# =============================================================================
# factory-halt-reset (major) — a re-run must not silently un-halt a factory a
# human deliberately halted, nor re-dispatch it.
# =============================================================================
reset_env; export HALT_STATE=true
run_bootstrap
if awk -F'\t' '$1=="FACTORY_HALT" && $2=="false"{f=1} END{exit f?1:0}' "$VARSET_LOG"; then rc=0; else rc=1; fi
expect "[factory-halt-reset] a pre-existing FACTORY_HALT=true is NOT reset to false" "$rc"
if grep -q 'workflow run factory-run' "$CALL_LOG"; then rc=1; else rc=0; fi
expect "[factory-halt-reset] no factory-run is dispatched while halted" "$rc"

# =============================================================================
# final-poll-set-e (major) — the final `gh run list` poll can fail transiently;
# under set -e that kills a fully-successful bootstrap with no output, violating
# the "only Factory is live" contract. Success must still print the live line.
# =============================================================================
reset_env; export RUNLIST_MODE=fail
run_bootstrap
if [ "$RC" -eq 0 ]; then expect "[final-poll-set-e] a failing run-list poll does not kill a successful bootstrap" 0; else expect "[final-poll-set-e] a failing run-list poll does not kill a successful bootstrap" 1; fi
lines="$(grep -c . "$OUT" 2>/dev/null || printf 0)"
if grep -q '^Factory is live: ' "$OUT" && [ "$lines" -eq 1 ]; then rc=0; else rc=1; fi
expect "[final-poll-set-e] stdout carries ONLY the single Factory-is-live line" "$rc"

# =============================================================================
# Runner + egress-proxy section. These are static parse assertions because the
# real path needs a docker daemon, which the suite must not require; each one
# pins a failure observed on the icculus host after the first live bootstrap.
# =============================================================================

# squid-acl-fatal (blocker) — squid >=6 treats a dstdomain ACL that lists both a
# domain and a wildcard covering it ('.github.com' + 'github.com') as a FATAL
# config error, so the proxy never listens, so the runner cannot reach
# factory-proxy:3128 and crash-loops forever while FACTORY_RUNNER silently falls
# back to hosted runners. No entry may cover another entry in the same ACL.
acl_line="$(grep -m1 '^acl allowed dstdomain ' "$BOOTSTRAP" || true)"
if [ -n "$acl_line" ]; then rc=0; else rc=1; fi
expect "[squid-acl-fatal] bootstrap declares a dstdomain allowlist" "$rc"
dupe="$(printf '%s\n' "$acl_line" | awk '
  { for (i = 4; i <= NF; i++) d[++n] = $i }
  END {
    for (i = 1; i <= n; i++) for (j = 1; j <= n; j++) {
      if (i == j) continue
      a = d[i]; b = d[j]
      if (substr(a, 1, 1) != ".") continue
      bare = substr(a, 2)
      # a (leading-dot .x.com) covers b when b IS x.com or ends in .x.com
      if (b == bare || (length(b) > length(a) && substr(b, length(b) - length(a) + 1) == a))
        print a " covers " b
    }
  }')"
if [ -z "$dupe" ]; then rc=0; else rc=1; fi
expect "[squid-acl-fatal] no allowlist entry shadows another (squid 6 fatals): ${dupe:-none}" "$rc"

# sudo-probe-mismatch (major) — the privilege probe must test the command it
# actually runs (iptables). Probing `sudo -n true` reports "no sudo" for a
# correctly scoped NOPASSWD:/usr/sbin/iptables rule, so bootstrap skips the
# egress firewall and files a false P1 security issue.
if grep -q 'sudo -n true' "$BOOTSTRAP"; then rc=1; else rc=0; fi
expect "[sudo-probe-mismatch] the privilege probe is not the unrelated 'sudo -n true'" "$rc"
if grep -qE 'sudo -n iptables' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[sudo-probe-mismatch] the privilege probe exercises iptables itself" "$rc"

# proxy-stale-config (blocker) — presence is not health: a crash-looping
# container still lists in `docker ps`, so a name check makes a broken proxy
# permanent and means a fixed config never lands on re-run. The proxy must be
# recreated from the current config every run.
if grep -q "docker rm -f factory-proxy" "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[proxy-stale-config] the proxy is recreated from the current config each run" "$rc"

# proxy-not-health-checked (blocker) — bootstrap must verify the proxy is really
# serving before it registers a runner against it, and must fail loudly with the
# proxy's own logs instead of leaving a crash-looping runner behind.
if grep -q 'proxy_healthy' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[proxy-not-health-checked] the proxy is health-checked before the runner starts" "$rc"
if grep -q 'docker logs factory-proxy' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[proxy-not-health-checked] a dead proxy surfaces its own logs" "$rc"

# health-probe-wrong-shell (blocker) — the probe uses bash's /dev/tcp, which
# does not exist in a POSIX sh; running it under `sh` fails on a perfectly
# healthy proxy, so bootstrap would refuse to ever register the runner.
if grep -q 'dev/tcp' "$BOOTSTRAP"; then
  if grep -E 'docker exec factory-proxy (sh|/bin/sh) ' "$BOOTSTRAP" | grep -q 'dev/tcp'; then rc=1; else rc=0; fi
else rc=1; fi
expect "[health-probe-wrong-shell] the /dev/tcp probe runs under bash, not sh" "$rc"

# proxy-egress-dropped (blocker) — the DROP rule covers the whole factory-net
# subnet, and the PROXY lives in that subnet, so squid itself cannot reach the
# internet: every CONNECT ends in a 60s timeout and a TCP_TUNNEL/503. The proxy
# host needs an explicit ACCEPT; the allowlist is enforced in squid, not here.
if grep -qE 'iptables .*-s "\$proxy_ip" -j ACCEPT' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[proxy-egress-dropped] the proxy's own egress is accepted above the subnet DROP" "$rc"

# js-actions-proxy-blind (blocker) — Node >=24 refuses to honour http_proxy
# unless NODE_USE_ENV_PROXY is set, so on a proxied runner EVERY JavaScript
# action (starting with create-github-app-token, the first step of every
# station) dies before the session runs. The runner container must export it.
if grep -q 'NODE_USE_ENV_PROXY=1' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[js-actions-proxy-blind] the runner exports NODE_USE_ENV_PROXY for JS actions" "$rc"

# proxy-ip-unvalidated (major) — `docker inspect` prints "invalid IP" (not an
# empty string) for a container with no live network, so an unvalidated capture
# feeds garbage to `iptables -d` and the firewall silently fails to apply.
if grep -qE 'case .\$proxy_ip. in|proxy_ip.*\[0-9\]' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[proxy-ip-unvalidated] the captured proxy IP is validated before use" "$rc"

# =============================================================================
# Static regression guards for defects whose trigger path needs a live browser /
# App-manifest exchange and so is not hermetically drivable end-to-end. Each
# greps/parses bootstrap.sh and fails on today's unfixed script.
# =============================================================================
extract_func create_role_app > "$CRA"

# secret-before-var (blocker) — APP_PRIVATE_KEY (secret) must be written BEFORE
# APP_ID (variable), so "APP_ID present" means genuinely complete.
sv="$(grep -n 'variable set APP_ID' "$CRA" | head -1 | cut -d: -f1)"
ss="$(grep -n 'secret  *set APP_PRIVATE_KEY' "$CRA" | head -1 | cut -d: -f1)"
if [ -n "$sv" ] && [ -n "$ss" ] && [ "$ss" -lt "$sv" ]; then rc=0; else rc=1; fi
expect "[secret-before-var] APP_PRIVATE_KEY is stored before APP_ID" "$rc"

# browser-before-listen (major) — the manifest server must be started before the
# browser is opened, or the first GET hits a not-yet-listening port.
xo="$(grep -n 'xdg-open "http://localhost:\$APP_PORT"' "$CRA" | head -1 | cut -d: -f1)"
sm="$(grep -n 'serve_manifest "\$role"' "$CRA" | head -1 | cut -d: -f1)"
if [ -n "$xo" ] && [ -n "$sm" ] && [ "$xo" -gt "$sm" ]; then rc=0; else rc=1; fi
expect "[browser-before-listen] the browser opens only after the manifest server is started" "$rc"

# user-installations-403 (blocker) + install-not-verified (major) — the
# user/installations poll (which 403s) must be gone, replaced by verifying repo
# coverage: mint an App JWT (RS256) and GET /repos/$REPO/installation.
if grep -q 'user/installations' "$BOOTSTRAP"; then rc=1; else rc=0; fi
expect "[user-installations-403] the 403-prone user/installations poll is removed" "$rc"
if grep -q 'repos/\$REPO/installation' "$BOOTSTRAP" && grep -q 'RS256' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[install-not-verified] install is verified by minting an app JWT and checking repo coverage" "$rc"

# pem-not-persisted (blocker) — the one-time pem must be persisted to a
# gitignored local file the instant it is minted, so a retry can resume.
if grep -q 'bootstrap-apps' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[pem-not-persisted] the one-time pem is persisted to a gitignored local file" "$rc"

# server-no-error-handler (minor) — server.listen must have an error handler so
# EADDRINUSE is a clear message and a distinct exit code, not a generic crash.
if grep -q 'server.on("error"' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[server-no-error-handler] the manifest server handles listen errors (EADDRINUSE)" "$rc"

# callback-no-state (minor) — the /callback handler must validate a per-run
# random state nonce and the server must bind to localhost only.
if grep -q 'randomUUID' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[callback-no-state] a per-invocation random state nonce is minted" "$rc"
if grep -q 'searchParams.get("state")' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[callback-no-state] the callback rejects a code whose state does not match" "$rc"
# Require the quoted host form passed to server.listen — the unquoted 127.0.0.1
# in the runner's no_proxy env must not satisfy this.
if grep -q '"127\.0\.0\.1"' "$BOOTSTRAP"; then rc=0; else rc=1; fi
expect "[callback-no-state] the manifest server binds to localhost (127.0.0.1) only" "$rc"

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
