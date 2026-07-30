# Product — backlog policy (owner: product-owner)

The product is the plugin; the customer is any repo that installs it. Value is
measured against the standing goal: **satisfy the v1.0.0 Release Gate**
(`docs/specs/epic-1/spec.md`).

## Value-ranking rules

1. `security` findings outrank everything at equal priority (first pillar).
2. Work that moves the v1.0.0 Release Gate (Epic 1 suite, gate plumbing,
   release path) outranks work that doesn't.
3. `bug` > `tech-debt` > `efficiency` > `ux` > `idea`/`research` at equal
   gate-relevance.
4. Cost matters second: between two items of equal value, pick the cheaper
   (the efficiency engineer's data decides ties).

Every priority decision gets a one-line rationale on the issue. Re-ranking is
cheap; silent ambiguity is not — decide, record, move.

## Milestones

- **v1.0.0** — Epic 1 suite + autonomous-SDLC hardening + the Release Gate
  (see `docs/ROADMAP.md` M1–M3).
- **v1.1.0** — everything the freeze deflects; re-ranked after 1.0 ships.

## Feature freeze

When the Release Gate is within one sprint of holding, the freeze is ON:
every new `idea`/`research`/retro issue goes to v1.1.0. New scope can never
reopen the v1.0 gate — only a genuine `bug` can enter the frozen milestone,
and it must be fixed, not deferred. Freeze state is recorded here when it
flips, with the date and the gate evidence.

**Freeze state: OFF** (gate not within one sprint of holding — M2 and M3 are
both 0% done. The "221 open `tech-debt` + 6 open `bug`" figures originally
recorded here were a 2026-07-28 snapshot taken under the since-superseded
literal-zero gate; the verified 2026-07-29 ground truth is 273 open
`tech-debt` / 9 open `bug`, and the gate is now the redefined one — ADR 0005,
authoritative in `docs/specs/epic-1/spec.md` — which is also not close to
holding). New `idea`/`research` issues discovered this pass (#222, #223) were
already correctly routed to `v1.1.0` by triage; no freeze-routing action
needed this snapshot.

## Sprint 2 backlog snapshot (2026-07-28)

232 open issues / 6 open PRs surveyed (up from 61 issues at sprint-1 open —
almost all of the growth is adversarial-review tech-debt: 221 open
`tech-debt` issues today vs. a handful at sprint-1 open). At this volume,
individual per-issue ranking doesn't scale and wasn't attempted for the long
tail; per the standing bucketing precedent (sprint-1's 30-issue P2 bundle),
themed buckets are ranked as units below. Every issue elevated by number in
this snapshot got its own P-label + one-line rationale comment on GitHub;
the bucketed tail did not (documented as a scope decision, not an oversight).

### Headline finding: the sprint-1 P0 floor moved, but a new P0 replaced it

Sprint-1's five-item P0 floor is down to three still-open items — **#175,
#97, #98 are closed** (roadmap cursor fixed, loop-closing bug pair fixed).
But a new **P0 bug, #228** ("Build loop stalled: factory-run sessions orient
then stop, producing zero commits") was filed and is *not* fully closed out.
Verified against the commit log and issue thread: checkpoint reconciliation
(#230, merged) and a prompt-only behavioral fix (#303/`fe9c131`, merged)
addressed both of #228's named root causes, and real work has landed since
(`a9cd802`, the observability epic) — the loop does appear to be producing
again. What's still missing is (a) a live-dispatch re-verification closing
the loop on #228 itself, which needs #115 (`actions:read`) to check its own
CI status, and (b) the mechanical no-op **detection guard** that was #228's
second named root cause — its only implementation lives on PR #250, which is
itself a stale, likely-abandonable draft carrying ~35 of its own adversarial
review findings. Recommendation: don't resurrect #250; scope a small, fresh
no-op guard as its own sprint-2 item once #115 unblocks verification.

### P0 — must not wait (security root cluster, carried from sprint 1)

| # | Why P0 |
|---|---|
| #100 | Root cause of #101/#120/#132 — workflow permission ceilings don't bind the credential sessions actually use. Security outranks everything at equal priority (rule 1); fix first. |
| #101 | Review station runs `bypassPermissions`, no tool allowlist, over attacker-controlled PR text — live prompt-injection surface. |
| #120 | `secrets: inherit` exposes full-scope `FACTORY_PAT` to inbound, attacker-triggered stations. PR #311 claims to close this but has stalled ~3 days on stale/pending CI checks — still open in fact. Not mine to unstick; flagging for the planner/implementer. |

`#132` and `#115` (below) share this cluster's root cause and are ranked
immediately after it, not inside the P0 tier itself, matching their own
P1 labels.

### P1 — sprint 2 core (top of backlog for the planner, ranked)

1. **#100, #101, #120** — P0 above, fix first.
2. **#115** — `coder` App lacks `actions:read`; blocks factory-run's own
   `gh run` checks. Elevated this sprint specifically because it now also
   gates verifying #228 is actually fixed — nothing else in the loop-health
   cluster can be closed out with confidence until this lands.
3. **#132** — shares #100's root cause (review job `issues:write` +
   `secrets:inherit` over an attacker-controlled diff); fix alongside #100.
   Note: PR #318 (stacked checkpoint PR touching this cluster) carries a
   `CHANGES_REQUESTED` review — same "not mine to unstick" caveat as #311.
4. **#228** — P0 bug, loop integrity (see headline finding above). Sprint-2
   task is narrow: verify via live dispatch once #115 lands, then either
   close it or land a fresh, minimal no-op detection guard — not a revival
   of PR #250.
5. **#229** — `guard-bash-writes` denies read-only inspection of trust-root
   paths (misdiagnosed as writes), discovered *while operating* the #228/#100
   cluster — it wastes a turn and misleads a session about its own gate
   state on every occurrence. Cheap, high-leverage hook fix.
6. **#342** — stations exit RED on a usage limit, which `.claude/CLAUDE.md`'s
   own usage-limit law forbids; no checkpoint gets written on a quota-out, so
   the session's work is lost instead of resumed. Direct violation of a
   mandatory house rule, not just a preference.
7. **#328** (P1, labeled this pass; dupes #227/#302 labeled P3 and pointed
   here) — `debt-reconcile`'s Stop hook fetches tech-debt issues with no
   `--limit`, defaulting to `gh`'s newest-30, against 221 open at the
   2026-07-28 snapshot (273 by the 2026-07-29 ground truth). The Stop-gate
   reconciliation this repo's whole tech-debt convention depends on — and by
   extension M4's Release Gate (ADR 0005; authoritative in
   `docs/specs/epic-1/spec.md`) — cannot see ~86% of what it's supposed to
   enforce against at current backlog size. This is a gate-integrity bug,
   not routine tech-debt.
8. **#231** (P1, labeled this pass) — cron-prod dispatch-condition inversion
   in the checkpoint reconciliation; same loop-health cluster as #206/#228.
   Bundle with #206 so both land in one change.
9. **#206** — durable end-of-turn checkpoint write-back. #230's manual
   reconciliation was a one-off stopgap, not the mechanism; still needed so
   a future usage-limit exit doesn't re-strand the loop the way #228 did.
10. **#159** (M2 stretch, unstarted) — Epic 1.1 static validation layer, the
    literal next unchecked roadmap item and actual Release-Gate substance.
    Sequenced after the floor above, same logic as sprint-1: gate work lands
    unreliably while loop-health and the security surface are still being
    closed out this sprint.

That's a 10-item ranked core, in the same size band as sprint-1's floor +
core. **#138** (labels-as-coordination-substrate, security-labeled,
foundational, P1, `v1.0.0`) remains open and unchanged in status from
sprint-1 — still correctly routed to `/judge-panel` as contested scope, not
decided here.

