# Sprint 4 — Review

- **Sprint:** 4
- **Plan:** `factory-ops/sprints/4/plan.md`
- **sprint_ends_at:** 2026-08-06T21:32:46Z
- **Review held:** 2026-08-12 (this wake) — **~131 hours (~5 days 11 hours)
  past the boundary.** A smaller overrun than sprint 3's ~142 hours but the
  same underlying gap (#361/#979: no standup step, no boundary-check
  precondition) — this ceremony still didn't fire on its own.
- **Reviewer:** planner session, verified against live GitHub issue/PR state
  via `curl` + `$GH_TOKEN` against the REST/Search APIs (`gh` is not
  installed in this runner), not taken on trust from
  `factory-ops/state/checkpoint.json` (itself still pinned to `sprint: 3`,
  `689e785`-era, several commits behind current `main`).

## Planned vs. shipped

Committed core (5 items):

| # | Planned outcome | Actual state | Verdict |
|---|---|---|---|
| #471 / #688 | `tech-debt-clerk` fingerprint idempotency fix | **OPEN** — PR #1054, 4 rounds of `CHANGES_REQUESTED` (2026-08-06, 08-07, 08-08, 08-11), unconverged after 5+ days. Round 4 found genuine meta-bugs *in the fix's own dedup logic* (#1354: `sameProblem`'s `>0.8` ratio guard can't mathematically exclude the `(N-1)/N` case it claims to close; #1362: `extractFingerprint` first-match-wins misparses an issue that quotes a hash before its real trailer — live-reproduced against the review's own freshly-filed #1354). | **not shipped** — the sprint's declared top priority |
| — | Board session: `/judge-panel` over PR #444/ADR 0005 | **SHIPPED** — PR #1107 merged 2026-08-12T03:28:52Z, **ADR 0006** ("Release Gate synthesis"), three stance-pinned proposals + three adversarial ballots (`docs/adr/0006-panel/`) resolving all **nine** panel-CONFIRMED fatal flaws with a named decision owner (architect for gate *mechanism*, product-owner for gate *scope* per ADR 0005, carried in the same PR). Per D8, PR #444 correctly reduced to a docs-only conformance-residue diff (80 additions / 13 deletions / 9 files, down from ~280 normative lines). | **SHIPPED** |
| #442 | `PROJECT_DIR` worktree resolution | **OPEN** — no session turn | not started |
| #419 | `debt-reconcile.sh` unbounded `gh issue list` | **OPEN** — no session turn | not started |
| #420 | same bug, `/factory-status` banner | **OPEN** — no session turn | not started |

**1 of 5 committed-core items (20%) shipped — the board session.** Same rate
as sprint 3 (20%), still below sprint 1 (33%), and this is now **two
consecutive sprints flat at 20%** with the *same three carried bug fixes*
(#442/#419/#420) getting zero session turns in either sprint — filed as a
new pattern-level finding this review (**#1445**, see below).

Required, non-deferrable action from sprint 4's plan: **#120 stays reopened**
— confirmed live (`state: open`), no relapse into the false-`completed`
closure sprint 3 found. Real fix (PR #311) remains open, blocked on #423,
`mergeable_state: unknown`.

## What actually happened instead (off-plan work that landed)

- **PR #1220** ("cron-rerun — automated limit-window recovery," merged
  2026-08-08T17:18:59Z) — closes what its own title calls "the last
  babysitter gap." Not on sprint 4's committed-core or overflow list, and
  `checkpoint.json`'s stale `issues[]` array has no trace of it — same
  reconciliation gap sprint 3's retro found for #725/#731/#878, tracked by
  **#979** (still open), not re-filed.
- **PR #982** (sprint-3 review/retro + sprint-4 plan itself, merged
  2026-08-06T15:54:25Z) and **PR #1055** (checkpoint chore, merged
  2026-08-06T07:58:38Z) — this sprint's own planning ceremony landing at the
  very start of the window, same pattern as prior sprints.
- **PR #1010** ("put `.github/scripts` under the tests-first and typecheck
  gates," merged 2026-08-05T23:36:29Z) — minor infra chore, off either
  sprint's plan.
- **PR #1415** ("check off static validation layer item (#375)," the M2
  roadmap checkbox #159 names) — **still open**, `mergeable_state: behind`
  (based on pre-ADR-0006 `main`). This session pushed a fix for its one
  `CHANGES_REQUESTED` finding (missing inline PR provenance on the checkbox)
  during this same wake. **In flight, not done** — and note it does not
  itself close #159 (see "Trust gaps" below).

## Trust gaps

