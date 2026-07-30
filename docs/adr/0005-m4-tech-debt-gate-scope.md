# ADR 0005 — Scope the v1.0.0 tech-debt gate: fail-closed on triage, security outranks priority

Status: accepted · Date: 2026-07-30

## Context

The v1.0.0 Release Gate (M4) reads literally "zero open `bug`/`tech-debt`
issues at any priority, no judgment calls" — stated in three places:
`docs/specs/epic-1/spec.md` (the definition `docs/ROADMAP.md`'s preamble and
`.claude/CLAUDE.md` pin the gate to), `docs/ROADMAP.md` M4, and, since PR
#444, a fourth *divergent* definition in `docs/PRODUCT.md`.

Ground truth (2026-07-29, fully-paginated `gh api graphql` — recorded in
`docs/PRODUCT.md`): **273 open `tech-debt` issues** (P0: 3, P1: 15, P2: 44,
P3: 23, **188 with no `P0`–`P3` label**, of which 147 carry no priority signal
of any kind), 10 of them `security`-labeled across all P-levels, plus 9 open
`bug`. The "30 open tech-debt" figure circulating in factory status output is
`gh issue list`'s default 30-item page leaking from two call sites that never
pass `--limit` (`hooks/scripts/debt-reconcile.sh:18`,
`hooks/lib/common.sh:582` — filed as #419/#420, both P0). A literal-zero gate
over 273 issues can only ever be "satisfied" by mass-closing issues unfixed or
by that counting bug quietly under-reporting — both worse than a scoped,
honest gate.

PR #444 (product owner) redefined the criterion, but only in
`docs/PRODUCT.md`, and the adversarial review returned REQUEST CHANGES with
confirmed findings #463–#470: contradicting definitions, an ownership-lane
violation, a missing ADR, a fail-open predicate over the 188 unlabeled issues,
undefined legacy-label semantics, and an unnamed deferral target. Per
`GOVERNANCE.md`, milestone scope is the product owner's call; the gate/spec
wording is architect-owned; a decision of this kind requires a numbered ADR
with a named owner.

## Decision

We will hold v1.0.0 to a **scoped, fail-closed, decidable** tech-debt gate,
defined **once** in `docs/specs/epic-1/spec.md` ("Release Gate for v1.0.0").
`docs/ROADMAP.md` M4 mirrors it by reference; `docs/PRODUCT.md` carries the
product rationale and points at the spec instead of restating a second
predicate. The criterion:

1. **Zero open `bug` issues** — literal, unwaived (a bug is fixed, never
   deferred, even under freeze).
2. **Zero open `tech-debt` issues labeled `P0` or `P1`.**
3. **Zero open `tech-debt` issues labeled `security`, at any `P0`–`P3`
   level.** This cross-priority precedence is **this ADR's own decision**:
   `docs/PRODUCT.md` ranking rule 1 is, as written, only an equal-priority
   tie-breaker — this ADR deliberately extends it across priority levels for
   release gating, because the ground truth shows `security` does not
   correlate with P-level.
4. **Zero open `tech-debt` issues lacking a valid `P0`–`P3` label**
   (fail-closed): an untriaged issue **blocks the gate** until it carries one
   of `P0`–`P3`. All gate label criteria match **exact, case-sensitive label
   names as they exist in the repo label set** (`P0`, `P1`, `P2`, `P3`,
   `security`, `bug`, `tech-debt`). Legacy `priority:*`/`high`/`medium`/`low`
   labels do **not** count as triage — an issue carrying only those blocks
   like an unlabeled one. If an issue carries more than one `P0`–`P3` label,
   the most severe governs. The triage pass that clears this criterion is
   tracked as #510 and as an explicit ROADMAP M4 item.
5. **Non-security `P2`/`P3` tech-debt does not block v1.0.0.** Its deferral
   home is the named ROADMAP **M5 (v1.1.0) item "P2/P3 tech-debt burndown
   (non-security)"** — deliberately distinct from M3's security-hardening
   pass, which is security-scoped and v1.0.0-scoped and therefore cannot
   absorb non-blocking deferrals without contradicting itself.

Prerequisite: **#419/#420 (the pagination counting bug) must be fixed and
re-verified before any automation trusts this gate** — the M4 "Release Gate
script" must count via fully-paginated queries, never a bare `gh issue list`.

Explicitly rejected: the literal zero (unachievable except via mass-closing or
the counting bug); treating unlabeled tech-debt as deferrable (fail-open — an
untriaged P0 or security issue would slide through); and using M3's
security-hardening pass as the P2/P3 dumping ground (scope contradiction).

### Review findings resolved

| Finding | Resolution |
|---|---|
| #463 three contradicting gate definitions | Single authoritative predicate in `docs/specs/epic-1/spec.md`; ROADMAP M4 and PRODUCT.md reference it |
| #464 ownership-lane violation | Scope decided by product owner (PR #444), gate wording landed in the architect-owned spec via this ADR |
| #465 PRODUCT.md self-contradiction (sweep-before-ship vs. does-not-block) | The sprint-1 P2 sweep claim is corrected to cite this gate; PRODUCT.md restates no predicate |
| #466 missing numbered ADR | This ADR; owner named below |
| #467 fail-open on 188 unlabeled issues | Criterion 4: unlabeled blocks, full stop, until triaged; triage pass tracked as #510 |
| #470 legacy-label semantics undefined | Criterion 4: legacy labels are not valid triage; exact-form case-sensitive `P0`–`P3` only; multi-label → most severe governs |
| #468 deferral target unnamed | Criterion 5: the named M5 "P2/P3 tech-debt burndown (non-security)" item |
| #469 ground-truth counts embedded as durable facts | Every count in this ADR and `docs/PRODUCT.md` is an explicitly dated 2026-07-29 snapshot, not a live value; the stale 221/6 freeze figures in `docs/PRODUCT.md` are corrected and date-stamped |

## Consequences

- **Decision owner: product-owner** (milestone scope / feature freeze per
  `GOVERNANCE.md`); the architect owns the spec text that expresses it. Any
  future change to the gate predicate is a new ADR, not an edit to a
  restatement.
- The gate stays decidable with no judgment calls: every criterion is a label
  query over open issues. Fail-closed on triage converts "triage the 188
  unlabeled issues" from a side condition into a structural property — the
  gate *cannot* pass while any tech-debt issue is untriaged, so nothing hides
  in the pile.
- New obligation: the triage pass over the 188 unlabeled (147 with zero
  signal) issues is now release-blocking work with a tracked home (#510 +
  a ROADMAP M4 item), and the M5 burndown item is a standing commitment —
  deferred P2/P3 debt is tracked scope, not amnesty.
- The M4 Release Gate script inherits hard requirements: fully-paginated
  counting (blocked on #419/#420), exact-form case-sensitive label matching,
  legacy-label rejection, and concrete eval-threshold values (owner: qa,
  tracked as #511) before the nightly-runs criterion is evaluable.
- Trade-off accepted: v1.0.0 can ship with known non-security P2/P3 debt
  open. That is honest and bounded (44 + 23 today, plus whatever triage
  reclassifies), versus a literal-zero gate that invites mass-closing or
  silent miscounting.
- `docs/PRODUCT.md`'s sprint-1 note that M4 "already guarantees they get
  swept before ship" is corrected in the same PR — under this gate, only
  `security`-labeled members of that P2 batch block v1.0.0.
