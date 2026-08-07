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
   `-C`/`cd` binding. **Coverage ≥95% lines on `hooks/scripts/**`, enforced as
   a failing test** — that is what makes "no uncovered cases"
   machine-decidable.
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
- [ ] Coverage gate ≥95% lines on `hooks/scripts/**` fails the suite when unmet
- [ ] Trigger + outcome evals exist for every skill and command, with
      thresholds that fail `nightly-eval.yml`
- [ ] `.factory/config.json` gates run all deterministic layers; nightly runs
      layer 3
- [ ] Three consecutive nightly runs green on `main` (feeds the Release Gate)

## Release Gate for v1.0.0

This section is the **single maintainable copy of the gate predicate**
(ADR 0005's single-copy rule; the spec governs on any divergence).
Mechanism and rationale: ADR 0006 (`docs/adr/0006-release-gate-synthesis.md`,
the sprint-4 board decision); scope: ADR 0005. All criteria are over
current state, from fully-paginated queries; the gate returns PASS,
FAIL (naming failed criteria with evidence), or BLOCKED (naming open
prerequisites) — no "not evaluable" meta-states.

1. Zero open issues labeled `bug`.
2. Zero open `tech-debt` issues currently labeled `P0` or `P1`
   (most-severe governs when several `P0`–`P3` labels are present).
3. Zero open issues labeled `security`, at any priority (ADR 0005's
   cross-priority security precedence).
4. Zero open `tech-debt` issues lacking a valid `P0`–`P3` label —
   fail-closed on untriaged; legacy `priority:*`/`high`/`medium`/`low`
   labels do not count (#510 clears this).
5. Zero open issues labeled `gate:confirmed-high` (clerk-applied floor;
   the nightly auditor re-applies any stripped floor label, which is
   what makes a current-state read safe).
6. Auditor liveness: a successful `close-audit` run within 24 hours of
   the gate run, with recorded audit windows covering [2026-07-29, the
   end of that run's window] gapless; the tail to gate time is bounded
   by the freshness rule.
7. Mechanical artifact checks: coverage ≥95% lines on
   `hooks/scripts/**`, `hooks/lib/common.sh`, and
   `connector/src/release-gate/**`, measured at the exact SHA `/ship`
   builds; three consecutive green `nightly-eval.yml` runs on `main`
   (thresholds per #511); the single-line `**Freeze state: ON**` marker
   in `docs/PRODUCT.md`; prerequisite issues #419, #420, #510, #511
   closed; zero unresolved `.factory/review` findings; every v1.0.0
   roadmap item merged-green except M4's own two terminal boxes.
8. Trust-anchor custody intact and one verified human acknowledgment
   per release (ADR 0006 §§ D5–D6 define both mechanically).
9. Zero standing contested closes (ADR 0006 § D4's parked bucket).

Then `/ship` on the release branch — never from red, release-proof
minted on the built artifact.