### P2 — real, bucketed by theme (not individually sequenced this sprint)

- **#177** — single self-hosted runner serializes the whole factory;
  `MAX_PARALLEL_AGENTS` unenforceable. Real, but a throughput constraint, not
  a correctness one — bucketed for a later infra pass rather than sprint-2
  core.
- **Bootstrap/egress-proxy hardening (PR #162 review, merged `c5259a4`)** —
  roughly 60 issues in the `#163`–`#249` range. Explicit P1-severity items
  inside this bucket, called out by number: **#179, #180, #195, #202, #238**
  (registration-token/firewall-persistence/health-probe gaps). Maps to
  ROADMAP M3's "Security hardening pass" bullet, same treatment as sprint-1's
  P2 bundle — one work item when M3 is picked up, not 60 individually-ranked
  ones.
- **No-op-guard PR #250 review findings (~#251–#310)** — deprioritized as a
  bucket because #250 itself is a stale, likely-abandonable draft. If #250
  is formally abandoned (planner/retro call, not mine), don't carry these
  findings forward against dead code; the replacement guard scoped under
  #228 above should be reviewed fresh instead.
- **Security PR #311/#318 review findings (~#312–#327)** — same cluster as
  #100/#101/#120/#132, bucketed here since both PRs are currently stuck (see
  P0 table). Re-rank individually once the planner's retro judges whether
  either PR rolls forward.
