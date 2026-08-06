# Sprint 3 — Review

- **Sprint:** 3
- **Plan:** `factory-ops/sprints/3/plan.md`
- **sprint_ends_at:** 2026-07-30T23:10:00Z
- **Review held:** 2026-08-05T21:32:46Z (UTC) — **~142 hours (~5 days 22
  hours) past the boundary.** Sprint 3's `sprint_ends_at` passed with no
  review, no retro, and no sprint 4 plan for six calendar days; this is a
  strictly worse instance of the exact failure mode sprint 2's review found
  (#459, "plan merged 2h12m after boundary") — the ceremony didn't just run
  late this time, it didn't run at all until this wake. Root cause below
  under "What actually happened instead," not repeated here.
- **Reviewer:** planner session, verified against live GitHub issue/PR state
  via `gh api`-equivalent (`curl` + `$GH_TOKEN` against the REST/Search
  APIs — `gh` itself is not installed in this runner) rather than taken on
  trust from `factory-ops/state/checkpoint.json`, which is itself five
  commits behind current `main` (see "Trust gaps").

## Planned vs. shipped

Committed core (5 items, the sprint's actual closeable-capacity claim):

| # | Planned outcome | Actual state | Verdict |
|---|---|---|---|
| #442 | `guard-commit`/`record-green` resolve `PROJECT_DIR` to the main checkout, not the worktree | **OPEN** — no fixing PR merged | not started |
| #419 | `debt-reconcile.sh:18` unbounded `gh issue list`, caps count at 30 | **OPEN** — no fixing PR merged | not started |
| #420 | `hooks/lib/common.sh:582` same bug, `/factory-status` banner | **OPEN** — no fixing PR merged | not started |
| #423 | PR #311's `secrets: inherit` removal hard-fails the reviewer's token mint | **OPEN** — bug unfixed; PR #311 still open, `mergeable_state: behind` | not started |
| #100 | Permission ceilings bound to actual token use | **CLOSED** — PR #441 merged 2026-07-31T20:58:54Z (`4414ac3`) | **SHIPPED** |

**1 of 5 committed-core items (20%) shipped by actual merge.** #100 took
two rounds of `CHANGES_REQUESTED` before landing: round 2 (2026-07-31) found
three real correctness gaps in the new static check
(`tests/static/security-ceiling-check.py`) — #625 (over-privilege check only
looped the four hardcoded rows, silently missing undocumented
release/orchestrator/security roles), #626 (`discover_session_jobs` keyed
jobs by `station:`, silently dropping one of two jobs sharing a station
string from every check), #627 (the environment-vs-documented-role check was
pre-filtered by the exact value it compared against — dead code, could never
fire). All three were fixed on the same branch (commit `af44db3`, four new
regression fixtures added) before merging clean. This is the
review→tech-debt convention and the adversarial-review loop working exactly
as designed — flagged in "What went well" territory, not a defect.

