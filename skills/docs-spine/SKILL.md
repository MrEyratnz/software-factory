---
name: docs-spine
description: "Author and maintain the docs spine (VISION.md, ARCHITECTURE.md, numbered ADRs, ROADMAP.md) with exact templates, monotonic ADR numbering via the connector, and merged-green roadmap checkbox discipline. Use when starting a repo, recording a decision, adding a milestone, or checking off a roadmap item."
---

# docs-spine

The docs spine is the durable, human-and-agent-readable memory of the project: **why** (VISION),
**how it is shaped** (ARCHITECTURE), **what we decided and why** (ADRs), and **what is left**
(ROADMAP). These four files live at the repo root (ADRs under `docs/adr/`) and are the source of
truth agents read before acting. Runtime verdicts come from the connector — do not eyeball.

## Invariants (never violate)

1. **The four files always exist**: `VISION.md`, `ARCHITECTURE.md`, `docs/adr/NNNN-*.md`, `ROADMAP.md`.
2. **ADR numbers are monotonic and connector-assigned.** Call `adr_index` for the next number.
   Never hand-pick — concurrent agents will collide.
3. **ADRs are append-only.** To reverse a decision, write a NEW ADR that supersedes the old one and
   set the old one's `Status:` to `Superseded by ADR NNNN`. Never rewrite decided history.
4. **Roadmap items are checked `[x]` ONLY when merged with green tests** — never in advance, never
   "about to". The flip is enforced by `guard-roadmap`, which demands a merged-green proof.
5. **Work the roadmap top-to-bottom.** `roadmap_next` names the next item; `roadmap_status` /
   `roadmap_check` are the authority on state — not your reading of the file.

## ADR procedure

1. `adr_index` → get the next number `NNNN` (zero-padded, e.g. `0009`) and confirm no collision.
2. Create `docs/adr/NNNN-kebab-title.md` from the template below.
3. Start at `Status: Proposed`; flip to `Accepted` when the decision is merged.
4. If it changes system shape, reflect the outcome in `ARCHITECTURE.md` in the same PR.
5. For contested design, use the judge-panel method (ADR-0009): 3 stance proposals → adversarial
   panel names each fatal flaw → synthesize a decision that resolves every named flaw, recorded here.

### ADR template (exact headings)

```markdown
# ADR NNNN — <concise decision title>

Status: Proposed | Accepted | Superseded by ADR NNNN

## Context

<The forces at play: the problem, constraints, and what made a decision necessary.
State facts, not the choice.>

## Decision

<The choice, in active voice: "We will …". Include what was explicitly rejected.>

## Consequences

<What becomes easier and harder. New obligations, follow-up ADRs, tech-debt created.
Name the trade-off you accepted.>

Date: YYYY-MM-DD
```

## ROADMAP procedure

- Structure as ordered milestones `M0..Mn`, each a heading with `- [ ]` checkbox items.
- Order items by dependency; the agent takes the **first unchecked** item (`roadmap_next`).
- Check `[x]` only after the item's PR is **merged green**. Add the proof link inline so the
  `guard-roadmap` receipt is auditable.
- Never add "future" checked items; never batch-check. One item, one merged-green flip.

### ROADMAP.md skeleton

```markdown
# Roadmap

Worked top-to-bottom. An item flips to [x] only when merged with green tests (guard-roadmap).

## M0 — Foundations
- [x] Scaffold modular monorepo + CI gates  (merged: #12)
- [ ] Design tokens single-source + drift gate

## M1 — Core domain
- [ ] Kernel domain model + contract-test-suite-per-port
- [ ] First adapter behind a port

## M2 — Delivery
- [ ] release-please wired (Conventional Commits)
- [ ] Smoke-test the built artifact in CI
```

## VISION.md skeleton

```markdown
# Vision

## Problem
<Who hurts and how, today.>

## Outcome
<The changed world when this works. One paragraph.>

## Principles
- <Non-negotiable that decides ties, e.g. "autonomy over convenience">

## Non-goals
- <Explicitly out of scope, so agents don't drift into it.>
```

## ARCHITECTURE.md skeleton

```markdown
# Architecture

## Shape
Modular monolith: kernel < modules < app. Ports/adapters; dependency direction enforced by
dependency-cruiser. Contract-test-suite per port.

## Modules
| Module | Responsibility | Depends on |
|--------|----------------|------------|
| kernel | pure domain    | —          |
| <mod>  | <capability>   | kernel     |
| app    | composition    | modules    |

## Cross-cutting
- Testing: typecheck → module-boundary → unit → BDD → build → generated-artifact drift.
- Decisions of record: see `docs/adr/`. This file reflects their outcomes, never overrides them.
```

## Definition of done

- [ ] Next ADR number came from `adr_index`, not a guess.
- [ ] ADR has all headings (Status/Context/Decision/Consequences) and a Date.
- [ ] ARCHITECTURE reflects any shape change from the ADR (same PR).
- [ ] Every `[x]` in ROADMAP has a merged-green proof (`guard-roadmap` passes).
