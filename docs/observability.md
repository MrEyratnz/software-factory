# Observability on `icculus`

The factory's stations run as headless Claude Code sessions on the self-hosted
runner (`icculus`, ADR 0003 §"runners"). This is how you see what they did:
an OpenTelemetry collector on that same host, fronting a self-hosted
[Langfuse](https://langfuse.com).

```
 GitHub Actions job (dsf-runner-icculus, network: factory-net)
   claude -p …  ── OTLP/HTTP ──▶ http://factory-collector:4318
   hooks otel_emit ─────────────▶ (same endpoint, FACTORY_OTEL_ENDPOINT)
                                        │
                              otel-collector (factory-net + factory-obs)
                                        │
                ┌───────────────────────┼──────────────────────┐
             traces                 metrics                  logs
                │                       │                      │
       langfuse-web:3000        prometheus :8889          stdout (debug)
       /api/public/otel                                    docker logs
                │
     postgres · clickhouse · redis · minio   ← factory-obs only
```

Two networks, and the split is the point. `factory-net` carries the AI-driven
runner and is egress-filtered by the squid allowlist (bootstrap.sh §8). Only the
collector sits on it — a write-only intake. Langfuse and its datastores live on
`factory-obs`, which the runner has no route to, so a prompt-injected session
cannot read or rewrite the traces of every session before it.

## Stand it up

On the runner host, from a checkout:

```bash
scripts/observability-up.sh
```

That is also what `bootstrap.sh` runs (§8b), right after it registers the
runner. It:

1. generates credentials **once** into
   `factory-ops/state/.bootstrap-runner/observability.env` (mode 0600,
   gitignored) — including the Langfuse org/project/user and the API key pair
   the collector authenticates with, so Langfuse initialises itself headlessly
   and nobody clicks through a signup form;
2. brings up `docker-compose.observability.yml`;
3. waits for a real `200` from Langfuse's health endpoint (first boot runs
   clickhouse + postgres migrations — a couple of minutes is normal);
4. prints the endpoint the runner dials: `http://factory-collector:4318`.

`bootstrap.sh` then sets the **`FACTORY_OTEL_ENDPOINT` repo variable**, and only
on a stack it proved healthy. That variable is the single switch every station
reads. If the stack is down, the variable is deleted rather than left stale:
the failure mode is "no telemetry", never "telemetry posted into a collector
that isn't there".

Skip the whole thing with `FACTORY_OTEL_SKIP=true bootstrap.sh`.

## Look at it

Nothing is published beyond loopback. Tunnel in:

```bash
ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 icculus
```

* **Langfuse UI** — <http://127.0.0.1:3000>. Sign in with the
  `LANGFUSE_INIT_USER_EMAIL` / `LANGFUSE_INIT_USER_PASSWORD` pair from
  `observability.env`. Sessions arrive as traces tagged with the station,
  model, effort, workflow and run id (`OTEL_RESOURCE_ATTRIBUTES`), so "which
  station burns the most tokens" and "where did the conductor stall" are one
  filter each.
* **Metrics** — `curl 127.0.0.1:8889/metrics`. Both families land here: Claude
  Code's `claude_code.*` (cost, tokens, lines of code, active time) and the
  factory's own `factory_*` gate counters from `hooks/lib/common.sh`.
* **Logs** — `docker compose -f docker-compose.observability.yml logs otel-collector`.

## What is deliberately not collected

Claude Code redacts prompts, assistant responses, tool inputs and raw API
bodies unless you opt in per-signal. The workflow leaves every one of those off,
and `tests/observability.contract.test.sh` fails if that changes. Stations read
untrusted issue and PR text and hold minted App tokens; shipping session content
into a trace store is a security decision, not a verbosity setting. What you get
without it is shape — models, token counts, cost, durations, tool names,
permission decisions — which is what the cost and stall questions actually need.

Langfuse's own usage telemetry (`TELEMETRY_ENABLED`) is off for the same reason.

## Turning it on for the hooks, anywhere

`otel_emit` reads `FACTORY_OTEL_ENDPOINT` from the environment first, and that
beats `.factory/config.json` — including an explicit `otel.enabled: false`. This
is the only way CI can opt in: `.factory/config.json` is a hook-managed trust
root, so a workflow step that edited it to enable telemetry would dirty the tree
the green receipt is bound to and trip the gates it was trying to instrument.

Locally, either works:

```bash
FACTORY_OTEL_ENDPOINT=http://localhost:4318 claude    # ambient, nothing committed
# …or the committed opt-in, per repo:
# .factory/config.json → { "otel": { "enabled": true, "endpoint": "…" } }
```

With neither set, `otel_emit` returns before forking anything at all. That
remains the default and is pinned by the hook contract tests.

## Local development

For local work you usually want the zero-backend collector, not this stack:

```bash
docker compose --profile otel -f docker-compose.otel.yml up -d
```

That one logs received metrics to its own stdout and talks to no backend. The
two configs are kept separate on purpose — a single config carrying the Langfuse
exporter would fill local logs with export retries against a Langfuse that isn't
running.

## Operating notes

* **Credentials are write-once.** Re-running `observability-up.sh` reuses
  `observability.env`. Regenerating it would hand Langfuse a new project key
  while the old project keeps every trace already ingested: an empty-looking UI
  and a healthy-looking collector. To start clean, delete the env file *and* the
  `langfuse_*` volumes together.
* **A runner container created before the collector** carries a `no_proxy`
  without `factory-collector`, so its OTLP posts go to the egress-allowlist
  proxy, which denies them — telemetry configured, enabled, and thrown away.
  Container env is fixed at creation, so the fix is to recreate it:
  `docker rm -f dsf-runner-icculus && bash bootstrap.sh`. Bootstrap detects this
  case and says so.
* **Compose refuses to start without the env file.** Every credential is a
  required variable with no inline default. Upstream's compose ships
  `${SALT:-mysalt}`-style fallbacks, which quietly start a "secured" stack on
  published secrets; this one fails loudly instead.
* **`factory-obs` is a normal bridge network**, so the Langfuse containers can
  still reach the internet even though they have no reason to. Tightening that
  (an `internal: true` network, or DOCKER-USER rules like the ones §8 applies to
  `factory-net`) is tracked as tech-debt.
