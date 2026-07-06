#!/usr/bin/env bash
# guard-scope — path-level least-privilege the tool frontmatter can't express.
# Blocks a Write/Edit outside the active agent's allowlist. This single hook
# closes BOTH the receipt-forgery vector and the poison-the-config (ACE) vector:
# .factory/state/ and .factory/config.json are write-protected for everyone,
# so the policed agent can neither forge its own green receipt nor rewrite the
# commands the gates run.
. "$(dirname "$0")/../lib/common.sh"

case "$(field tool_name)" in Write|Edit|MultiEdit) ;; *) allow ;; esac
fp="$(field tool_input.file_path)"
[ -n "$fp" ] || allow

rel="$(FP="$fp" PD="$PROJECT_DIR" node -e '
  const p=require("path");
  const abs=p.isAbsolute(process.env.FP)?process.env.FP:p.resolve(process.env.PD,process.env.FP);
  process.stdout.write(p.relative(process.env.PD, abs));
')"

# Writing outside the project tree is never allowed.
case "$rel" in
  ../*|/*) deny "write outside the project directory is not allowed: $rel" ;;
esac

# Universal protection of the factory's own trust roots (any agent, including
# the conductor). The hooks that legitimately update these use shell I/O, not
# the Write/Edit tool, so this is safe to enforce for all.
case "$rel" in
  .factory/state/*|.factory/config.json)
    deny "$rel is factory-managed state — it may not be written via the editor tools" ;;
esac

active="$(cat "$FACTORY_DIR/active-agent" 2>/dev/null | tr -d '[:space:]')"
design_dir="$(config_get designDir 'design/')"

case "$active" in
  reviewer|panelist)
    deny "the $active agent is read-only by construction — it may not write files (findings go to its return artifact)" ;;
  architect)
    case "$rel" in docs/*) allow ;; *) deny "the architect writes only under docs/ (attempted: $rel)" ;; esac ;;
  proposer)
    case "$rel" in .factory/panel/*) allow ;; *) deny "a proposer writes only under .factory/panel/ (attempted: $rel)" ;; esac ;;
  design-lead)
    case "$rel" in "$design_dir"*|docs/*) allow ;; *) deny "the design-lead writes only under the design dirs (attempted: $rel)" ;; esac ;;
  implementer|"")
    # implementer + conductor: source/tests are fine; the universal .factory
    # guard above already blocks the dangerous paths.
    allow ;;
  *)
    allow ;;
esac
