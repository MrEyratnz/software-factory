# Roadmap

Milestones are ordered; within a milestone, tasks are independent unless noted.
The autonomous loop works this list top-to-bottom, TDD-first, keeping the full
suite green at every commit. **An item is checked off only when its work merges
with green tests — never in advance.** (The `guard-roadmap` gate enforces this.)

## M0 — Foundation

- [x] Plugin + marketplace manifests (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) validating `--strict`
- [x] Hooks layer (guard-commit/scope/bash-writes/roadmap/release/mcp-commit, record-green, debt-reconcile, loop-guard, …) with hermetic contract tests (`tests/hooks.contract.test.sh`)
- [x] Zero-dependency connector MCP server (`connector/`) sharing one pure core with the hooks, with unit + stdio protocol tests
- [x] CI validate workflow (both suites, shellcheck, plugin + marketplace validation) and gated release automation via release-please
- [x] Claude issue-triage and adversarial code-review workflows with ready-label / project-board handoff
- [x] Docs spine (ADR 0001–0002) and self-dogfooding: the repo runs the plugin from its own working tree (lands in the same PR as this file)

## M1 — Hardening

- [ ] Node adapter `sourceRegex`/`testRegex` cover `.tsx` and monorepo source roots so the tests-first gate stops under-firing (#47)
- [ ] `roadmap-proof.json` gains a sanctioned CI/runner producer so `/roadmap check` has an in-repo path to succeed (#51)
- [ ] Hard gates surface loudly (or fail closed) instead of silently failing open when `node` is unavailable (#52)
- [ ] Target-aware gates read enforcement config from the target repo, not the session repo, in multi-repo sessions (#53)
- [ ] Review workflow's `gh pr comment` is pinned to the triggering PR instead of prefix-matched (#60)
- [ ] Triage runs lose the direct `gh label create` write — labels are ensured deterministically before the model step (#61)

## M2 — Later

- [ ] OTEL traces/spans for the lights-out loop (beyond the shipped metrics-only MVP)
- [ ] Prometheus/Grafana dashboards over the factory metrics
- [ ] Ledger-scraping sidecar
- [ ] Per-agent token accounting

## Continuous (every milestone)

- Keep README, CONTRIBUTING, and this file truthful
- Unfixed review findings become `tech-debt` issues — never dropped in chat
- No milestone closes with skipped tests or a red CI
