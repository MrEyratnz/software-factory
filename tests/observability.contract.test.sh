#!/usr/bin/env bash
# observability.contract.test.sh — static contract tests for the icculus
# observability stack (OTEL collector + self-hosted Langfuse).
#
# Hermetic: no docker, no network, no live Langfuse. Everything asserted here is
# a *shape* invariant of the committed files, because the stack itself runs on
# one host (icculus) that CI cannot reach. The invariants are the ones whose
# violation is silent and expensive:
#
#   * network isolation — the AI-driven runner container may reach the collector
#     and nothing else; the datastores holding every prompt/trace must not sit on
#     the runner's network.
#   * no host-wide exposure — Langfuse holds session content; every published
#     port binds loopback, and the datastores publish nothing at all.
#   * no baked-in credentials — upstream's compose ships `${SALT:-mysalt}` style
#     defaults, which start a "secured" stack with public secrets. Every
#     credential here must be a bare `${VAR}` with NO default, so a missing env
#     file fails loudly instead of running wide open.
#   * no phone-home — self-hosted Langfuse posts usage telemetry upstream by
#     default; a factory whose traces carry customer prompts must opt out.
#   * no prompt/response capture — Claude Code redacts prompts, responses, tool
#     inputs and raw API bodies unless explicitly opted in. Sessions read
#     untrusted issue text and hold minted tokens, so the workflow must never
#     turn that capture on.
#   * reachability — the runner talks to the collector through an egress proxy
#     allowlist that would deny it; `no_proxy` must carry the collector's name.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); [ -n "${VERBOSE:-}" ] && printf 'ok   - %s\n' "$1"; return 0; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; return 0; }
# expect "<label>" <rc>
expect() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

COMPOSE="docker-compose.observability.yml"
COLLECTOR="otel-collector-langfuse.yaml"
UPSCRIPT="scripts/observability-up.sh"
SESSION_WF=".github/workflows/claude-session.yml"

# py <label> <script>  — run a python assertion; exit 0 means the invariant held,
# and anything it prints on failure is appended to the label.
py() {
  local label="$1" src="$2" out
  out="$(python3 -c "$src" 2>&1)"
  if [ $? -eq 0 ]; then ok "$label"; else bad "$label${out:+ — $out}"; fi
}

# --- files exist -------------------------------------------------------------
for f in "$COMPOSE" "$COLLECTOR" "$UPSCRIPT"; do
  if [ -f "$f" ]; then ok "$f exists"; else bad "$f is missing"; fi
done
[ -x "$UPSCRIPT" ] && ok "$UPSCRIPT is executable" || bad "$UPSCRIPT is not executable"
bash -n "$UPSCRIPT" 2>/dev/null && ok "$UPSCRIPT parses" || bad "$UPSCRIPT fails bash -n"

# Nothing below can run without the compose file; bail early with a clear count
# rather than emitting a wall of secondary failures.
if [ ! -f "$COMPOSE" ] || [ ! -f "$COLLECTOR" ]; then
  printf '\nobservability contract: %d passed, %d failed (stack files missing)\n' "$PASS" "$FAIL"
  exit 1
fi

PRELUDE='
import sys, yaml
c = yaml.safe_load(open("docker-compose.observability.yml"))
svcs = c.get("services", {})
nets = c.get("networks", {})
def net_names(s):
    n = svcs[s].get("networks")
    if n is None: return []
    return list(n.keys()) if isinstance(n, dict) else list(n)
def ports(s):
    return [str(p) if not isinstance(p, dict) else "%s:%s" % (p.get("host_ip",""), p.get("published","")) for p in svcs[s].get("ports", [])]
def fail(m):
    print(m); sys.exit(1)
'

# --- compose parses and carries the whole stack ------------------------------
py "$COMPOSE parses as YAML" "$PRELUDE"

py "$COMPOSE defines the full Langfuse stack + collector" "$PRELUDE"'
want = {"otel-collector","langfuse-web","langfuse-worker","postgres","clickhouse","redis","minio"}
missing = want - set(svcs)
if missing: fail("missing services: %s" % sorted(missing))
'

