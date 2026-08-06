# Sprint 4 — Plan

- **Sprint:** 4
- **Planned:** 2026-08-05T21:32:46Z (UTC, anchor — no `SPRINT_HOURS` repo
  variable found (queried via the Actions Variables API, returned
  `403 Resource not accessible by integration`); using the same documented
  default of 24h sprints 1–3 used).
- **sprint_ends_at:** 2026-08-05T21:32:46Z + 24h = **2026-08-06T21:32:46Z**
- **Planner:** conductor/planner session (this file), from sprint 3's
  `review.md`/`retro.md` (held immediately before this plan, same wake,
  after a six-day-overdue ceremony gap — see retro), a live GitHub
  ground-truth pass (issue/PR state via the REST/Search APIs), and
  `GOVERNANCE.md`.
- **Status:** **fourth sprint — the board convenes this sprint.**
  `GOVERNANCE.md`: "Convenes: every 4th sprint." This is also
  `docs/ROADMAP.md` M3's own still-open item, "Board session #1 held via
  judge-panel with a synthesized ADR" (line 58).

## Sprint goal

Sprint 3 shipped 1 of 5 committed-core items (20%) and, unnoticed for six
days, let a live security/process crisis compound: **PR #444/ADR 0005 (the
M4 gate-scope redefinition) has absorbed 20 unconverged adversarial-review
rounds since 2026-07-30, driving open tech-debt from 289 to 754 (~465 net
new, mostly duplicate) because `tech-debt-clerk`'s fingerprinting diverges
from the connector's canonical algorithm** (#471/#688) — every review of
that PR makes the M4 "zero open tech-debt" gate *recede*, not approach.
Sprint 4's goal, in strict priority order:

1. **Stop the bleed.** Fix #471/#688 (fingerprint idempotency) first, before
   anything else — it's the mechanism actively causing damage on every
   review cycle today, independent of whether or when PR #444 itself
   resolves. This is this sprint's single highest-priority item.
2. **Convene the board.** Per `GOVERNANCE.md`'s mandatory 4th-sprint
   cadence, hold `/judge-panel` over PR #444/ADR 0005's contested M4
   gate-scope redefinition — a decision that has proven itself contested by
   staying open and unconverged for six days under normal review, and is
   exactly the kind of "scope change to a milestone" `GOVERNANCE.md` names
   as an on-demand board trigger even outside the cadence. Roster: chair
   (conductor), product-owner, architect, security-steward, treasurer,
   efficiency-engineer.
3. **Carry sprint 3's unfinished committed core forward, unchanged in
   substance:** #442 (`PROJECT_DIR` worktree resolution), #419/#420
   (unbounded `gh issue list`, two call sites). All three are gate-
   correctness bugs sprint 3 explicitly sequenced ahead of the security
   floor for the same reason they're first again here — a gate that counts
   or resolves wrong is worse than no gate.
