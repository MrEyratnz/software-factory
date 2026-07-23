# dark-software-factory

A **lights-out software factory for Claude Code**. Drop it into any repository
and it runs an autonomous production line: scaffold the docs spine, drive a
TDD roadmap loop, run parallel adversarial reviews that auto-file tech-debt,
design by judge panel, and ship via gated Conventional-Commit releases.

The methodology's laws are **enforced by hooks** locally (fast, fail-early) and
**re-enforced by CI** as the authoritative boundary — so "never commit red,"
"a roadmap box is checked only when merged green," and "never release from red"
are preconditions the harness denies, not documentation an agent skips.

> **Provenance.** Every practice here was distilled and hardened against the
> agent it governs, then productized. This plugin was itself designed by the
> very method it encodes: a three-proposal adversarial judge panel
> (contract / agent-crew / governance) synthesized into one blueprint.

## Install

```
/plugin marketplace add MrEyratnz/software-factory
/plugin install dark-software-factory@software-factory
```

Then, in the repo you want to run as a factory:

```
/factory-init          # scaffold docs, config, CI, labels
/factory-run --max 20  # lights-out: /next → /review → ship, bounded
```

## What's inside

### Commands (the assembly line)

| Command | Station |
|---|---|
| `/factory-init` | Scaffold the factory into a repo |
| `/vision`, `/architecture`, `/adr` | Author the docs spine |
| `/judge-panel` | Settle a contested decision the ADR-0009 way |
| `/roadmap` | Generate / show / reorder / check off milestones |
| `/next` | TDD-implement the next roadmap item, open a PR |
| `/review` | 3-lens adversarial panel → fix or file tech-debt |
| `/ship` | Gated Conventional-Commit release |
| `/factory-run` | The bounded lights-out loop |
| `/factory-status` | Read-only dashboard |
| `/design` | Design-system rigor (tokens → drift gate → contrast test) |
| `/debt` | Reconcile the tech-debt ledger |

### Agents (least-privilege crew)

`architect` · `implementer` · `reviewer` ×3 (read-only) · `proposer` ×3 ·
`panelist` ×3 · `tech-debt-clerk` (sole gh-write) · `release-captain` (no source
edits) · `design-lead`. Fan-out is reserved for the two bounded panels
(judge-panel, review) where independence *is* the enforcement value; the core
loop is a single session working the roadmap top-to-bottom.

### Hooks (the enforced invariants)

`guard-commit` (TDD / never commit red, via a `git write-tree`-bound green
receipt) · `guard-scope` (path least-privilege — closes receipt-forgery and
config-poisoning, and per-role fences: `architect`/`design-lead` docs-only,
`release-captain` docs-only, `tech-debt-clerk` `.factory/review/` only,
`reviewer` denied all writes) · `guard-bash-writes` (denies Bash writes to the
factory's trust roots for every role, and denies ANY tree-mutating Bash for the
read-only `reviewer` role) · `guard-roadmap` (a box flips only with
merged-green proof) · `guard-release` (Bash + github-MCP) · `guard-mcp-commit`
(denies
`create_or_update_file` / `push_files` / `delete_file` over github-MCP —
commits must go through local `git commit`, which `guard-commit` already
gates — except while a release is in progress, when it steps aside and
`guard-release` is the sole arbiter) · `record-green` · `check-drift` ·
`ledger-record` · `validate-handoff` · **`debt-reconcile`** (a session cannot end
while a review finding is unfixed *and* unfiled) · `loop-guard` (bounded
lights-out) · `bootstrap` + `inject-status` (orientation). Several of the above
also push an optional OTEL metric at their decision points — see
[Optional OTEL metrics (opt-in)](#optional-otel-metrics-opt-in) below; off by
default and a no-op unless configured.

### Connector (the model-free spine)

A zero-dependency MCP server ([`connector/`](connector/)) exposing the factory's
rules as deterministic, read-only tools — `roadmap_status` / `roadmap_next` /
`roadmap_check`, `adr_index`, `commit_lint`, `techdebt_lint` / `techdebt_audit`,
`gate_evaluate`, `release_plan`, `ledger_read`. The same pure core
(`factory-core.mjs`) backs both the connector's read tools and the hooks (via
`cli.mjs`), so the read path and the enforcement path can never disagree — and
CI re-runs the identical gate commands as the authoritative boundary. It never
mutates the repo; the command / agent / hook layer does, under normal
permissions.

## Optional OTEL metrics (opt-in)

The hooks can push a handful of push-based metrics to an OpenTelemetry
collector so you can answer "is the lights-out loop healthy, where does it
stall" — off by default, zero new dependencies (no `@opentelemetry/*`; OTLP/HTTP
JSON is hand-built and POSTed with node's built-in `http`/`https`).

**Enable it:**

```jsonc
// .factory/config.json
{
  "otel": { "enabled": true, "endpoint": "http://localhost:4318", "exporter": "otlphttp" }
}
```

```
docker compose --profile otel -f docker-compose.otel.yml up -d   # local collector, logs to stdout
```

**What's emitted** (all `sum` counters unless noted `gauge`):

| Metric | Emitted by | Attributes |
|---|---|---|
| `factory_gate_commit_total` | `guard-commit` | `result` (allow/deny), `reason` on deny |
| `factory_gate_release_total` | `guard-release` | `result` (allow/deny) |
| `factory_gate_suite_total` | `record-green` | `result` (pass/fail) |
| `factory_commits_total` | `ledger-record` | `station` |
| `factory_loop_iterations_total` | `loop-guard` | — |
| `factory_roadmap_percent_complete` (gauge) | `loop-guard` | — |
| `factory_techdebt_missing_total` (gauge) | `debt-reconcile` | — |

**Off by default, and safe when on.** With `otel.enabled` unset/false (the
default), every gating hook returns before forking anything network-facing —
no measurable latency, no network touch. When enabled, the emit runs fully
backgrounded and detached from the hook (`otel-emit.mjs &` + `disown`), with a
~250ms client-side timeout that swallows every failure (DNS, connection
refused, timeout) and always exits 0 — a dead or missing collector is
invisible to the commit/release path and can never change a hook's decision.
Collector-only, metrics-only MVP: no traces/spans, no Prometheus/Grafana, no
ledger-scraping sidecar, no per-agent token accounting (candidates for a later
phase).

## Develop

```
cd connector && node --test        # connector: unit + stdio protocol
bash tests/hooks.contract.test.sh  # hooks: hermetic contract tests
claude plugin validate .claude-plugin/plugin.json --strict
```

CI runs all of the above plus `shellcheck` and marketplace validation. Releases
are automated (release-please) and gated on a green run and a clean-checkout
smoke test. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for this repo's working
agreements.

> **Release setup (one-time):** release-please opens a release PR, so enable
> **Settings → Actions → General → Workflow permissions → "Allow GitHub Actions
> to create and approve pull requests"**, or set a `RELEASE_PLEASE_TOKEN` secret
> (a PAT with `contents:write` + `pull-requests:write`). Without one of these,
> the release job fails with *"GitHub Actions is not permitted to create or
> approve pull requests."*

## License

MIT — see [LICENSE](LICENSE).
