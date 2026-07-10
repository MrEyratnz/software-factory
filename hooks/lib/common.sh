#!/usr/bin/env bash
# common.sh — shared substrate for every Dark Software Factory hook.
#
# Hooks source this, then read the Claude Code event JSON already captured into
# $HOOK_INPUT and use the helpers below. The design rule: all rule *verdicts*
# come from the pure factory-core (via the cli.mjs bridge), never reimplemented
# here, so the enforcement path and the connector's read path can never
# disagree. This file only does I/O, git plumbing, and decision emission.
#
# Decision contract (uniform, easy to test):
#   allow / proceed  -> exit 0, no output
#   block            -> exit 2, human-readable reason on stderr
#   inject context   -> exit 0, {"hookSpecificOutput":{...,"additionalContext"}} on stdout
set -u

# --- locations -------------------------------------------------------------
# scripts/ live under $PLUGIN_ROOT/hooks/scripts; lib/ under $PLUGIN_ROOT/hooks/lib.
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_LIB_DIR/../.." && pwd)}"
FACTORY_CLI="$PLUGIN_ROOT/connector/src/cli.mjs"

# Read stdin once (hooks are invoked with the event JSON on stdin).
if [ -z "${HOOK_INPUT:-}" ]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi
# NOTE: HOOK_INPUT is a plain shell variable and is deliberately NOT exported.
# The event JSON can be large (a Bash tool_response carries the command's full
# stdout/stderr). On Linux a single environment-variable string is capped at
# MAX_ARG_STRLEN (128KB); once HOOK_INPUT crosses it, execve() of EVERY child
# process fails with E2BIG. That would make `field`/`config_get`/`fc` — and thus
# every gate verdict — silently fail open (a verbose passing suite would then
# never mint a receipt, and a commit could slip past). So the payload is fed to
# the node helpers on STDIN (not env/argv), which has no such limit.

# Project dir: explicit env wins, else the event's cwd, else PWD.
_project_from_input="$(printf '%s' "$HOOK_INPUT" | node -e 'let s="";process.stdin.setEncoding("utf8");process.stdin.on("data",c=>s+=c).on("end",()=>{try{const o=JSON.parse(s||"{}");process.stdout.write(o.cwd||"")}catch(e){}})' 2>/dev/null || true)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${_project_from_input:-$PWD}}"
FACTORY_DIR="$PROJECT_DIR/.factory"
STATE_DIR="$FACTORY_DIR/state"
CONFIG_FILE="$FACTORY_DIR/config.json"

# --- json helpers ----------------------------------------------------------
# field <dotted.path> — extract a field from the event JSON as a plain string.
# The event is piped on STDIN, never passed via env/argv, so a large
# tool_response (big test output) cannot trip execve's E2BIG limit (see the
# HOOK_INPUT note above).
field() {
  printf '%s' "$HOOK_INPUT" | node -e '
    let s = ""; process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => { s += c; }).on("end", () => {
      let o = {}; try { o = JSON.parse(s || "{}"); } catch (e) {}
      let v = o;
      for (const k of String(process.argv[1]).split(".")) v = (v == null ? undefined : v[k]);
      process.stdout.write(v == null ? "" : (typeof v === "object" ? JSON.stringify(v) : String(v)));
    });
  ' "$1" 2>/dev/null
}

# fc <subcommand> — bridge to factory-core; JSON in on stdin, JSON out on stdout.
fc() {
  if command -v node >/dev/null 2>&1 && [ -f "$FACTORY_CLI" ]; then
    node "$FACTORY_CLI" "$1" 2>/dev/null
  else
    # POSIX fallback keeps the factory running without node for the one gate
    # that must never be skipped: a bare Conventional-Commit shape check.
    echo '{"ok":true,"degraded":true}'
  fi
}

# json_str <value> — emit a JSON-quoted string (for building stdout payloads).
# The value is piped on STDIN (a roadmap file or a whole command string can be
# large — see the HOOK_INPUT note); passing it via env would risk E2BIG.
json_str() { printf '%s' "$1" | node -e 'let s="";process.stdin.setEncoding("utf8");process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.stringify(s)))'; }

