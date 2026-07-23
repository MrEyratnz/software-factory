#!/usr/bin/env bash
# guard-scope — path-level least-privilege the tool frontmatter can't express.
# Blocks a Write/Edit/MultiEdit outside the active agent's allowlist, and denies
# ALL editor-tool writes to the factory's trust roots (.factory/state/**,
# .factory/config.json). NOTE: this covers only the Write/Edit/MultiEdit tools;
# the Bash write path to those roots is denied by the companion
# guard-bash-writes hook. Neither is airtight against a determined agent — which
# is precisely why CI, not any local hook, is the authoritative boundary.
. "$(dirname "$0")/../lib/common.sh"

respect_pause guard-scope
# issue #52: degrade LOUDLY (never silently) when node is unavailable.
node_guard guard-scope || allow
case "$(field tool_name)" in Write|Edit|MultiEdit) ;; *) allow ;; esac
fp="$(field tool_input.file_path)"
[ -n "$fp" ] || allow

# Resolve BOTH rel and abs against the canonical (realpath) project root and
# canonicalize the target's own path, so a symlink inside the project that points
# into a trust root (e.g. `ln -s .factory/state sneak` then Write sneak/receipt)
# cannot smuggle a write past the lexical trust-root match (issue #58). The
# target file itself may be new, so we realpath the deepest existing ancestor.
_scope="$(FP="$fp" PD="$PROJECT_DIR" node -e '
  const p=require("path"),fs=require("fs");
  const FP=process.env.FP,PD=process.env.PD;
  // Canonicalize as far as the path EXISTS, then re-append the not-yet-created
  // tail — walking up to the deepest existing ancestor (not just the immediate
  // parent), so a new file in a not-yet-created nested dir under a SYMLINKED
  // project root still canonicalizes correctly instead of being mis-judged
  // out-of-tree (issue #58 follow-up).
  const canon=(a)=>{
    try{return fs.realpathSync(a)}catch(e){}
    const tail=[]; let cur=a;
    for(let i=0;i<64;i++){ const par=p.dirname(cur); if(par===cur) break; tail.unshift(p.basename(cur)); cur=par; try{return p.join(fs.realpathSync(cur),...tail)}catch(e){} }
    return a;
  };
  const abs=canon(p.isAbsolute(FP)?p.resolve(FP):p.resolve(PD,FP));
  let root=PD;try{root=fs.realpathSync(PD)}catch(e){root=p.resolve(PD)}
  process.stdout.write(JSON.stringify({rel:p.relative(root,abs),abs}));
')"
rel="$(printf '%s' "$_scope" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).rel)}catch(e){}})')"
abs="$(printf '%s' "$_scope" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{process.stdout.write(JSON.parse(s).abs)}catch(e){}})')"

