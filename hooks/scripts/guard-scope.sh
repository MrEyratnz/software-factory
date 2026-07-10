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
case "$(field tool_name)" in Write|Edit|MultiEdit) ;; *) allow ;; esac
fp="$(field tool_input.file_path)"
[ -n "$fp" ] || allow

rel="$(FP="$fp" PD="$PROJECT_DIR" node -e '
  const p=require("path");
  const abs=p.isAbsolute(process.env.FP)?process.env.FP:p.resolve(process.env.PD,process.env.FP);
  process.stdout.write(p.relative(process.env.PD, abs));
')"
abs="$(FP="$fp" PD="$PROJECT_DIR" node -e '
  const p=require("path");
  process.stdout.write(p.isAbsolute(process.env.FP)?p.resolve(process.env.FP):p.resolve(process.env.PD,process.env.FP));
')"

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
    .factory/state/*|.factory/config.json)
      deny "$rel is factory-managed state — it may not be written via the editor tools" ;;
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
