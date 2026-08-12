# Sprint 4 — Retro

- **Sprint:** 4
- **Retro held:** 2026-08-12, immediately after `review.md` (same planner
  wake).
- **Board cadence:** per `GOVERNANCE.md`, the board convenes "every 4th
  sprint." **Sprint 4 was that sprint, and the board session already
  happened** — PR #1107 ("Board session: ADR 0006 — Release Gate
  synthesis") merged 2026-08-12T03:28:52Z, resolving all nine
  panel-CONFIRMED fatal flaws from the three stance-pinned proposals judged
  by three adversarial panelists against PR #444/ADR 0005's contested M4
  gate-scope redefinition. This retro does not re-run or second-guess that
  session; it accounts for its outcome (see "What went well" and the freeze
  finding below) and reserves the **next** mandatory convening for sprint 8.

## What went well

- **The board session ran on schedule and produced a real, decisive
  synthesis.** ADR 0006 names a concrete decision owner per clause
  (architect for gate mechanism, product-owner for gate scope), resolves
  all nine confirmed flaws with a specific mechanism for each (D1–D8), and
  gives PR #444 — 33 review rounds deep, 26+ of them before the freeze —
  an actual exit: reduce to docs-only conformance, land, done. This is the
  judge-panel machinery working exactly as designed under real, sustained
  pressure, not a toy case.
- **The adversarial-review discipline stayed sharp even under pressure to
  just ship.** PR #1054's four unconverged rounds are not noise — round 4
  found genuine, non-obvious bugs *inside the fingerprint-idempotency fix
  itself* (#1354, #1362), including one live-reproduced against the
  review's own freshly-filed finding. A lower-quality reviewer would have
  approved a fix that silently reintroduces the bug class it exists to
  close.
- **#120 held.** No relapse into sprint 3's false-`completed` closure —
  confirmed live, still correctly reopened, six days after this same
  planner reopened it directly rather than deferring the action a third
  time.

## What went wrong

### 1. The sprint's #1 committed-core priority — stopping the tech-debt
   bleed — did not land, and the bleed got worse under its own watch

Sprint 4 declared #471/#688 (PR #1054) the single highest-priority item,
explicitly to stop review-loop-driven tech-debt manufacture. It is still
open 6+ days later. Meanwhile open `tech-debt` went **754 → 1188 (+57%)**
during the sprint — worse growth in six days than the crisis that triggered
sprint 4's plan in the first place (289 → 754 over sprint 3's whole
six-day gap). The mechanism meant to fix duplicate/runaway filing is itself
generating findings faster than it converges. Not a new root cause (#980
already names the underlying loop), but the magnitude — worse this sprint
than last, on the sprint whose entire priority order was built around
stopping it — is the sharpest evidence yet that iterating this fix in the
ordinary review loop isn't working. Feeds directly into sprint 5's #1444.

### 2. The board's own freeze decision has no teeth, and it showed the
   same night

ADR 0006 §D8 explicitly freezes further ordinary adversarial review on
PR #444 once the ADR merges. Thirty-one minutes after merge, a full
3-lens review ran anyway and filed 10 more tech-debt issues against a
93-line diff. This is not a hypothetical gap — it fired in real time,
against the exact PR the freeze names, hours after the ADR that declared
the freeze became the decision of record. A governance decision recorded
only in prose (an ADR) has no effect on an automated workflow unless
something in that workflow actually reads it. **Filed this retro: #1443**
(P0).

### 3. A plan naming a reassignment isn't the same as a reassignment
   happening — again