# --- config ----------------------------------------------------------------
# config_get <key> [default] — read a key from .factory/config.json. <key> may
# be a dotted path (e.g. "otel.enabled") to reach into a nested object, same
# convention as field() above.
config_get() {
  local key="$1" def="${2:-}"
  [ -f "$CONFIG_FILE" ] || { printf '%s' "$def"; return; }
  CFG_FILE="$CONFIG_FILE" node -e '
    const fs=require("fs");let o={};try{o=JSON.parse(fs.readFileSync(process.env.CFG_FILE,"utf8"))}catch(e){}
    let v=o;
    for (const k of String(process.argv[1]).split(".")) v = (v && typeof v==="object") ? v[k] : undefined;
    process.stdout.write(v==null?process.argv[2]:(typeof v==="object"?JSON.stringify(v):String(v)));
  ' "$key" "$def" 2>/dev/null || printf '%s' "$def"
}

# --- enforcement levers (issues #29, #30) ----------------------------------
# The hard gates are ON by default. Two levers relax them without the binary
# all-or-nothing plugin toggle:
#
#   1. enforcement_on <gate> — a per-gate boolean in .factory/config.json's
#      "enforcement" block (committed, reviewable, per-repo). Every hard gate
#      defaults to true; a repo opts a single gate out deliberately and
#      visibly, e.g. {"enforcement":{"requireGreenReceiptOnCommit":false}}.
#      Returns 0 (enforce) unless the key is explicitly the string "false".
enforcement_on() {
  [ "$(config_get "enforcement.$1" true)" != "false" ]
}

#   2. factory_paused / respect_pause — a session-local escape hatch. When a
#      human drops a marker at $STATE_DIR/paused (or paused.json), every hard
#      gate steps aside for this worktree, independent of Claude Code's
#      settings hot-reload semantics (which do not reliably detach a plugin's
#      hooks mid-session). The marker lives under the trust-root
#      .factory/state/, so the policed agent cannot forge it through the gated
#      tools — only a human or CI with direct filesystem access sets it
#      (`touch .factory/state/paused`) and clears it (`rm`). factory_paused
#      returns 0 (paused) when the marker is present.
factory_paused() {
  [ -f "$STATE_DIR/paused" ] || [ -f "$STATE_DIR/paused.json" ]
}

# respect_pause <hook-name> — call at the top of an enforcing guard: if the
# factory is paused, emit a metric and allow (exit 0). No-op otherwise.
respect_pause() {
  factory_paused || return 0
  otel_emit factory_gate_paused_total sum 1 "$(printf '{"hook":%s}' "$(json_str "${1:-unknown}")")"
  allow
}

