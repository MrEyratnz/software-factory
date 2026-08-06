# Sprint 3 — Retro

- **Sprint:** 3
- **Retro held:** 2026-08-05, immediately after `review.md` (same planner
  wake).
- **Board cadence:** per `GOVERNANCE.md`, the board convenes "every 4th
  sprint." Sprint 3 was not a board sprint. **Sprint 4, planned immediately
  after this retro, is the 4th sprint — this is the pre-board retro.** Its
  findings, and the live PR #444/ADR 0005 contested decision, are handed to
  sprint 4's plan as the designated board-convening topic.

## What went well

- **The adversarial-review loop caught real correctness bugs before they
  merged.** PR #441 (#100) took two rounds of `CHANGES_REQUESTED`; round 2
  found three genuine gaps in the new static ceiling-check (#625/#626/#627
  — a silent escape for undocumented roles, a station-key collision that
  dropped jobs from checks, and dead code in the environment check) and all
  three were fixed on-branch before merge. This is the review→tech-debt
  convention working exactly as intended under real pressure, same pattern
  sprint 2's retro praised.
- **The product owner's ground-truth audit discipline continued.** The
  221–289 range quietly cited in older docs was caught against a live,
  paginated count (754 open tech-debt, 12 open bugs) rather than trusted —
  the same practice that caught the #328/#419/#420 undercounting bug last
  sprint. That same discipline is what surfaced this sprint's dominant
  finding (the #444 review-cycle duplication crisis) rather than letting it
  hide behind a stale number.
- **A genuine human-priority override (#725) got acted on fast and well.**
  Two PRs (#731, #878) landed a real session-resume capability within about
  10 hours of each other, with #878 itself a same-day fix-forward on a gap
  #731 introduced — tight, TDD-disciplined turnaround on work that
  materially matters to the factory's own reliability.

## What went wrong

### 1. The sprint ceremony did not fire for six days — a categorically worse instance of #459's pattern

Sprint 2's retro found the ceremony *firing late* (2h12m after boundary,
#459). Sprint 3's ceremony **did not fire at all** for ~142 hours past its
`sprint_ends_at` (2026-07-30T23:10:00Z) until this wake. This is not a new
root cause — it's the same missing mechanism (#361: no standup step, no
hard boundary-check precondition) producing a worse outcome because, this
time, real off-plan priority work (#725) gave every intervening wake a
legitimate-looking reason not to stop and hold ceremony. **Already filed
this session: #979** ("no mechanism reconciles the active sprint plan when
human-injected priority work displaces it — an explicit overdue-ceremony
flag went unactioned for 4+ days across 3+ wakes"). Not re-filed here;
#361/#459 (pre-existing, still open) are the mechanism-level fixes this
depends on, also not re-filed.

### 2. Should the ceremony-skip pattern be formalized rather than silently tolerated?

Yes, and #979 is the concrete answer, not a new question. #725's override
of the sprint queue was itself legitimate — GOVERNANCE.md's human
kill-switches and the "humans interact through issues and PRs like anyone
else" path both anticipate a human redirecting the factory. The actual gap
isn't that override happened; it's that nothing *closes the loop* — no
step re-anchors `checkpoint.json`, re-evaluates the sprint boundary, or
flags "ceremony overdue" as a blocking condition the way a stale green
receipt blocks a commit. #979 already scopes this precisely (adjacent to
#361 in `factory-run.yml`'s dispatch flow). This retro's contribution is
confirming, from the receiving end, that the six-day gap is exactly the
failure #979 predicts — not filing a duplicate of it.

### 3. The tech-debt-count crisis is a compounding-cost bug, not a one-off

754 open tech-debt issues (up from 289 six days ago, ~465 net new) is not
465 new distinct problems — it is a small number of real problems
(dominated by findings against one unmerged PR, #444/ADR 0005) getting
re-filed on every unconverged review round because
**`tech-debt-clerk`'s fingerprint algorithm diverges from the connector's
canonical `fingerprintFinding`** (filed this session: **#471**, CONFIRMED;
pre-existing, confirmed again: **#688**). The mechanism that exists
specifically to make review idempotent — "file each unfixed finding
exactly once, by content fingerprint" — is the thing that's broken, and
it's broken in a way that also **self-blocks `debt-reconcile`'s Stop hook**
on every pass (per #688), meaning the review station is fighting itself on
every single review of PR #444. This is worse than #372's pre-existing
"backlog growth outpaces closure" finding: that trend is closure being too
slow; this is the *counting mechanism itself* actively multiplying the
number to close. Filed this session as the umbrella process finding:
**#980** ("PR #444/ADR 0005 has absorbed 500+ tech-debt findings across
repeated unconverged adversarial-review rounds without merging — route to
judge-panel instead"). Not re-filed; sprint 4 makes #471/#688 its top
implementation priority specifically because every day this stays broken,
the M4 "zero open tech-debt" gate moves further away regardless of any
other work.

### 4. A committed-core item's own required first action silently did not happen

Sprint 3's plan named "reopen #120" as an unconditional first action on an
overflow item, not something deferrable. It was never done during sprint 3
itself — #120 stayed closed for six more days of staleness than sprint 2's
review found, until this same wake's sprint-4 plan finally executed the
reopen directly (2026-08-05T21:38:54Z) rather than deferring it to an
overflow row a second time. Already tracked as a pattern, not re-filed:
**#474**/**#580** ("#120 reopen trapped in deferrable overflow with no
unconditional owner" — #580 still open, making exactly this point). What
this retro adds: the pattern predicted by #580 played out precisely as
described — a plan can name an action "first" in prose without any
enforcement distinguishing it from the rest of an overflow table a session
might never reach.

### 5. Cheap paperwork keeps losing to real work, three sprints running

#159's "verify-and-close" disposition — flagged as "cheapest item on this
plan" in sprint 2's and sprint 3's plans alike — was not executed either
time, third sprint total. Already tracked: **#981** ("'already-delivered,
verify-and-close' plan items have no forcing function") and **#709**
("cheap paperwork dispositions have no execution owner"). Not re-filed;
noting only that three sprints of confirming evidence now exist for both.

## Efficiency engineer's cost review

`factory-ops/cost/` was not re-inspected in depth this retro (out of this
review's evidence-gathering scope, and #437 already tracks the underlying
gap from sprint 1), but the volume of this sprint's off-plan, high-value,
fast-turnaround work (#725/#731/#878, all within ~10 hours) versus the
essentially-stalled committed core (1 of 5 items, and that one already
mid-flight) is itself a cost-routing signal worth naming: whatever
prioritization mechanism let #725 preempt cleanly and execute fast is
functioning well; the mechanism that would have let the *displaced* sprint
plan get reconciled cheaply (rather than silently going six days stale) is
what's missing, and is exactly #979's scope. No new cost-telemetry issue
filed here — #437 remains the tracked gap and appears still unaddressed
(`factory-ops/cost/` was not observed to have grown this session either,
though a full recount was out of scope for this retro).

## New issues filed this retro

None. Every finding this retro surfaced was checked against live GitHub
state and found already filed: **#979**, **#980**, **#471**, **#688**,
**#978** (per the task brief — already filed this session, not re-derived),
plus pre-existing **#452/#474/#537/#580** (#120 false-closure lineage),
**#981/#709** (verify-and-close paperwork), **#742** (triage-pass-1
non-execution), **#459/#361/#342/#193/#233/#235** (ceremony-timing
lineage), **#372/#437/#177** (backlog growth, cost telemetry, single-runner
concurrency). This retro's contribution is confirming each against current
evidence and routing the two live-bleeding ones (#471/#688, and the board
convening over PR #444/ADR 0005) into sprint 4's committed core, not
generating new tickets for problems this repository's own review discipline
had already caught.

## Carryover recommendation for sprint 4

Not this retro's call to finalize (that's sprint 4 planning) but stated for
the record: sprint 4 is the mandatory board sprint (`GOVERNANCE.md`, every
4th sprint). PR #444/ADR 0005's contested M4 gate-scope redefinition is a
natural, ready-made topic for that convening — it is also `docs/ROADMAP.md`
M3's own still-open item ("Board session #1 held via judge-panel with a
synthesized ADR"). Separately and with higher urgency, #471/#688
(fingerprint idempotency) should be sprint 4's top implementation item
regardless of when PR #444 itself resolves, since it is the mechanism
actively causing damage on every review cycle today. Sprint 3's unfinished
committed core (#442/#419/#420/#423) and the still-falsely-closed #120
carry forward. #132/PR #318 should be reassigned per #978's own finding
rather than carried unchanged a fourth time.
