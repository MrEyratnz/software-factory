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

## Release Gate for v1.0.0 (decidable, no judgment calls)

All of, verified by the release manager in one script: zero open `bug` or
`tech-debt` issues at any priority; zero unresolved `.factory/review` findings
(debt-reconcile clean); v1.0.0 roadmap items 100% merged-green; coverage and
eval thresholds green on `main` for 3 consecutive nightly runs; feature freeze
per `docs/PRODUCT.md`. Then `/ship` on the release branch — never from red,
release-proof minted on the built artifact.
