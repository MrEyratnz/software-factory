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

**Freeze state: OFF** (gate not yet within one sprint of holding — M2 and M3
are both 0% done by roadmap checkbox, and as of sprint-4 planning **754 open
`tech-debt` + 12 open `bug`** issues stood between here and the then-literal M4 gate (superseded:
the adopted gate — spec § "Release Gate for v1.0.0" — blocks on open
bug/P0-P1/ever-security/ever-confirmed-high/untriaged, not raw counts) — up from 221/6 at sprint-2 snapshot and 289 at sprint-2
review; ground-truth counts re-pulled this pass via the GitHub search API,
paginated past the 30-item default that undercounts elsewhere in this repo's
own tooling, see #419/#420 below). The gate is materially **farther** away
than at sprint-2, not closer — see the sprint-4 headline finding. No new
`idea`/`research` issues required freeze-routing this pass.

## Sprint 4 backlog snapshot (2026-08-05)

769 open issues / 5 open PRs, ground-truth counts (GitHub search API,
paginated): 754 `tech-debt`, 12 `bug`, 16 `security`, 8 `P0`, 45 `P1`, 81
`P2`, 42 `P3`, 591 `tech-debt` issues carrying no P-label at all. Sprint 3's
`sprint_ends_at` (2026-07-30T23:10:00Z) passed **six days** ago with no
review/retro held and no sprint-4 plan written as of this session's
orientation (`factory-ops/sprints/` had only folders `1/`, `2/`, `3/`, and
`3/` held only `plan.md` — this pass's own ceremony is what adds
`3/review.md`, `3/retro.md`, and `4/plan.md`).
`factory-ops/state/checkpoint.json` is still pinned to commit `689e785`
(2026-08-01) — **4 commits behind current `HEAD`** — so it does not reflect
sprint 3's actual close-out state. This snapshot re-derives ranking from
live GitHub state rather than trusting either stale artifact.

### Headline finding: the gate's own repair mechanism is the thing breaking it

The dominant fact this sprint is **not** a backlog of real defects — it's a
single contested, unmerged PR actively manufacturing backlog faster than
anyone can work it. **PR #444** (`docs(product): redefine M4 tech-debt
gate-scope from ground-truth counts`, open since 2026-07-29, carrying
ADR 0005 in its diff, never merged) has been re-reviewed by the reviewer
station **20 times** since 2026-07-30 (every round `CHANGES_REQUESTED`,
most recently 2026-08-05T11:43Z, still `mergeable_state: behind`). Per the
review station's own finding (**#980**, filed today): open `tech-debt` grew
from 289 at sprint-2 review to **750 in ~6 days** (+461, #980's frozen
snapshot — this pass's own re-pull above reads 754/~465, a few hours newer),
of which **521**
were created since sprint-2 review ended and ~100 in the 24h window before
#980 was filed — nearly all authored against this one PR's successive push
rounds, many self-referential to the PR's own contested claims (e.g. #940,
#911, #963). A meaningful fraction are outright duplicates (#977 restates
#420 verbatim, joining #328/#419/#610/#698/#864 on the same bug) because the
idempotency mechanism meant to prevent re-filing is itself broken and
unfixed (**#471**, **#688** — `tech-debt-clerk` fingerprints diverge from
`techdebt_audit`'s fingerprints, so every `/review` re-files instead of
recognizing prior findings, and per #688's own title this **also
self-blocks the `debt-reconcile` Stop hook on every `/review`**). A PR whose
entire purpose is to make M4's Release Gate (per `docs/specs/epic-1/spec.md` § "Release Gate for v1.0.0", scoped by ADR 0005 / mechanized by ADR 0006) achievable is,
through its own unconverged review loop, making the gate's raw count
~2.6x worse in under a week — the opposite of its intent — while never
reaching a mergeable state. This is exactly the shape ADR-0009's judge-panel
process exists for (contested, endlessly re-litigated, not converging on
ordinary review) — and per `GOVERNANCE.md`, the board convenes every 4th
sprint, and **sprint 4 (next) is the 4th sprint**. Both the review finding
(#980) and the mechanism match: **route PR #444 / ADR 0005 to `/judge-panel`
as sprint 4's board session**, and freeze further adversarial-review rounds
on that branch until the panel resolves it — continuing to re-review it as
an ordinary PR is what is causing the damage. This outranks nearly
everything else below: it is actively working against the standing goal,
not just failing to advance it.

### Verified this pass: M2's first item is already done in substance

`docs/ROADMAP.md`'s `roadmap_next` names M2's "Static validation layer in
the commit gate: manifest + frontmatter schema" (line 29) as the next
unchecked item. I ran `bash tests/scaffold.contract.test.sh` myself: it
passes clean, including "plugin static validation (frontmatter/manifest
schema, `${CLAUDE_PLUGIN_ROOT}` portability, referenced-files-exist, JSON
validity) is clean" plus four regression fixtures that positively prove the
check fires (malformed JSON, missing frontmatter, hardcoded absolute path,
dangling script reference). This is PR #375 / commit `3fb17dc` (merged
2026-07-28), wired into `tests/run-suite.sh`'s boundaries stage. The roadmap
checkbox at `docs/ROADMAP.md:29` has never been flipped — **flagging for the
architect** (checkbox flips are `guard-roadmap`-gated on a merged-green
proof and not the product owner's to make, but the proof already exists).
Issue **#159** tracks this and, per **#981** (filed today), has been
"redeferred 3 sprints running" as a low-effort "verify-and-close" item that
keeps losing to higher-effort picks (**#709** names this exact failure
pattern generically). Ranked below as a cheap sprint-4 close, and the
architect action is a same-day unblock, not a sprint-4-sized item.

### Verified this pass: real work landed off-plan, uncheckpointed

Three merged PRs since sprint 3's plan was written are in neither its
committed core (#442/#419/#420/#423/#100) nor its overflow
(#101/#120/#132/#342/#361/#459/#94/#95) list: **#731** ("failed sessions
resume on rerun instead of re-paying from zero", merged 2026-08-04) —
its source issue **#725** is titled "P0: CI sessions restart from zero
after a failure" and the sprint-3 plan itself was never updated to reflect
it as a human-injected top priority; **#421** ("fail the CI run when a
session lands no real deliverable", merged 2026-08-04); **#878** (staging
fix for #731's resume helper, merged 2026-08-04). This is legitimate,
valuable work — not a complaint about it happening — but it explains part
of why sprint 3's ceremonies never fired: **#979** (filed today) names the
exact gap — "no mechanism reconciles the active sprint plan when
human-injected priority work (#725-style) displaces it." That's a process
fix, not mine to implement, but it's ranked below as P1 because it's the
same root cause that produced this session's six-day ceremony silence and
will recur every time a genuine top-priority item lands off-cycle.
`checkpoint.json` needs reconciliation to current `HEAD` before the planner
can trust its `issues[]` resume list — flagging for the planner, not fixing
it here (docs/state boundary).

### Verified this pass: #120 was silently, falsely closed for a week — now reopened

**#120** (`secrets: inherit` exposes full-scope `FACTORY_PAT` to inbound,
attacker-triggered stations) was found **closed** (`state_reason: completed`,
closed 2026-07-29T04:30:45Z by PR #405) while its actual fix, **PR #311**,
remains open and unmerged to this day (`mergeable_state: behind`). This was
the exact false-closure **#452** was filed to track — #452 is itself still
open, unresolved, a week later. The reopen action was one API call, but per
**#580** (open; **#474** and **#537**, the same finding's earlier filings,
are already closed) it had been "trapped in deferrable overflow
with no unconditional owner" across two sprint plans, and **#709** names
this as a systemic pattern (cheap paperwork fixes starved by higher-effort
picks). This same wake's sprint-4 plan executed the reopen directly
(2026-08-05T21:38:54Z) rather than deferring it a third time, so #120 no
longer reads closed as of this PR — but it read closed on every dashboard
and every `/factory-status` check for the entirety of this review. Ranked
P0 below — security outranks everything at equal priority (rule 1), and a
*miscounted* security gap is worse than an honestly-open one.

### P0 — must not wait

| # | Why P0 |
|---|---|
| #444 / ADR 0005 | Headline finding above — route to `/judge-panel` as sprint 4's board session; the review loop on this PR is actively growing the M4 gate's blocking count. Not an implementer pick — architect convenes. |
| #471, #688 | Root cause of the duplication that's inflating the tech-debt count, and #688 also self-blocks `debt-reconcile`'s Stop hook on every `/review` — fixing this is what makes any tech-debt count trustworthy again. |
| #120 | Falsely shown closed for a week while its real fix (PR #311) sits unmerged — see finding above. Reopen now; close correctly only when #311 merges. |
| #423 | Blocks #311 (hence #120): PR #311's `secrets: inherit` removal hard-fails the reviewer station's token mint with no fallback. Sprint-3 committed-core item, still open. |
| #442 | Sprint-3 committed core, P0-labeled, still open: `guard-commit`/`record-green` resolve `PROJECT_DIR` to the main checkout instead of the worktree — the commit gate can check the wrong tree in a worktree-isolated session. |
| #419, #420 | Sprint-3 committed core, P0-labeled, still open: unbounded `gh issue list` calls in `debt-reconcile.sh` and the `/factory-status` banner cap real counts at the newest 30. This session had to hand-paginate the GitHub search API to get the true 754/12 counts above — proof the bug is live today, not theoretical. |
| #101, #132 | Security-floor overflow, still open. #132's PR #318 has its own **#978** P0 incident open today: zero state delta across 3 consecutive sprints (2026-07-25 → 2026-08-05, confirmed via the PR's `updated_at`). Per sprint-3 plan's own staleness rule, reassign away from the stalled owner rather than carry a 4th sprint. |

### P1 — sprint 4 core (top of backlog for the planner, ranked)

1. **#444/ADR 0005, #471/#688, #120, #423, #442, #419/#420, #101/#132** — P0
   above, in that order; the first two stop active damage, the rest are
   sprint 3's own unclosed committed core plus the falsely-closed security
   item.
2. **#159** — cheap: verify-and-close (substance already merged, verified
   by me this pass — see above). Actually close it this time.
3. **#979** — no mechanism reconciles the sprint plan when human-injected
   priority work displaces it; root cause of this sprint's own ceremony
   silence and of #731/#421/#878 landing uncheckpointed. Feeds the
   planner's retro.
4. **#360** — P0-labeled incident, still open: sprint-1's ceremony silence
   recurred as sprint-3's (this session exists because of it); bundle with
   #361 (standup step, still open) and #979 as one ceremony-reliability
   fix rather than three separate items.
5. **#314** — active-agent role marker has no in-session reset path, locks
   a session out of all local writes after any review dispatch. Plausible
   contributor to stalled/silent sessions; worth confirming against the
   ceremony-silence pattern above.
6. **#319** — `debt-reconcile`'s Stop hook silently treats a missing `gh`
   CLI as *zero* open tech-debt (permanently blocking Stop with a false
   green signal). Verified live in this session's own environment: `gh` is
   in fact not installed here. Masks the exact gate this repo depends on.
7. **Hook unit tests** (`docs/ROADMAP.md` M2, next real item after the
   already-done static-validation layer) — actual Release-Gate substance.
   Sequenced after the floor above, same logic as sprints 1–3: gate work
   lands unreliably while the review-loop is actively poisoning the count
   it's supposed to reduce.

That's a 13-item ranked core (7 P0 + 6 P1), sized similarly to prior
sprints' floor+core bands. **#138** (coordination-substrate, contested)
remains routed to `/judge-panel`, unchanged, not decided here — now sharing
a convening slot naturally with #444/ADR 0005 if the architect chooses to
run both at sprint 4's board session.

### P2 — real, bucketed by theme (not individually sequenced this sprint)

- **Loop-health cluster (#231, #206)** — unchanged disposition from
  sprints 2–3: bundle as one item, cron-prod dispatch inversion +
  durable checkpoint write-back.
- **#229** — `guard-bash-writes` misdiagnoses read-only trust-root
  inspection as writes. Unchanged from sprint 3's disposition: real, P1
  severity, ranked below this sprint's P0/P1 on dependency grounds.
- **Bootstrap/egress-proxy hardening (#163–#249 range)** — unchanged from
  sprints 1–3, maps to M3's "Security hardening pass" bullet as one bundled
  item; explicit P1-severity items inside remain **#179, #180, #195, #202,
  #238**.
- **The ~591 zero-priority-signal `tech-debt` issues** — this pool did not
  shrink from sprint 3's "triage pass 1" effort; it *grew*, almost entirely
  from the PR #444 review-loop (headline finding above). Re-attempting
  triage on this pool before the loop is stopped is pouring water into a
  running tap — sequence the judge-panel routing and #471/#688 fix first,
  then re-measure before committing further triage capacity.
- **#177** — single self-hosted runner serializes the factory; throughput
  constraint, not correctness. Unchanged disposition.

### P3 — unchanged from sprint 1

`#141–143, #146–157`: doc cross-reference drift, routed to `v1.1.0`. PR #139
(the PR these depended on) has since closed; moot unless a judge-panel
convening on #138 revives the underlying question.

### Milestone-scope decisions this pass

- No milestone moves. `v1.0.0` set stands.
- Freeze stays **OFF**, restated above with current evidence — the gate is
  farther away than at any prior snapshot, not closer.
- **ADR 0005's M4 gate-scope redefinition is now ADOPTED** — the
  judge-panel this snapshot routed the contest to has since convened
  (sprint-4 board session) and settled it as **ADR 0006**; the single
  normative gate definition is `docs/specs/epic-1/spec.md` § "Release
  Gate for v1.0.0" (scope per ADR 0005, mechanism per ADR 0006). The
  reservation recorded here at planning time is resolved by that board
  decision — and note the lane: the reservation's OWN text conditioned
  adoption on "until judge-panel resolves it," so this conform executes
  the product owner's recorded condition rather than crossing into the
  scope lane (#1212); the edit was made by the ADR 0006 landing PR so
  no document contradicts the gate at merge (#1192).
- Left #138 with its standing disposition: `v1.0.0`, P1, routed to
  `/judge-panel` — unchanged.

### Not touched this pass

PRs #444, #318, #311, #250, #92 are implementer/release-captain/architect
territory, not product-owner's to merge, close, or convene alone. #444 is
flagged above only because its review-loop's *output* (the tech-debt count)
is exactly what this ranking depends on being trustworthy — the decision to
route it to judge-panel and pause its review cycle is the architect's/
conductor's to execute, not mine to do unilaterally beyond recording the
recommendation and evidence here.

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
   `--limit`, defaulting to `gh`'s newest-30, against 221 currently open. The
   Stop-gate reconciliation this repo's whole tech-debt convention depends on
   — and by extension M4's Release Gate (per `docs/specs/epic-1/spec.md` § "Release Gate for v1.0.0", scoped by ADR 0005 / mechanized by ADR 0006) — cannot see ~86%
   of what it's supposed to enforce against at current backlog size. This is
   a gate-integrity bug, not routine tech-debt.
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
unmilestoned for now. (Correction under the adopted gate, #1223: the
retired literal reading would have swept these before ship; the
adopted scope — spec § "Release Gate for v1.0.0" — blocks only open
bug/P0-P1/ever-security/ever-confirmed-high/untriaged, so non-security
P2/P3 in this batch can ship open and route to the M5 burndown.)

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
