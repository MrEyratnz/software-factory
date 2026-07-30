# Sprint 3 — Plan

- **Sprint:** 3
- **Planned:** 2026-07-29T23:10:00Z (UTC, anchor — no `SPRINT_HOURS` repo
  variable override found; using `.github/workflows/factory-run.yml`'s
  documented default of 24)
- **sprint_ends_at:** 2026-07-29T23:10:00Z + 24h = **2026-07-30T23:10:00Z**
- **Planner:** conductor/planner session (this file), from sprint 2's
  `review.md`/`retro.md` (held immediately before this plan, same wake),
  the product owner's tech-debt-gate-scope decision (PR #444, 2026-07-29),
  and `docs/ROADMAP.md`'s M2/M3 bullets.
- **Status:** third sprint. Not a board sprint — `GOVERNANCE.md` convenes
  the board every 4th sprint; that's sprint 4, next.

## Sprint goal

Sprint 2 shipped its own plan two hours after that plan's own boundary
(filed as **#459**) and, as a direct result, closed zero of its 5
committed-core items — all of which (#100, #101, #120, #342, #361) roll
forward unchanged. Rather than re-picking the identical core a third time
at the same size, sprint 3's goal is threefold, ordered so that gate-truth
and commit-gate reliability come first — everything else, including finishing
the security floor, depends on those being trustworthy:

1. **Fix the two mechanisms actively lying to every session right now**
   (#442, #419+#420) — #442 makes the commit gate spuriously deny green
   commits from worktree-isolated sessions (this session's own execution
   model); #419/#420 make the tech-debt count wrong in the two places every
   session reads it (`debt-reconcile`'s Stop hook and the `/factory-status`
   banner). The product owner's M4 gate-scope redefinition (PR #444, open)
   is explicitly conditioned on these landing first — a redefined gate is
   worse than no gate if it still counts wrong. Also here: **#423**, a
   regression in PR #311 (blocks #120) discovered last sprint, since it's a
   correctness bug actively blocking real security work, not new scope.
2. **Finish the security floor sprint 2 never started** (#100, #101, #120,
   #132) — carried forward unchanged, PR #441 already open for #100 (cheapest
   to land first), PR #311 for #120 blocked on #423 above.
3. **M3 hardening, biased toward what the roadmap names explicitly and what
   sprint 1/2's own retros found broken** — the bootstrap-era receipt bugs
   `docs/ROADMAP.md` M3 calls out by name (#94, #95), plus the ceremony
   mechanisms that caused sprint 1's 3-day silence and sprint 2's late-plan
   problem (#342, #361, #459) — M3's own roadmap bullet is literally "sprint
   ceremonies produce their artifacts end-to-end... across two consecutive
   sprints," so fixing the mechanism is in-scope, not a side quest.
4. **M2 cleanup**: #159's substance shipped in sprint 1 (commit `3fb17dc`);
   only the verify-and-close paperwork, twice deferred, remains.
5. **Kick off the product owner's second M4 prerequisite** — triage pass 1
   on the 204 (as of this planning) zero-priority-signal tech-debt issues,
   scoped to a realistic first slice rather than claimed as a one-sprint
   finish.

### Capacity note (learned from two sprints of evidence)

Sprint 1 closed 3-of-9 picked items (~33%). Sprint 2 closed 0-of-5, not for
lack of effort but because its own plan merged after its sprint boundary.
Following sprint 2's own restructuring (finding #365, validated as a good
call in this session's retro), this plan sizes an explicit **committed
core** to what a ~24h window can realistically close, and tracks the rest
as **overflow** (carried automatically into sprint 4 if not reached) rather
than claiming all of it as this sprint's capacity.

## Picked issues

### Committed core (5 items — this sprint's closeable-capacity target)

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #442 | `guard-commit`/`record-green` resolve `PROJECT_DIR` to the main checkout, not the worktree | P0 | **implementer** | PR merges fixing `PROJECT_DIR` resolution in the affected hook scripts so a worktree-isolated session's commit gate checks that session's own tree, verified by a failing-then-passing test that runs the gate from a simulated worktree path distinct from the main checkout. Full suite green (`bash tests/run-suite.sh`). Issue #442 closes via merge. |
| #419 | `debt-reconcile.sh:18` — `gh issue list` has no `--limit`, silently caps at 30 | P0 | **implementer** | PR merges adding an explicit high limit or full pagination to the `gh issue list` call in `hooks/scripts/debt-reconcile.sh`, verified by a test seeding >30 open tech-debt issues (mocked `gh`) and asserting a finding fingerprinted onto an issue outside the old 30-newest window is still recognized as filed. Full suite green. Issue #419 closes via merge. |
| #420 | `hooks/lib/common.sh:582` — same unbounded `gh issue list` bug, different call site (the `/factory-status` banner) | P0 | **implementer** | PR merges (same series as #419 acceptable) adding the same limit/pagination fix to `hooks/lib/common.sh:582`, verified by a test asserting the status banner reports the true open-tech-debt count against a >30-issue fixture, not capped at 30. Full suite green. Issue #420 closes via merge. |
| #423 | PR #311's `secrets: inherit` removal breaks the reviewer station's app-token mint (hard-fails, no fallback) | P1 (unblocks #120) | **implementer (security-steward focus)** | PR #311 (or a follow-up on its branch) merges adding a fallback/alternate token-mint path so removing `secrets: inherit` doesn't hard-fail the reviewer station, verified by a test/fixture simulating the no-`secrets:inherit` case and asserting the reviewer station still successfully mints a usable token. Full suite green. Issue #423 closes via merge, unblocking #120/#311. |
| #100 | Permission ceilings don't bind the credentials actually used | P0 | **implementer (security-steward focus)** | Land PR #441 (already open) or equivalent: declared `permissions:` blocks match the actual token used per job, with a test/lint step enumerating every job's effective token and granted scopes. Full suite green. Issue #100 closes via merge. |

### Overflow (picked, capacity-driven deferral — carried into sprint 4 if not reached)

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #101 | Review station: `bypassPermissions`, no tool allowlist, attacker-controlled PR text | P0 | **implementer (security-steward focus)** | PR merges replacing `bypassPermissions` with an explicit read-only tool allowlist, verified by a fixture proving a crafted malicious PR body cannot trigger a disallowed tool call. Full suite green. Issue #101 closes via merge. |
| #120 | `secrets: inherit` exposes full-scope `FACTORY_PAT` to inbound stations | P0 | **implementer (security-steward focus)** | Was wrongly closed by PR #405 while its fix (#311) was unmerged — see #452. **First action: reopen #120** (or verify at sprint-3 planning time it has been reopened) before treating it as done. Once #423 lands, PR #311 merges removing `secrets: inherit` from every inbound-triggered workflow, with a CI check asserting none remains. Full suite green. Issue #120 closes via merge of #311, not by hand. |
| #132 | Review job grants `issues:write` + `secrets:inherit` over attacker-controlled diff | P1 | **implementer (security-steward focus)**, unsticking PR #318 | PR #318 (rebased onto current `main`, its stale #115/#120 false-closure claims corrected, original CHANGES_REQUESTED addressed) or a fresh replacement merges dropping `issues:write`/`secrets: inherit` from the review job's `permissions:`. Full suite green. Issue #132 closes via merge. |
| #342 | Stations exit RED on a usage limit, violating `.claude/CLAUDE.md`'s mandatory protocol | P0 (elevated sprint 2, unchanged) | **implementer** | PR merges so hitting the usage limit writes `checkpoint.json` per protocol and exits 0, verified by a test simulating a 429/usage-limit response. Full suite green. Issue #342 closes via merge. |
| #361 | `factory-run.yml` has no standup step; step-1 parked-work can preempt the sprint-boundary check | P1 (elevated sprint 2, unchanged) | **implementer** | PR adds a standup-digest step run every wake during an active sprint, plus a hard precondition so the boundary check is evaluated even with parked work, verified by a dry-run/test. Full suite green. Issue #361 closes via merge. |
| #459 | Sprint-2's own plan merged 2h12m after its `sprint_ends_at`, leaving ~0 window for committed-core work | P1 (new, this retro) | **implementer** | PR merges either (a) anchoring `sprint_ends_at` from the plan PR's actual merge time rather than a pre-planning cadence, or (b) budgeting planning-and-review as a fixed slice with an explicit re-anchor rule if exceeded, verified by a test/assertion checking a plan's merge timestamp against its declared `sprint_ends_at`. Full suite green. Issue #459 closes via merge. |
| #94 | `/factory-init` cannot create `.factory/config.json` under its own trust-root fence (bootstrap chicken-and-egg) | P1 (M3-named) | **implementer** | PR merges giving `/factory-init` a sanctioned write path for the initial `.factory/config.json` without weakening the trust-root fence for any other writer, verified by a failing-then-passing test exercising a from-scratch `/factory-init` run. Full suite green. Issue #94 closes via merge. |
| #95 | Green-receipt mint/check location asymmetry for sibling-repo (worktree) commits | P1 (M3-named) | **implementer** | PR merges fixing the receipt mint/check path resolution so a sibling-repo (worktree) commit mints and checks the receipt at the same location, verified by a failing-then-passing test simulating a worktree commit. Full suite green. Issue #95 closes via merge. |

### Already delivered (not picked as new work — re-verify and close)

| # | Title (abridged) | Priority | Disposition |
|---|---|---|---|
| #159 | Epic 1.1: static validation layer in the commit gate | P1 (M2, v1.0.0 gate) | Substance merged to `main` via commit `3fb17dc` (#375) since sprint 1. Disposed as verify-and-close in sprint 2's plan; never executed (sprint 2 review finding). **Re-verify against acceptance criteria and close this sprint** — cheapest item on this plan. |

### Tech-debt burndown (product owner's decision, PR #444 — its own bucket, not counted against committed-core capacity)

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| — | Triage pass 1: eliminate zero-priority-signal tech-debt in the highest-risk label areas (`security`, `area:build`, `area:hooks`) | — | **product-owner**, with implementer support if automation is warranted | A PR/process artifact merges (rubric doc + either a bulk-labeling script or documented manual pass) that applies at least one of `P0`–`P3` (or a legacy `priority:*`/`high`/`medium`/`low` signal) to every currently zero-signal tech-debt issue tagged `security`, `area:build`, or `area:hooks` (a bounded, named subset of the 204 zero-signal issues at planning time, not the whole pool). PR body reports the before/after zero-signal count via the same paginated `gh api graphql` method the product owner used, for at least that subset. This is the first of a multi-sprint effort — M4 stays unchecked until the full pool clears per the product owner's decision. |

### Blocked-on-human (tracked, does not count against capacity either way)

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #115 | coder App lacks `actions:read`; factory-run's own CI-check calls 403 | P1 | **BLOCKED-on-human** — org-admin must grant the coder App `actions:read` | Unchanged from sprint 2. Once granted: a real `gh run`/CI-status call succeeds from the coder station, linked in the issue. |
| #228 | Build-loop no-op-guard: live evidence suggests it may not be fully resolved | P0 (loop integrity) | **BLOCKED-on-human** — depends on #115 | Unchanged from sprint 2: (a) a live post-#115 `factory-run` dispatch is cited; AND (b) a fresh no-op detection guard merges with a failing-then-passing test. |

17 issues tracked total (5 committed core + 8 overflow + 1 already-delivered
+ 1 triage-bucket item + 2 blocked-on-human, plus #423 counted once in the
committed core though it is a prerequisite for overflow item #120). Only the
5-item committed core counts toward this sprint's closeable-capacity claim.

## Routed, not decided here

| # | What | Route |
|---|---|---|
| #138 | Coordination-substrate milestone-scope decision — contested. PR #139 (which carried the unresolved findings #141–157) has since been **closed** without resolving #138 itself. | **judge-panel** — unchanged from sprints 1–2, still not the planner's or product owner's call. Owner of convening: architect. Sprint 3 planning note: if #139's closure means the underlying question is now moot, that determination should be made by the judge-panel convening, not assumed here. |

## Flagged for early sequencing (not this planner's issues to pick, noted for the implementer/release-captain)

- **PR #444** — the product owner's M4 tech-debt-gate-scope redefinition
  (docs-only). Recommend merging early once #419/#420 (its own stated
  prerequisites) are in flight or landed — it doesn't block them, but citing
  it as settled before they land would be premature per the decision's own
  text.
- **PR #441** — already-open fix for #100 (this sprint's cheapest
  committed-core item to land). Implementer should continue/land this
  branch, not restart.
- **PR #443** — checkpoint-only chore recording real sprint-2-end-of-window
  triage (discovered #422, #423, opened #441). Land or fold into the next
  checkpoint write rather than letting it go stale a third cycle.
- **PR #318** — carries #132's fix; per the disposition above, needs a
  rebase and the original CHANGES_REQUESTED actually addressed — two full
  sprints of zero state delta on this specific PR as of this planning.
- **PR #421** — `factory-run` CI-stall fix, unrelated to this plan's picks
  (per the task context that surfaced it); implementer/release-captain
  discretion, no sprint-3 dependency either way.
- **PR #102** (dependabot), **PR #92** (release-please) — routine, no
  sprint-goal dependency.

## Deliberately not picked (left in backlog, ranked for sprint 4+)

- **#229** — `guard-bash-writes` misdiagnoses read-only trust-root
  inspection as writes. Real, P1, but ranked below this sprint's committed
  core and overflow on severity/dependency grounds (sprint 2's own overflow
  ranking already put it behind #132); first candidate for sprint 4's core
  if capacity allows.
- **#422** — `/factory-run` step-1 loop.json arming has no sanctioned write
  path. Newly discovered (PR #443), real, but not yet triaged for severity;
  candidate for sprint 4 once its priority signal exists (also a candidate
  for the triage-pass-1 bucket above, since it's currently unlabeled).
- **#160, #161** — remaining M2 Epic 1 sub-issues (hook unit tests +
  coverage gate; behavioral/outcome evals). Natural continuation of #159
  once it's actually closed this sprint; sequenced for sprint 4 rather than
  picked alongside #159's paperwork this sprint.
- **#231, #206** — loop-health cluster (cron-prod dispatch-condition
  inversion; durable checkpoint write-back). Unchanged disposition from
  sprint 2: bundle together as one sprint-4 item per the product owner's own
  note that they should land in one change.
- **#177** — single self-hosted runner serializes the factory. Real
  throughput constraint, not correctness; infra pass, not sprint-3 core.
- **The remaining ~199 zero-priority-signal tech-debt issues** (204 minus
  the `security`/`area:build`/`area:hooks` slice picked as triage-pass-1) —
  explicitly multi-sprint per the product owner's decision; M4 stays
  unchecked regardless of this sprint's slice.
- **Non-security P2/P3 tech-debt** (the ~90 already-triaged P2/P3 issues,
  growing) — per the product owner's redefinition, does not block M4; the
  ~60-issue bootstrap/egress-proxy cluster (#163–#249) still maps to M3's
  "Security hardening pass" as one bundled work item when M3 capacity allows
  beyond this sprint's picks (#94/#95/#342/#361/#459).
- **P3 doc drift (#141–143, #146–157)** — unchanged, routed to `v1.1.0`,
  moot given PR #139's closure unless the judge-panel convening on #138
  revives it.

## Reassignment / staleness note

No item on this plan has gone through three consecutive wakes with zero
state delta under a *working* standup mechanism — because that mechanism
(#361) still doesn't exist. Until it lands: **#132's PR (#318) is the
clearest staleness case on this plan** — two full sprints (2026-07-25 to
2026-07-29) with a genuine, never-addressed `CHANGES_REQUESTED` review and
no commits. Per the fence rules in `.claude/CLAUDE.md`, if sprint 3 also
produces zero state delta on #318, the next wake must reassign it away from
"implementer (security-steward focus)" generically and file a `P0`
incident naming the specific stall, rather than carry it silently into a
fourth sprint.
