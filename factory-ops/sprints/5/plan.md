# Sprint 5 — Plan

- **Sprint:** 5
- **Planned:** 2026-08-12T09:00:00Z (UTC, anchor — no `SPRINT_HOURS` repo
  variable found, queried via the Actions Variables API, returned
  `403 Resource not accessible by integration`; using the same documented
  24h default sprints 1–4 used).
- **sprint_ends_at:** 2026-08-12T09:00:00Z + 24h = **2026-08-13T09:00:00Z**
- **Planner:** conductor/planner session (this file), from sprint 4's
  `review.md`/`retro.md` (held immediately before this plan, same wake,
  ~131 hours after sprint 4's own boundary), a live GitHub ground-truth pass
  (issue/PR state via the REST/Search APIs), `docs/PRODUCT.md`'s sprint-5
  snapshot (written by this same wake in the product owner's absence, marked
  unilateral there), and `GOVERNANCE.md`.
- **Status:** **not a board sprint.** Sprint 4 was the 4th sprint and the
  mandatory board session already happened — PR #1107 merged
  2026-08-12T03:28:52Z, ADR 0006 ("Release Gate synthesis") resolves all
  nine panel-confirmed flaws from the judge-panel over PR #444/ADR 0005. The
  next mandatory convening is **sprint 8**.

## Sprint goal

Sprint 4 shipped 1 of 5 committed-core items (20%, the board session) —
flat with sprint 3's 20%, and the same three carried bug fixes
(#442/#419/#420) got zero session turns for a **second** consecutive
sprint. Meanwhile the tech-debt count sprint 4's top priority was supposed
to shrink instead grew 754 → 1188 (+57%), and — the sharpest new finding —
the board's own freeze on PR #444's review rounds fired for 31 minutes
before an ordinary adversarial round ran anyway and added 10 more findings.
Sprint 5's goal, in strict priority order:

1. **Guarantee the carried bug fixes a turn.** #442, #419, #420 have now
   been committed core for two straight sprints without a single session
   touching them, because one large item (a board session, an unconverged
   PR) consumed all capacity both times — a pattern this same wake filed as
   **#1445**. This plan sequences these three **first**, before #1054's
   capped round or the #132 reassignment, as a direct application of
   #1445's own suggested fix.
2. **Make a bounded decision on PR #1054 (#471/#688), not a fifth
   open-ended round.** Four rounds of real, non-converging churn (2026-08-06,
   08-07, 08-08, 08-11) is itself now filed as a process gap (**#1444**).
   This plan's decision: the implementer gets **one** more capped review
   round this sprint. If round 5 does not converge to `APPROVED`, the
   implementer stops iterating on the full diff and re-scopes to the
   minimal change that lands `techdebtAudit`'s core cross-check (the part
   already proven correct across 4 rounds) — deferring the `sameProblem`/
   `extractFingerprint` refinements (#1354, #1362) as their own tracked
   `tech-debt`, not further blocking on them. This is a planner decision
   made explicitly here, not left to another open-ended iteration.
3. **Actually execute the #132 reassignment.** Sprint 4's plan ordered this
   (per #978's P0 incident) and it never happened — PR #318 is unchanged
   since 2026-07-25 (now 18 days stale). This sprint, security-steward
   re-specifies against current `main` on a **fresh branch**, and an
   implementer lands it — not another plan note.
4. **Flag the M3 roadmap checkbox for the architect.** "Board session #1
   held via judge-panel with a synthesized ADR" has shipped substance
   (ADR 0006/PR #1107) but the checkbox is unflipped — the same class of
   gap as #159/M2 last sprint. Not this plan's to execute (architect-owned,
   `docs/**`, `guard-roadmap`-gated on a merged-green proof) — named here as
   a required, non-deferrable flag so it isn't lost the way #120's reopen
   nearly was.
5. **Take #1443 (freeze-enforcement) if capacity remains.** High leverage —
   it's the single change most likely to stop the exact bleed that made
   sprint 4's headline finding worse, not better — but not committed core
   given this sprint's conservative sizing (see capacity note).

### Capacity note (four sprints of evidence)

Sprint 1: 3-of-9 (~33%). Sprint 2: 0-of-5. Sprint 3: 1-of-5 (20%). Sprint 4:
1-of-5 (20%) — flat with sprint 3, and in both flat sprints the same three
items (#442/#419/#420) got zero turns. This plan keeps committed core at
**5 items** (same size as sprints 3–4) but changes *sequencing*, not size,
per #1445's finding: the three cheapest, most-carried items go first, so a
long-running item (PR #1054's capped round, or the #132 reassignment) can
never again zero out this sprint's entire committed-core throughput the way
the board session and #100 did in sprints 4 and 3 respectively.

## Picked issues

### Committed core (5 items — this sprint's closeable-capacity target, in sequence order)

| Seq | # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|---|
| 1 | #442 | `guard-commit`/`record-green` resolve `PROJECT_DIR` to the main checkout, not the worktree | P0 (carried, 3rd sprint) | **implementer** | Unchanged from sprints 3–4: PR merges fixing `PROJECT_DIR` resolution so a worktree-isolated session's commit gate checks that session's own tree, verified by a failing-then-passing test from a simulated worktree path. Full suite green. Issue #442 closes via merge. |
| 2 | #419 | `debt-reconcile.sh:18` — `gh issue list` has no `--limit`, caps at 30 | P0 (carried, 3rd sprint) | **implementer** | Unchanged: explicit high limit or full pagination added, verified by a test seeding >30 open tech-debt issues (mocked `gh`). Full suite green. Issue #419 closes via merge. |
| 3 | #420 | `hooks/lib/common.sh:582` — same bug, `/factory-status` banner | P0 (carried, 3rd sprint; same series as #419, land together if cheap) | **implementer** | Unchanged: same limit/pagination fix, verified by a test asserting the true count against a >30-issue fixture. Full suite green. Issue #420 closes via merge. |
| 4 | #471 / #688 | `tech-debt-clerk` fingerprint idempotency — **capped decision this sprint** | **P0 — bounded, see sprint goal #2** | **implementer**, escalating to **security-steward** if round 5 doesn't converge | PR #1054 gets one more review round. **If `APPROVED`:** merges as-is, closes #471/#688. **If not:** implementer re-scopes to the minimal diff landing the core cross-check only (the part stable across 4 rounds), files #1354/#1362's refinements as their own tracked `tech-debt` (not blocking), and that minimal PR must converge within the same sprint. Full suite green either path. |
| 5 | #132 | Review job grants `issues:write` + `secrets:inherit` over an attacker-controlled diff — **reassignment executed, not just planned** | P0 (carried, reassignment ordered sprint 4, never executed) | **security-steward** re-specifies on a fresh branch (not PR #318); **implementer** lands it | A fresh PR (explicitly not a continuation of stale PR #318, unchanged since 2026-07-25) merges dropping `issues:write`/`secrets: inherit` from the review job's `permissions:`. Full suite green. Issues #132 and #978 (the P0 staleness incident) both close via merge. |

### Required, non-deferrable action (not committed-core capacity, but not optional either)

| # | What | Owner | Why it's not in an overflow table this time |
|---|---|---|---|
| M3 checkbox | Flag `docs/ROADMAP.md` M3's "Board session #1" item for the architect to check off, citing ADR 0006/PR #1107 as the merged-green proof. | **architect** (this plan flags it; the flip itself is architect-owned, `docs/**`, `guard-roadmap`-gated) | Same failure class as sprint 3's #120 reopen and sprint 4's #159 checkbox: a completed action sitting unrecorded because no single session owned recording it. Naming it here, unconditionally, rather than burying it in overflow. |

### Overflow (picked, capacity-driven deferral — carried into sprint 6 if not reached)

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #1443 | ADR 0006 §D8's review freeze on PR #444 has no mechanical enforcement | **P0 — highest-leverage overflow item, take first if core finishes early** | **architect** (review-workflow design) | A PR merges giving `/review`'s dispatch a machine-readable freeze signal (e.g. a board-set marker on the frozen PR) that skips or downgrades a full adversarial round while the freeze holds, verified by a fixture asserting a frozen PR's review pass does not file new `tech-debt`. Full suite green. |
| #1444 | No round-cap/escalation trigger for unconverged-but-real-delta review churn | P1 (carried, this session's finding) | **planner/qa** | Extends the staleness convention with a round-count or elapsed-days cap that auto-files a P0 escalation issue. Not urgent to implement this sprint since sprint 5's plan applies its logic manually to PR #1054 already. |
| #1445 | Committed-core capacity structurally drains to one headline item | P1 (carried, this session's finding) | **planner** (practice, applied starting this plan) / **architect** (optional `factory-run` dispatch change) | This sprint's sequencing (carried bugs first) is the practice-level fix in effect now; the code-level option (parallel dispatch) remains open, unscheduled. |
| #423 | PR #311's `secrets: inherit` removal breaks the reviewer station's token mint | P1 (unblocks #120/#311, carried 3 sprints) | **implementer (security-steward focus)** | Unchanged from sprints 3–4. |
| #101 | Review station: `bypassPermissions`, no tool allowlist | P0 (carried 4 sprints) | **implementer (security-steward focus)** | Unchanged. |
| #342 | Stations exit RED on a usage limit | P0 (carried 4 sprints, unchanged) | **implementer** | Unchanged. |
| #361 | `factory-run.yml` has no standup step / boundary-check precondition | P1 (carried 4 sprints — directly relevant to why sprint 4's overrun went uncaught) | **implementer** | Unchanged. |
| #459 | Sprint-2 ceremony-lateness fix | P1 (carried, unchanged) | **implementer** | Unchanged. |
| #94 | `/factory-init` bootstrap chicken-and-egg | P1 (carried) | **implementer** | Unchanged. |
| #95 | Green-receipt mint/check location asymmetry, worktree commits | P1 (carried) | **implementer** | Unchanged. |
| #159 | Epic 1.1 static validation layer — verify-and-close, 4th sprint named | P1 (**land PR #1415, then close #159 itself as a fast follow — the PR flips the roadmap box but its body does not close the issue**) | **implementer or architect, whichever gets a turn first** | PR #1415 merges (fixes its one open `CHANGES_REQUESTED` finding, already pushed this wake); a same-day or next-turn follow-up explicitly closes #159 citing `3fb17dc`. |
| #229 | `guard-bash-writes` misdiagnoses read-only trust-root inspection as writes | P1 (carried) | **implementer** | Unchanged. |
| #422 | `/factory-run` step-1 `loop.json` arming has no sanctioned write path | P2 (carried, untriaged for severity) | **implementer** | Unchanged. |

### Tech-debt burndown (product owner's, own bucket, not counted against committed-core capacity)

| # | What | Priority | Owner | Done-condition |
|---|---|---|---|---|
| — | **Do not re-attempt triage pass 1 yet.** Per sprint 4's own P2 disposition (unchanged): the zero-priority-signal pool grew again this sprint (mostly PR #444/#1054 review-loop output), so triaging it before the manufacture engine (#471/#688) and the freeze-enforcement gap (#1443) are actually fixed is pouring water into a running tap. Re-measure once both land. | — | **product-owner** | Re-baseline the pool's size against post-fix counts before scheduling a fresh triage pass. |

### Blocked-on-human (tracked, unchanged)

| # | Title (abridged) | Priority | Owner | Done-condition |
|---|---|---|---|---|
| #115 | coder App lacks `actions:read` | P1 | **BLOCKED-on-human** | Unchanged. |
| #228 | Build-loop no-op-guard, depends on #115 | P0 | **BLOCKED-on-human** | Unchanged. |

21 issues tracked total (5 committed-core + 1 required non-deferrable action
+ 11 overflow + 1 triage-bucket item + 2 blocked-on-human, plus #1443/#1444/
#1445 counted once each above). Only the 5-item committed core counts
toward this sprint's closeable-capacity claim.

## Routed, not decided here

| # | What | Route |
|---|---|---|
| #138 | Coordination-substrate milestone-scope decision — contested since sprint 1, PR #139 closed without resolving it | **judge-panel**, unchanged disposition. Not a sprint-5 board item (next mandatory convening: sprint 8); on-demand convening remains available per `GOVERNANCE.md` if it becomes urgent before then. |

## Flagged for early sequencing (not this planner's issues to pick, noted for the implementer/security-steward/architect)

- **PR #1054** — do not start a 5th open-ended round; apply the sprint
  goal's capped-decision rule (see committed core #4 above) at the first
  review checkpoint this sprint.
- **PR #318** — do not continue this branch for #132; security-steward
  specifies fresh, per the reassignment sprint 4 ordered but never executed.
- **PR #1415** — near done (this wake pushed its one outstanding review
  fix); land it, then close #159 as a fast follow, not a fifth-sprint
  recurrence of the paperwork pattern.
- **`docs/ROADMAP.md` M3, "Board session #1"** — architect action, proof
  already exists (ADR 0006/PR #1107). See required non-deferrable action
  above.
- **PR #102** (dependabot) and any routine dependency-bump PRs — no
  sprint-goal dependency, implementer/release-captain discretion.

## Deliberately not picked (left in backlog, ranked for sprint 6+)

- **#231, #206** — loop-health cluster (cron-prod dispatch-condition
  inversion; durable checkpoint write-back). Unchanged disposition: bundle
  together when picked.
- **#177** — single self-hosted runner serializes the factory. Real
  throughput constraint, not correctness; infra pass, not sprint-5 core.
- **The zero-priority-signal `tech-debt` pool** — explicitly not
  re-triaged this sprint (see tech-debt burndown bucket above); it grew
  again this sprint, almost entirely from review-loop output on PR #444
  and PR #1054.
- **Bootstrap/egress-proxy hardening bundle (#163–#249 range)** — unchanged
  disposition from sprints 1–4, maps to M3's "Security hardening pass."
- **P3 doc drift (#141–143, #146–157)** — unchanged, routed to `v1.1.0`.
- **The M4 implementation track** (gate script + cores + fixtures; the
  close-audit auditor + fixtures; `/ship` wiring — ADR 0006 §D8's named
  follow-ups) — real, substantial, and now unblocked by a settled design,
  but not started and not this sprint's size. Noted as the next real
  Release-Gate-substance epic once the floor above (carried bugs,
  #471/#688, #132) is actually closed out — the same sequencing logic
  every prior sprint has applied to M2/M3 work.

## Reassignment / staleness note

**#132/PR #318's reassignment, ordered by sprint 4's plan, is executed by
this plan, not merely repeated.** Committed core #5 above requires a fresh
branch — PR #318 is no longer an acceptable continuation path 18 days after
its last commit. **PR #1054 gets a hard cap this sprint** (committed core
#4): one more round, then a mandatory re-scope if unconverged — per #1444's
finding, an open-ended round count is itself the failure mode, not just a
symptom of it. No other item on this plan has yet crossed a comparable
threshold; #442/#419/#420 enter their third sprint carried unchanged
(now sequenced first, per #1445) rather than reassigned, since the gap here
is capacity sequencing, not a stalled owner.
