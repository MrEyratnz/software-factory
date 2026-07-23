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

# issue #52: without node, the quote-aware parsers and fc verdicts below cannot
# run and every field() read comes back empty — the gate would fail OPEN
# silently. node_guard makes the degradation loud; this guard additionally
# holds the hardest boundary with a POSIX-only fallback: the raw event (the
# parsed command is unreachable without node) mentioning both a commit and a
# bypass flag is denied. Quote-blind by design — in a node-less (broken)
# environment a rare false positive with a clear message beats a silent
# `--no-verify` bypass. Un-inited repos keep their advisory posture (the
# target-aware init union needs the parser; session init is the signal here).
if ! node_guard guard-commit; then
  # POSIX-only fallback (the quote-aware parser needs node); it may use only what
  # a node-less PATH is assumed to have — grep + shell builtins, no sed/jq. Two
  # refinements over a whole-event grep (issue #70):
  #  1. Narrow the match surface to the tool_input.command VALUE, not the entire
  #     raw event (which also carries cwd / transcript_path) — so a bypass flag or
  #     "commit" sitting in a path/field, not the command, no longer trips it. If
  #     extraction finds nothing (format drift), fall back to the whole event, so
  #     a change can only WIDEN the surface, never blind the check (fail-safe).
  #  2. Engage the boundary when the SESSION repo is initialized OR the command
  #     targets an initialized repo via `cd <dir>`/`git -C <dir>` — without node
  #     the target parser is gone, so an un-inited scratch session cannot be a
  #     blanket bypass for an initialized sibling reached via cd/git -C. The dir
  #     scan is best-effort: an absolute target resolves reliably; a relative one
  #     is tested against the hook's CWD.
  fb_cmd="$(printf '%s' "$HOOK_INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' 2>/dev/null)"
  [ -n "$fb_cmd" ] || fb_cmd="$HOOK_INPUT"
  fb_engaged=no
  factory_initialized && fb_engaged=yes
  if [ "$fb_engaged" = no ]; then
    # Normalize JSON whitespace-escapes (\t \n \r) to spaces first, so a
    # tab-separated `git -C\t<dir>` — which valid JSON encodes as a literal
    # backslash-t the grep's [[:space:]] would never match — tokenizes like a
    # space-separated one. Then for each `cd …`/`git -C …` region test EVERY
    # argument token as a candidate dir: read -ra splits on any real whitespace
    # (space OR tab) without glob-expanding, and skipping the verb + `-…` flags
    # covers `cd -L`/`cd -P`/`cd --` and a real-tab separator alike, so the
    # target-init check can't be dodged by whitespace or flag choice (issue #70
    # follow-up). Best-effort: an absolute target resolves reliably; a relative
    # one is tested against the hook's CWD.
    fb_scan="$fb_cmd"
    fb_scan="${fb_scan//\\t/ }"; fb_scan="${fb_scan//\\n/ }"; fb_scan="${fb_scan//\\r/ }"
    while IFS= read -r fb_seg; do
      [ -n "$fb_seg" ] || continue
      read -ra fb_toks <<<"$fb_seg"
      for fb_d in "${fb_toks[@]}"; do
        case "$fb_d" in cd|-C|-*) continue ;; esac
        [ -f "$fb_d/.factory/config.json" ] && { fb_engaged=yes; break 2; }
      done
    done <<EOF
$(printf '%s' "$fb_scan" | grep -oE '(cd|-C)[[:space:]]+[^;&|)"]+' 2>/dev/null)
EOF
  fi
  if [ "$fb_engaged" = yes ]; then
    case "$fb_cmd" in
      *--no-verify*|*--no-gpg-sign*)
        case "$fb_cmd" in
          *commit*) deny "node is unavailable on the hook PATH, so the quote-aware commit parser cannot run — refusing a command that mentions both a commit and a bypass flag (--no-verify/--no-gpg-sign). Restore node or drop the flag." ;;
        esac ;;
    esac
  fi
  allow
