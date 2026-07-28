# Sprint 2 — Plan

- **Sprint:** 2
- **Planned:** 2026-07-28T20:00:00Z (UTC, anchor — no `SPRINT_HOURS` repo
  variable override found; using `.github/workflows/factory-run.yml`'s
  documented default of 24)
- **sprint_ends_at:** 2026-07-28T20:00:00Z + 24h = **2026-07-29T20:00:00Z**
- **Planner:** conductor/planner session (this file), from the product
  owner's ranked backlog in `docs/PRODUCT.md` ("Sprint 2 backlog snapshot",
  2026-07-28) and sprint 1's `review.md` / `retro.md`.
- **Status:** second sprint. Not a board sprint — `GOVERNANCE.md` convenes
  the board every 4th sprint; that's sprint 4.

## Sprint goal

Sprint 1 shipped the roadmap-truth and loop-closing floor (#175, #97, #98)
but never touched the P0 security cluster it had already sequenced next, and
both PRs meant to close part of it (#311, #318) stalled for three days —
compounded by a weekly usage-limit outage and a `factory-run.yml` control-flow
gap that let off-plan work win every wake after the limit reset. Sprint 2's
goal is threefold, in this order:

1. **Finish the security floor sprint 1 never started** (#100, #101, #120,
   #132, #115) — these were never worked, not deprioritized, and #100/#101/
   #120 remain the highest-severity open items by the product owner's own
   "security outranks everything at equal priority" rule. #120 and #132 each
   have a stalled PR (#311, #318); this sprint explicitly assigns who
   unsticks them and how (see "Carryover PR disposition" below) rather than
   letting them sit for a fourth ceremony in a row.
2. **Fix the two mechanisms that caused sprint 1's own ceremony to go silent
   for 3+ days** (#342, #361) — sequenced immediately after the security
   floor, ahead of the rest of the product owner's P1 core, on this
   planner's own judgment (explicitly invited by the sprint-2 task framing).
   Rationale: #342 is a direct violation of `.claude/CLAUDE.md`'s own
   mandatory usage-limit protocol (stations must checkpoint and exit 0 on a
   quota-out, never exit RED), and #361 is the compounding bug — no standup
   step at any cadence, and step-1 "parked work" can preempt the
   sprint-boundary check indefinitely. Both are cheap, mechanical, workflow
   -YAML-scoped fixes that don't compete with the security cluster's turns,
   and every wake they stay unfixed is a wake sprint 2's own standup/review/
   retro could silently fail to fire — exactly what just happened.
3. **Close out the loop-integrity items the product owner ranked next**
   (#228 verify-then-guard, #229, #328, #159 stretch) — real bugs discovered
   *while operating* the above two clusters, ranked by the product owner
   immediately after the security/process floor.

11 items total, same size band as sprint 1 (8-12 target).

## Off-plan work: explicit rule for this sprint

Sprint 1's retro (item 3) found that an unrelated observability epic
(#329/#359) — never on the sprint-1 backlog — won every post-usage-limit-
reset wake while three P0 security items and two stuck PRs sat untouched,
because `factory-run.yml`'s step-1 doesn't distinguish "parked work that is
this sprint's own picked item" from "parked work that is a concurrent,
unrelated epic." Rule for sprint 2, until #361 lands a mechanical fix:
**a picked sprint-2 item (including unsticking #311/#318) takes precedence
over any off-plan branch — including PR #359, which remains open and is
implementer/release-captain discretion to merge, but must not consume a
wake ahead of a picked item that is ready for a turn.**

## Picked issues

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #100 | Permission ceilings don't bind the credentials actually used | P0 | **implementer (security-steward focus)** | PR merges changing the affected workflow files so declared `permissions:` blocks match the actual token used per job, with a test/lint step (or documented manual verification in the PR body) enumerating every job's effective token and granted scopes. Full suite green (`bash tests/run-suite.sh`). Issue #100 closes via merge; #101/#120/#132 re-verified against the fix. |
| #101 | Review station: `bypassPermissions`, no tool allowlist, attacker-controlled PR text | P0 | **implementer (security-steward focus)** | PR merges replacing `bypassPermissions` on the review station with an explicit read-only tool allowlist, verified by a test/fixture that a crafted malicious PR body cannot trigger a disallowed tool call. Full suite green. Issue #101 closes via merge. |
| #120 | `secrets: inherit` exposes full-scope `FACTORY_PAT` to inbound stations (PR #311 stalled) | P0 | **implementer (security-steward focus)**, unsticking PR #311 | PR #311 (rebased onto current `main`, review re-triggered per the disposition below) or a fresh replacement merges removing `secrets: inherit` from every inbound-triggered workflow, with a CI check asserting none remains. Full suite green. Issue #120 closes via merge. |
| #342 | Stations exit RED on a usage limit, violating `.claude/CLAUDE.md`'s mandatory protocol | P0 (elevated by planner) | **implementer** | PR merges changing station failure handling so that hitting the Anthropic usage limit writes `factory-ops/state/checkpoint.json` per the documented protocol and exits 0 instead of RED, verified by a test/fixture simulating a 429/usage-limit response and asserting a checkpoint is written and the process exit code is 0. Full suite green. Issue #342 closes via merge. |
| #361 | `factory-run.yml` has no standup step; step-1 parked-work can preempt the sprint-boundary check indefinitely | P1 (elevated by planner) | **implementer** | PR merges to `.github/workflows/factory-run.yml` (and/or the invoked prompt) adding (a) a standup-digest step that runs every wake during an active sprint and (b) a hard precondition so the sprint-boundary/ceremony check is evaluated even when step-1 finds parked work, verified by a dry-run/test showing a wake with parked work still reaches the boundary check. Full suite green. Issue #361 closes via merge. |
| #132 | Review job grants `issues:write` + `secrets:inherit` over attacker-controlled diff (PR #318 stalled) | P1 (shares #100's root cause) | **implementer (security-steward focus)**, unsticking PR #318 | PR #318 (rebased onto current `main`, CHANGES_REQUESTED findings addressed, #322/#323 false-closure claims corrected in the body) or a fresh replacement merges dropping `issues:write`/`secrets: inherit` from the review job's `permissions:`. Full suite green. Issue #132 closes via merge. |
| #115 | coder App lacks `actions:read`; factory-run's own CI-check calls 403, also blocks verifying #228 | P1 | **implementer** | App-manifest/config change (or PR) grants the coder App `actions:read`, verified by a real `gh run`/CI-status call succeeding from the coder station in a real or replayed run (link the run in the PR/issue). Issue #115 closes via merge or linked verification comment. |
| #228 | Build-loop no-op-guard: two merged fixes exist (#230, #303) but live evidence suggests it may not be fully resolved | P0 (loop integrity) | **implementer**, depends on #115 | (a) A live `factory-run` dispatch is triggered post-#115 and its run log/checkpoint is cited (run URL + commit SHA, or explicit no-op confirmation) in the issue; AND (b) a fresh, minimal no-op detection guard merges (new PR, **not** a revival of PR #250) with a failing-then-passing test asserting a no-progress wake is detected and never silently reported as success. Full suite green. Issue #228 closes via merge of (b), citing (a). |
| #229 | `guard-bash-writes` misdiagnoses read-only trust-root inspection as writes | P1 | **implementer** | PR merges fixing the hook so read-only commands (`cat`, `grep`, `ls`, etc.) against `.factory/state/**`, `.factory/review/**`, `.factory/config.json` are no longer denied, verified by a failing-then-passing test. Full suite green. Issue #229 closes via merge. |
| #328 | `debt-reconcile` Stop hook only sees 30 of 221 open tech-debt issues | P1 (gate integrity) | **implementer** | PR merges raising/paginating the `gh issue list` limit used by `debt-reconcile` beyond the default 30, verified by a test asserting reconciliation sees >30 open `tech-debt` issues against a >30-issue fixture. Full suite green. Issue #328 closes via merge. |
| #159 | Epic 1.1: static validation layer in the commit gate | P1 (M2, v1.0.0 gate) | **implementer** | **Stretch — only if capacity remains after items above are merged-green.** PR merges adding manifest + frontmatter schema checks for every command/agent/skill/hook config to the commit gate, with new tests failing red before and green after. Full suite green. Issue #159 closes via merge. If not started, first item planned for sprint 3. |

11 concrete work items (#100, #101, #120, #342, #361, #132, #115, #228, #229,
#328, #159) — within the 8–12 target range.

## Carryover PR disposition

Sprint 1's retro found #311 and #318 stuck with no reassignment mechanism
(standup never fired to trigger the plan's own staleness rule) and asked
sprint 2 to decide who unsticks them and how. Decisions:

- **PR #311** (closes #120): `mergeable_state: behind`; combined status
  `pending` because its `review / session` check-run itself hit the weekly
  429 wall mid-review and was never retried (not a real review rejection —
  confirmed in sprint-1's `review.md`). **Disposition: rebase onto current
  `main` and re-trigger the review** (the usage-limit wall that stalled it
  has since reset per #360's chronology). If re-review then surfaces real
  findings, address them in place. If the branch proves too stale/conflicted
  to salvage cheaply after rebase, close and reopen fresh off current `main`
  carrying the same diff intent — implementer's call at that point, not
  re-litigated here.
- **PR #318** (checkpoint update, touches #132's cluster): carries a genuine,
  never-addressed **CHANGES_REQUESTED** review, plus factual errors in its
  own body (#322/#323's false #115/#120 closure claims) and `mergeable_state:
  behind` (main moved via #303/#329 since). This is not a re-trigger
  situation like #311 — a human/agent must actually act on the review.
  **Disposition: rebase onto current `main`, correct the false claims in the
  body, address the CHANGES_REQUESTED findings, request re-review.** If the
  review is now moot given how far main has moved, close and reopen fresh
  with corrected content rather than carry the stale/wrong claims forward.
- **PR #250** (no-op detection guard, draft): its behavioral half was split
  out and merged via #303 (`fe9c131`); its remaining scope
  (`claude-session.yml` guard + `scripts/session-progress.mjs`) was never
  carried into any merged PR, and it is `draft`/`mergeable_state: dirty`,
  untouched since 2026-07-25. Both sprint-1's review and the product owner's
  sprint-2 snapshot independently recommend against reviving it.
  **Disposition: close PR #250 as superseded**, with a comment pointing to
  #228 (picked above) as where the remaining no-op-guard scope now lives,
  scoped fresh rather than resurrected. Its ~35 open review findings
  (#251–#310) are **not** individually carried forward as tech-debt against
  code that will never merge — this matches the product owner's explicit
  call in the sprint-2 backlog snapshot ("don't resurrect #250... if #250 is
  formally abandoned, don't carry these findings forward against dead
  code"). This plan makes that call explicit and final.

## Routed, not decided here

| # | What | Route |
|---|---|---|
| #138 | Coordination-substrate milestone-scope decision — contested, PR #139 carries unresolved review findings #141–157 | **judge-panel** — unchanged from sprint 1, still not the planner's or product owner's call to make unilaterally. Owner of convening: architect. |

## Flagged for early sequencing (not this planner's issues to pick, noted for the implementer/release-captain)

- **PR #359** — observability follow-up review, still open. Merge if green
  and unblocked, but per the off-plan-work rule above it must not preempt a
  picked sprint-2 item that's ready for a turn.
- **PR #102** (dependabot), **PR #92** (release-please) — routine, no
  sprint-goal dependency; implementer/release-captain discretion.

## Deliberately not picked (left in backlog, ranked for sprint 3+)

- **#231, #206** — related loop-health items the product owner flagged
  (cron-prod dispatch inversion; durable checkpoint write-back replacing
  #230's stopgap) but did not rank inside the sprint-2 core 10. Bundle
  together as one sprint-3 item per the product owner's own note that they
  should land in one change.
- **#177** — single self-hosted runner serializes the factory
  (`MAX_PARALLEL_AGENTS` unenforceable). Real, but a throughput constraint,
  not a correctness one — infra pass, not sprint-2 core.
- **Bootstrap/egress-proxy cluster (~60 issues, #163–#249)** — maps to
  ROADMAP M3's "Security hardening pass" as one work item when M3 is picked
  up. P1-severity items called out by number within it: #179, #180, #195,
  #202, #238.
- **No-op-guard PR #250 findings (~#251–#310)** — deprioritized and not
  carried forward; see "Carryover PR disposition" above. The replacement
  guard under #228 should be reviewed fresh instead.
- **Security PR #311/#318 findings (~#312–#327)** — re-rank individually
  once #311/#318 actually land this sprint per the disposition above.
- **Observability epic findings (#330–#358, excluding #342 which is picked)**
  — mostly low/medium severity, bucketed for a themed pass. Two items flagged
  by the product owner as higher severity than their label suggests, noted
  here for sprint 3's attention: **#332** (`FACTORY_OTEL_ENDPOINT` set on an
  unproven/dead observability stack) and **#343** (observability contract
  test runs only nightly, never on PR).
- **P3 doc drift (#141–143, #146–157)** — unchanged, routed to `v1.1.0`,
  moot unless #138/#139 merge.

## Reassignment / staleness note

Sprint 1's own version of this rule never executed because standup never
ran (the exact gap #361 above is meant to close). Until #361 lands: if any
owner above produces no state delta across three consecutive wakes, the
next wake that *does* run must reassign that item and file a `P0` incident
per `.claude/CLAUDE.md`'s fence rules — the same manual fallback this
planner used at sprint-1 review time, since the automated trigger doesn't
exist yet.