# --- network isolation -------------------------------------------------------
# The runner container is AI-driven and reads untrusted issue text. It gets the
# collector and nothing else: postgres/clickhouse/redis/minio/langfuse-* must be
# unreachable from factory-net, or a prompt-injected session could read (or
# rewrite) every trace and credential the observability stack holds.
py "factory-net is declared external (bootstrap owns it, compose must not recreate it)" "$PRELUDE"'
n = nets.get("factory-net")
if not isinstance(n, dict) or not n.get("external"): fail("factory-net is not declared external: %r" % (n,))
'

py "the collector bridges factory-net and factory-obs" "$PRELUDE"'
got = set(net_names("otel-collector"))
if got != {"factory-net","factory-obs"}: fail("otel-collector networks = %s" % sorted(got))
'

py "the collector answers to the name the runner dials (factory-collector)" "$PRELUDE"'
s = svcs["otel-collector"]
n = s.get("networks")
aliases = []
if isinstance(n, dict):
    aliases = (n.get("factory-net") or {}).get("aliases") or []
if s.get("container_name") != "factory-collector" and "factory-collector" not in aliases:
    fail("neither container_name nor a factory-net alias resolves factory-collector")
'

py "no datastore or Langfuse service sits on factory-net" "$PRELUDE"'
for s in ("langfuse-web","langfuse-worker","postgres","clickhouse","redis","minio"):
    if "factory-net" in net_names(s): fail("%s is on factory-net" % s)
    if "factory-obs" not in net_names(s): fail("%s is not on factory-obs" % s)
'

# --- exposure ----------------------------------------------------------------
py "every published port binds loopback only" "$PRELUDE"'
for s in svcs:
    for p in svcs[s].get("ports", []):
        spec = p if isinstance(p, str) else "%s:%s" % (p.get("host_ip",""), p.get("published",""))
        if not spec.startswith("127.0.0.1:"): fail("%s publishes %r off-loopback" % (s, spec))
'

py "the datastores publish no host port at all" "$PRELUDE"'
for s in ("postgres","clickhouse","redis"):
    if svcs[s].get("ports"): fail("%s publishes host ports: %s" % (s, svcs[s]["ports"]))
'

# --- credentials -------------------------------------------------------------
# Upstream ships `${SALT:-mysalt}` / `${POSTGRES_PASSWORD:-postgres}`; copying
# that shape gives a stack that comes up "configured" with published secrets and
# never tells you. Require bare `${VAR}` so compose refuses to start without the
# generated env file.
py "no credential carries an inline default (a missing env file must fail loudly)" "$PRELUDE"'
import re
# Connection strings are matched separately below: they legitimately carry a
# scheme and host alongside the interpolated password.
SECRET = re.compile(r"(PASSWORD|SECRET|SALT|ENCRYPTION_KEY|AUTH|_KEY$|ROOT_USER|ACCESS_KEY_ID)")
for s in svcs:
    env = svcs[s].get("environment", {}) or {}
    items = env.items() if isinstance(env, dict) else [tuple(e.split("=",1)) for e in env if "=" in e]
    for k, v in items:
        if k.endswith("_URL") or not SECRET.search(k): continue
        v = "" if v is None else str(v)
        if not v.startswith("${"): fail("%s.%s is a literal value, not an env reference: %r" % (s,k,v))
        if ":-" in v.split("}")[0]: fail("%s.%s has an inline default: %r" % (s,k,v))
'

py "the postgres connection string interpolates its password (never inlines one)" "$PRELUDE"'
for s in ("langfuse-web","langfuse-worker"):
    env = svcs[s].get("environment", {}) or {}
    url = str(env.get("DATABASE_URL",""))
    if not url: fail("%s has no DATABASE_URL" % s)
    if "${POSTGRES_PASSWORD" not in url: fail("%s DATABASE_URL does not interpolate POSTGRES_PASSWORD: %r" % (s,url))
'

py "no upstream credential placeholder survived into a value" "$PRELUDE"'
bad_toks = ("CHANGEME","mysalt","miniosecret","myredissecret","mysecret","postgres:postgres@")
for s in svcs:
    env = svcs[s].get("environment", {}) or {}
    items = env.items() if isinstance(env, dict) else [(e,"") for e in env]
    for k, v in items:
        for t in bad_toks:
            if t in str(v): fail("%s.%s still carries the upstream placeholder %r" % (s,k,t))
    for t in bad_toks:
        if t in str(svcs[s].get("command","")): fail("%s.command still carries %r" % (s,t))