# Writing outside the project tree is never allowed (unless the scope gate is
# relaxed for this repo via enforcement.enforceProjectDirScope) — except for
# first-party carve-outs so factory adoption doesn't silently break Claude
# Code's own features (issue #31): ~/.claude (incl. the memory feature),
# temp dirs, and /dev.
if enforcement_on enforceProjectDirScope; then
  case "$rel" in
    ../*|/*)
      # ${HOME:-} not $HOME: under `set -u` an unset HOME would abort the hook
      # (exit 1), which Claude Code treats as a non-blocking error — a hard
      # boundary must never fail OPEN. With HOME unset the carve-out simply
      # doesn't match and the write is denied (fail closed).
      case "$abs" in
        "${HOME:-/dev/null/nohome}/.claude/"*|/tmp/*|/private/tmp/*|/var/folders/*|/dev/*) allow ;;
        *) deny "write outside the project directory is not allowed: $rel" ;;
      esac ;;
  esac
fi

active="$(cat "$FACTORY_DIR/active-agent" 2>/dev/null | tr -d '[:space:]')"
design_dir="$(config_get designDir 'design/')"

# Universal protection of the factory's own trust roots (any agent, including
# the conductor). The hooks that legitimately update these use shell I/O, not
# the Write/Edit tool, so this is safe to enforce for all — with ONE sanctioned
# carve-out: the release-captain writes .factory/state/release-intent.json to
# signal a release is in progress (issue #14). That is the intent flag's
# sanctioned producer; release-proof.json is minted by the record-release-proof
# hook, never hand-written, and every other trust-root path stays unwritable.
if enforcement_on protectTrustRoots; then
  case "$rel" in
    .factory/state/release-intent.json)
      [ "$active" = "release-captain" ] || deny "release-intent.json is written only by the release-captain (via /ship)" ;;
    .factory/config.json)
      # First-run creation is the sanctioned /factory-init step; once the config
      # exists it is protected (edit + commit it as source, not via a live
      # gate bypass). Without this carve-out, /factory-init could never stamp the
      # config it is documented to create (issues #1, #54).
      [ -f "$CONFIG_FILE" ] && deny "$rel already exists and is the committed enforcement contract — edit it in a normal commit, not as a live gate change" ;;
    .factory/state/*)
      deny "$rel is factory-managed state — it may not be written via the editor tools" ;;
    # A NESTED or SIBLING repo's enforcement contract / hook state (issue #53).
    # config_get_for / enforcement_on_for now read a TARGET repo's
    # .factory/config.json (and record-green pipes its testCommand to `sh -c`),
    # so a sub-repo's contract must be as unwritable as the session's own — else
    # an agent plants an opt-out or a malicious testCommand one directory over
    # and defeats every target-aware gate. These patterns match only a path with
    # a segment BEFORE .factory (a different repo); the session's own depth-0
    # .factory/… is handled by the cases above, so its carve-outs are unaffected.
    */.factory/config.json)
      deny "$rel is a target repo's enforcement contract — a sub-repo's .factory/config.json is not writable via the editor tools (issue #53)" ;;
    */.factory/state|*/.factory/state/*)
      deny "$rel is a target repo's factory-managed state — not writable via the editor tools (issue #53)" ;;
  esac
fi

case "$active" in
  reviewer)
    # Read-only w.r.t. SOURCE, but it must be able to emit its findings artifact
    # — validate-handoff blocks the reviewer's stop until that file exists, and
    # it has no other sanctioned way to produce it (its Bash writes are fenced).
    # So: allow ONLY .factory/review/*.json (mirrors the panelist's .factory/panel
    # carve-out); every other path, including source, stays denied.
    case "$rel" in .factory/review/*) allow ;; *) deny "the reviewer writes only its findings under .factory/review/ (no source edits — attempted: $rel)" ;; esac ;;
  panelist)
    # The panelist writes exactly one ballot artifact; nothing else.
    case "$rel" in .factory/panel/*) allow ;; *) deny "a panelist writes only its ballot under .factory/panel/ (attempted: $rel)" ;; esac ;;
  architect)
    case "$rel" in docs/*) allow ;; *) deny "the architect writes only under docs/ (attempted: $rel)" ;; esac ;;
  proposer)
    case "$rel" in .factory/panel/*) allow ;; *) deny "a proposer writes only under .factory/panel/ (attempted: $rel)" ;; esac ;;
  design-lead)
    case "$rel" in "$design_dir"*|docs/*) allow ;; *) deny "the design-lead writes only under the design dirs (attempted: $rel)" ;; esac ;;
  release-captain)
    case "$rel" in docs/*|.factory/state/release-intent.json) allow ;; *) deny "the release-captain does not edit source (high blast radius) — it cuts releases via the gated release path (attempted: $rel)" ;; esac ;;
  tech-debt-clerk)
    case "$rel" in .factory/review/*) allow ;; *) deny "the tech-debt clerk touches no source — it files issues; findings/status go under .factory/review/ (attempted: $rel)" ;; esac ;;
  implementer|"")
    # implementer + conductor: source/tests are fine; the universal .factory
    # guard above already blocks the dangerous paths.
    allow ;;
  *)
    allow ;;
esac
