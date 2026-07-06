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
export HOOK_INPUT

# Project dir: explicit env wins, else the event's cwd, else PWD.
_project_from_input="$(HOOK_JSON="$HOOK_INPUT" node -e 'try{const o=JSON.parse(process.env.HOOK_JSON||"{}");process.stdout.write(o.cwd||"")}catch(e){}' 2>/dev/null || true)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${_project_from_input:-$PWD}}"
FACTORY_DIR="$PROJECT_DIR/.factory"
STATE_DIR="$FACTORY_DIR/state"
CONFIG_FILE="$FACTORY_DIR/config.json"

# --- json helpers ----------------------------------------------------------
# field <dotted.path> — extract a field from the event JSON as a plain string.
field() {
  HOOK_JSON="$HOOK_INPUT" node -e '
    const o = JSON.parse(process.env.HOOK_JSON || "{}");
    let v = o;
    for (const k of String(process.argv[1]).split(".")) v = (v == null ? undefined : v[k]);
    process.stdout.write(v == null ? "" : (typeof v === "object" ? JSON.stringify(v) : String(v)));
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
json_str() { HOOK_S="$1" node -e 'process.stdout.write(JSON.stringify(process.env.HOOK_S||""))'; }

# --- config ----------------------------------------------------------------
# config_get <key> [default] — read a top-level key from .factory/config.json.
config_get() {
  local key="$1" def="${2:-}"
  [ -f "$CONFIG_FILE" ] || { printf '%s' "$def"; return; }
  CFG_FILE="$CONFIG_FILE" node -e '
    const fs=require("fs");let o={};try{o=JSON.parse(fs.readFileSync(process.env.CFG_FILE,"utf8"))}catch(e){}
    const v=o[process.argv[1]];process.stdout.write(v==null?process.argv[2]:(typeof v==="object"?JSON.stringify(v):String(v)));
  ' "$key" "$def" 2>/dev/null || printf '%s' "$def"
}

# --- git plumbing ----------------------------------------------------------
# tree_hash — deterministic hash of the working tree (tracked + untracked),
# EXCLUDING .factory/, computed via a throwaway index so the real index is
# never touched. Binding a green receipt to this hash means any later edit to
# source silently invalidates it.
tree_hash() {
  local idx out
  idx="$(mktemp)"; rm -f "$idx"
  out="$(
    cd "$PROJECT_DIR" 2>/dev/null || exit 0
    GIT_INDEX_FILE="$idx" git add -A -- ':(exclude).factory' >/dev/null 2>&1
    GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null
  )"
  rm -f "$idx"
  printf '%s' "$out"
}

staged_files() { ( cd "$PROJECT_DIR" 2>/dev/null && git diff --cached --name-only 2>/dev/null ); }

# --- decisions -------------------------------------------------------------
deny()  { printf '%s\n' "dark-software-factory: $1" >&2; exit 2; }
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
    cur="$(tree_hash)"
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