1. **The tech-debt bleed sprint 4 was built to stop got *worse*, not
   better.** Open `tech-debt`: 289 (sprint-2 review) → 754 (sprint-4 start,
   ADR 0006's own baseline) → **1188 today** (+434 since sprint-4 start,
   **+57%**) — while #471/#688, sprint 4's declared single highest-priority
   "stop the bleed" item, sat unmerged the entire sprint. **302 tech-debt
   issues were filed since 2026-08-06 alone.** Open `bug` held flat at 12
   (unchanged) — the growth is entirely in `tech-debt`, i.e. entirely
   review-loop output, not new defects.
2. **New, live finding: the board's own freeze has no mechanical
   enforcement.** ADR 0006 §D8: *"the sprint-4 review freeze holds ... no
   further ordinary adversarial rounds on the gate design."* ADR 0006
   merged 2026-08-12T03:28:52Z. At **04:00:01Z — 31 minutes later** — a full
   3-lens adversarial review ran against PR #444 anyway (`CHANGES_REQUESTED`,
   its 33rd round) and filed **10 more tech-debt issues** (#1433–#1442)
   against the 93-line conformance-residue diff. A board decision that says
   "freeze review" has no effect if nothing downstream reads the freeze.
   Filed this review as **#1443** (P0).
3. **#132/PR #318 reassignment, ordered by sprint 4's own plan, never
   executed.** Sprint 4's plan cited #978 (P0 incident: zero delta across 3
   sprints) and said security-steward should re-specify a fresh branch. PR
   #318 is **unchanged since 2026-07-25** — now 18 days stale, #978 still
   open. A plan *naming* a reassignment isn't the same as one happening;
   this needs an actual session turn in sprint 5, not another plan note.
4. **#159 "verify-and-close" — 4th sprint this disposition was named,
   still not closed.** PR #1415 (in flight) flips the roadmap checkbox but
   its body does not close #159 itself. If #1415 merges without a
   follow-up close, this becomes a 5th-sprint recurrence of the pattern
   #981/#709 already track (cheap paperwork loses to real work) — flagged
   for sprint 5, not re-filed as a new issue.

## Eval report

Still none. `factory-ops/qa/` is unchanged — `.gitkeep` only. M2's eval
bullets remain 0 checked in `docs/ROADMAP.md`.

## What did NOT land, and why

- **#442, #419, #420** (3 of 5 committed core) — zero session turns. Capacity
  went to the board session (mandatory, large, legitimately time-consuming)
  and to iterating PR #1054 (P0 stop-the-bleed item). Reasonable
  prioritization in the moment, but the effect — three cheap, well-scoped,
  twice-carried bug fixes never touched — is now a filed pattern
  (**#1445**).
- **Overflow** (#423, #101, #342, #361, #459, #94, #95, #229, #422) —
  correctly not reached; core never finished this sprint either.
- **#115/#228** — unchanged, still blocked on the org-admin `actions:read`
  grant. No new evidence.

## New issues found this review

Filed this review, each checked against live GitHub state and confirmed not
already tracked under this framing:

- **#1443** (P0) — ADR 0006 §D8's review freeze on PR #444 has no mechanical
  enforcement; `/review` filed 10 more tech-debt issues 31 minutes after the
  ADR merged.
- **#1444** (P1) — no round-cap/escalation trigger for a PR stuck in
  unconverged-but-real-delta review churn (generalizes #978, which only
  covers zero-delta staleness); PR #1054 is the live instance.
- **#1445** (P1) — committed-core capacity structurally drains to one
  headline item; #442/#419/#420 carried untouched into a 3rd sprint across
  sprints 3–4.

Already tracked, not re-filed: **#1342** (D7's one-time disposal lane for
the ~465 superseded-draft findings has no batch mechanics yet — the
`factory-ops/release/disposals/` directory does not exist, confirmed this
review), **#979** (off-plan-work reconciliation), **#978** (PR #318
staleness), **#981/#709** (verify-and-close paperwork pattern), **#437**
(cost telemetry gap — see retro).

## Carryover recommendation for sprint 5

Not this review's call to finalize (that's sprint 5 planning) but the
evidence: sprint 5 should make a **bounded** decision on PR #1054 rather
than a fifth open-ended round (continue one capped round, or re-scope to a
minimal-diff fix and defer the meta-refinements as tracked tech-debt);
carry #442/#419/#420 into their **third** sprint, now with #1445's
sequencing finding in hand; actually execute the #132/PR #318 reassignment
sprint 4 only planned; and flag `docs/ROADMAP.md` M3's "Board session #1"
checkbox for the architect to flip (substance shipped via ADR 0006/PR
#1107, checkbox unflipped — same class of gap #159/M2 was last sprint).
