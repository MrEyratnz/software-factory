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

**Freeze state: OFF** (gate not yet within one sprint of holding).

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
unmilestoned for now; M4's Release Gate ("zero open bug/tech-debt") already
guarantees they get swept before ship.

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

`docs/ROADMAP.md` M4 reads literally: "Release Gate script green: zero open
`bug`/`tech-debt`, zero unresolved review findings, v1.0.0 roadmap 100%
merged-green, coverage + eval thresholds green on `main` for 3 consecutive
nightly runs." Multiple disagreeing counts were circulating (a stale cached
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
  these (30 P2 bundled into ROADMAP M3's security-hardening pass, 15 P3
  routed to v1.1.0) — the remaining ~228 tech-debt issues have never been
  triaged or referenced in any plan.
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
worse than a scoped, honest gate. **M4's tech-debt criterion is redefined,
effective this decision, as:**

> Release Gate holds tech-debt to: **zero open `P0`/`P1` tech-debt, and
> zero open tech-debt carrying the `security` label regardless of
> `P0`–`P3`** (security outranks priority per this file's ranking rule 1).
> `P2`/`P3` non-security tech-debt does not block v1.0.0; it is explicitly
> routed to `v1.1.0` or bundled into a named hardening-pass work item,
> mirroring the sprint-1 precedent. `bug` stays **literal zero, unwaived**
> — bugs are small in volume (9 open today) and the charter already
> requires a `bug` to be fixed, not deferred, even under freeze.

This is conditioned on two prerequisites, both blocking:

1. **#419 and #420 (the counting bug) must be fixed and re-verified before
   this redefined gate is trusted by any automation.** A gate that counts
   wrong is worse than no gate. This is not optional cleanup — it is a
   precondition for the M4 "Release Gate script" work item even being
   buildable correctly.
2. **The 188 tech-debt issues with no `P0`–`P3` label (147 with zero
   priority signal at all) must be triaged before the `P2`/`P3` routing
   above can be applied to them.** Until labeled, we cannot tell how many
   of the 188 are actually `P0`/`P1`/security and hiding in the untriaged
   pile — silently treating "unlabeled" as "P2/P3, deferrable" would be
   exactly the kind of silent ambiguity this file's ranking rules forbid.
   This is sized as its own debt-burndown allocation (a dedicated triage
   pass, sprint-1-style: "N issues triaged, `P0`–`P3` applied to all with a
   one-line rationale"), not a one-line milestone move — it does not fit
   in a single sprint's planning-comment budget. Recommended to the
   planner as a standing agenda item until the 188 reach zero.

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