'

py "Langfuse phone-home telemetry is off" "$PRELUDE"'
for s in ("langfuse-web","langfuse-worker"):
    env = svcs[s].get("environment", {}) or {}
    if isinstance(env, dict) and str(env.get("TELEMETRY_ENABLED","")).lower() not in ("false","0"):
        fail("%s TELEMETRY_ENABLED=%r" % (s, env.get("TELEMETRY_ENABLED")))
'

py "images are version-pinned (no :latest, no bare tag)" "$PRELUDE"'
for s in svcs:
    img = svcs[s].get("image","")
    if not img: fail("%s has no image" % s)
    tag = img.rsplit(":",1)[-1] if ":" in img.rsplit("/",1)[-1] else ""
    if not tag or tag == "latest": fail("%s image is not version-pinned: %r" % (s, img))
'

# --- collector config --------------------------------------------------------
py "$COLLECTOR parses and routes traces to Langfuse" "$PRELUDE"'
k = yaml.safe_load(open("otel-collector-langfuse.yaml"))
pipes = k["service"]["pipelines"]
for sig in ("traces","metrics","logs"):
    if sig not in pipes: fail("no %s pipeline" % sig)
exps = k["exporters"]
lf = [n for n in exps if n.startswith("otlphttp/")]
if not lf: fail("no otlphttp exporter for Langfuse")
lf = lf[0]
if lf not in pipes["traces"]["exporters"]: fail("traces do not reach %s" % lf)
'

py "the collector takes its Langfuse credentials from the environment" "$PRELUDE"'
k = yaml.safe_load(open("otel-collector-langfuse.yaml"))
lf = [n for n in k["exporters"] if n.startswith("otlphttp/")][0]
e = k["exporters"][lf]
auth = str((e.get("headers") or {}).get("Authorization",""))
if "${env:" not in auth: fail("Authorization header is not an env reference: %r" % auth)
if "sk-lf" in auth or "pk-lf" in auth: fail("a Langfuse key is hardcoded in the collector config")
if "${env:" not in str(e.get("endpoint","")): fail("endpoint is not an env reference: %r" % e.get("endpoint"))
'

py "the collector keeps the hooks metrics pipeline alive" "$PRELUDE"'
k = yaml.safe_load(open("otel-collector-langfuse.yaml"))
rx = k["service"]["pipelines"]["metrics"]["receivers"]
if "otlp" not in rx: fail("metrics pipeline does not receive otlp: %s" % rx)
http = ((k["receivers"]["otlp"]["protocols"]) or {}).get("http") or {}
if not str(http.get("endpoint","")).endswith(":4318"): fail("otlp/http receiver is not on :4318")
'

# --- up script ---------------------------------------------------------------
# Regenerating keys on every run silently orphans every trace already ingested
# under the old project key, so the generated env file is write-once.
grep -q 'observability.env' "$UPSCRIPT" \
  && ok "$UPSCRIPT persists an env file" || bad "$UPSCRIPT does not reference observability.env"
grep -Eq '\[ -f "\$ENV_FILE" \]|\[ ! -f "\$ENV_FILE" \]' "$UPSCRIPT" \
  && ok "$UPSCRIPT is key-stable (it checks before writing the env file)" \
  || bad "$UPSCRIPT does not guard the env file against being regenerated"
grep -q 'chmod 600' "$UPSCRIPT" \
  && ok "$UPSCRIPT writes the env file 0600" || bad "$UPSCRIPT does not chmod 600 the env file"
grep -q 'factory-ops/state/.bootstrap-runner' "$UPSCRIPT" \
  && ok "$UPSCRIPT keeps host-local secrets in the gitignored runner state dir" \
  || bad "$UPSCRIPT does not use factory-ops/state/.bootstrap-runner for secrets"
grep -q '^factory-ops/state/\.bootstrap-runner/' .gitignore \
  && ok "the runner state dir (holding observability.env) is gitignored" \
  || bad ".gitignore does not ignore factory-ops/state/.bootstrap-runner/"

