# Epic 1 — the plugin test suite (spec)

Tracking issue: created by `bootstrap.sh` (milestone v1.0.0). Owner: qa
(suite health) + implementer (all code). This spec is the definition of
"covered" for this plugin, and the first sprint's scope.

## Why

The plugin enforces discipline on other repos; its own hooks, commands, and
skills are currently validated only by contract tests and manifest checks. A
factory that ships enforcement tooling with untested enforcement is not
credible — and the suite is what makes the v1.0.0 Release Gate decidable.

## What (three layers)

1. **Static validation** (commit-gate speed): manifest + frontmatter schema
   checks for every command/agent/skill/hook config; path portability
   (`${CLAUDE_PLUGIN_ROOT}` only — no absolute or repo-relative plugin paths);
   referenced files exist; JSON validity. Fails the gate on any violation.
   Seed exists in `tests/scaffold.contract.test.sh`; this layer extends it to
   full schema depth.
2. **Unit tests for every hook script**: stdin JSON fixtures per event type;
   assertions on exit codes AND stderr class tags (`[hard-boundary]` vs
   `[heuristic]`); matcher edge cases; forgery-guard cases; multi-repo
   `-C`/`cd` binding. **Coverage ≥95% lines on `hooks/scripts/**` and
   `hooks/lib/common.sh`, enforced as a failing test** — that is what makes
   "no uncovered cases" machine-decidable.
3. **Behavioral evals** (nightly): per skill/command, trigger evals — 8–10
   should-trigger and 8–10 near-miss shouldn't-trigger prompts, ≥3 runs each,
   trigger-rate thresholds — and outcome evals with programmatic assertions
   plus with-vs-without-plugin baseline lift. Headless `claude -p` harness;
   results to `factory-ops/qa/`; thresholds enforced in `nightly-eval.yml`.

Layers 1–2 run in the commit-gate suite (`tests/run-suite.sh`); layer 3 is
nightly. All layers are wired into `.factory/config.json` green stages so the
receipt/commit contract enforces them forever.

## Acceptance criteria

- [ ] Every command/agent/skill/hook config passes layer-1 checks in the gate
- [ ] Every hook script has fixture-driven unit tests incl. both stderr classes
- [ ] Coverage gate ≥95% lines on `hooks/scripts/**` and
      `hooks/lib/common.sh` fails the suite when unmet
- [ ] Trigger + outcome evals exist for every skill and command, with
      thresholds that fail `nightly-eval.yml`
- [ ] `.factory/config.json` gates run all deterministic layers; nightly runs
      layer 3
- [ ] Three consecutive nightly runs green on `main` (feeds the Release Gate)

## Release Gate for v1.0.0

Decidable, no judgment calls — every criterion below is either a pure label
query or a mechanical artifact check.

This section is the **single authoritative definition** of the gate — it is
where `docs/ROADMAP.md` (its preamble and M4) and `.claude/CLAUDE.md` pin the
gate, and `docs/PRODUCT.md` and `docs/ARCHITECTURE.md` point here rather than
restating it. Scope and rationale: ADR 0005
(`docs/adr/0005-m4-tech-debt-gate-scope.md`).

Every label criterion below matches **exact, case-sensitive label names as
they exist in this repo's label set**: `P0`, `P1`, `P2`, `P3`, `security`,
`bug`, `tech-debt`, `gate:confirmed-high`. Severity order, where a rule
says "most severe": `P0` > `P1` > `P2` > `P3`.

All of, verified by the `release-captain` in one script whose issue counts come
from **fully-paginated queries** (never a bare `gh issue list`, whose 30-item
default page is the counting bug tracked as #419/#420 — both must be fixed,
and the #649 anti-laundering backfill completed, before any automation
trusts this gate):

