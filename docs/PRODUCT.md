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