fi

[ "$(field tool_name)" = "Bash" ] || allow
cmd="$(field tool_input.command)"
[ -n "$cmd" ] || allow

info="$(printf '%s' "$cmd" | node "$PLUGIN_ROOT/hooks/lib/parse-git-commit.mjs" 2>/dev/null)"
is_commit="$(printf '%s' "$info" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).isCommit))}catch(e){process.stdout.write("false")}})')"
[ "$is_commit" = "true" ] || allow

# The repo this commit actually targets (honors `cd <dir> &&`/`git -C <dir>`),
# so the green gate binds to it, not the fixed session project (issue #28).
target_root="$(repo_root "$(command_target_dir "$cmd")")"

# The factory is advisory only when NEITHER the session NOR the target repo is
# initialized. Enforcing on session-init keeps the established model (the session
# factory gates commits to any repo it touches, binding the receipt to the target
# tree — issue #28); ALSO enforcing on target-init means an un-inited scratch
# session cannot be used as a blanket bypass for an initialized sibling reached
# via `cd`/`git -C`. Both un-inited → step aside (no producer can mint a receipt).
if ! factory_initialized && [ ! -f "$target_root/.factory/config.json" ]; then
  otel_emit factory_gate_uninitialized_total sum 1 '{"hook":"guard-commit"}'
  allow
fi

# The governing config must be valid JSON, or a corrupt contract would silently
# revert this repo's gates to defaults (issue #65) — fail closed here.
require_config_sane "$target_root"

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
  # target-aware (issue #53): the TARGET repo's enforcement contract governs
  if enforcement_on_for "$target_root" conventionalCommitLint; then
    [ "$ok" = "false" ] && { otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"lint"}'; deny_soft "commit message is not a valid Conventional Commit (feat/fix/…): $message"; }
  fi
fi

# (c) tests-first for feat/fix
# target-aware (issue #53): a commit to sibling repo B is classified by B's
# regexes, not the session repo's (different stacks → different contracts).
src_re="$(config_get_for "$target_root" sourceRegex '^src/')"
test_re="$(config_get_for "$target_root" testRegex '(\.test\.|\.spec\.|_test\.|/tests?/|\.feature$)')"
if { [ "$ctype" = "feat" ] || [ "$ctype" = "fix" ]; } && enforcement_on_for "$target_root" requireTestsFirst; then
  files="$(staged_files "$target_root")"
  # `git commit -a/-am` stages tracked modifications AT commit time, so nothing
  # is staged yet at PreToolUse — evaluate the tracked changeset instead, or the
  # TDD check would be silently skipped. The -a flag comes from the quote-aware
  # parser (its `all` field), NOT a grep over the whole command: a message like
  # `-m "handle the -a flag"` must not be misread as `commit -a` (which would
  # evaluate the wrong changeset).
  all="$(printf '%s' "$info" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).all))}catch(e){process.stdout.write("false")}})')"
  if [ "$all" = "true" ]; then
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
if enforcement_on_for "$target_root" requireGreenReceiptOnCommit; then
  receipt="$(receipt_file "$target_root")"
  if [ ! -f "$receipt" ]; then
    otel_emit factory_gate_commit_total sum 1 '{"result":"deny","reason":"no-receipt"}'
    # A suite too slow for the hook budget is finishing out of band (issue #93);
    # say so, because "no receipt yet" and "the tests were red" call for very
    # different next actions — waiting versus fixing. Only for THIS repo's run
    # (the marker is keyed per target), and only while its lease holds: a marker
    # abandoned by a killed runner must not promise a suite that will never
    # finish.
    if [ -f "$(gate_marker "$target_root")" ] && ! gate_lease_expired "$(gate_lock "$target_root")"; then
      deny_soft "the gate run for this tree is still in flight — wait for the suite to finish (the receipt is minted when it exits), then commit"
    fi
    deny_soft "no green gate receipt — run the full test suite; it must pass on this exact tree before committing"
  fi
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
