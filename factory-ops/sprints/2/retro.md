# Sprint 2 — Retro

- **Sprint:** 2
- **Retro held:** 2026-07-29, immediately after `review.md` (same planner
  wake).
- **Board cadence:** per `GOVERNANCE.md`, the board convenes "every 4th
  sprint." Sprint 2 is not a board sprint. Sprint 3, planned immediately
  after this retro, is also not a board sprint — **sprint 4 is next.**

## What went well

- The plan itself, once it landed, was well-sequenced: security floor
  (#100/#101/#120) ahead of the two process fixes that caused sprint 1's own
  silence (#342/#361), with an honest 5-item committed-capacity claim
  (finding #365 from PR #362's own review) instead of sprint 1's
  everything-is-a-pick approach. That discipline is worth keeping.
- The review→tech-debt convention kept working under real pressure: PR #362
  itself picked up 4 CONFIRMED-blocking findings (#363–#366) before merge,
  and a same-session review of PR #311 caught a real regression (#423)
  before it could land and break the reviewer station for every future PR.
  Adversarial review is doing exactly what it's for.
- The product owner's independent ground-truth audit (paginated
  `gh api graphql`, PR #444) is a genuinely good catch: it found the exact
  mechanism (`gh issue list` with no `--limit`, defaulting to 30) behind a
  number that had been quietly wrong in two places (`debt-reconcile.sh` and,
  newly discovered, `hooks/lib/common.sh:582` — the status banner every
  session reads). Filing both as P0 (#419, #420) before trusting any
  redefinition of M4 is the right order of operations.

## What went wrong

### 1. Sprint 2's own plan consumed almost the entire sprint window

Sprint 2 was anchored at 2026-07-28T20:00:00Z with a 24h boundary
(2026-07-29T20:00:00Z). The plan PR (#362) did not merge until
**2026-07-29T22:12:42Z — 2h12m *after* its own sprint's boundary**, having
itself needed a full review-and-fix cycle (#363–#366) first. That leaves, at
most, the last couple of hours of a 24h-nominal sprint for any committed-core
work to actually start — which is exactly why 0 of 5 committed-core items
merged (see `review.md`). This is a distinct failure from sprint 1's (total
silence for 3 days); sprint 2's ceremony *did* eventually fire, but so late
relative to its own declared window that it structurally could not have
produced committed-core throughput. Filed as **#459** rather than assumed
to be the same root cause as #360/#361, since those are about the ceremony
not firing at all — this is about the ceremony firing, but late enough to
eat its own sprint.

### 2. An issue was closed while its fix was still open, unmerged, and regressed

#120 — this sprint's own #3 committed-core item — shows `CLOSED` in the
tracker. Its fix (PR #311) is open, unmerged, and (discovered this sprint)
has a real regression blocking it (#423). The closing PR (#405)'s own body
states the fix wasn't merged at the time it closed the issue. Filed as
**#452**. This matters beyond one issue: if the tracker's `state` field can
drift this far from reality, then anything that counts on it — including
the M4 Release Gate's own "zero open bug/tech-debt" criterion, in either its
literal or product-owner-redefined form — inherits the same trust gap the
product owner just spent this cycle fixing for the *count*. A closed-but-
unfixed issue is arguably worse for gate integrity than an uncounted one:
it's invisible to every audit, not just the paginated ones.

### 3. Cost telemetry gap persists, second sprint running, still not filed as its own root-cause fix

Sprint 1's retro found `factory-ops/cost/` contains exactly one record
(`2026-07-25-observability-icculus.json`, off-plan work) and zero records
for any of that sprint's actual picked-issue work, and explicitly declined
to file a new issue pending investigation ("may simply mean sessions never
reached the cost-recording step... needs the efficiency-engineer's own
investigation"). That investigation does not appear to have happened:
`factory-ops/cost/` is **unchanged** — still the same single file, now
covering zero of sprint 2's real work either (#362's fix-and-merge cycle,
PR #441, PR #443's triage session, the product owner's audit). This gap is
**already tracked** as **#437** ("Sprint-1 retro identifies missing cost
telemetry but explicitly declines to file it") — filed by a reviewer of
PR #362 for exactly this reason, so no new issue needed here. What this
retro adds: the gap is now two sprints deep with no cost data for either
sprint's real work, which the efficiency-engineer should treat as urgent —
`ROUTING.md`'s own north-star metrics (cost per merged PR, cost per sprint)
are currently uncomputable for the entire life of this factory.

### 4. Concurrent sessions are colliding on the same PRs

PR #443's body describes discovering that #311 (open since sprint 1)
carries a regression its own author didn't see, and separately that
`/factory-run`'s own arming step has no sanctioned write path (#422) — both
found by a session that was itself triaging *other* sessions' unmerged work
from the last few hours. Multiple sessions are visibly operating on
overlapping scope in tight succession (#362's fix-up, #405's checkpoint,
#443's re-triage, #441's new PR, #444's audit — five PRs opened or merged
within about a 19-hour span, several touching the same underlying issues).
No new issue filed for this pattern itself — it's a capacity/scheduling
question (how many concurrent sessions this factory should run against one
sprint) rather than a code defect, and the single-runner constraint is
already tracked as pre-existing **#177**, not re-filed.

## Efficiency engineer's cost review

Same finding as sprint 1, worse: **zero cost records exist for any
sprint-2 work.** `factory-ops/cost/` has one file, dated before sprint 2
began, for off-plan work. `ROUTING.md`'s stated review cadence ("revisit
with cost data at every retro") cannot be honored — there is no data to
revisit. This is not re-filed (see #437 above) but is escalated in
severity: this is now blocking, not just missing, informed model/effort
routing decisions for sprint 3 and beyond.

## New issues filed this retro

| # | Title | Labels |
|---|---|---|
| **#452** | process: issue #120 was closed by PR #405 while that PR's own body states the fix (#311) is unmerged | `tech-debt`, `P1` |
| **#459** | Sprint-2's own plan (PR #362) merged 2h12m after the sprint's own `sprint_ends_at`, leaving ~0 window for committed-core work | `tech-debt`, `P1` |

Checked against and **not** duplicated: #360, #361 (ceremony-silence
mechanism — distinct from #459's "ceremony fires but too late" finding),
#322 (a different PR's false-claim prose, not an actual issue-state flip
like #452), #423 (the #311 regression itself), #422 (`loop.json` arming
gap), #372 (backlog-growth-outpaces-closure trend), #437 (missing cost
telemetry), #177 (single-runner concurrency constraint).

## Carryover recommendation for sprint 3

Not this retro's call to finalize (that's sprint 3 planning) but stated for
the record: sprint 3 should (a) inherit sprint 2's entire committed core
unchanged since none of it shipped, (b) treat #459 as directly relevant to
how sprint 3 itself gets planned — if this retro/plan cycle also runs long
against a sprint boundary, the pattern repeats a third time, and (c) fold
in the product owner's tech-debt-gate-scope decision (PR #444, #419, #420,
and the untriaged-pool triage prerequisite) as explicitly requested for
this planning cycle.
