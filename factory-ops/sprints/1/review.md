# Sprint 1 — Review

- **Sprint:** 1
- **Plan:** `factory-ops/sprints/1/plan.md`
- **sprint_ends_at:** 2026-07-25T02:42:24Z
- **Review held:** 2026-07-28 (~74h / ~3 days past the boundary — see retro for why)
- **Reviewer:** planner session, verified against live GitHub state at review time
  (issue/PR states, check-runs, workflow-run history — not taken on trust from
  the checkpoint or PR bodies, both of which are independently shown to be
  unreliable this sprint; see "Trust gaps" below).

## Planned vs. shipped

Plan order was #175, #97, #98, #100, #101, #120, #132, #115, #159 (stretch).

| # | Planned outcome | Actual state | Verdict |
|---|---|---|---|
| #175 | Roadmap cursor fixed, M1 6/6 | **CLOSED**, merged | shipped |
| #97 | Reviewer gets a write-capable token | **CLOSED**, merged | shipped |
| #98 | `--merge` policy fixed | **CLOSED**, merged | shipped |
| #100 | Permission ceilings bound to actual token use | **OPEN** | not started |
| #101 | Review station off `bypassPermissions` | **OPEN** | not started |
| #120 | `secrets: inherit` removed from inbound stations | **OPEN** — fix exists in **PR #311** (open, unmerged) | in flight, stuck |
| #132 | Review job drops `issues:write`/`secrets:inherit` | **OPEN** | not started (bundled into #311's series per plan, but #311 hasn't landed) |
| #115 | coder App gets `actions:read` | **OPEN** | not started — **and was wrongly marked done**, see below |
| #159 | Stretch: static validation layer in commit gate | **OPEN** | not started (correctly deferred — it was always the stretch slot) |

**3 of 9 shipped** (#175, #97, #98 — exactly the plan's items 1–2, the
roadmap-truth and loop-closing floor). **1 of 9 has a fix in flight but
unmerged** (#120, via PR #311). **5 of 9 never started** (#100, #101, #132,
#115, #159), including three P0 security items (#100, #101, #132) the plan
called "highest severity" and sequenced right after the loop fix.

Verified directly against the GitHub API at review time (issue `state` field
per number above); this contradicts the claim recorded in PR #318's body that
"#175/#97/#98/#115 verified already merged-green and closed by hand" — #115 is
open. That discrepancy is tracked as tech-debt **#323** (already filed by an
earlier adversarial review of #318; not re-filed here).

## What's stuck, and why

### PR #311 — closes #120 (secrets: inherit fix)

Open since 2026-07-25T01:16Z. `mergeable: true`, but `mergeable_state: behind`
and the combined status is **`pending`** — the `review / session` check-run
shows `failure`, and no other reviewer verdict has landed. Log evidence (job
`89637802508` and neighboring runs) shows the review station hit the
account's **429 usage-limit wall** repeatedly starting 2026-07-25T03:28Z
("You've hit your weekly limit · resets Jul 28, 4am (UTC)") — the review
never completed, so the check sits `pending`/`failure` rather than ever
resolving, and nothing re-triggers it. This is exactly the gap already
tracked in **#237** ("stalled reviews are not resumed after a 429, only
`factory-run` is") and **#342** ("stations exit RED on a usage limit,
which the repo's own usage-limit law forbids") — both pre-existing and not
re-filed here.

### PR #318 — checkpoint update, stacked on #311's branch

Open since 2026-07-25T01:49Z. Carries a **CHANGES_REQUESTED** review from
`dsf-reviewer-mreyratnz[bot]` (submitted 2026-07-25T02:07Z) that has never
been addressed — no commits, no reply, no re-review since. `mergeable_state:
behind` (main has moved since, via #329). Its own body contains a factual
error (the #115/#120 false-closure claims, #322/#323) that would itself need
fixing before merge. Net effect: **the checkpoint on `main` has not moved
since sprint planning** — it is still the 2026-07-24 planning-time file
(`next_action: factory-run`, notes say "start #175," which is closed). Every
downstream ceremony trigger that reads `factory-ops/state/checkpoint.json`
has been reading that stale file for 3+ days.

Neither PR has been reassigned or escalated despite the plan's own
staleness rule ("three consecutive wakes with no state delta reassigns the
owner and files a P0"). See retro for why.

### PR #250 — no-op detection guard (draft)

Confirmed **stale/supersedable**: its own author split the behavioral half
out into **PR #303** ("Split out of #250 so the behavioural fix for #228 can
be shipped and verified on its own"), which merged 2026-07-25T00:59Z
(commit `fe9c131`). #250's remaining scope (`claude-session.yml` no-op
`require_progress` guard, `scripts/session-progress.mjs`) was **not** carried
by #303's diff — #303 only touched the workflow prompt. #250 is `draft`,
`mergeable_state: dirty` (conflicts against current `main`), untouched since
2026-07-25T00:48Z. Recommend closing or rebasing-and-finishing in sprint 2;
this review does not decide which — that's implementer/release-captain
discretion per the plan's own routing note.

## Off-plan work that consumed real capacity

A parallel **observability epic** (OTEL collector + self-hosted Langfuse on
the `icculus` runner) was **not** in the sprint-1 plan or backlog at all, yet
consumed the sprint's actual wall-clock capacity:

- **PR #329** opened 2026-07-25T02:27Z — after both #311 (01:16Z) and #318
  (01:49Z), and about an hour before the weekly usage ceiling hit
  (03:28Z). It sat unmerged through the entire 3-day stall alongside
  #311/#318, then became the **first thing to land** after the weekly limit
  reset (2026-07-28T04:00Z UTC) — merged 2026-07-28T11:14Z as commit
  `a9cd802`.
- **PR #359**, a review follow-up on #329, opened 2026-07-28T11:23Z — nine
  minutes after #329 merged.
- A large wave of ~100 tech-debt issues (#249–#358) landed from adversarial
  reviews of PR #162 (egress proxy), PR #250, PR #311/#318, and this
  observability work — real findings, but volume the sprint-1 plan did not
  size for.

The material point for review: across at least **four separate successful
`factory-run` wakes after the weekly-limit reset** (2026-07-28T06:33,
09:41, 16:45, and one in-progress at 18:20 UTC), the loop did **not** resume
#311/#318 or hold the overdue sprint-1 review/retro ceremony — the only
commit that landed in that window was the off-plan observability merge.
`sprint_ends_at` (2026-07-25T02:42:24Z) had been in the past the entire time.
This is a distinct process gap from the already-filed checkpoint-data-honesty
issues; see retro for the new issue filed against it.

## Trust gaps this review had to route around

- `factory-ops/state/checkpoint.json` on `main` is 4 days stale and cannot be
  used as a source of truth for "what happened" — this review used the
  GitHub API directly (issue/PR state, check-runs, workflow-run history)
  instead.
- PR #318's body (the closest thing to an end-of-sprint-1 status write-up)
  contains two false closure claims (#115, #120/#311) — already tracked as
  #322/#323, not re-verified here beyond confirming both are still accurate
  as of 2026-07-28.

## Gate status

The v1.0.0 Release Gate is untouched this sprint — #159 (the only picked
item that touches Epic 1 gate substance) never started. No release was cut;
none was planned for sprint 1.
