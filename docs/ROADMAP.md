# Roadmap

Milestones are ordered; within a milestone, tasks are independent unless noted.
The autonomous loop works this list top-to-bottom, TDD-first, keeping the full
suite green at every commit. **An item is checked off only when its work merges
with green tests — never in advance.** (The `guard-roadmap` gate enforces this.)
Milestone gate for v1.0.0: the Release Gate in `docs/specs/epic-1/spec.md`.

## M0 — Foundation

- [x] Plugin + marketplace manifests (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) validating `--strict`
- [x] Hooks layer (guard-commit/scope/bash-writes/roadmap/release/mcp-commit, record-green, debt-reconcile, loop-guard, …) with hermetic contract tests (`tests/hooks.contract.test.sh`)
- [x] Zero-dependency connector MCP server (`connector/`) sharing one pure core with the hooks, with unit + stdio protocol tests
- [x] CI validate workflow (both suites, shellcheck, plugin + marketplace validation) and gated release automation via release-please
- [x] Claude issue-triage and adversarial code-review workflows with ready-label / project-board handoff
- [x] Docs spine (ADR 0001–0002) and self-dogfooding: the repo runs the plugin from its own working tree (lands in the same PR as this file)

## M1 — Hardening

- [x] Node adapter `sourceRegex`/`testRegex` cover `.tsx` and monorepo source roots so the tests-first gate stops under-firing (#47)
- [x] `roadmap-proof.json` gains a sanctioned CI/runner producer so `/roadmap check` has an in-repo path to succeed (#51)
- [x] Hard gates surface loudly (or fail closed) instead of silently failing open when `node` is unavailable (#52)
- [x] Target-aware gates read enforcement config from the target repo, not the session repo, in multi-repo sessions (#53)
- [x] Review workflow's `gh pr comment` is pinned to the triggering PR instead of prefix-matched (#60)
- [x] Triage runs lose the direct `gh label create` write — labels are ensured deterministically before the model step (#61)

## M2 — Epic 1: the plugin test suite (milestone v1.0.0)

- [ ] Static validation layer in the commit gate: manifest + frontmatter schema
  checks for every command/agent/skill/hook config, `${CLAUDE_PLUGIN_ROOT}`
  path portability, referenced-files-exist, JSON validity (extends
  `tests/scaffold.contract.test.sh`)
- [ ] Hook unit tests: stdin JSON fixtures per event type, exit-code and
  stderr-class (`[hard-boundary]` vs `[heuristic]`) assertions, matcher edge
  cases, forgery-guard cases, multi-repo `-C`/`cd` binding
- [ ] Coverage threshold ≥95% lines on `hooks/scripts/**`, enforced as a
  failing test in the suite
- [ ] Behavioral evals: trigger evals per skill/command (8–10 should /
  8–10 near-miss shouldn't, ≥3 runs each, trigger-rate thresholds) via a
  headless `claude -p` harness, results to `factory-ops/qa/`
- [ ] Outcome evals with programmatic assertions plus with-vs-without-plugin
  baseline lift, thresholds enforced in `nightly-eval.yml`
- [ ] Wire all suite layers into `.factory/config.json` green stages so the
  receipt/commit contract enforces them permanently

## M3 — Autonomous SDLC hardening (milestone v1.0.0)

- [ ] Fix the bootstrap-era receipt bugs: `record-green`'s 30s hook timeout vs
  multi-minute suites, the `/factory-init` config chicken-and-egg, and the
  receipt mint/check location asymmetry for sibling-repo commits
- [ ] Sprint ceremonies produce their artifacts end-to-end (planning, standup,
  review, retro with filed improvement issues) across two consecutive sprints
- [ ] Cost telemetry recorded per station to `factory-ops/cost/` and the
  routing table revisited with real data at a retro
- [ ] Security hardening pass: CodeQL + secret-scanning config verified,
  SHA-pin audit across ALL workflows (including pre-factory ones), per-session
  pinned container images per `docs/security/README.md` gap register
- [ ] Board session #1 held via judge-panel with a synthesized ADR

## M4 — v1.0.0 (milestone v1.0.0)

- [ ] Release Gate script green: zero open `bug`/`tech-debt`, zero unresolved
  review findings, v1.0.0 roadmap 100% merged-green, coverage + eval
  thresholds green on `main` for 3 consecutive nightly runs
- [ ] `/ship` v1.0.0 from the release branch (proof minted on the built
  artifact)

## M5 — Post-1.0 (milestone v1.1.0)

- [ ] Feature-freeze overflow: `idea`/`research`/retro issues routed here by
  the product owner once the v1.0.0 gate is within one sprint of holding
- [ ] OTEL traces/spans for the lights-out loop (beyond the shipped metrics-only MVP)
- [ ] Prometheus/Grafana dashboards over the factory metrics
- [ ] Ledger-scraping sidecar
- [ ] Per-agent token accounting

## Continuous (every milestone)

- Keep README, CONTRIBUTING, and this file truthful
- Unfixed review findings become `tech-debt` issues — never dropped in chat
- No milestone closes with skipped tests or a red CI