- **Observability epic findings (#330–#358, excluding #342 which is ranked
  above)** — mostly low/medium severity: docs, compose files, credential-probe
  edge cases on an epic that shipped (PR #329 merged) with PR #359 still
  open. Two items read as higher severity than their (missing) P-label
  suggests — **#332** ("`FACTORY_OTEL_ENDPOINT` set on an unproven/dead
  observability stack") and **#343** ("observability contract test runs only
  nightly, never on PR") — flagging both for the planner's attention without
  formally re-labeling; bucketed with the rest pending a themed pass.

### P3 — unchanged from sprint 1

`#141–143, #146–157`: doc cross-reference drift on the still-unmerged PR
#139, routed to `v1.1.0`. No status change — PR #139 hasn't landed.

### Milestone-scope decisions this pass

- No milestone moves. The `v1.0.0` set from sprint-1 stands; #228, #229,
  #206, #231, #328, #342 all landed in `v1.0.0` by triage already (correct —
  all are loop/gate-integrity, in scope for the Release Gate) and needed no
  correction from me.
- Freeze stays **OFF** (see above) — recorded per the freeze-state rule.
- Left #138 with sprint-1's disposition: `v1.0.0`, P1, routed to
  `/judge-panel` — still contested, still not mine to decide unilaterally.

### Not touched this pass

PRs #311, #318, #250, #359 are implementer/release-captain/planner
territory. #311 and #318 are flagged above only because their stalled state
changes how much of the P0/P1 security cluster is *actually* closed versus
merely PR'd — the decision to unstick, re-scope, or abandon either is the
planner's retro call, not mine.

## Sprint 1 backlog snapshot (2026-07-24)

First sprint the factory has ever planned (`factory-ops/sprints/` was empty,
checkpoint station "idle", sprint 0). 61 open issues / 4 open PRs triaged;
P0–P3 applied to all 61 with a one-line rationale comment on each. Full
ranking logic and per-issue rationale live on the issues themselves (GitHub
is the ledger); this section records the *decisions*, not a duplicate list.

### Finding that reorders everything: the roadmap cursor was wrong

`roadmap_next` was reporting M1 item **#47** as the next unit of work. All
six M1 — Hardening items (#47, #51, #52, #53, #60, #61) were actually closed
`completed` on 2026-07-11 and shipped (CHANGELOG entries for #72/#71/#69/#73,
commits `f60b216`/`f368743` for #60/#61) — twelve days *before*
`docs/ROADMAP.md`'s M1 section was written (PR #91, 2026-07-23). M1 is
functionally 6/6 done; the roadmap shows 0/6. Filed as **#175, P0** — fixing
this (an architect-owned, docs-only checkbox flip with evidence already in
hand) is prerequisite to trusting any other roadmap-driven planning this
sprint. True progress is ~12/30 (40%), not the connector's reported 20%.

### P0 — must not wait (security + loop-breaking + roadmap integrity)

| # | Why P0 |
|---|---|
| #175 | Roadmap cursor is wrong (see above) — blocks correct planning of everything else |
| #97 | GITHUB_TOKEN fallback is read-only for every station; the reviewer can never approve — the lights-out loop can never close |
| #100 | Workflow permission ceilings don't bind the credential sessions actually use (App token/PAT) — root cause behind #101/#120/#132 |
| #101 | Review station runs `bypassPermissions`, no tool allowlist, over attacker-controlled PR text — live prompt-injection surface |
| #120 | `secrets: inherit` exposes the full-scope `FACTORY_PAT` to inbound, attacker-triggered stations |

These five are the sprint-1 floor: nothing else the loop does is trustworthy
while the reviewer can't approve, the cursor lies, or an inbound PR can
exfiltrate the factory's own credentials.

### P1 — sprint 1 core (top of backlog for the planner)

Ranked, not just listed — do in roughly this order:

1. **#175** — fix the roadmap cursor first (P0, above).
2. **#97, #98** — loop-closing bug pair (read-only fallback, then the
   `--merge` policy mismatch it was masking). Fix together.
3. **#100, #101, #120, #132** — the permission/credential cluster from PR
   #99's adversarial review (P0/P1). #132 shares #100's root cause; fix
   alongside it.
4. **#115** — factory-run's own CI-check calls 403 (coder App lacks
   `actions:read`) — the loop can't verify its own green.
