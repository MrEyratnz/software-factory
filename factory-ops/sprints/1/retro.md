# Sprint 1 — Retro

- **Sprint:** 1
- **Retro held:** 2026-07-28, immediately after `review.md` (same planner
  wake), ~74h late relative to the boundary.
- **Board cadence:** per `GOVERNANCE.md`, the board convenes "every 4th
  sprint." Sprint 1 is not a board sprint — noted for the record, no board
  session required here.

## What went well

- The plan itself held up. Ordering the floor as roadmap-truth (#175) →
  loop-closing pair (#97/#98) → security cluster (#100/#101/#120/#132/#115)
  → stretch (#159) was the right shape: the three items that *did* ship are
  exactly the two highest-priority tiers, in order, and #120's fix (PR #311)
  exists and is real work, not abandoned — it's blocked on infrastructure,
  not on someone dropping it.
- The plan's "Flagged for early sequencing" note correctly called out PR
  #162 (egress proxy) as sprint-relevant-by-inspection even though it wasn't
  a picked issue; it merged as commit `c5256a4` ahead of most of the
  sprint's own items, exactly as recommended.
- Adversarial review is doing its job: the false claims in PR #318's body
  (#115 and #120/#311 both wrongly marked closed) were caught by a review
  pass on #318 itself and filed as #322/#323 before this retro ever ran —
  the review→tech-debt convention worked even while the ceremony loop was
  stalled.

## What went wrong

### 1. The ceremony didn't fire for 3+ days — root cause is usage-limit exhaustion, not a checkpoint bug

Filed as incident **#360** (P0) with the full chronology. Short version: the
factory hit its **weekly** Anthropic usage limit at 2026-07-25T03:28Z
(right after PR #311/#318/#329 were all opened within the same ~20-minute
window) and didn't clear until 2026-07-28T04:00Z. Every `factory-run` job in
between 429'd on turn 0-1 — before any bash could execute, so **no session
in that window could even attempt the documented usage-limit checkpoint
protocol**. This is the dominant cause of the 3-day silence, not a defect in
this planner's own logic or in the checkpoint's schema.

This is **already tracked** as **#342** ("Stations exit RED on a usage limit,
which the repo's own usage-limit law forbids") and **#237** ("Better
post-usage-reset resume ... auto-retry stalled reviews") — both pre-existing,
both correctly diagnosing the mechanism, neither re-filed here. What *is*
new: even after the weekly limit cleared, the ceremony **still** didn't fire
for at least 4 more successful wakes, because `factory-run.yml`'s prompt has
no standup step at any cadence and lets step-1 "parked work" (in this case,
the off-plan observability PR) preempt the step-2 boundary check
indefinitely. Filed as **#361**.

So: is the checkpoint-never-updated symptom the same gap as **#327**
(checkpoint bakes a stale "boundary not reached" claim)? **No — distinct.**
#327 is about the checkpoint's *content* being wrong when it *is* written.
What actually happened this sprint is the checkpoint was **never written at
all** after planning, for two different reasons stacked on top of each
other: (a) no session had any turns for 3 days (#342/#237's territory), and
(b) once turns came back, the prompt's own control flow still didn't reach
the ceremony branch (#361's territory). Both needed filing; neither was
covered by #327.

### 2. #311/#318 sat stuck for 3 days with no reassignment, despite the plan's own rule

The plan's "Reassignment / staleness note" says three consecutive wakes with
no delta reassigns the owner and files a P0. That rule lives in the
*standup* ceremony — and standup never ran (see #361: it isn't wired into
the loop at any cadence, not even during an active sprint). So the rule
existed on paper but had no mechanism to execute it. This isn't a case of
someone ignoring the rule; it's a case of the rule's trigger never being
built. #360 is the P0 this retro files in its place, late but per the fence
charter's own instruction ("stop planning retries — file a P0 incident and
hand the next session root-cause mode").

Separately, PR #311's specific stuck-ness has its own proximate cause:
its `review / session` check-run itself 429'd and was never retried
(#237's exact scenario), so the check sits `pending`/`failure` with no path
to green short of a manual re-trigger. PR #318 is stuck differently — a real
`CHANGES_REQUESTED` review that nobody (human or agent) has had a turn to
act on, compounded by #318 having been authored via the GitHub API (not a
local commit) because of the active-agent lockout bug **#314** (already
filed, not re-filed here).

### 3. Off-plan work is a repeatable risk, and this sprint is evidence of it, not just a one-off

The observability epic (#329, #359) was never part of the sprint-1 backlog
or plan — it ran on its own track, concurrently, and won the scarce capacity
that came back after the usage-limit reset: it's the *only* thing that
landed in the entire post-reset window this review inspected, while three
P0 security items and two stuck PRs from the actual sprint plan sat
untouched. Contributing factors, concretely:

- The plan had no WIP limit or explicit statement that off-plan branches
  compete with picked issues for the same scarce agent-turn budget — it
  implicitly assumed the picked issues would get the turns.
- `factory-run.yml`'s step-1 "finish parked work first" instruction doesn't
  distinguish "parked work that is this sprint's own picked item" from
  "parked work that is an unrelated concurrent epic" — both read as
  equally eligible to consume the wake. #361 covers the fix for the
  boundary-preemption half of this; the plan-level half (should the planner
  explicitly rank off-plan branches against the sprint backlog when both are
  in flight) is a planning-process question for sprint 2, not a code fix —
  noting it here rather than filing a redundant issue, since #361 already
  captures the mechanical trigger and the planning answer is "give the
  boundary ceremony a hard precondition," which #361 already proposes.
- This is very likely to recur: nothing currently stops a second concurrent
  epic from doing the same thing to sprint 2. Sprint 2's plan should say
  explicitly what happens when off-plan work is in flight against a live
  sprint (defer it, or explicitly rank it, rather than letting whichever
  branch happens to be unblocked first win the wake).

### 4. Cost/efficiency review

Only one cost record exists under `factory-ops/cost/` for the entire window
this retro covers:
`factory-ops/cost/2026-07-25-observability-icculus.json` — the off-plan
observability work, run at **opus/high** rather than `ROUTING.md`'s default
`sonnet/high` for implementation, justified in the record itself as a
"gnarly implementation epic" escalation. That escalation path exists in
`ROUTING.md` but is explicitly "flagged by planner" — this planner did not
flag it (the work wasn't on this planner's radar at all, being off-plan).
Whether that self-escalation was warranted is a judgment call for the
efficiency-engineer to make with real cost figures; it can't be assessed
from this record alone since `tokens_in`/`tokens_out`/`cost_usd` are all
`null` (an interactive session has no result JSON to read them from — the
record's own notes flag this as fixed once `FACTORY_OTEL_ENDPOINT` is live,
which is what #329 itself stood up). **Zero cost records exist for any of
the actual sprint-1 work** (#175/#97/#98/#311's series) — those ran as
scheduled `factory-run` workflow sessions, which should have populated
`record cost summary` per `claude-session.yml`; their absence from
`factory-ops/cost/` is worth the efficiency-engineer's attention next
sprint, but is not re-filed here as it may simply mean the sessions that
did that work never reached the cost-recording step (plausible given how
much of the window was 429s) rather than a recording defect — needs the
efficiency-engineer's own investigation to distinguish those, not a
planner guess.

## New issues filed this retro

| # | Title | Labels |
|---|---|---|
| **#360** | P0 incident: sprint-1 ceremony never fired — ~70 wakes, 3+ days past `sprint_ends_at` with zero state delta | `P0`, `bug`, `tech-debt` |
| **#361** | `factory-run.yml` never wires a standup step, and step-1 parked work can preempt the sprint-boundary ceremony indefinitely | `tech-debt`, `P1` |

Checked against and **not** duplicated: #327, #320, #321, #322, #323, #325,
#314 (checkpoint-trust findings from the #318 review), #342 (usage-limit red
failures), #237 (post-reset stalled-review resume), #233 (sprint_ends_at
staleness trap), #193 (SPRINT_HOURS-as-capacity-budget ambiguity).

## Carryover recommendation for sprint 2

Not this planner's call to finalize (that's sprint 2 planning, a separate
step) but the evidence is unambiguous: **#100, #101, #120, #132, #115, #159,
and both stuck PRs (#311, #318) should roll forward as sprint-2 carryover**,
ahead of new backlog — they were never actually worked, not deprioritized,
and #100/#101/#132 are the highest-severity items the product owner ranked
this sprint. #250 should be explicitly triaged (close or finish) rather than
carried forward silently. Sprint 2 planning should also decide, up front,
how the sprint treats any concurrently-running off-plan epic so this
sprint's capacity loss doesn't repeat.
