---
description: Run the 3-lens adversarial review panel over a diff or PR, write verified findings, and reconcile them — fixed-in-diff vs filed as tech-debt.
argument-hint: "[pr-number | --staged | --range main..HEAD]"
---

Adversarially review: `$ARGUMENTS` (default `--staged`).

1. Record the active worker: `echo reviewer > .factory/active-agent`.
2. Launch 3 **reviewer** subagents in parallel, one per axis —
   correctness+security, architecture+boundaries, product+a11y-gate. Each is
   read-only and writes ranked, verified findings (location `file:line`, impact,
   provenance, suggestedFix, severity, CONFIRMED|PLAUSIBLE, status) to
   `.factory/review/<ref>.json`. `validate-handoff` blocks any reviewer that
   emits no schema-valid findings.
3. Reconcile every finding: either **fix it in the diff** (then mark it
   `status:"fixed"`) or **file it as tech-debt** — dispatch the
   **tech-debt-clerk**, which files each missing finding idempotently (by
   fingerprint) as a `tech-debt` GitHub issue with location/impact/provenance/
   suggested-fix.

The `debt-reconcile` Stop hook will block the session from ending while any
finding is neither fixed nor filed — so nothing is ever silently dropped, even
outside `/factory-run`. Load `adversarial-review`.
