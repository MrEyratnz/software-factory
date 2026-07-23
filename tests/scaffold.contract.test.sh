#!/usr/bin/env bash
# scaffold.contract.test.sh — static validation of the autonomous-factory
# scaffolding (Epic 1 layer 1, seed). Deterministic, hermetic, no network.
# Asserts the invariants the factory's own workflows rely on:
#   - bootstrap.sh exists, is executable, and parses
#   - every factory workflow is FACTORY_HALT-guarded, least-privilege
#     (explicit permissions block), and SHA-pins every third-party action
#   - .factory/config.json parses, carries the schema-required keys, and
#     leaves every enforcement gate ON
#   - the ops-state and docs scaffolding the sessions read actually exists
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# --- bootstrap.sh ------------------------------------------------------------
if [ -f bootstrap.sh ] && [ -x bootstrap.sh ] && bash -n bootstrap.sh 2>/dev/null; then
  ok "bootstrap.sh exists, is executable, and parses"
else
  bad "bootstrap.sh missing, not executable, or fails bash -n"
fi

# --- factory workflows -------------------------------------------------------
# The factory's own workflows (not the pre-existing repo CI). Every one must:
# be guarded by the FACTORY_HALT kill switch, declare an explicit permissions
# block (least privilege), and pin every `uses:` action to a full 40-hex SHA.
FACTORY_WORKFLOWS="claude-session factory-run cron-prod on-issue on-pr nightly-eval project-sync"
for wf in $FACTORY_WORKFLOWS; do
  f=".github/workflows/$wf.yml"
  if [ ! -f "$f" ]; then bad "$f missing"; continue; fi
  if grep -q 'FACTORY_HALT' "$f"; then ok "$f has the FACTORY_HALT guard"; else bad "$f lacks the FACTORY_HALT guard"; fi
  if grep -Eq '^[[:space:]]*permissions:' "$f"; then ok "$f declares permissions"; else bad "$f lacks an explicit permissions block"; fi
  unpinned="$(grep -E '^[[:space:]]*(-[[:space:]]*)?uses:' "$f" | grep -Ev '@[0-9a-f]{40}([[:space:]]|$)' | grep -v 'uses: ./' || true)"
  if [ -z "$unpinned" ]; then ok "$f pins every action by SHA"; else bad "$f has unpinned actions: $(printf '%s' "$unpinned" | tr '\n' ' ')"; fi
done

# --- .factory/config.json ----------------------------------------------------
if [ -f .factory/config.json ]; then
  CFG=.factory/config.json node -e '
    const fs = require("fs");
    const cfg = JSON.parse(fs.readFileSync(process.env.CFG, "utf8"));
    const schema = JSON.parse(fs.readFileSync("schemas/factory.config.schema.json", "utf8"));
    const missing = (schema.required || []).filter(k => !(k in cfg));
    if (missing.length) throw new Error("config missing required keys: " + missing.join(", "));
    if (!(schema.properties.stack.enum || []).includes(cfg.stack)) throw new Error("bad stack: " + cfg.stack);
    const gateKeys = Object.keys(schema.properties.gates.properties || {});
    for (const [k, v] of Object.entries(cfg.gates)) {
      if (!gateKeys.includes(k)) throw new Error("unknown gate key: " + k);
      if (typeof v !== "string" || !v.trim()) throw new Error("gate " + k + " must be a non-empty command string");
    }
    for (const [k, v] of Object.entries(cfg.enforcement || {})) {
      if (v !== true) throw new Error("enforcement." + k + " must stay true — gates are not to be pre-weakened");
    }
    for (const re of ["sourceRegex", "testRegex", "testCommandRegex", "releaseVerbRegex"]) {
      if (cfg[re]) new RegExp(cfg[re]);
    }
  ' && ok ".factory/config.json parses, satisfies the schema, and keeps every gate on" \
    || bad ".factory/config.json invalid (see node error above)"
else
  bad ".factory/config.json missing"
fi

# --- ops state the sessions resume from --------------------------------------
if [ -f factory-ops/state/checkpoint.json ]; then
  node -e '
    const c = JSON.parse(require("fs").readFileSync("factory-ops/state/checkpoint.json", "utf8"));
    if (typeof c.version !== "number" || typeof c.station !== "string" || typeof c.next_action !== "string")
      throw new Error("checkpoint must carry version:number, station:string, next_action:string");
  ' && ok "factory-ops/state/checkpoint.json parses with the resume contract fields" \
    || bad "factory-ops/state/checkpoint.json invalid"
else
  bad "factory-ops/state/checkpoint.json missing"
fi

# --- agents ------------------------------------------------------------------
# Every agent (including the new factory roles) begins with frontmatter carrying
# name: and description: — the fields `claude plugin validate --strict` needs.
for f in agents/*.md; do
  if [ "$(head -1 "$f")" = "---" ] && grep -q '^name:' "$f" && grep -q '^description:' "$f"; then
    ok "$f frontmatter has name + description"
  else
    bad "$f frontmatter missing name/description"
  fi
done

# --- docs + governance scaffolding -------------------------------------------
for f in .claude/CLAUDE.md GOVERNANCE.md MAINTAINERS.md .github/FUNDING.yml \
         docs/VISION.md docs/ARCHITECTURE.md docs/ROADMAP.md docs/PRODUCT.md \
         docs/adr/0001-record-architecture-decisions.md \
         docs/adr/0002-dogfood-the-plugin-from-the-working-tree.md \
         docs/adr/0003-event-driven-github-actions-factory.md \
         docs/rfcs/README.md docs/specs/epic-1/spec.md docs/specs/epic-1/plan.md \
         docs/security/README.md factory-ops/README.md factory-ops/cost/ROUTING.md; do
  if [ -f "$f" ]; then ok "$f exists"; else bad "$f missing"; fi
done

# --- workflow YAML parses (duplicate-key-free) -------------------------------
# CI's structural job is the authority; run the same check locally when pyyaml
# is available so a broken workflow never reaches the push.
if python3 -c "import yaml" 2>/dev/null; then
  python3 - <<'PY' && ok "all workflows parse as duplicate-key-free YAML" || bad "workflow YAML parse failure"
import glob, sys, yaml

class Dup(Exception):
    pass

class L(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        seen = set()
        for k, _ in node.value:
            key = self.construct_object(k, deep=deep)
            if key in seen:
                raise Dup(f"duplicate key {key!r}")
            seen.add(key)
        return super().construct_mapping(node, deep=deep)

for f in sorted(glob.glob(".github/workflows/*.yml")):
    with open(f) as fh:
        yaml.load(fh, Loader=L)
PY
else
  ok "pyyaml unavailable locally — workflow YAML parse deferred to CI (structural job)"
fi

exit $fail
