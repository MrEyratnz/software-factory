---
description: List, sync, or close the tech-debt ledger — reconcile review findings against open GitHub tech-debt issues, idempotently by fingerprint.
argument-hint: "list | sync | close <id>"
---

Manage tracked tech-debt: `$ARGUMENTS`

- **list**: show open GitHub issues labeled `tech-debt`, plus any unreconciled
  findings in `.factory/review/*.json`.
- **sync**: set `echo tech-debt-clerk > .factory/active-agent` and dispatch the
  **tech-debt-clerk** to reconcile — the connector
  `techdebt_audit` diffs this session's findings against the open `tech-debt`
  issues by content fingerprint, and the clerk files each missing one (with
  location/impact/provenance/suggested-fix) without ever double-filing.
- **close <id>**: close the issue (the underlying debt is resolved) and mark the
  matching finding `status:"fixed"`.

This is the manual companion to the automatic filing inside `/review`; both run
through the same fingerprint audit, so re-runs never duplicate.
