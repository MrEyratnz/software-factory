---
description: Create the next sequentially-numbered ADR in house format (Status/Context/Decision/Consequences/Date) for a settled decision, and link it from ARCHITECTURE.md.
argument-hint: "<decision title>"
---

Record the decision: `$ARGUMENTS`

Set the write-fence (`echo architect > .factory/active-agent`), then dispatch
the **architect** (load `docs-spine`). Get the next ADR number from the
connector (`adr_index`) — never hand-pick it; `adr_index` scans the repo's
configured `adrDir` (default `docs/adr`), so numbering honors a non-default ADR
location. Write `<adrDir>/NNNN-<slug>.md` (default `docs/adr/…`) in the exact
house shape: `# ADR NNNN — <title>`, then `Status: accepted · Date: <today>`,
then `## Context`, `## Decision`, `## Consequences`. Link it from
`docs/ARCHITECTURE.md`.

Use this for a decision that is already settled. If the decision is *contested*
and needs to be argued out, use `/judge-panel` instead — that produces an ADR
by adversarial synthesis.