4. **Do not re-pick #120 as committed core.** It is still falsely closed
   (six days longer than when sprint 2's review found it) with its real fix
   (PR #311) blocked on #423. Reopening it is named explicitly below as a
   required, non-deferrable action — not buried in an overflow table this
   time (see #474/#580, which predicted exactly that failure mode).
5. **Reassign #132/PR #318** per the P0 incident already filed against it
   (#978: zero state delta across three consecutive sprints).

### Capacity note (three sprints of evidence)

Sprint 1 closed 3-of-9 (~33%). Sprint 2 closed 0-of-5. Sprint 3 closed 1-of-5
(20%), and that one item was already mid-flight from the prior sprint — no
newly-started committed-core item has shipped in three sprints. This plan
sizes committed core to **5 items**, weighted toward the two highest-value,
most tractable items (a scoped bug fix and a ceremony this session itself
can drive to completion) rather than repeating sprint 2's over-commit
mistake. The three carried bug-fix items are the same scope sprint 3 already
sized as "committed core" and failed to start — not new capacity claims.

## Picked issues

### Committed core (5 items — this sprint's closeable-capacity target)

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #471 / #688 | `tech-debt-clerk` fingerprints diverge from the connector's canonical `fingerprintFinding`/`techdebt_audit` — review idempotency and `debt-reconcile`'s Stop hook both broken | **P0 — top priority, stop-the-bleed** | **implementer** | PR merges making `tech-debt-clerk`'s fingerprint computation call (or exactly reproduce) the connector's canonical `fingerprintFinding`/`techdebt_audit` algorithm, verified by a failing-then-passing test asserting the same finding content produces the same fingerprint via both code paths, and a second test asserting a re-run of `/review` against an already-filed finding does not open a duplicate issue. Full suite green (`bash tests/run-suite.sh`). Both #471 and #688 close via merge (same root cause, same fix). |
| — | **Board session:** convene `/judge-panel` over PR #444/ADR 0005's contested M4 tech-debt-gate-scope redefinition | **P0 — mandatory, 4th-sprint cadence** | **chair: conductor**; roster: product-owner, architect, security-steward, treasurer, efficiency-engineer (`GOVERNANCE.md`) | Three stance-pinned proposals are written to `.factory/panel/`, an adversarial panel (one judge per proposal-independent axis) names each proposal's fatal flaw with a CONFIRMED/PLAUSIBLE verdict, and a synthesis lands as a numbered ADR in `docs/adr/` that resolves every panel-confirmed flaw — either affirming, amending, or superseding the current ADR 0005/PR #444 direction. The ADR names its own decision owner in its Consequences section per `GOVERNANCE.md`. This board session also satisfies `docs/ROADMAP.md` M3's "Board session #1" item (architect flips that checkbox on the ADR's merge, not this plan). |
| #442 | `guard-commit`/`record-green` resolve `PROJECT_DIR` to the main checkout, not the worktree | P0 (carried, sprint 3 unstarted) | **implementer** | Unchanged from sprint 3's plan: PR merges fixing `PROJECT_DIR` resolution so a worktree-isolated session's commit gate checks that session's own tree, verified by a failing-then-passing test from a simulated worktree path. Full suite green. Issue #442 closes via merge. |
| #419 | `debt-reconcile.sh:18` — `gh issue list` has no `--limit`, caps at 30 | P0 (carried, sprint 3 unstarted) | **implementer** | Unchanged from sprint 3's plan: explicit high limit or full pagination added, verified by a test seeding >30 open tech-debt issues (mocked `gh`). Full suite green. Issue #419 closes via merge. |
| #420 | `hooks/lib/common.sh:582` — same bug, `/factory-status` banner | P0 (carried, sprint 3 unstarted; same series as #419 acceptable) | **implementer** | Unchanged from sprint 3's plan: same limit/pagination fix, verified by a test asserting the true count against a >30-issue fixture. Full suite green. Issue #420 closes via merge. |

### Required, non-deferrable action (not committed-core capacity, but not optional either)

| # | What | Owner | Why it's not in an overflow table this time |
|---|---|---|---|
| #120 | **Reopen #120 now.** It has been falsely closed since 2026-07-29, six days longer than when sprint 2's review found it, because sprint 3's plan put this exact action in an overflow row with no unconditional owner (predicted failure mode: #474/#580). | **planner action, this plan** — treated as executed by this ceremony, not deferred to implementation capacity | Reopening a mistracked issue costs one API call, not a sprint slot. Real fix (PR #311, blocked on #423) remains implementer work, tracked below. |

### Overflow (picked, capacity-driven deferral — carried into sprint 5 if not reached)

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #423 | PR #311's `secrets: inherit` removal breaks the reviewer station's token mint | P1 (unblocks #120/#311) | **implementer (security-steward focus)** | Unchanged from sprint 3: fallback/alternate token-mint path added, verified by a fixture simulating the no-`secrets:inherit` case. Full suite green. |
| #101 | Review station: `bypassPermissions`, no tool allowlist | P0 | **implementer (security-steward focus)** | Unchanged from sprint 1–3: explicit read-only tool allowlist, verified by a malicious-PR-body fixture. Full suite green. |
| #132 | Review job grants `issues:write` + `secrets:inherit` over attacker-controlled diff | P0 (**reassigned** — see below) | **security-steward** (posture) handing a fresh branch to **implementer**, not a continuation of PR #318 | Per **#978** (P0 incident, zero state delta 2026-07-25→2026-08-05): PR #318 is not the vehicle going forward. Security-steward re-specifies the fix against current `main`; a fresh PR (or an unstuck #318 only if it can be rebased clean within this sprint) merges dropping `issues:write`/`secrets: inherit` from the review job's `permissions:`. Full suite green. Issue #978 closes alongside #132 once a real merge lands. |
| #342 | Stations exit RED on a usage limit | P0 (carried, unchanged 3 sprints) | **implementer** | Unchanged. |
| #361 | `factory-run.yml` has no standup step / boundary-check precondition | P1 (carried, unchanged 3 sprints — directly relevant to why sprint 3's overrun went uncaught) | **implementer** | Unchanged. |
| #459 | Sprint-2 ceremony-lateness fix | P1 (carried, unchanged) | **implementer** | Unchanged. |
| #94 | `/factory-init` bootstrap chicken-and-egg | P1 (M3-named, carried) | **implementer** | Unchanged. |
| #95 | Green-receipt mint/check location asymmetry, worktree commits | P1 (M3-named, carried) | **implementer** | Unchanged. |
| #159 | Epic 1.1 static validation layer — verify and close | P1 (**4th sprint** this disposition is named) | **implementer or architect, whichever gets a turn first** | Substance shipped `3fb17dc` since sprint 1. Given #981/#709 (paperwork dispositions have no forcing function, no execution owner), this plan makes the done-condition explicit rather than trusting disposition alone: close #159 citing `3fb17dc`, AND flip `docs/ROADMAP.md`'s corresponding M2 checkbox in the same PR (architect action, merged-green proof = the commit already on `main`). |
| #229 | `guard-bash-writes` misdiagnoses read-only trust-root inspection as writes | P1 (carried) | **implementer** | Unchanged. Note: this session's own orientation hit exactly this class of false-positive (a plain `cat` on `.factory/active-agent`/`.factory/config.json` was denied as a write) — live, current-session evidence this is a real, active nuisance, not theoretical. |
| #422 | `/factory-run` step-1 `loop.json` arming has no sanctioned write path | P2 (carried, still untriaged for severity) | **implementer** | Unchanged. |

### Tech-debt burndown (product owner's, own bucket, not counted against committed-core capacity)

| # | What | Priority | Owner | Done-condition |
|---|---|---|---|---|
| — | **Re-attempt triage pass 1** (previously failed to execute — #742) on the `security`/`area:build`/`area:hooks` zero-priority-signal slice | — | **product-owner** | Unchanged scope from sprint 3's plan. Given #742's finding that this bucket lost to real work twice running, and the zero-signal count grew from 204→591 in the interim, the product owner should re-baseline the slice size against current counts before re-attempting, not assume the original 204-based scope still applies. |

### Blocked-on-human (tracked, unchanged)

| # | Title (abridged) | Priority | Owner | Done-condition |
|---|---|---|---|---|
| #115 | coder App lacks `actions:read` | P1 | **BLOCKED-on-human** | Unchanged. |
| #228 | Build-loop no-op-guard, depends on #115 | P0 | **BLOCKED-on-human** | Unchanged. |

20 issues tracked total (2 headline committed-core items + 3 carried
committed-core bug fixes + 1 required non-deferrable action + 11 overflow +
1 triage-bucket item + 2 blocked-on-human). Only the 5-item committed core
counts toward this sprint's closeable-capacity claim; #120's reopen is
executed by this plan itself, not claimed as sprint capacity.

## Routed, not decided here

| # | What | Route |
|---|---|---|
| #444 / ADR 0005 | M4 tech-debt-gate-scope redefinition — contested by six days of unconverged review | **This sprint's board session** (see committed core above) — the planner does not pre-judge the outcome. |
| #138 | Coordination-substrate milestone-scope decision — contested since sprint 1, PR #139 closed without resolving it | **judge-panel** — unchanged disposition from sprints 1–3. If sprint 4's board convening has capacity after #444, this is the next-oldest routed item; otherwise carries to sprint 5. Owner of convening: architect. |

## Flagged for early sequencing (not this planner's issues to pick, noted for the implementer/release-captain)

- **PR #311** — #120's real fix, blocked on #423. Land #423's fallback
  first, then this.
- **PR #318** — per the #132 reassignment above, do not default to
  continuing this branch; security-steward should confirm whether it's
  salvageable before an implementer picks it up again.
- **`docs/ROADMAP.md` M2, "Static validation layer in the commit gate"** —
  substance already merged (`3fb17dc`/PR #375), checkbox never flipped.
  Architect action, bundled into #159's done-condition above so it isn't
  lost a fourth time.
- **PR #102** (dependabot), and any routine dependency-bump PRs — no
  sprint-goal dependency, implementer/release-captain discretion.

## Deliberately not picked (left in backlog, ranked for sprint 5+)

- **#231, #206** — loop-health cluster (cron-prod dispatch-condition
  inversion; durable checkpoint write-back). Unchanged disposition: bundle
  together when picked, per the product owner's own note.
- **#177** — single self-hosted runner serializes the factory. Real
  throughput constraint, not correctness; infra pass, not sprint-4 core.
- **The remaining zero-priority-signal tech-debt pool beyond this sprint's
  re-attempted triage slice** — explicitly multi-sprint; M4 stays unchecked
  regardless of this sprint's slice, and stays unchecked pending the board's
  ADR on what M4 actually requires.
- **Non-security P2/P3 tech-debt** — per the product owner's prior
  redefinition (subject to revision by this sprint's board session), does
  not block M4 pending the ADR.
- **P3 doc drift (#141–143, #146–157)** — unchanged, routed to `v1.1.0`.

## Reassignment / staleness note

**#132/PR #318 is reassigned this sprint**, per the P0 incident already
filed against it (**#978**: zero state delta 2026-07-25 → 2026-08-05, three
full sprints). Per the fence rules in `.claude/CLAUDE.md` and the staleness
trigger sprint 3's own plan set (and this sprint's evidence confirms fired),
PR #318 is no longer the default continuation path — security-steward
re-specifies against current `main` before any implementer picks this back
up. No other item on this plan has yet crossed a three-consecutive-sprint
threshold with zero delta; #442/#419/#420/#423 are each entering only their
second sprint as committed/overflow core (first appearance: sprint 3) and
are carried forward unchanged rather than reassigned.
