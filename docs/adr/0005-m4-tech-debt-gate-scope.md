# ADR 0005 — Scope the v1.0.0 tech-debt gate: fail-closed on triage, security outranks priority

Status: accepted · Date: 2026-07-30

## Context

The v1.0.0 Release Gate (M4) reads literally "zero open `bug`/`tech-debt`
issues at any priority, no judgment calls" — stated in three places:
`docs/specs/epic-1/spec.md` (the definition `docs/ROADMAP.md`'s preamble and
`.claude/CLAUDE.md` pin the gate to), `docs/ROADMAP.md` M4, and, since PR
#444's first draft, a third *divergent* definition in `docs/PRODUCT.md`.

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
predicate. **The normative predicate is not restated here either** — by this
ADR's own rule there is exactly one maintainable copy, in the spec section
above; if any summary in this ADR and the spec ever diverge, the spec
governs. What this ADR decides is the *scope change* the spec now expresses:

- literal-zero tech-debt is replaced by severity-scoped criteria over
  exact-form, case-sensitive labels (fail-closed on untriaged issues —
  triage tracked as #510 and as an explicit ROADMAP M4 item);
- **security blocks at any `P0`–`P3` level** — this cross-priority
  precedence is **this ADR's own decision**: `docs/PRODUCT.md` ranking
  rule 1 is, as written, only an equal-priority tie-breaker, and this ADR
  deliberately extends it across priority levels for release gating,
  because the ground truth shows `security` does not correlate with
  P-level;
- non-security `P2`/`P3` tech-debt no longer blocks v1.0.0 and defers to
  the named ROADMAP **M5 (v1.1.0) item "P2/P3 tech-debt burndown
  (non-security)"** — deliberately distinct from M3's security-hardening
  pass, which is security-scoped and v1.0.0-scoped and therefore cannot
  absorb non-blocking deferrals without contradicting itself;
- `bug` stays literal zero, unwaived;
- the authorship of this and any future gate-scope change follows the
  **joint-lane rule recorded in `GOVERNANCE.md` § "Decision owners"**: the
  product owner authors the `docs/PRODUCT.md` rationale, the architect
  authors the spec/ARCHITECTURE/ADR wording, and a fenced agent's charter
  is never widened by that agent's own edit to its file;
- the ≥95% coverage floor **widens to include `hooks/lib/common.sh`** —
  recorded here because a gate-threshold scope change needs an ADR row:
  the gate's own paginated counting lives in that library, and an
  untested counting path is the #419/#420 class recurring. qa owns the
  threshold going forward (its charter mirrors this scope and defers to
  the spec on drift).

Prerequisite: the canonical set is the spec's CLOSED-state criterion
(**#419, #420, #510, #511, #649** — the spec governs on drift); notably
**#419/#420 (the pagination counting bug) and #649 (the
anti-laundering backfill audit) must be fixed and
re-verified before any automation trusts this gate** — the M4 "Release Gate
script" must count via fully-paginated queries, never a bare `gh issue list`.

Explicitly rejected: the literal zero (unachievable except via mass-closing or
the counting bug); treating unlabeled tech-debt as deferrable (fail-open — an
untriaged P0 or security issue would slide through); and using M3's
security-hardening pass as the P2/P3 dumping ground (scope contradiction).

### Review findings resolved

Rows below record what THIS PR's diff resolves; the tracked issues
**close on this PR's merge** via its `Closes #N` links with fingerprint
citations in the merge evidence — they are open until then, and this
table does not claim otherwise.

| Finding | Resolution |
|---|---|
| #463 three contradicting gate definitions | Single authoritative predicate in `docs/specs/epic-1/spec.md`; ROADMAP M4 and PRODUCT.md reference it |
| #464 ownership-lane violation | Scope decided by product owner (PR #444), gate wording landed in the architect-owned spec via this ADR |
| #465 PRODUCT.md self-contradiction (sweep-before-ship vs. does-not-block) | The sprint-1 P2 sweep claim is corrected to cite this gate; PRODUCT.md restates no predicate |
| #466 missing numbered ADR | This ADR; owner named below |
| #467 fail-open on 188 unlabeled issues | The spec's fail-closed triage bullet: unlabeled blocks, full stop, until triaged; triage pass tracked as #510 |
| #470 legacy-label semantics undefined | The same fail-closed triage bullet: legacy labels are not valid triage; exact-form case-sensitive `P0`–`P3` only; multi-label → most severe governs |
| #468 deferral target unnamed | The spec's non-security P2/P3 deferral paragraph: the named M5 "P2/P3 tech-debt burndown (non-security)" item |
| #469 ground-truth counts embedded as durable facts | Every count in this ADR and `docs/PRODUCT.md` is an explicitly dated 2026-07-29 snapshot, not a live value; the stale 221/6 freeze figures in `docs/PRODUCT.md` are corrected and date-stamped |

## Consequences

- **Decision owner: product-owner** (milestone scope / feature freeze per
  `GOVERNANCE.md`); the architect owns the spec text that expresses it. Any
  future change to the gate predicate is a new ADR, not an edit to a
  restatement.
- The gate stays decidable with no judgment calls, across three mechanical
  bucket kinds: label queries over **open** issues (including the
  anti-laundering floor via the clerk-applied `gate:confirmed-high`
  label), the close-laundering query over **closed** issues
  (`stateReason` + merged-PR cross-reference, spec-defined), and the
  artifact checks (coverage, nightly evals, the freeze marker) as
  mechanical file/CI checks. Fail-closed on triage converts "triage the 188
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
  open. That is honest and bounded (41 P2 + 20 P3 today — the 6
  security-labeled P2/P3 items block under the security criterion — plus
  whatever triage reclassifies), versus a literal-zero gate that invites
  mass-closing or silent miscounting.
- `docs/PRODUCT.md`'s sprint-1 note that M4 "already guarantees they get
  swept before ship" is corrected in the same PR — under this gate, only
  `security`-labeled members of that P2 batch block v1.0.0.