**Set membership is always ever-carried; only priority is current.** In
every criterion below, "tech-debt issue" and "bug issue" mean an issue
that has **ever carried** that label (`LabeledEvent` timeline, same
paginated GraphQL) — stripping `tech-debt`, `bug`, or `security` is not a
ranking act any charter authorizes, and a current-state anchor would let
exactly that strip remove an issue from the counted set entirely
(#887). The `P0`–`P3` labels alone are read current-state, because
re-ranking IS an authorized, auditable product-owner act — and the
ever-carried floors below bound what re-ranking can launder.

- zero open bug issues (ever-carried `bug`) — literal, unwaived (a bug
  is fixed, never deferred, even under freeze);
- zero open tech-debt issues currently labeled `P0` or `P1`;
- zero open issues that have **ever carried** `security`, at any
  `P0`–`P3` level and regardless of any other label — issue-type-agnostic
  by design, a cross-priority rule decided in ADR 0005, which
  deliberately **extends** `docs/PRODUCT.md` ranking rule 1 (on its own
  that rule is only an equal-priority tie-breaker);
- zero open tech-debt issues lacking a valid `P0`–`P3` label
  (**fail-closed**: an untriaged issue blocks the gate until it carries one
  of `P0`–`P3`; legacy `priority:*`/`high`/`medium`/`low` labels do not
  count as triage; if more than one `P0`–`P3` label is present, the most
  severe governs). The triage pass that clears this is tracked as #510;
- zero open issues that have **ever carried** `gate:confirmed-high` —
  the **anti-laundering criterion**, with no further qualifier: an OPEN
  issue in this set always blocks (a fixed finding exits the set by being
  closed by its fix PR, which the close-laundering criterion then
  verifies — there is no "fixed but still open" state to adjudicate, so
  no judgment call). This one is deliberately a **timeline query, not a
  current-label query** (`LabeledEvent`s in the same fully-paginated
  GraphQL): a current-state label query would be defeated by simply
  removing the label from an open, down-triaged issue. The tech-debt
  clerk applies
  `gate:confirmed-high` at filing time to every issue it opens from a
  CONFIRMED-high adversarial-review finding; the label is a severity
  **floor** that coexists with whatever `P0`–`P3` label triage assigns.
  Because history cannot be unlabeled, neither down-triage nor label
  removal unblocks the gate — only the finding's fix merging (per the
  close-laundering criterion's exemption (a), fingerprint-bound) does.
  The clerk mechanism is prospective
  only — the one-time backfill audit of the pre-existing backlog is
  tracked as #649 and is a **prerequisite of this criterion**: until #649
  closes, this criterion is not evaluable (same gating shape as the eval
  thresholds on #511);
- zero gate-relevant issues closed at or after **2026-07-29** (the
  ground-truth baseline date) other than through a mechanically-verified
  fix or duplicate — the close-laundering criterion, **fail-closed across
  every close reason**. "Gate-relevant" uses the same ever-carried set
  membership the open-issue criteria use (a strip-the-labels-then-close
  sequence must not slip past the close audit either): ever-carried
  `bug`; or ever-carried `security` or `gate:confirmed-high` (regardless
  of any other label); or ever-carried `tech-debt` with `P0`/`P1`
  current at close time; or ever-carried `tech-debt` lacking a valid
  `P0`–`P3` label at close time. A closed gate-relevant issue is exempt
  only if:
  (a) `stateReason` is `completed` **and** GitHub's closed-by-PR
  cross-reference (`closedByPullRequestsReferences` in the same
  fully-paginated GraphQL) lists at least one **merged** pull request,
  **and** that merged PR has a **non-empty diff**, **and** — for an issue
  whose body carries a `fingerprint:` trailer (all clerk-filed review
  findings do) — two bindings both hold: (i) the same fingerprint is
  cited in **immutable evidence only** — a commit message of that merged
  PR, or of a later commit merged to the default branch that names both
  the issue and the fingerprint (the remediation path for a genuine fix
  whose author forgot — still never a permanent block); the PR **body is
  explicitly NOT accepted**, being editable after merge; and (ii) the
  qualifying PR's diff **touches the finding's location**: at least one
  changed file path equals the `file` component of the issue's recorded
  `location` (`file:line` in the clerk-filed body — decidable from the
  PR file list in the same GraphQL), so a one-line no-op PR citing the
  publicly-visible fingerprint cannot retire a finding it never went
  near. Where the location file no longer exists (renamed/deleted), a
  commit message of the qualifying PR must name the old path — same
  immutability rule. The fix-side obligation lives in
  `agents/implementer.md` step 6, defined together with this check. An
  issue with no fingerprint trailer needs the merged, non-empty-diff
  closing PR — stated honestly as a **heuristic floor**, not a proof of
  fix, since hand-filed issues carry no machine-readable location; or
  (b) `stateReason` is `duplicate` and the duplicate target — the issue
  named by the **most recent `MarkedAsDuplicateEvent`** on the closed
  issue's timeline (same fully-paginated GraphQL; no such event → the
  exemption does not apply, fail closed), followed **transitively**
  through further duplicate closures to a terminal issue (a cycle or a
  chain that does not terminate → fail closed) — is itself
  **gate-relevant** and either still open (so the open-issue criteria
  count it) or exempt under (a). A duplicate whose terminal target is not
  gate-relevant blocks: routing debt onto an issue no criterion watches
  is laundering, not deduplication. Everything else — `completed` with no
  merged PR, `not planned`, duplicate without a qualifying target —
  blocks the gate. Mass-closing the backlog therefore cannot green the
  gate under any close reason;
- issues **#419, #420, #511, and #649 are CLOSED** — the gate-tooling
  integrity prerequisites as a mechanical **state** check, not a prose
  note and not a label query: down-triaging any of them cannot defer the
  requirement, because the criterion asks whether the issue is closed,
  not what priority it carries. (Their closes are themselves subject to
  the close-laundering criterion above, so closing-without-fixing does
  not satisfy this either.);
- zero unresolved `.factory/review` findings (debt-reconcile clean);
- v1.0.0 roadmap items 100% merged-green;
- coverage ≥95% lines on `hooks/scripts/**` **and `hooks/lib/common.sh`**
  (the library the gate's own paginated counting relies on — an untested
  counting path is the #419/#420 class recurring), measured at **the exact
  SHA `/ship` builds: the tip of the release branch at the moment the
  Release Gate script runs, the same commit the release-proof is minted
  on** — a commit-gate artifact bound to one concrete ref, not a nightly
  one;
- the `nightly-eval.yml` eval thresholds green on `main` for 3 consecutive
  nightly runs. The eval threshold **values** are TBD — owner: qa, tracked
  as #511; this criterion is not evaluable until #511 closes;
- feature freeze ON — machine-decidable marker: the `## Feature freeze`
  section of `docs/PRODUCT.md` contains **exactly one** line beginning
  `**Freeze state:`, and that line **begins with** `**Freeze state: ON**`
  (trailing annotation after the marker is allowed). A freeze
  flip edits that single line in place — never appends a second state line —
  so the test is over the current state, not a flip log.

Non-security `P2`/`P3` tech-debt does not block v1.0.0; it is routed to the
named ROADMAP M5 (v1.1.0) item "P2/P3 tech-debt burndown (non-security)" —
distinct from M3's security-hardening pass, which is security-scoped and
v1.0.0-scoped. Then `/ship` on the release branch — never from red,
release-proof minted on the built artifact.
