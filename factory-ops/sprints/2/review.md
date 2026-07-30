# Sprint 2 — Review

- **Sprint:** 2
- **Plan:** `factory-ops/sprints/2/plan.md`
- **sprint_ends_at:** 2026-07-29T20:00:00Z
- **Review held:** 2026-07-29T23:05Z (~3h05m past the boundary — the sprint
  planning PR for this very sprint, #362, only merged at 22:12:42Z, ~2h12m
  AFTER its own 20:00:00Z sprint_ends_at boundary; see retro for the
  mechanism)
- **Reviewer:** planner session, verified against live GitHub issue/PR state
  and a fully-paginated `gh api graphql` label count at review time — not
  taken on trust from `factory-ops/state/checkpoint.json`, which sprint 1's
  review already showed to be unreliable and which this review finds is
  unreliable again (see "Trust gaps").

## Planned vs. shipped

Committed core (5 items, the sprint's actual closeable-capacity claim):

| # | Planned outcome | Actual state | Verdict |
|---|---|---|---|
| #100 | Permission ceilings bound to actual token use | **OPEN** — PR #441 open (created 22:51Z, in flight, unmerged) | in flight, not landed |
| #101 | Review station off `bypassPermissions` | **OPEN** — no PR found | not started |
| #120 | `secrets: inherit` removed from inbound stations | **CLOSED** — but the fixing PR (#311) is still **open, unmerged, and has a confirmed regression** (#423: removing `secrets: inherit` breaks the reviewer's app-token mint with no fallback). The issue was closed by PR #405 at the same instant #405 merged, while #405's own body states "Neither #362 nor #311 is merged yet." | **falsely closed — not actually shipped**, filed as #452 |
| #342 | Stations exit RED on a usage limit → checkpoint + exit 0 | **OPEN** — no PR found | not started |
| #361 | Standup step + boundary-check precondition in `factory-run.yml` | **OPEN** — no PR found | not started |

**0 of 5 committed-core items shipped by an actual merge.** One (#120) is
recorded as closed but is not really fixed — see "Trust gaps." One (#100)
has real in-flight work. Three (#101, #342, #361) were never started.

Overflow (3 items, capacity-driven, only reached if core finishes early):

| # | Planned outcome | Actual state | Verdict |
|---|---|---|---|
| #132 | Review job drops `issues:write`/`secrets: inherit` | **OPEN** — PR #318 unchanged since sprint 1 (`mergeStateStatus: CONFLICTING`/`DIRTY`, original CHANGES_REQUESTED still unaddressed) | not started (correctly — core wasn't reached) |
| #229 | `guard-bash-writes` false-denies read-only trust-root inspection | **OPEN** | not started (correctly deferred) |
| #328 | `debt-reconcile` sees only 30 of N open tech-debt issues | **CLOSED as duplicate of #419** | superseded — the product owner's independent ground-truth audit (`gh api graphql`, fully paginated) found the *same* bug plus a second call site (`hooks/lib/common.sh:582`, #420) and a more precise fix scope; #328's closure-as-duplicate is the right call, not a false-closure like #120's |

Blocked-on-human (excluded from capacity either way): #115, #228 — both
**unchanged, still open, still blocked** on an org-admin `actions:read`
grant to the coder GitHub App. No new evidence this grant has landed.

Already-delivered, disposed as verify-and-close: #159 — **still open**.
The plan's own disposition ("re-verify against acceptance criteria and
close, citing commit `3fb17dc`") was never executed. Cheapest possible
finding in this review: the work is done, only the paperwork isn't.

## What actually landed this sprint window

The one substantive thing that *did* merge in the sprint-2 window was the
sprint-2 plan itself: **PR #362** (`dd6d96f`, merged 22:12:42Z) — sprint 1's
overdue review/retro plus this sprint's own plan.md, after a separate
session fixed 4 CONFIRMED-blocking review findings on it (#363–#366).
That means sprint 2 spent the overwhelming majority of its own 24h window
(planned start 2026-07-28T20:00Z, boundary 2026-07-29T20:00Z) not yet having
a merged plan for roughly the first 26h of a 24h-nominal window — the plan
merged *after* its own `sprint_ends_at`. See retro for why.

In the ~50 minutes between #362 landing and this review, one session (via
checkpoint PR #443, itself still unmerged) did real, valuable triage work
off the back of the newly-landed plan: unstuck #362 itself, discovered and
filed the #311 regression (#423) and a `loop.json` arming write-path gap
(#422), and opened PR #441 for #100. None of that is merged yet either, but
it is genuine forward motion on the committed core's #1 item.

Separately, and off this plan entirely: the product owner ran an
independent ground-truth audit of the tech-debt backlog (using paginated
`gh api graphql`, sidestepping the exact `--limit`-less bug #328/#419/#420
describe) and opened **PR #444** (open, unmerged) redefining M4's gate
scope, plus filed #419, #420 (P0, the counting bug itself) and #442 (P0,
worktree `PROJECT_DIR` resolution in the commit gate). This is real,
high-value work but was not on this sprint's plan — the same "off-plan work
competes for the same scarce turns" pattern sprint 1's retro flagged, this
time from the product-owner track rather than an engineering epic. It did
not appear to cost the committed core anything this time (the core simply
never started), so it is noted, not treated as a repeat failure.

## Trust gaps

1. **Issue #120 is closed but not fixed** — filed as **#452** this review.
   The tracker currently says the highest-severity item in this sprint's
   plan is done. It is not: PR #311 (its fix) is open, unmerged, and has a
   confirmed regression (#423) that must land first. Any session or gate
   that reads "#120: closed" as ground truth (including a naive M4
   zero-open-tech-debt check) would be wrong. This is the same failure
   *shape* sprint 1's review found in #322 (a false claim in PR #318's
   body) — except here the issue's actual GitHub `state` drifted from
   reality, not just prose in a PR description.
2. **`factory-ops/state/checkpoint.json` is stale again.** It still reads
   `sprint: 2`, `sprint_ends_at: "2026-07-29T20:00:00Z"` (now in the past),
   `station: idle`, and a `notes` field describing a moment (both #362 and
   #311 "awaiting fresh CI/review") that PR #443's body shows has already
   moved past (#362 merged, #311 found to be regressed and held). The
   planner's fence (`.claude/CLAUDE.md`) puts checkpoint.json out of scope
   for this review to fix directly; noting it here so the next station that
   writes it does so from real state, not from this stale file.
3. **Tech-debt count moved during this single review.** A recount via
   paginated `gh api graphql` at review time shows **289 open `tech-debt`
   issues** (up from the 273 the product owner's decision cited a few hours
   earlier) and **204 with no P0–P3 label** (up from 188). The backlog is
   growing faster than this sprint closed anything — consistent with
   pre-existing #372 ("tech-debt backlog growth outpaces closure"), not
   re-filed.

## Eval report

None exists. `factory-ops/qa/` contains only `.gitkeep`. M2's eval bullets
(trigger evals, outcome evals, `nightly-eval.yml` thresholds) are unstarted
— consistent with the roadmap showing M2 at 0 checked boxes. No eval
regression to report because no evals have ever run.

## What did NOT land, and why

- **#100, #101, #342, #361** (4 of 5 committed core) — never got a session
  turn before the boundary. The plan merged at 22:12:42Z against a
  20:00:00Z boundary; by the time real implementer work could start against
  it (PR #441 for #100 opened 22:51Z), the sprint was already ~3h over.
  This is a direct consequence of the retro-finding below: the planning
  ceremony itself ran late enough to consume nearly the whole window.
- **#120** — fix exists (PR #311) but is blocked on a real regression
  (#423) introduced by #311's own diff, discovered only in the last hour of
  the window. The issue's premature closure (#452) means this doesn't even
  show as "not landed" without this review checking PR state directly.
- **#132** (overflow) — PR #318 remains exactly where sprint 1 left it:
  `CONFLICTING`/`DIRTY` merge state, original `CHANGES_REQUESTED` still
  unaddressed, no commits since 2026-07-25T02:07Z. Two full sprints now with
  zero state delta on this specific PR.
- **#115/#228** — still blocked on the same human action (org-admin grant of
  `actions:read` to the coder App) named in sprint 2's plan. No new
  evidence either way this sprint.
- **#159** — substance shipped (commit `3fb17dc`, sprint 1), but the
  planned cleanup (verify + close) never got a turn.

## New issues found this review

Filed: **#452** (#120 falsely closed while its fix is unmerged and
regressed). Checked against and not duplicated: #322 (different PR, false
claim in prose rather than an actual state flip), #423 (the #311 regression
itself — already filed by the session that found it), #422 (`loop.json`
arming write-path gap — already filed), #372 (backlog-growth-outpaces-
closure trend — already filed), #437 (missing cost telemetry — already
filed, see retro).

## Carryover recommendation for sprint 3

Not this review's call to finalize (that's sprint 3 planning) but the
evidence: **the entire 5-item committed core (#100, #101, #342, #361, and
#120-via-#423-then-#311) rolls forward unfinished**, alongside overflow
#132/#229, blocked-on-human #115/#228 (unchanged), and the still-undone
paperwork on #159. Net: sprint 2 shipped its own plan (late) and some
valuable off-plan triage/discovery, but zero committed-core issues actually
merged. Sprint 3 needs to either fix why planning itself is consuming most
of the window (see retro), size its committed core to what's realistically
left after that, or both.
