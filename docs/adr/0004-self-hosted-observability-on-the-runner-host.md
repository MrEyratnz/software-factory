# ADR 0004 — Keep factory observability self-hosted on the runner host, and isolate it from the runner

Status: accepted · Date: 2026-07-25

## Context

The factory is lights-out: stations run as headless `claude -p` sessions on the
self-hosted `icculus` runner (ADR 0003), and nobody watches them. When the loop
stalls, burns tokens, or a station quietly no-ops, the only evidence today is a
job log and a cost row in the step summary. The questions that actually matter —
*which station burns the budget, where does the loop stall, which gate denies
most often, did this session do anything* — need session-level traces and
metrics, not log archaeology.

Two constraints shape the answer. Sessions read untrusted issue and PR text and
hold minted GitHub App tokens, so anything that captures session content becomes
a secrets store. And the runner container is itself AI-driven: whatever the
telemetry backend is, a prompt-injected session must not be able to reach into
it.

The hooks already ship an opt-in, push-based OTLP metrics emitter
(`hooks/lib/otel-emit.mjs`) with a deliberately backend-free local collector.
That is the floor, not the ceiling.

## Decision

- **Self-hosted Langfuse on `icculus`, never a hosted trace backend.** Station
  traces describe a private repo's engineering work. They stay on the same host
  that already holds the runner and its credentials.
  Langfuse's own phone-home telemetry (`TELEMETRY_ENABLED`) is off.
- **An OTEL collector is the only component the runner can reach.** It sits on
  both `factory-net` (the egress-filtered runner network created by
  `bootstrap.sh` §8) and `factory-obs`. Langfuse, postgres, clickhouse, redis
  and minio live on `factory-obs` alone, so the runner has no route to the store
  holding every previous session's traces. The collector's own surfaces on
  `factory-net` — OTLP intake on `:4318`, Prometheus scrape on `:8889` — are
  unauthenticated and the scrape endpoint is readable; it serves aggregate
  counters, no secrets and no trace content. The boundary is "cannot reach the
  trace store", not "write-only".
- **Content stays redacted.** `OTEL_LOG_USER_PROMPTS`,
  `OTEL_LOG_ASSISTANT_RESPONSES`, `OTEL_LOG_TOOL_DETAILS`,
  `OTEL_LOG_TOOL_CONTENT` and `OTEL_LOG_RAW_API_BODIES` are left off, and a
  contract test fails if any is turned on. Shape (model, effort, tokens, cost,
  duration, tool names, permission decisions) answers the questions above
  without turning the trace store into a secondary copy of every prompt.
- **`FACTORY_OTEL_ENDPOINT`, an environment variable, is the switch.** CI cannot
  opt in through `.factory/config.json`: that file is a hook-managed trust root,
  and a workflow step editing it would dirty the tree the green receipt binds
  to and trip the gates it is instrumenting. So the environment overrides the
  config — including an explicit `otel.enabled: false` — because the operator
  running the process is the one deciding.
- **The switch is set only against a proven-healthy stack, and deleted
  otherwise.** `bootstrap.sh` §8b sets the `FACTORY_OTEL_ENDPOINT` repo variable
  after `scripts/observability-up.sh` gets a real `200` from Langfuse, and
  removes it when the stack is absent. Stations gate on it *and* on running
  the `icculus` runner, since the endpoint is a `factory-net` DNS name.
- **Credentials are generated once and required.** Every credential in the
  compose file is a variable with no inline default, so compose refuses to start
  without the generated `observability.env`.

## Consequences

- Observability is host-local: it dies with `icculus` and is unavailable to
  hosted-runner stations. Accepted — the same host already carries the runner,
  so a station that can run is a station that can be observed.
- Upstream's Langfuse compose cannot be tracked by copy. Version bumps are a
  deliberate edit to `docker-compose.observability.yml`, and the hardening
  (required credentials, loopback-only publishing, split networks) has to be
  re-applied on each bump. The contract test is what catches a regression.
- `factory-obs` is a normal bridge network, so the Langfuse containers retain
  outbound internet access they have no use for. Tightening it (an internal
  network, or DOCKER-USER rules like §8 applies to `factory-net`) is tracked
  as tech-debt.
- Enabling telemetry from the environment means an exported
  `FACTORY_OTEL_ENDPOINT` in a developer's shell turns emits on for every repo
  in that shell. The emit stays fire-and-forget with a ~250ms timeout, so the
  cost is a background fork per gate decision, not latency or a changed
  decision.