# A healthy Langfuse is NOT a working pipeline. The collector authenticates with
# Basic credentials, and a 401 is swallowed by its retry queue and sending
# queue — from the runner's side that is indistinguishable from a healthy
# export. So the credential pair has to be proved against Langfuse itself, not
# inferred from the health endpoint.
grep -q '401' "$UPSCRIPT" \
  && ok "$UPSCRIPT distinguishes a rejected credential from a healthy stack" \
  || bad "$UPSCRIPT never checks for a 401 — a bad Langfuse key would look healthy"
grep -q 'api/public/otel' "$UPSCRIPT" \
  && ok "$UPSCRIPT verifies against the OTLP endpoint the collector actually posts to" \
  || bad "$UPSCRIPT does not exercise the Langfuse OTLP endpoint"

# --- bootstrap wiring --------------------------------------------------------
# The runner runs behind an egress allowlist proxy. Without the collector in
# no_proxy, every OTLP POST goes to squid, which denies it — telemetry that is
# configured, enabled, and silently discarded.
grep -q 'no_proxy=.*factory-collector' bootstrap.sh \
  && ok "bootstrap keeps collector traffic out of the egress proxy (no_proxy)" \
  || bad "bootstrap's runner no_proxy does not include factory-collector"
grep -q 'FACTORY_OTEL_SKIP' bootstrap.sh \
  && ok "bootstrap has a FACTORY_OTEL_SKIP escape hatch" \
  || bad "bootstrap has no FACTORY_OTEL_SKIP knob"
grep -q 'FACTORY_OTEL_ENDPOINT' bootstrap.sh \
  && ok "bootstrap publishes FACTORY_OTEL_ENDPOINT for the workflows" \
  || bad "bootstrap never sets the FACTORY_OTEL_ENDPOINT repo variable"

# --- workflow wiring ---------------------------------------------------------
if [ -f "$SESSION_WF" ]; then
  grep -q 'CLAUDE_CODE_ENABLE_TELEMETRY' "$SESSION_WF" \
    && ok "$SESSION_WF enables session telemetry" \
    || bad "$SESSION_WF never enables CLAUDE_CODE_ENABLE_TELEMETRY"
  grep -q 'vars.FACTORY_OTEL_ENDPOINT' "$SESSION_WF" \
    && ok "$SESSION_WF reads the endpoint from the repo variable" \
    || bad "$SESSION_WF does not read vars.FACTORY_OTEL_ENDPOINT"
  # Hosted runners cannot resolve factory-collector; pointing them at it makes
  # every session pay export retries for telemetry that can never arrive.
  grep -q "inputs.runner == 'icculus'" "$SESSION_WF" \
    && ok "$SESSION_WF scopes telemetry to the runner that can reach the collector" \
    || bad "$SESSION_WF does not gate telemetry on the icculus runner"
  # OTEL_RESOURCE_ATTRIBUTES is comma/equals delimited, so ANY interpolated
  # value carrying one of those splits a single attribute into two and corrupts
  # every attribute after it. Sanitizing only some of them is the asymmetry that
  # becomes a bug the first time a caller threads a less-trusted value through
  # `inputs.station`.
  if grep -q 'OTEL_RESOURCE_ATTRIBUTES' "$SESSION_WF" &&
     grep 'OTEL_RESOURCE_ATTRIBUTES' "$SESSION_WF" | grep -Eq '\$(SESSION_STATION|SESSION_MODEL|SESSION_EFFORT|GITHUB_WORKFLOW)'; then
    bad "$SESSION_WF interpolates a raw value into OTEL_RESOURCE_ATTRIBUTES (must be sanitized first)"
  else
    ok "$SESSION_WF sanitizes every value it puts in OTEL_RESOURCE_ATTRIBUTES"
  fi

  # Prompts, responses, tool inputs and raw bodies stay redacted: sessions read
  # untrusted issue text and hold minted App tokens.
  for leak in OTEL_LOG_USER_PROMPTS OTEL_LOG_ASSISTANT_RESPONSES OTEL_LOG_TOOL_CONTENT OTEL_LOG_RAW_API_BODIES; do
    if grep -q "$leak *[:=] *[\"']\?1" "$SESSION_WF"; then
      bad "$SESSION_WF turns on $leak — session content would be shipped to Langfuse"
    else
      ok "$SESSION_WF leaves $leak off (content stays redacted)"
    fi
  done
else
  bad "$SESSION_WF is missing"
fi

printf '\nobservability contract: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
