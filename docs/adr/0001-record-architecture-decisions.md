# ADR 0001 — Record architecture decisions

Status: accepted · Date: 2026-07-23

## Context

We are building autonomously, over many sessions, with the durable record of a
decision living in the repository rather than in any one conversation. Decisions
that are only remembered are decisions that get silently reversed.

## Decision

Every significant architecture decision is captured as a numbered Architecture
Decision Record under `docs/adr/NNNN-<slug>.md`, in this exact shape:

- `# ADR NNNN — <title>`
- `Status: <proposed|accepted|superseded by ADR MMMM> · Date: <YYYY-MM-DD>`
- `## Context` — the forces and constraints
- `## Decision` — what we chose
- `## Consequences` — what follows, good and bad

Numbers are monotonic and never reused (the connector's `adr_index` computes the
next one). A contested decision is settled by `/judge-panel` — three stance
proposals, an adversarial panel, and a synthesis ADR that resolves every
confirmed flaw.

## Consequences

- The architecture is legible to any new session by reading `docs/adr/` top to
  bottom.
- Superseding a decision means a new ADR, not editing history.
