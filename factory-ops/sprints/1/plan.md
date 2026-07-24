# Sprint 1 — Plan

- **Sprint:** 1
- **Planned:** 2026-07-24T02:42:24Z (UTC, anchor)
- **sprint_ends_at:** 2026-07-24T02:42:24Z + 24h (SPRINT_HOURS default) = **2026-07-25T02:42:24Z**
- **Planner:** conductor/planner session (this file), from the product owner's
  ranked backlog in `docs/PRODUCT.md` ("Sprint 1 backlog snapshot",
  2026-07-24).
- **Status:** first sprint the factory has ever planned. No prior sprint to
  review or retro against (`factory-ops/sprints/` was seeded with only
  `.gitkeep`, checkpoint station was `idle`, sprint 0). Going straight to
  planning per charter.

## Sprint goal

Make the roadmap trustworthy, make the autonomous loop able to close a PR on
its own, and close the highest-severity permission/credential gaps that let
an attacker-controlled PR touch the factory's own credentials — then, if
capacity remains, start the M2 Epic 1 test-suite substance that is the
v1.0.0 Release Gate itself. Concretely, in this order:

1. **Fix the roadmap cursor** (#175) — M1's six Hardening items are already
   merged-green but the roadmap shows 0/6; every other roadmap-driven
   decision this sprint (and every sprint after) depends on this being
   correct first.
2. **Close the loop-breaking bug pair** (#97, #98) — the reviewer cannot
   approve on the read-only `GITHUB_TOKEN` fallback, and the `--merge`
   policy mismatch it was masking breaks self-merge the moment approval is
   fixed. Without both, `factory-run` can never close a PR unattended.
3. **Close the highest-severity permission/credential gaps** (#100, #101,
   #120, #132, #115) — the root-cause permission-ceiling bug and its two
   worst live consequences (prompt-injection surface on the review station,
   full-scope `FACTORY_PAT` reachable from inbound webhooks), plus the App
   scope gap that makes factory-run's own CI-check calls 403.
4. **Start M2 Epic 1 test-suite substance if capacity remains** (#159) — the
   first slice of the actual v1.0.0 Release Gate content, sequenced last
   because landing it on top of a still-broken merge loop or a leaking
   credential would be unreliable.

Everything else the product owner ranked (#106, #123, #94, #95, #160, #161,
and the 30 P2 items) is real and stays in the backlog for sprint 2+ — see
"Deliberately not picked" below.

## Picked issues

| # | Title (abridged) | Priority | Owner | Done-condition (machine-checkable) |
|---|---|---|---|---|
| #175 | ROADMAP.md M1 items shown 0/6 but already merged-green | P0 | **architect** | PR merges to `main` editing only `docs/ROADMAP.md` (M1 section), checking `- [x]` for all six of #47/#51/#52/#53/#60/#61, with the PR body citing the six merge-commit SHAs (`0791f5c`,`91a0b6d`,`3172785`,`aae1868`,`f60b216`,`f368743`) as evidence. Post-merge: `roadmap_status`/`roadmap_next` MCP tools report M1 as 6/6 and advance the cursor past M1. Docs-only diff (no `src/` touched). Issue #175 auto-closes via the PR's closing keyword. |
| #97 | `GITHUB_TOKEN` fallback is read-only — reviewer can never approve | P0 | **implementer** | PR merges with a failing-then-passing test asserting the review/approval workflow step authenticates with a token that has `pull-requests: write` (App token or equivalent, not the read-only default fallback) in every station that can be asked to approve. Full suite green (`bash tests/run-suite.sh`) on the merge commit. Issue #97 closes via merge. |
| #98 | on-pr merge job uses `--merge`, which this repo forbids | P0/P1 | **implementer** | PR merges (paired with #97 in the same PR or a stacked PR) changing the merge job's policy to the repo's allowed merge method (squash/rebase per repo settings), with a test/assertion pinning the merge-method argument. Full suite green. A synthetic/staged PR (or a workflow dry-run) demonstrates auto-merge succeeds post-fix without a `--merge`-forbidden failure. Issue #98 closes via merge. |
| #100 | Permission ceilings don't bind the credentials actually used | P0 | **implementer (security-steward focus)** | PR merges changing the affected workflow files so declared `permissions:` blocks match the actual token used per job (App token or PAT), with a test/lint step (or documented manual verification in the PR body) enumerating every job's effective token and its granted scopes. Full suite green. Issue #100 closes via merge; #101/#120/#132 re-verified against the fix (see below). |
| #101 | Review station: `bypassPermissions`, no tool allowlist, attacker-controlled PR text | P0 | **implementer (security-steward focus)** | PR merges replacing `bypassPermissions` on the review station with an explicit tool allowlist scoped to read-only review actions, verified by a test/fixture that a crafted malicious PR body cannot trigger a disallowed tool call. Full suite green. Issue #101 closes via merge. |
| #120 | `secrets: inherit` exposes full-scope `FACTORY_PAT` to inbound stations | P0 | **implementer (security-steward focus)** | PR merges removing `secrets: inherit` from every workflow reachable by an inbound issue/PR webhook, replacing it with an explicit least-privilege secret pass-through (or none). Full suite green plus a check (grep/test in CI) asserting no `secrets: inherit` remains on an inbound-triggered workflow. Issue #120 closes via merge. |
| #132 | Review job grants `issues:write` + `secrets:inherit` over attacker-controlled diff | P1 (shares #100's root cause) | **implementer (security-steward focus)** | Fixed alongside #100/#101/#120 in the same PR series: review job's `permissions:` drops `issues:write` unless actually needed for that job, and drops `secrets: inherit`. Full suite green. Issue #132 closes via merge. |
| #115 | coder App lacks `actions:read`; factory-run's own CI-check calls 403 | P1 | **implementer** | PR (or App-manifest/config change with evidence in the PR body since GitHub App permission grants aren't a repo-file diff) grants the coder App `actions:read`, verified by a `gh run` / equivalent CI-status call succeeding from the coder station in a real or replayed run (link the successful run in the PR body). Issue #115 closes via merge or a linked verification comment if the fix is an App-settings change with no diff. |
| #159 | Epic 1.1: static validation layer in the commit gate | P1 (M2, v1.0.0 gate) | **implementer** | **Stretch — only if capacity remains after items 1–3 above are merged-green.** PR merges adding manifest + frontmatter schema checks for every command/agent/skill/hook config to the commit gate (extends `tests/scaffold.contract.test.sh`), with new tests failing red before the change and green after. Full suite green. Issue #159 closes via merge. If not started this sprint, it is the first item planned for sprint 2. |

9 concrete work items (#175, #97, #98, #100, #101, #120, #132, #115, #159) —
within the 8–12 target range, biased toward the floor (roadmap truth + loop
+ security) with one M2 item as an explicit stretch goal.

## Routed, not decided here

| # | What | Route |
|---|---|---|
| #138 | Coordination-substrate milestone-scope decision — contested, PR #139 carries unresolved review findings #141–157 | **judge-panel** — convene `/judge-panel` before deciding; not the planner's or product owner's call to make unilaterally. Owner of convening: architect. |

## Flagged for early sequencing (not this planner's issues to pick, noted for the implementer/release-captain)

- **PR #162** — fixes the egress proxy fatally crashing runners. Not a
  backlog issue but an open PR; the product owner flagged it as
  sprint-1-relevant by inspection since a flaky runner blocks every station
  above. Recommend the implementer/release-captain merge it early, ahead of
  or alongside #97/#98, if it is green and unblocked — but the merge
  decision belongs to those roles, not this plan.
- **PR #139** — contested coordination-substrate docs change carrying the
  unresolved findings that #138 is routed to judge-panel over. Do not merge
  ahead of the judge-panel synthesis.
- **PR #102** (dependabot), **PR #92** (release-please) — routine, no
  sprint-goal dependency; implementer/release-captain discretion on when to
  merge.

## Deliberately not picked (left in backlog, ranked for sprint 2+)

- **#106, #123** — narrower loop/security gaps in the same permission
  cluster as #100/#101/#120/#132; the product owner's own review verdicts
  rank these lower-severity. Next after the sprint-1 floor.
- **#94, #95** — the two bootstrap-era receipt bugs ROADMAP M3 names
  explicitly (30s hook timeout vs multi-minute suites; mint/check location
  asymmetry for sibling-repo commits). Real and cheap, but sequenced after
  the security floor per the product owner's ranking; first candidates if
  #159 is dropped from this sprint's stretch slot for capacity reasons.
- **#160, #161** — remaining M2 Epic 1 sub-issues (hook unit tests +
  coverage gate; behavioral/outcome evals). Natural continuation of #159 in
  sprint 2.
- **30 P2 issues** (#103–105, #107–114, #116–119, #121–122, #124–131,
  #133–137) — all genuine PR #99 adversarial-review findings, none blocking
  the loop today. Per the product owner's milestone-scope decision, these
  bundle into ROADMAP M3's "Security hardening pass" as one work item, not
  30 individually-sequenced sprint items.
- **15 P3 issues** (#141–143, #146–157) — doc cross-reference drift internal
  to unmerged PR #139; routed to v1.1.0 by the product owner, moot unless
  #138/#139 actually merge.

## Reassignment / staleness note

No prior sprint exists, so there is no owner to have gone stale yet. This
note is here per charter for the standup ceremony to reference going
forward: if any of the above owners produce no state delta across three
consecutive wakes, the standup reassigns that item and files a `P0`
incident per the fence rules in `.claude/CLAUDE.md`.
