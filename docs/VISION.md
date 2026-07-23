# Vision — dark-software-factory

## What this is

A lights-out software factory for Claude Code, shipped as a plugin. Drop it into a
repository (`/factory-init`) and it runs a bounded autonomous production line:
scaffold the docs spine, drive a TDD roadmap loop (`/next` → `/review` → `/ship`),
settle contested decisions by judge panel, and release via gated Conventional
Commits. Its laws — "never commit red," "a roadmap box flips only with merged-green
proof," "never release from red," "no review finding is silently dropped" — are not
conventions an agent is asked to follow; they are preconditions the harness
**denies** via hooks locally and re-enforces in CI. It is for teams who want agents
doing real, unattended production work without having to trust the agent's
discipline. This repository builds the plugin and is governed by it: the working
tree enforces itself (ADR-0002), and the SDLC around it — sprints, triage, review,
release — runs as an autonomous, event-driven factory in GitHub Actions (ADR-0003)
whose standing goal is the decidable v1.0.0 Release Gate
(`docs/specs/epic-1/spec.md`).

## Why it wins

| Competitor | Weakness we exploit |
|---|---|
| Plain Claude Code + a CLAUDE.md conventions file | Laws are prose. A busy or drifted agent skips them, and nothing stops a red commit, an out-of-scope write, or a dropped review finding. |
| CI-only enforcement (branch protection + required checks) | Catches red only after push — slow feedback, burned iterations — and cannot see in-session behavior at all: scope fences, receipt forgery, roadmap check-offs, tech-debt filing. |
| Agent-workflow plugins/frameworks relying on prompt-level discipline | Rules live in prompts and agent descriptions, so they degrade exactly when they matter most: long sessions, stale context, adversarial inputs. No deterministic gate backs them. |

Differentiators:

1. **Denial, not advice.** `guard-commit` requires a green receipt bound to the
   exact `git write-tree`; `guard-roadmap` demands merged-green proof;
   `guard-release` gates both Bash and github-MCP release paths; `debt-reconcile`
   will not let a session end with a finding unfixed *and* unfiled.
2. **One rule engine, two enforcement points.** The same pure, zero-dependency
   core (`connector/src/factory-core.mjs`) backs both the connector's read tools
   and the hooks (via `connector/src/cli.mjs`), so advice and enforcement can
   never disagree — and CI re-runs the identical gates as the authoritative
   boundary.
3. **Least-privilege crew.** Per-role fences (reviewers denied all source writes
   and fenced to their `.factory/review/` findings, a docs-only architect, a
   design-dirs-fenced design-lead, a no-source-edits release-captain, a sole
   gh-write tech-debt clerk) close receipt forgery and config poisoning rather
   than discourage them.
4. **Self-hardened.** The plugin was designed by the method it encodes and
   dogfoods itself from its own working tree, so a hook regression surfaces in
   the very session that introduces it — and its own backlog, sprints, and
   releases are worked by the factory it implements, under per-role GitHub App
   identities with security as the first pillar and token-efficiency as the
   second (`GOVERNANCE.md`, `docs/security/README.md`,
   `factory-ops/cost/ROUTING.md`).

## Product pillars

1. **Enforced invariants** — every methodology law is a hook decision locally and
   a re-run check in CI; the docs describe the law, the harness applies it.
2. **A deterministic, read-only spine** — the connector MCP server exposes the
   rules (`roadmap_status`, `gate_evaluate`, `commit_lint`, `release_plan`, …) as
   pure tools and never mutates the repo; mutation stays in the
   command/agent/hook layer under normal permissions.
3. **Bounded autonomy** — `/factory-run` is a lights-out loop with a hard
   iteration cap (`loop-guard`, `maxIterations`); fan-out is reserved for the two
   panels (judge-panel, review) where independence is the enforcement value, and
   the core loop stays a single session working the roadmap top-to-bottom.
4. **Nothing gets lost** — adversarial review ends in fix-or-file: unfixed
   findings become `tech-debt` GitHub issues, and the `debt-reconcile` stop gate
   plus `/debt` keep the debt reconciled instead of buried in chat.
5. **Portable installation** — `/factory-init` scaffolds the docs spine,
   `.factory/config.json`, CI, and labels into any repo, with node/python/go
   stack templates and custom gates for everything else.

## Non-goals (for now)

- OTEL traces/spans, Prometheus/Grafana dashboards, or a ledger-scraping
  sidecar — telemetry is an opt-in, collector-only, metrics-only MVP that can
  never change a hook's decision.
- Per-agent token accounting.
- Unbounded autonomy — no self-extending loops; the factory stops at its
  iteration cap (locally) or its `FACTORY_HALT`/pause kill switches (in CI) and
  hands back to a human.
- Replacing CI or branch protection — CI remains the authoritative boundary;
  hooks are fast local pre-enforcement, not a substitute.
- A mutating connector — the MCP server stays pure and read-only, and hooks stay
  POSIX + node stdlib with zero runtime dependencies.
- Replacing human judgment where GitHub requires a human (account creation,
  KYC/banking, app-install clicks) — those stay one-time `bootstrap.sh` acts.
