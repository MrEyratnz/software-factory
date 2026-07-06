---
description: Settle a contested decision by the ADR-0009 method — 3 stance-pinned proposals, a 3-judge adversarial panel that names each fatal flaw, then a synthesized ADR that resolves every flaw.
argument-hint: "<hard decision to settle> [--stances a,b,c]"
---

Settle this by judge panel: `$ARGUMENTS`

Run the ADR-0009 method (load `judge-panel`):

1. **Propose (parallel).** Launch 3 **proposer** subagents, each pinned to a
   distinct stance (default `contract-first`, `security-first`, `dx-first`; or
   the `--stances` given). Each writes one deliberately partisan proposal to
   `.factory/panel/<stance>.json`. They do not read each other's files.
2. **Judge (parallel).** Launch 3 **panelist** subagents on distinct attack axes.
   Each reads all proposals and returns a ballot naming each proposal's single
   fatal flaw with a CONFIRMED/PLAUSIBLE verdict.
3. **Synthesize.** Dispatch the **architect** to write a numbered ADR that takes
   the best spine from each proposal and **resolves every panel-confirmed fatal
   flaw** — with an explicit "flaws resolved" table — rather than inheriting any.

Handoffs go through the `.factory/panel/` files and the ballots, not this
conversation. `validate-handoff` blocks any proposer/panelist that fails to emit
a schema-valid artifact.
