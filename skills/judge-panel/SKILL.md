---
name: judge-panel
description: "Design-by-judge-panel (ADR-0009) for high-stakes or contested design decisions — draft N stance-committed partisan proposals, run an adversarial panel that names each one's single fatal flaw as a ballot, then synthesize one design that resolves every confirmed flaw and emit it as a numbered ADR. Use when a decision has real trade-offs, multiple defensible stances, or would otherwise be settled by a single author's bias."
---

# Judge Panel

Turn a contested design decision into a design that survives its own strongest critics.
Three partisan proposals collide, an adversarial panel names the fatal flaw in each, and you
synthesize one design that **resolves** every confirmed flaw instead of inheriting it.

## Invariants (never violate)

1. **Proposer != panelist.** The agent/persona that wrote a proposal MUST NOT judge it.
   Independence is the whole point — it is the enforcement value, not a nicety.
2. **Each proposal is deliberately partisan.** No proposal hedges or covers all bases; it
   commits to one stance and pays that stance's price openly.
3. **One fatal flaw per proposal.** Each panelist names the single most damaging flaw with
   evidence, not a laundry list. Rank by severity; report the one that kills it.
4. **Synthesis resolves, not averages.** The output is a new design that neutralizes every
   `CONFIRMED` flaw. Picking a "winner" and shipping its flaw is a failure.
5. **State lives on disk.** Proposals in `.factory/panel/`, ballots alongside, decision as a
   numbered ADR. Nothing load-bearing stays only in conversation.

## Procedure

### Step 1 — Draft N stance-committed proposals (default N=3)

Pick N attack axes / stances that genuinely pull against each other for THIS decision, e.g.
`contract-first`, `security-first`, `dx-first` (or `simplicity` / `performance` / `extensibility`).
Write one file per stance to `.factory/panel/proposal-<stance>.json` using the template below.
Each is authored as a true believer in that stance.

### Step 2 — Run the adversarial panel (one reviewer per axis)

Spawn N independent panelists, none of which authored the proposal it reviews. Each panelist
attacks from its own axis and returns a **ballot** naming the single fatal flaw with evidence
and a `CONFIRMED | PLAUSIBLE` verdict. Every proposal gets a ballot from every other axis.
Write ballots to `.factory/panel/ballot-<axis>.json`. `CONFIRMED` = the reviewer
demonstrated the failure (repro, citation, counterexample); `PLAUSIBLE` = argued but unproven.

### Step 3 — Synthesize the resolving ADR

Collect every `CONFIRMED` flaw (treat `PLAUSIBLE` as a risk to address or explicitly wave off).
Design ONE approach that resolves all of them. Emit a numbered ADR
(`Status / Context / Decision / Consequences / Date`) with an explicit **Flaws resolved** table.
Any flaw you cannot resolve is a named, accepted Consequence — never a silent inheritance.

## Templates

### Proposal (`.factory/panel/proposal-<stance>.json`)

```markdown
# Proposal: <stance> (e.g. contract-first)
Stance: <the one principle this proposal maximizes>
Decision: <the concrete design this stance leads to>
Why this wins: <the case, argued as a partisan>
Price paid: <what this stance knowingly sacrifices — be honest>
Key mechanics: <APIs / boundaries / data flow that make it real>
```

### Ballot (`.factory/panel/ballot-<axis>.json`)

```markdown
# Ballot — reviewer:<axis> vs proposal:<stance>
Fatal flaw: <the single most damaging flaw>
Evidence: <repro / citation / counterexample — not an opinion>
Verdict: CONFIRMED | PLAUSIBLE
Blast radius: <what breaks and who it hurts if unfixed>
Cheapest fix direction: <hint for the synthesizer, optional>
```

### Synthesis ADR (numbered, e.g. `docs/adr/0042-<slug>.md`)

```markdown
# ADR-0042: <decision title>
Status: Accepted
Context: <the decision, the N stances, why a panel was warranted>
Decision: <the synthesized design>

## Flaws resolved
| Proposal | Confirmed flaw | How the synthesis resolves it |
|----------|----------------|-------------------------------|
| contract-first | <flaw> | <mechanism that neutralizes it> |
| security-first | <flaw> | <mechanism that neutralizes it> |
| dx-first | <flaw> | <mechanism that neutralizes it> |

Consequences: <new trade-offs, incl. any PLAUSIBLE risk knowingly accepted>
Date: <YYYY-MM-DD>
```

## Synthesis checklist (gate before writing Status: Accepted)

- [ ] Every proposal has a ballot from every OTHER axis (proposer never judged own work).
- [ ] Each ballot names exactly ONE fatal flaw with evidence and a CONFIRMED|PLAUSIBLE verdict.
- [ ] Every `CONFIRMED` flaw appears as a row in the **Flaws resolved** table.
- [ ] Each row shows a mechanism that RESOLVES the flaw — not "we chose the other proposal".
- [ ] No confirmed flaw silently inherited; unresolved ones are explicit Consequences.
- [ ] `PLAUSIBLE` flaws are either resolved, mitigated, or waved off with a stated reason.
- [ ] Decision emitted as a NUMBERED ADR (`adr_index` sees it); proposals + ballots retained
      in `.factory/panel/` for provenance.

## When to reach for this

Use the panel when the decision has real trade-offs, several defensible stances, cross-cutting
cost (security × DX × contracts), or would otherwise be decided by one author's taste. For a
low-stakes or single-obvious-answer choice, a plain ADR is enough — don't over-ceremony it.
