# ADR 0005 — Scope the v1.0.0 tech-debt gate: fail-closed on triage, security outranks priority

Status: accepted · Date: 2026-08-05 · Amended: 2026-08-08 (conformed
to ADR 0006, the sprint-4 board synthesis — its forward references to
0006 and to spec criteria 6/9 date from this amendment, #1297)

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

- literal-zero tech-debt is replaced by the severity-scoped,
  fail-closed criteria **as written in the spec section — no
  restatement here** (#924);
- one decision originates in this ADR rather than the spec:
  **security-precedence extends across priority levels for release
  gating** — `docs/PRODUCT.md` ranking rule 1 is, as written, only an
  equal-priority tie-breaker, and the ground truth shows `security`
  does not correlate with P-level; the spec expresses the resulting
  criterion;
- the deferral home for what no longer blocks is the named ROADMAP
  **M5 (v1.1.0) item "P2/P3 tech-debt burndown (non-security)"** —
  deliberately distinct from M3's security-hardening pass, which is
  security-scoped and v1.0.0-scoped and therefore cannot absorb
  non-blocking deferrals without contradicting itself;
- the authorship of this and any future gate-scope change follows the
  **joint-lane rule recorded in `GOVERNANCE.md` § "Decision owners (default path — no meeting needed)"**: the
  product owner authors the `docs/PRODUCT.md` rationale, the architect
  authors the spec/ARCHITECTURE/ADR wording, and a fenced agent's charter
  is never widened by that agent's own edit to its file;
- the ≥95% coverage floor **widens to include `hooks/lib/common.sh`** —
  recorded here because a gate-threshold scope change needs an ADR row:
  the gate's own paginated counting lives in that library, and an
  untested counting path is the #419/#420 class recurring. qa owns the
  threshold going forward (its charter mirrors this scope and defers to
  the spec on drift).

Prerequisite: the canonical set is the spec's CLOSED-state criterion —
no copy of the list here, the spec governs; notably the pagination
counting bug and the anti-laundering backfill audit within it must be
fixed and re-verified before any automation trusts this gate — the M4
"Release Gate script" must count via fully-paginated queries, never a
bare `gh issue list`.

Explicitly rejected: the literal zero (unachievable except via mass-closing or
the counting bug); treating unlabeled tech-debt as deferrable (fail-open — an
untriaged P0 or security issue would slide through); and using M3's
security-hardening pass as the P2/P3 dumping ground (scope contradiction).

(The per-finding resolution record for the PR #444 review rounds lives
in that PR's description, not here — a durable ADR records the
decision, not its own review's ticket ledger, and it makes **no claim
about its own findings' exemption status**: whether any hand-closed
finding's close qualifies is for the Release Gate script to evaluate
mechanically post-merge, like every other close — a PR pre-asserting
its own merge as exempting evidence would be the self-certification
the gate exists to forbid, #964/#969.)

## Consequences

- **Decision owner: product-owner** (milestone scope / feature freeze per
  `GOVERNANCE.md`); the architect owns the spec text that expresses it. Any
  future change to the gate predicate is a new ADR, not an edit to a
  restatement.
- The gate stays decidable with no judgment calls, across three mechanical
  bucket kinds: label queries over **open** issues (including the
  anti-laundering floor via the clerk-applied `gate:confirmed-high`
  label), closed-issue laundering detection — **moved by ADR 0006 § D1
  to the nightly close-audit workflow**, whose liveness and standing
  contested-close bucket the gate consumes as criteria 6 and 9 instead
  of running its own closed-issue query at gate time — and the
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
  open. That is honest and bounded (41 P2 + 20 P3 in the dated
  2026-07-29 snapshot; the live number is the gate script's to compute —
  the 6
  security-labeled P2/P3 items block under the security criterion — plus
  whatever triage reclassifies), versus a literal-zero gate that invites
  mass-closing or silent miscounting.
- `docs/PRODUCT.md`'s sprint-1 note that M4 "already guarantees they get
  swept before ship" is corrected in the same PR — under this gate, only
  `security`-labeled members of that P2 batch block v1.0.0.
