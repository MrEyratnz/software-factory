# Roadmap

Worked top-to-bottom. An item flips to `[x]` only when its PR merged with
green tests (`guard-roadmap` demands the proof — never check a box by hand).
Milestone gate for v1.0.0: the Release Gate in `docs/specs/epic-1/spec.md`.

## M1 — Epic 1: the test suite (milestone v1.0.0)

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

## M2 — Autonomous SDLC hardening (milestone v1.0.0)

- [ ] Sprint ceremonies produce their artifacts end-to-end (planning, standup,
  review, retro with filed improvement issues) across two consecutive sprints
- [ ] Cost telemetry recorded per station to `factory-ops/cost/` and the
  routing table revisited with real data at a retro
- [ ] Security hardening pass: CodeQL + secret-scanning config verified,
  SHA-pin audit across ALL workflows (including pre-factory ones), per-session
  pinned container images per `docs/security/README.md` gap register
- [ ] Board session #1 held via judge-panel with a synthesized ADR

## M3 — v1.0.0 (milestone v1.0.0)

- [ ] Release Gate script green: zero open `bug`/`tech-debt`, zero unresolved
  review findings, v1.0.0 roadmap 100% merged-green, coverage + eval
  thresholds green on `main` for 3 consecutive nightly runs
- [ ] `/ship` v1.0.0 from the release branch (proof minted on the built
  artifact)

## M4 — Post-1.0 (milestone v1.1.0)

- [ ] Feature-freeze overflow: `idea`/`research`/retro issues routed here by
  the product owner once the v1.0.0 gate is within one sprint of holding
