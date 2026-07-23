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
  # claude-session.yml is the exception, and deliberately so: it is a REUSABLE
  # workflow, where a permissions block caps every caller instead of restricting
  # itself (#97). Its own rule — declare nothing — is asserted separately below.
  if [ "$wf" = "claude-session" ]; then
    ok "$f is the reusable session workflow — its permissions rule is asserted separately"
  elif grep -Eq '^[[:space:]]*permissions:' "$f"; then
    ok "$f declares permissions"
  else
    bad "$f lacks an explicit permissions block"
  fi
  unpinned="$(grep -E '^[[:space:]]*(-[[:space:]]*)?uses:' "$f" | grep -Ev '@[0-9a-f]{40}([[:space:]]|$)' | grep -v 'uses: ./' || true)"
  if [ -z "$unpinned" ]; then ok "$f pins every action by SHA"; else bad "$f has unpinned actions: $(printf '%s' "$unpinned" | tr '\n' ' ')"; fi
done

# --- the session workflow decides whether the factory works at all -----------
# Every station runs through claude-session.yml, so two properties there are
# load-bearing for the whole factory:
#   1. it must authenticate with whichever credential the repo actually holds —
#      Claude Code in CI takes CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY, and
#      wiring only one leaves every station unauthenticated on a repo that has
#      the other;
#   2. `claude -p --output-format json` EXITS 0 even when the run failed (the
#      result JSON carries "is_error": true, e.g. "Not logged in"), so the step
#      must inspect the result and fail the job. Without that, a station reports
#      success while doing nothing and cron-prod re-dispatches that no-op hourly
#      forever — false green is worse than red.
SESSION_WF=".github/workflows/claude-session.yml"
if [ -f "$SESSION_WF" ]; then
  for cred in CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY; do
    if grep -q "$cred" "$SESSION_WF"; then
      ok "$SESSION_WF wires the $cred credential"
    else
      bad "$SESSION_WF never passes $cred — stations would run unauthenticated"
    fi
  done
  # Merely MENTIONING is_error is not enough (the cost-telemetry step does that
  # and cannot fail the job): some step must inspect it AND exit non-zero.
  if python3 -c "import yaml" 2>/dev/null; then
    if WF="$SESSION_WF" python3 -c '
import os, sys, yaml
wf = yaml.safe_load(open(os.environ["WF"]))
steps = wf["jobs"]["session"]["steps"]
guard = [s for s in steps
         if "is_error" in str(s.get("run", "")) and "exit 1" in str(s.get("run", ""))]
sys.exit(0 if guard else 1)
    '; then
      ok "$SESSION_WF fails the job when the session result reports an error"
    else
      bad "$SESSION_WF never exits non-zero on is_error — a failed station reports success"
    fi
  else
    ok "pyyaml unavailable locally — session failure-guard check deferred to CI"
  fi
else
  bad "$SESSION_WF missing"
fi

# The self-merge job needs write scope to merge at all — with only `contents:
# read` its fallback token fails with "Resource not accessible by integration"
# — and it must merge ONLY on a real approving review, never merely on the
# absence of a rejection (an unreviewed change must not reach main).
PR_WF=".github/workflows/on-pr.yml"
if [ -f "$PR_WF" ] && python3 -c "import yaml" 2>/dev/null; then
  if WF="$PR_WF" python3 -c '
import os, sys, yaml
job = yaml.safe_load(open(os.environ["WF"]))["jobs"]["merge"]
perms = job.get("permissions") or {}
sys.exit(0 if perms.get("pull-requests") == "write" and perms.get("contents") == "write" else 1)
  '; then
    ok "$PR_WF merge job declares the write scope a merge actually needs"
  else
    bad "$PR_WF merge job cannot merge: its permissions lack contents/pull-requests write"
  fi
  if grep -q 'APPROVED' "$PR_WF"; then
    ok "$PR_WF self-merges only on an approving review"
  else
    bad "$PR_WF merges without requiring an approving review"
  fi
  # A hardcoded merge method fails outright on any repo whose policy differs —
  # this one allows squash only, so the original `--auto --merge` could never
  # have merged anything (#98).
  if grep -q 'merge-method.mjs' "$PR_WF" && ! grep -qE 'gh pr merge .*--auto (--merge|--squash|--rebase)\b' "$PR_WF"; then
    ok "$PR_WF picks a merge method the repository allows"
  else
    bad "$PR_WF hardcodes a merge method instead of reading the repository's policy"
  fi
fi

# --- reusable-workflow permission semantics (#97) ----------------------------
# GitHub's rule: the CALLER's job-level `permissions` is the ceiling, and
# anything the called workflow declares can only downgrade it — never raise it.
# claude-session.yml therefore must declare NO permissions of its own: a block
# there silently caps every station regardless of what its caller grants, which
# is exactly what left the review station unable to post a review after a
# 37-minute session. Each caller declares its own station's needs instead.
if python3 -c "import yaml" 2>/dev/null; then
  if WF="$SESSION_WF" python3 -c '
import os, sys, yaml
wf = yaml.safe_load(open(os.environ["WF"]))
bad = []
if wf.get("permissions") is not None:
    bad.append("workflow-level")
if (wf["jobs"]["session"].get("permissions")) is not None:
    bad.append("job-level")
if bad:
    print("declares " + " and ".join(bad) + " permissions, which cap every caller")
    sys.exit(1)
  '; then
    ok "$SESSION_WF declares no permissions of its own (callers set the ceiling)"
  else
    bad "$SESSION_WF caps every station's token — remove its permissions block and grant per caller"
  fi

  # Every station that calls it must then say what it needs, or it runs on the
  # repository default rather than a considered least-privilege set.
  for caller in factory-run on-issue on-pr nightly-eval; do
    f=".github/workflows/$caller.yml"
    [ -f "$f" ] || continue
    if WF="$f" python3 -c '
import os, sys, yaml
wf = yaml.safe_load(open(os.environ["WF"]))
callers = [n for n, j in wf["jobs"].items()
           if isinstance(j.get("uses"), str) and "claude-session.yml" in j["uses"]]
missing = [n for n in callers if not (wf["jobs"][n].get("permissions"))]
sys.exit(1 if (not callers or missing) else 0)
    '; then
      ok "$f grants its session job an explicit permission set"
    else
      bad "$f calls claude-session.yml without declaring the station's permissions"
    fi
  done

  # Security invariant: the inbound-triggered station reads attacker-controlled
  # text, so it must never hold write access to repository contents.
  if WF=".github/workflows/on-issue.yml" python3 -c '
import os, sys, yaml
wf = yaml.safe_load(open(os.environ["WF"]))
for n, j in wf["jobs"].items():
    perms = j.get("permissions") or {}
    if perms.get("contents") == "write":
        sys.exit(1)
sys.exit(0)
  '; then
    ok "on-issue.yml grants the untrusted-inbound station no contents write"
  else
    bad "on-issue.yml gives an inbound-triggered session contents:write — attacker-controlled input must never reach a writable token"
  fi
fi

if grep -q 'CLAUDE_CODE_OAUTH_TOKEN' bootstrap.sh; then
  ok "bootstrap.sh stores whichever Claude credential the human already has"
else
  bad "bootstrap.sh only handles one credential name — a repo authenticated the other way silently no-ops"
fi

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