# --- git plumbing ----------------------------------------------------------
# tree_hash [dir] — deterministic hash of a working tree (tracked + untracked),
# EXCLUDING .factory/, computed via a throwaway index so the real index is
# never touched. Binding a green receipt to this hash means any later edit to
# source silently invalidates it. Defaults to the session PROJECT_DIR, but
# accepts an explicit dir so a gate can hash the repo the command actually
# targets, not just the one the session started in (issue #28).
tree_hash() {
  local dir="${1:-$PROJECT_DIR}" idx out rel
  idx="$(mktemp)"; rm -f "$idx"
  # Exclude the SESSION's .factory wherever it actually lives relative to the
  # hashed dir, not just a top-level .factory. When Claude is opened in a
  # subdirectory of the repo (a monorepo package), FACTORY_DIR is
  # <repo>/<subdir>/.factory but the receipt binds to the repo-root tree — so a
  # ':(exclude).factory' pathspec (relative to the repo root) would miss it, the
  # freshly-minted receipt would land INSIDE the hashed tree, and every commit
  # would be denied "stale-tree" forever. Compute the receipt dir's path
  # relative to the hashed dir (pure prefix strip, no node) and exclude it too.
  case "$FACTORY_DIR" in
    "$dir"/*) rel="${FACTORY_DIR#"$dir"/}" ;;
    *) rel="" ;;
  esac
  out="$(
    cd "$dir" 2>/dev/null || exit 0
    if [ -n "$rel" ] && [ "$rel" != ".factory" ]; then
      GIT_INDEX_FILE="$idx" git add -A -- ':(exclude).factory' ":(exclude)$rel" >/dev/null 2>&1
    else
      GIT_INDEX_FILE="$idx" git add -A -- ':(exclude).factory' >/dev/null 2>&1
    fi
    GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null
  )"
  rm -f "$idx"
  printf '%s' "$out"
}

# --- target-repo resolution (issue #28) ------------------------------------
# The green gate must bind to the repo a command actually operates on, not the
# fixed session PROJECT_DIR — otherwise a commit to a sibling repo in a
# multi-repo session is checked against the ORIGINAL project's tree, which is
# meaningless. These helpers derive that target repo and key its receipt.
#
# command_target_dir <cmd> — best-effort working directory a git command
# operates on, mirroring git's OWN precedence: `git -C <dir>` overrides the
# shell cwd, which a leading `cd <dir>` sets. So `git -C <dir>` wins over `cd`
# even when both are present (`cd G && git -C R commit` targets R, not G — the
# gate must bind to R). A `git -C`/`cd` merely mentioned inside a commit message
# or heredoc is ignored: the `git -C` target must be an existing directory to be
# trusted, and the `cd` is only honored at command start. Falls back to
# PROJECT_DIR.
command_target_dir() {
  local cmd="$1" out cd gitC
  out="$(printf '%s' "$cmd" | HOOK_PROJECT_DIR="$PROJECT_DIR" node "$PLUGIN_ROOT/hooks/lib/parse-cmd-target.mjs" 2>/dev/null)"
  gitC="$(printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).gitC||"")}catch(e){}})')"
  cd="$(printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).cd||"")}catch(e){}})')"
  if [ -n "$gitC" ]; then printf '%s' "$gitC"; return; fi
  if [ -n "$cd" ]; then printf '%s' "$cd"; return; fi
  printf '%s' "$PROJECT_DIR"
}

# repo_root <dir> — the git top-level of dir (so a subdir maps to one receipt),
# or dir itself when it is not inside a git repo.
repo_root() {
  local d="$1" top
  top="$(cd "$d" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$top" ] && printf '%s' "$top" || printf '%s' "$d"
}

# receipt_file [repo-root] — the gate-receipt path for a repo. The session's own
# project keeps the canonical gate-receipt.json (backward compatible); any OTHER
# repo committed to in the same session gets its own receipt keyed by a short
# hash of its root, so concurrent per-repo receipts can coexist. All receipts
# live under the SESSION's protected .factory/state trust root, never the
# target repo's.
receipt_file() {
  local root="${1:-$PROJECT_DIR}" sroot key
  sroot="$(repo_root "$PROJECT_DIR")"
  if [ "$root" = "$sroot" ] || [ "$root" = "$PROJECT_DIR" ] || [ -z "$root" ]; then
    printf '%s' "$STATE_DIR/gate-receipt.json"
  else
    key="$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
    printf '%s' "$STATE_DIR/gate-receipt-$key.json"
  fi
}

# --- optional receipt signing (issue #2) -----------------------------------
# The gate proofs live inside the repo the policed agent can write, and
# record-green infers "green" from the agent's command + exit code — so a
# determined agent can hand-write a proof. guard-scope/guard-bash-writes raise
# the bar, but the residual weakness is architectural (CI is the authoritative
# boundary regardless).
#
# When a runner-only signing secret is configured (FACTORY_RECEIPT_KEY, or a
# path in FACTORY_RECEIPT_KEYFILE), receipts/proofs are HMAC-SHA256-signed and a
# missing/invalid signature is REJECTED — so a hand-written receipt no longer
# certifies green. The protection is exactly as strong as the secret's privacy
# from the agent: a runner that keeps it hook-private (or scrubs it from the
# agent's shell env) closes hand-forgery outright; elsewhere it still raises the
# bar. When no secret is set (the default) behavior is unchanged — no signature
# is required, fully backward compatible.
receipt_secret() {
  if [ -n "${FACTORY_RECEIPT_KEY:-}" ]; then printf '%s' "$FACTORY_RECEIPT_KEY"; return; fi
  local kf="${FACTORY_RECEIPT_KEYFILE:-}"
  [ -n "$kf" ] && [ -f "$kf" ] && cat "$kf" 2>/dev/null
}

# receipt_sign <ok> <tree> — HMAC-SHA256 hex over "<ok>:<tree>" under the secret
# (empty string when no secret is configured).
receipt_sign() {
  local secret; secret="$(receipt_secret)"
  [ -n "$secret" ] || { printf ''; return; }
  PAYLOAD="$1:$2" SECRET="$secret" node -e 'const c=require("crypto");process.stdout.write(c.createHmac("sha256",process.env.SECRET).update(process.env.PAYLOAD||"").digest("hex"))' 2>/dev/null
}

# receipt_verify <file> — 0 if the receipt is acceptable: no secret configured
# (nothing to verify), or a secret is set and the file carries a valid signature
# over its own ok+tree. 1 if a secret is set and the signature is missing/wrong.
receipt_verify() {
  local secret; secret="$(receipt_secret)"
  [ -n "$secret" ] || return 0
  REC="$1" SECRET="$secret" node -e '
    const fs=require("fs"),c=require("crypto");
    try{
      const o=JSON.parse(fs.readFileSync(process.env.REC,"utf8"));
      const want=c.createHmac("sha256",process.env.SECRET).update(String(o.ok)+":"+(o.tree||"")).digest("hex");
      const got=String(o.sig||"");
      process.exit(got.length===want.length && c.timingSafeEqual(Buffer.from(got),Buffer.from(want))?0:1);
    }catch(e){process.exit(1)}
  ' 2>/dev/null
}

# receipt_embed_sig — read a receipt JSON on stdin, add a "sig" field signing
# its ok+tree, write it back on stdout. A no-op passthrough when no secret.
receipt_embed_sig() {
  local secret; secret="$(receipt_secret)"
  [ -n "$secret" ] || { cat; return; }
  SECRET="$secret" node -e '
    const c=require("crypto");let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{const o=JSON.parse(s);o.sig=c.createHmac("sha256",process.env.SECRET).update(String(o.ok)+":"+(o.tree||"")).digest("hex");process.stdout.write(JSON.stringify(o));}
      catch(e){process.stdout.write(s);}
    });'
}

staged_files() { ( cd "${1:-$PROJECT_DIR}" 2>/dev/null && git diff --cached --name-only 2>/dev/null ); }

# --- otel (optional, opt-in, push-based metrics) ----------------------------
# otel_emit <name> <type:sum|gauge> <value> [attrsJson] — fire-and-forget push
# of ONE metric datapoint to an OTEL collector. OFF BY DEFAULT: the very first
# thing this does is check otel.enabled, and it returns immediately (no fork,
# no network) unless that is exactly "true" — so a repo that never sets it
# pays no cost beyond the one config read every hook already does for its own
# settings. When enabled, the actual POST happens in otel-emit.mjs, run fully
# backgrounded and disowned with its own hard client-side timeout, so this
# call can never add latency to — or change the exit code of — the gate that
# invoked it. Callers must invoke this BEFORE their allow/deny so the emit is
# never skipped by an early exit, and must never let its (irrelevant) return
# value influence $?.
otel_emit() {
  [ "$(config_get otel.enabled false)" = "true" ] || return 0
  command -v node >/dev/null 2>&1 || return 0
  local name="$1" type="$2" value="$3" attrs="${4:-{}}"
  local endpoint; endpoint="$(config_get otel.endpoint 'http://localhost:4318')"
  ( OTEL_ENDPOINT="$endpoint" node "$PLUGIN_ROOT/hooks/lib/otel-emit.mjs" "$name" "$type" "$value" "$attrs" >/dev/null 2>&1 & disown ) 2>/dev/null
  return 0
}

# --- decisions -------------------------------------------------------------
# Two denial classes so a human — or Claude Code's separate auto-mode
# classifier — can tell a hard boundary from a best-effort heuristic (issues
# #32, #33). The [hard-boundary] / [heuristic] tag is machine-readable on
# purpose: it is the structured signal that distinguishes the two.
#
#   deny      — a HARD boundary: a bypass flag, a trust-root write, a write
#               outside the project tree, an exact tool-name policy. There is no
#               false positive here and routing around it is not sanctioned.
#   deny_soft — a HEURISTIC, fail-early match on command *text* (commit/release
#               detection, lint, tests-first) that can misfire. Satisfying the
#               requirement OR rephrasing so the heuristic no longer matches is
#               expected and fine — CI re-runs the authoritative gate regardless.
#               Appending this note gives any classifier/reviewer reading the
#               transcript a clear signal that a retry is not evasion.
deny()  { printf '%s\n' "dark-software-factory: [hard-boundary] $1" >&2; exit 2; }
deny_soft() {
  printf '%s\n' "dark-software-factory: [heuristic] $1 — best-effort, fail-early match on command text, not a hard security boundary; satisfying the requirement or rephrasing to avoid the match is expected (CI re-runs the authoritative gate)." >&2
  exit 2
}
allow() { exit 0; }

# inject_context <text> — additionalContext for SessionStart / UserPromptSubmit.
inject_context() {
  local ev; ev="$(field hook_event_name)"; [ -n "$ev" ] || ev="SessionStart"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' "$ev" "$(json_str "$1")"
  exit 0
}

# block_stop <reason> — block a Stop/SubagentStop with a reason (exit 2).
block_stop() { printf '%s\n' "dark-software-factory: $1" >&2; exit 2; }

# status_text — one-line factory dashboard for context injection: roadmap
# cursor + % complete, local gate state, open tech-debt count.
status_text() {
  local roadmap md summary pct nexttxt gate debt
  roadmap="$PROJECT_DIR/$(config_get roadmapPath 'docs/ROADMAP.md')"
  if [ -f "$roadmap" ]; then
    md="$(cat "$roadmap" 2>/dev/null)"
    summary="$(printf '{"markdown":%s}' "$(json_str "$md")" | fc roadmap-status)"
    pct="$(printf '%s' "$summary" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).totals.percent))}catch(e){process.stdout.write("?")}})')"
    nexttxt="$(printf '%s' "$summary" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const n=JSON.parse(s).next;process.stdout.write(n?n.text:"(roadmap complete)")}catch(e){process.stdout.write("?")}})')"
  else
    pct="n/a"; nexttxt="no roadmap — run /factory-init"
  fi
  if [ -f "$STATE_DIR/gate-receipt.json" ]; then
    local rtree cur rok
    rok="$(REC="$STATE_DIR/gate-receipt.json" node -e 'const fs=require("fs");try{process.stdout.write(String(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).ok))}catch(e){process.stdout.write("false")}')"
    rtree="$(REC="$STATE_DIR/gate-receipt.json" node -e 'const fs=require("fs");try{process.stdout.write(JSON.parse(fs.readFileSync(process.env.REC,"utf8")).tree||"")}catch(e){}')"
    cur="$(tree_hash "$PROJECT_DIR")"
    if [ "$rok" = "true" ] && [ "$cur" = "$rtree" ]; then gate="green"; else gate="stale/red (re-run tests)"; fi
  else
    gate="unknown (no gate run yet)"
  fi
  debt="?"
  if command -v gh >/dev/null 2>&1; then
    debt="$(gh issue list --label tech-debt --state open --json number 2>/dev/null | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).length))}catch(e){process.stdout.write("?")}})')"
  fi
  printf 'Dark Software Factory — roadmap %s%% done; next: %s | local gate: %s | open tech-debt: %s' \
    "$pct" "$nexttxt" "$gate" "$debt"
}