5. **#106, #123** — narrower loop/security gaps in the same cluster (P1;
   lower severity per their own review verdicts).
6. **#94, #95** — the two bootstrap-era receipt bugs ROADMAP M3 names
   explicitly by number.
7. **#159, #160, #161** (parent: #158) — M2, the Epic 1 test suite. This
   *is* the v1.0.0 Release Gate's substance, already correctly milestoned
   `v1.0.0`. Sequenced after the loop/security floor above because a
   still-broken merge loop or a leaking credential makes the test-suite work
   land unreliably.
8. **#138** — coordination-substrate decision (security-labeled,
   foundational). **Milestone-scope decision:** left in `v1.0.0` and P1, but
   the M1-renumbering question it raises is contested (PR #139 carries
   unresolved findings #141–157) — routed to `/judge-panel`, not decided
   unilaterally here.

### P2 — real, deferred to a themed hardening pass (30 issues)

#103–105, #107–114, #116–119, #121–122, #124–131, #133–137: all genuine
findings from PR #99's adversarial review (permission-ceiling edge cases,
bootstrap `set -e` dead branches, App-scope gaps, contract-test coverage
gaps). None block the loop today. **Milestone-scope decision:** these map to
ROADMAP M3's "Security hardening pass" bullet as one batch, not 30
individually-sequenced sprint-1 items — bundle them into that M3 work item
when it's picked up rather than re-ranking each one every sprint. Left
unmilestoned for now. (Correction under ADR 0005: which of this batch blocks
v1.0.0 is decided solely by the Release Gate predicate in
`docs/specs/epic-1/spec.md` § "Release Gate for v1.0.0"; the remainder that
M3's pass doesn't consume and the gate doesn't block rolls to ROADMAP M5's
"P2/P3 tech-debt burndown (non-security)" item.)

### P3 — doc/spec cross-reference drift on an unmerged PR (15 issues)

#141–143, #146–157: all about internal consistency of the *not-yet-merged*
PR #139 (coordination-substrate renumber) — stale cross-references to a
milestone numbering that only exists in that PR's diff, not on `main`.
**Milestone-scope decision:** routed to `v1.1.0`. This is lower-value noise
relative to the sprint-1 floor above: fixing doc cross-references inside an
unlanded PR is either resolved by the PR's own next revision or moot if the
PR is abandoned/reworked via judge-panel. Re-rank if/when #138/#139 actually
merges and these become live drift against `main`.

### Not touched this pass

PRs #162, #139, #102, #92 are implementer/release-captain territory, not
product-owner's to label. #162 (egress-proxy CI reliability fix) looks
sprint-1-relevant by inspection — flagging for the planner to prioritize
merging it early since a flaky runner blocks everything else, but the
decision to merge is not mine to make.

## M4 Release Gate scope: "zero open tech-debt" redefined (2026-07-29)

### The problem

`docs/ROADMAP.md` M4 read literally (before ADR 0005 rewrote it): "Release
Gate script green: zero open `bug`/`tech-debt`, zero unresolved review
findings, v1.0.0 roadmap 100% merged-green, coverage + eval thresholds green
on `main` for 3 consecutive nightly runs." Multiple disagreeing counts were
circulating (a stale cached
"30", a `gh`-CLI query capped at 200 showing ">=194", a same-day dashboard
run reporting 273) — before this decision, nobody had ground truth.

### Ground truth (verified 2026-07-29, `gh api graphql`, fully paginated —
not `gh issue list`, which silently truncates)

- **286 open issues total.**
- **273 labeled `tech-debt`.** (The 273 figure quoted elsewhere was
  correct; the "30" figure was not a stale cache — it is `gh issue list`'s
  *default page size* leaking into two production call sites that never
  pass `--limit`. See "Root cause" below.)
