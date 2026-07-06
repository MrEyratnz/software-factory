---
description: Pick the next unchecked roadmap item, TDD-implement it red→green→refactor keeping the full suite green, and open a PR — the atomic unit of the autonomous loop.
argument-hint: "[item-id] [--dry-run]"
---

Advance the line by one item: `$ARGUMENTS`

1. Determine the item: the connector `roadmap_next` unless one is named.
2. Record the active worker: `echo implementer > .factory/active-agent`.
3. Dispatch the **implementer** (load `tdd-green-gate`, `module-boundaries`,
   `conventional-release`) to: write the failing test first, add the minimal
   implementation, keep the gate green (typecheck → boundaries → unit → BDD →
   build → drift), and produce exactly one Conventional Commit. `guard-commit`
   enforces tests-first + a tree-bound green receipt + a conventional message.
4. Open a PR for the item. Do **not** check the roadmap box here — it flips only
   on merge with green tests (via a merged-green proof), enforced by
   `guard-roadmap`.

`--dry-run`: report the item and the plan; make no changes.
