# ADR 0002 — Dogfood the plugin from the working tree

Status: accepted · Date: 2026-07-11

## Context

This repository builds the `dark-software-factory` Claude Code plugin and
already dogfoods the plugin's *laws* (see CONTRIBUTING.md), but until now a
Claude Code session opened in this repo loaded the plugin from the **GitHub
release of this same repo** (`.claude/settings.json` declared the
`software-factory` marketplace with a `github` source). That meant a session
working on hook or command changes was governed by the *last published*
version of those hooks, not the code under edit — changes could not be
exercised before merging, and a session could be gated by stale enforcement.

## Decision

We will point the project-scoped marketplace at the repository's own working
tree: `.claude/settings.json` declares the `software-factory` marketplace with
a `directory` source and the relative path `"./"`. Claude Code resolves a
relative directory source against the repository checkout (and, from a git
worktree, against the main checkout), so the setting is portable across
clones, containers, and CI. The factory is initialized for this repo with a
committed `.factory/config.json` whose gates are the repo's real suites
(connector `node --test`, hooks contract tests).

Rejected alternatives:

- **Keep the `github` source** — sessions run last-release hooks against
  next-release code; the gap this ADR exists to close.
- **`--plugin-dir` at launch** — works for ad-hoc local testing but is not a
  checked-in, team-shared configuration; every session/CI invocation would
  need the flag re-supplied.

## Consequences

- A session in this repo runs the plugin code as edited — hook regressions
  surface immediately in the very session that introduces them.
- `.factory/config.json` is committed and becomes the enforcement contract
  for this repo; the runtime state under `.factory/` stays gitignored
  (including `.factory/active-agent`).
- An edit to a hook mid-session takes effect on the *next* session (plugins
  load at session start) — a known, accepted lag.
- A broken working-tree plugin can break its own enforcement in-session; CI
  (`validate.yml`) remains the authoritative boundary, unchanged by this ADR.