- **9 labeled `bug`** (2 `P0`, 5 `P1`, 2 unlabeled).
- Tech-debt by severity: **`P0`: 3, `P1`: 15, `P2`: 44, `P3`: 23, no
  `P0`–`P3` label at all: 188** (of which 147 carry *no* priority signal of
  any kind — not even a legacy `priority:*`/`high`/`medium`/`low` label).
  Sprint-1's plan (`factory-ops/sprints/1/plan.md`) accounts for only 45 of
  the 273 open tech-debt issues (30 P2 bundled into ROADMAP M3's
  security-hardening pass, 15 P3 routed to v1.1.0) — the remaining ~228
  have never been referenced in any plan. Of the 273, it is the **188**
  lacking any `P0`–`P3` label that constitute the gate-blocking triage
  prerequisite tracked as #510; the two figures overlap but are not the
  same set.
- **10 tech-debt issues carry the `security` label** (2 `P0`, 2 `P1`, 3
  `P2`, 3 `P3`) — security does not correlate with severity label here, so
  it cannot be inferred from `P0`/`P1` alone.

### Root cause of the disagreeing counts: a real bug, now filed

`hooks/scripts/debt-reconcile.sh:18` and `hooks/lib/common.sh:582` (the
`/factory-status` and `inject-status` banner every agent reads every
session) both call `gh issue list --label tech-debt --state open` with no
`--limit`. `gh`'s default limit is 30 — which is exactly the stale figure
that was circulating. #419 already tracked the first call site; I filed
**#420** for the second (undiscovered) one, since it's the one that
actively misleads every session's orientation step. Labeled both **`P0`**
with rationale comments: this must be fixed before M4's own "Release Gate
script" is built, or that script inherits the same bug and can false-green
a release with hundreds of issues still open. This is the single most
concrete risk this investigation surfaced — a correctness bug in gate
tooling itself, not just a scope question.

### Decision

The literal "zero open tech-debt" gate is **not achievable as written**
before v1.0.0, and — following the same reasoning that already led sprint 1
to bundle 30 P2 findings into one M3 work item and route 15 P3 items to
v1.1.0 — it should not be pursued as written. Holding a 200+ open-issue
factory to a literal zero is not rigor, it is a gate that can only ever be
satisfied by either mass-closing issues without fixing them or by the
counting bug above quietly making it look satisfied. Both outcomes are
worse than a scoped, honest gate.

**The redefined criterion is recorded in ADR 0005
(`docs/adr/0005-m4-tech-debt-gate-scope.md`) and defined authoritatively —
once — in `docs/specs/epic-1/spec.md` § "Release Gate for v1.0.0" (the
section `docs/ROADMAP.md` and `.claude/CLAUDE.md` pin the gate to). This
file carries the product rationale only and deliberately does not restate
the predicate — read the spec section for the criteria.**

Two blocking prerequisites remain before the gate can be evaluated:

1. **#419 and #420 (the counting bug) must be fixed and re-verified before
   this redefined gate is trusted by any automation.** A gate that counts
   wrong is worse than no gate. This is not optional cleanup — it is a
   precondition for the M4 "Release Gate script" work item even being
   buildable correctly.
2. **The 188 tech-debt issues with no `P0`–`P3` label (147 with zero
   priority signal at all) must be triaged — tracked as #510 and as an
   explicit ROADMAP M4 item.** Under the spec's fail-closed criterion this
   is structural, not advisory (see the spec section for the mechanics) —
   the gate cannot hold until the 188 reach zero, because silently treating
   "unlabeled" as "P2/P3,
   deferrable" is exactly the silent ambiguity this file's ranking rules
   forbid, and the predicate now makes it impossible. This is sized as its
   own debt-burndown allocation (a dedicated triage pass, sprint-1-style:
   "N issues triaged, `P0`–`P3` applied to all with a one-line rationale"),
   not a one-line milestone move — it does not fit in a single sprint's
   planning-comment budget. Recommended to the planner as a standing agenda
   item until the 188 reach zero.

Until both prerequisites clear, **M4 stays unchecked** and the Release Gate
should not be evaluated as "close to holding" on tech-debt count alone —
current true state is 18 `P0`/`P1` tech-debt items + 10 security-labeled
tech-debt items (some overlapping) outstanding against even the *redefined*
gate, before the ~228 untriaged issues are even sorted into it.

### Freeze interaction

This does not flip the feature freeze (still **OFF** — the gate is not
within one sprint of holding under either the literal or redefined
reading). It does mean that once the freeze does go on, `idea`/`research`
issues route to `v1.1.0` as normal, but the ~228 untriaged tech-debt items
are pre-existing debt, not new scope — they still need the triage pass
above regardless of freeze state.