This 20% is between sprint 1's 3-of-9 (~33%) and sprint 2's 0-of-5, not an
improvement on the trend once #459's own root cause (a ceremony that eats
its own window) is accounted for: the plan (`7e3c5ce`) itself only merged
at the very start of the window, and the one item that shipped was already
mid-flight (PR #441 open since sprint 2) rather than newly started.

Overflow (8 items, capacity-driven, only reached if core finishes early):

| # | Planned outcome | Actual state | Verdict |
|---|---|---|---|
| #101 | Review station off `bypassPermissions` | **OPEN** | not started |
| #120 | `secrets: inherit` removed from inbound stations | **CLOSED — still falsely.** Plan's own "first action: reopen #120" was never executed; issue still shows `closed_at: 2026-07-29T04:30:45Z`, unchanged since before this sprint began. Real fix (PR #311) still open. | **not shipped, and the false-closure got worse** — now six days stale on top of the original miscount |
| #132 | Review job drops `issues:write`/`secrets: inherit` | **OPEN** — PR #318 unchanged, `mergeable_state: dirty`. Now a filed **P0 incident, #978**: zero state delta across 3 consecutive sprints (2026-07-25 to 2026-08-05) | not started — staleness now formally escalated |
| #342 | Stations exit RED on a usage limit | **OPEN** | not started |
| #361 | `factory-run.yml` standup step + boundary-check precondition | **OPEN** | not started — directly relevant, since its absence is part of why this six-day gap went uncaught (see retro) |
| #459 | Sprint-2 ceremony-lateness fix | **OPEN** | not started — its own root-cause pattern then repeated worse (see above) |
| #94 | `/factory-init` bootstrap chicken-and-egg on `.factory/config.json` | **OPEN** | not started |
| #95 | Green-receipt mint/check location asymmetry for worktree commits | **OPEN** | not started |

Already-delivered, disposed as verify-and-close: **#159** — **still OPEN**,
third consecutive sprint this exact disposition ("cheapest item on this
plan") was never executed. Now tracked as a process pattern, not a one-off:
**#981** ("'already-delivered, verify-and-close' plan items have no forcing
function") and **#709** ("cheap paperwork dispositions have no execution
owner") — both pre-existing, not re-filed here.

Tech-debt burndown bucket (product owner's, not counted against
committed-core capacity): **triage pass 1 never executed** — confirmed
already tracked as **#742** ("sprint-3's triage-pass-1 tech-debt-labeling
bucket never executed — zero-signal backlog grew instead"), not re-filed.
The zero-priority-signal count moved from 204 (planning time) to **591**
(this review) — see "Trust gaps" below for why the raw count moved even
further than that.

Blocked-on-human (unchanged, excluded from capacity): #115, #228 — still
open, still blocked on the org-admin `actions:read` grant. No new evidence.

## What actually happened instead (off-plan work that landed)

None of sprint 3's own picks beyond #100 shipped, but real work did land in
this window — all of it off-plan, and none of it reconciled into any sprint
file or `checkpoint.json` until now:

- **#725** ("CI sessions restart from zero after a failure") — closed
  2026-08-04, explicitly **user-set #1 priority, ahead of all other factory
  work**. This is a legitimate human override of the sprint queue, not a
  process failure by itself — GOVERNANCE.md's human kill-switches and
  direct-priority path exist for exactly this. What's missing is anything
  that *reconciles* the displaced sprint plan afterward (see "Trust gaps").
- **PR #731** (`8dae11a`, merged 2026-08-04T11:15:37Z) — "failed sessions
  resume on rerun instead of re-paying from zero," the #725 implementation.
- **PR #878** (`c824678`, merged 2026-08-04T21:34:33Z) — fix-forward on
  #731, closing **#877** ("session-resume post step reads the helper from
  the mutable workspace"), found within hours of #731 shipping.
- **PR #421** (`bc31383`, merged 2026-08-04T10:41:30Z) — "fail the CI run
  when a session lands no real deliverable." Not linked to #725/#731 by any
  closing keyword; a freestanding fix, also off this sprint's plan.

All three PRs are real, valuable, TDD-disciplined work (each has its own
green suite run per the commit contract). The problem is not that they
happened — it's that **`factory-ops/state/checkpoint.json` still reads
`sprint: 3`, `sprint_ends_at: "2026-07-30T23:10:00Z"` and lists issues
`[100, 101, 311, 318, 342, 361, 419, 420, 423, 442, 625-629]`** — four
commits behind current `main` (`d2e1a83`), with no trace of #725/#731/#878/
#421 anywhere in it. Anyone reading checkpoint.json as ground truth would
not know this work happened at all.

## Trust gaps

1. **#120 is still falsely closed, now six days longer than sprint 2's
   review found it.** The sprint 3 plan's own overflow row named "reopen
   #120" as its required first action; that action was never taken. Real
   fix (PR #311) is still open, `mergeable_state: behind`. Already tracked:
   **#452** (the original false-closure), **#474**/**#580** (the "buried in
   deferrable overflow with no unconditional owner" pattern that explains
   why the reopen never happened — #474 has since been closed but #580
   remains open making the same point). Not re-filed.
2. **`checkpoint.json` staleness compounded by off-plan work with no
   reconciliation mechanism.** Filed this session (immediately preceding
   this review, by the product owner's ground-truth pass): **#979**
   — "no mechanism reconciles the active sprint plan when human-injected
   priority work (#725-style) displaces it — an explicit overdue-ceremony
   flag went unactioned for 4+ days across 3+ wakes." This is the review's
   own finding above, already filed; not duplicated.
3. **The tech-debt count crisis is the dominant finding of this review
   period.** Ground truth (paginated GitHub Search API) at review time:
   **754 open `tech-debt` issues, 12 open `bug` issues** — not the
   221–289 range still cited in some docs. Root cause: **PR #444**
   (the M4 gate-scope redefinition / ADR 0005) has been re-reviewed
   **20 times since 2026-07-30 without merging** (22 commits, still open,
   `mergeable_state: behind`). Each unconverged adversarial-review round
   mass-duplicates findings because **`tech-debt-clerk`'s fingerprinting
   diverges from the connector's canonical `techdebt_audit`/
   `fingerprintFinding`** — filed this session as **#471** (CONFIRMED) and
   confirmed pre-existing at **#688** — so `/review`'s tech-debt filing
   cannot recognize its own prior findings as already-filed, and the same
   divergence self-blocks `debt-reconcile`'s Stop hook on every pass. This
   has driven the open count from **289 → 754 in six days (~465 net new)**,
   almost certainly mostly duplicate. Filed this session as the umbrella
   finding: **#980** — "PR #444/ADR 0005 has absorbed 500+ tech-debt
   findings across repeated unconverged adversarial-review rounds without
   merging — route to judge-panel instead." **This is actively bleeding
   right now**: the M4 Release Gate ("zero open bug/tech-debt") gets
   further away, not closer, every time anyone reviews PR #444. Sprint 4's
   plan makes stopping this the top committed-core item.
4. **PR #318 (#132's fix): zero state delta across three consecutive
   sprints (2026-07-25 → 2026-08-05).** Sprint 3's own plan named this the
   clearest staleness case and set a reassignment trigger if it recurred a
   third time; it did. Filed this session as **#978** (P0 incident). Sprint
   4 plan reassigns per that finding.

## Eval report

Still none. `factory-ops/qa/` is unchanged from sprint 2 — `.gitkeep` only.
M2's eval bullets remain unstarted, consistent with `docs/ROADMAP.md` M2
showing 0 checked eval-related boxes. Separately noted (not this review's
call to fix): `docs/ROADMAP.md` M2's "Static validation layer in the commit
gate: manifest + frontmatter schema" line is **already done in substance**
— PR #375/commit `3fb17dc` (merged 2026-07-28) implemented it fully and it
is wired into `tests/run-suite.sh`; the checkbox was simply never flipped.
Flipping it is an architect action (merged-green-proof roadmap discipline
per `.claude/CLAUDE.md`), not this review's or this planner's to do by hand
— noted here and in sprint 4's plan as a known gap.

## What did NOT land, and why

- **#442, #419, #420, #423** (4 of 5 committed core) — never got a session
  turn. The plan (`7e3c5ce`) merged essentially at the start of the
  22:55–23:10 window on 2026-07-29; the only item that progressed (#100)
  was already mid-flight from sprint 2. No implementer session appears to
  have picked up the other four before #725 became the user's explicit #1
  priority and displaced the queue on 2026-08-01+.
- **#120** — see "Trust gaps" #1. The plan's own required first action
  (reopen it) was never executed; it is not even tracked as "not started,"
  it is actively mis-tracked as done.
- **#101, #132, #342, #361, #459, #94, #95** (overflow) — correctly not
  reached; core never finished. #132/PR #318 crossed the staleness
  threshold sprint 3's own plan set and is now a P0 incident (#978).
- **#159** — third consecutive sprint the verify-and-close disposition was
  named as this sprint's cheapest item and not executed. See #981/#709.
- **Triage pass 1** (product owner's tech-debt-labeling bucket) — never
  executed; see #742. The zero-signal count grew instead of shrinking
  (204 → 591), compounded by the #444 review-cycle duplication crisis
  above.
- **#115/#228** — unchanged, still blocked on the same human grant.

## New issues found this review

All findings this review period were already filed (by the product owner's
ground-truth pass and prior review sessions) before this review was
convened: **#979**, **#980**, **#471**, **#688**, **#978**, **#452/#474/
#537/#580** (the #120 false-closure lineage), **#981/#709** (verify-and-
close paperwork pattern), **#742** (triage-pass-1 non-execution). This
review confirms and cites each rather than re-filing. No genuinely new
finding surfaced beyond what is captured above.

## Carryover recommendation for sprint 4

Not this review's call to finalize (that's sprint 4 planning) but the
evidence: sprint 4 should lead with stopping the tech-debt bleed (#471/#688)
and convening the board (`GOVERNANCE.md`: sprint 4 is the mandatory 4th-
sprint board session) over PR #444/ADR 0005's contested gate-scope
redefinition, since every review cycle on that PR while unconverged is
actively making the M4 gate worse. Sprint 3's unfinished committed core
(#442/#419/#420/#423) and the still-falsely-closed #120 carry forward.
Given three sprints of evidence (33% / 0% / 20% committed-core throughput),
size sprint 4's committed core conservatively.