Sprint 4's plan explicitly ordered #132's fix reassigned off PR #318 (per
#978's P0 incident). No fresh branch materialized; PR #318 sits exactly
where it did on 2026-07-25, now 18 days stale. This is the same shape as
sprint 3's #120 finding (a plan's named action, sitting in prose, doesn't
execute itself) — that time the planner closed the gap directly at
ceremony time (the #120 reopen); this time the action needed an
implementer/security-steward session turn that never came. Not re-filed as
its own issue — #978 already carries the underlying incident — but sprint
5 needs to actually do this, not re-plan it a third time.

### 4. Committed-core throughput is now flat at 20% for two sprints
   running, and the same three items are paying for it

Sprint 3: 1-of-5 (20%). Sprint 4: 1-of-5 (20%). In both sprints, the exact
same three carried bug fixes (#442, #419, #420) got zero session turns
while all capacity went to that sprint's one largest item. Sprint 4's plan
explicitly tried to correct for sprint 2's over-commit mistake by sizing
conservatively (5 items) — that didn't help, because the problem isn't
commitment size, it's that one large item can structurally consume 100% of
a sprint's capacity before smaller committed items are ever touched.
**Filed this retro: #1445** (P1) — a sequencing gap, not a duplicate of
#978 (single-PR staleness) or #979 (off-plan work displacing the plan).

### 5. Off-plan work landed uncheckpointed, a second sprint running

PR #1220 (cron-rerun, merged 2026-08-08) is real, valuable work, absent
from both `checkpoint.json`'s stale `issues[]` list and sprint 4's plan —
the same shape as sprint 3's #725/#731/#878. Already tracked by #979
(open, unchanged); confirming here only that the gap recurred a second
sprint with no mechanism yet built to close it.

## Efficiency engineer's cost review

`factory-ops/cost/` still holds exactly **one** record
(`2026-07-25-observability-icculus.json`) — unchanged since before sprint 1
began, despite `docs/ROADMAP.md` M3 explicitly naming "cost telemetry
recorded per station... and the routing table revisited with real data at a
retro" as a sprint-3-hardening item. Meanwhile this sprint's review-loop
volume is the highest yet recorded: PR #444 accumulated 33 review rounds
total (opus/high effort per `factory-ops/cost/ROUTING.md`'s PR-review row),
PR #1054 four more, plus the board session's own proposer/panelist/synthesis
calls (opus/high/**ultracode-on** per the routing table's judge-panel row —
the single most expensive tier this factory runs). None of it has a cost
record. The gate this sprint spent the most compute defending — the
tech-debt count — is also the one metric with zero cost-per-outcome
visibility, which is exactly backwards for a program whose second pillar is
token efficiency: the busier the review loop gets, the more expensive not
measuring it becomes. Not a new issue — **#437** already tracks the
original gap and remains open, unaddressed, four sprints in — but the
retro records that the gap is compounding, not static.

## New issues filed this retro

- **#1443** (P0, tech-debt) — ADR 0006 §D8's review freeze on PR #444 has
  no mechanical enforcement.
- **#1444** (P1, tech-debt) — no round-cap/escalation trigger for
  unconverged-but-real-delta review churn (generalizes #978).
- **#1445** (P1, tech-debt) — committed-core capacity structurally drains
  to one headline item, starving smaller carried items two sprints
  running.

Checked and confirmed already filed, not duplicated: **#980** (the
manufacture-vs-resolve umbrella), **#1342** (D7 disposal-lane batch
mechanics), **#979** (off-plan-work reconciliation), **#978** (PR #318
staleness), **#981/#709** (verify-and-close paperwork), **#437** (cost
telemetry).

## Carryover recommendation for sprint 5

Not this retro's call to finalize (that's sprint 5 planning) but stated for
the record: sprint 5 is **not** a board sprint (the next mandatory
convening is sprint 8) — the board session already happened this cycle. The
carryover items are: a bounded (not open-ended) decision on PR #1054;
#442/#419/#420 entering a third sprint, now sequenced explicitly ahead of
any single large item per #1445's finding; actually executing the #132
reassignment; and flagging `docs/ROADMAP.md` M3's board-session checkbox
for the architect (substance shipped, checkbox unflipped — the same class
of gap #159/M2 carries from sprint 3).
