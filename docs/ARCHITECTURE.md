# Architecture

## Shape

Two layers in one repo: the **plugin** (the product) and the **factory ops**
(the autonomous SDLC that builds it). Decisions of record live in `docs/adr/`;
this file reflects their outcomes, never overrides them.

### The plugin (product)

| Component | Responsibility | Depends on |
|---|---|---|
| `connector/` | model-free spine: pure rule verdicts (`factory-core.mjs`) exposed as MCP tools + `cli.mjs` bridge | — (zero-dep node) |
| `hooks/` | enforced invariants (commit contract, trust roots, scopes, receipts) | connector (verdicts via `cli.mjs`) |
| `commands/` | the assembly-line stations (`/factory-init` … `/ship`) | agents, skills, connector |
| `agents/` | least-privilege crew, one charter + write-fence each | skills |
| `skills/` | operating knowledge (laws, playbooks, config authoring) | — |
| `schemas/`, `templates/` | validated config + scaffolding sources | — |

Dependency rule: enforcement verdicts come only from the connector's pure
core, so the hook path and the read path can never disagree. Hooks never eval
agent-supplied strings — commands come only from the validated
`.factory/config.json` allowlist.

### The factory ops (this repo building itself)

| Component | Responsibility |
|---|---|
| `.github/workflows/` | event-driven orchestrator: `cron-prod` (hourly resume), `on-issue` (triage), `on-pr` (review + self-merge), `factory-run` (station loop), `nightly-eval`, `claude-session` (reusable headless session), `project-sync` |
| `factory-ops/` | agent-owned state: `state/checkpoint.json` (resume contract), `sprints/`, `qa/`, `cost/` — never `.factory/` (hook-managed trust root) |
| `bootstrap.sh` | the only human touchpoint: repo protection, per-role GitHub Apps, secrets/vars, labels/milestones/backlog, board, runner, first dispatch |
| `docs/` | spine (VISION/ARCHITECTURE/ROADMAP/adr) + PRODUCT, rfcs, specs, security, research, community |

Runtime topology: **GitHub Actions is the orchestrator** — all control flow is
event-driven workflows with state in the repo, so any single host can die.
`icculus` (self-hosted, Dockerized, egress-allowlisted) is preferred muscle;
every workflow degrades to hosted runners. Sessions are headless
`claude -p --plugin-dir .` — the factory dogfoods its own hooks. Identity is
one least-privilege GitHub App per role (ADR 0002).

## Cross-cutting

- Green gate (ordered, short-circuiting): `typecheck → boundaries → unit →
  BDD → build` = `tests/run-suite.sh` = `.factory/config.json` gates; CI
  (`validate.yml`) re-runs the identical stages and its `green-gate` check is
  what branch protection requires.
- Trust roots: `.factory/state/**`, `.factory/config.json` — hook-managed,
  agent-unwritable; config changes land only as reviewed PRs.
- Security architecture and gap register: `docs/security/README.md`.
- Decision standards (ADRs, RFC flow, spec-per-epic): `docs/rfcs/README.md`.
