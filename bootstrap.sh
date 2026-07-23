#!/usr/bin/env bash
# bootstrap.sh — Phase 0 of the autonomous factory: the ONLY human touchpoint.
# Run once, locally, from a checkout of this repo. Idempotent: every step
# checks before it creates, so re-running after a partial failure is safe.
#
# What it does (see docs/adr/0002-event-driven-github-actions-factory.md):
#   1. verify prereqs                      6. OSS scaffolding + funding handles
#   2. create/confirm repo + protect main  7. Projects v2 board + fields
#   3. one GitHub App per agent role       8. Dockerized self-hosted runner
#   4. secrets + repo variables               (label: icculus, egress-allowlisted)
#   5. labels, milestones, Epic 1 backlog  9. dispatch the first factory-run
#
# Env knobs (all optional unless noted):
#   ANTHROPIC_API_KEY      required (prompted for if unset and interactive)
#   FACTORY_PAT            PAT fallback identity + Projects v2 board sync
#   FACTORY_REPO           owner/name (default: derived from origin remote)
#   FACTORY_LICENSE        SPDX id for LICENSE if absent (default apache-2.0)
#   MAX_PARALLEL_AGENTS    repo variable (default 3)
#   SPRINT_HOURS           repo variable (default 24)
#   CLAUDE_CODE_VERSION    pinned CLI for sessions (default 2.1.218)
#   FUNDING_GITHUB FUNDING_BUYMEACOFFEE FUNDING_KOFI FUNDING_OPENCOLLECTIVE
#   FACTORY_APPS_SKIP=true   skip GitHub App creation (PAT/GITHUB_TOKEN fallback)
#   FACTORY_RUNNER_SKIP=true skip self-hosted runner registration
#   FACTORY_APP_PORT       localhost port for the app-manifest flow (default 8927)
#
# Output contract: progress goes to stderr; stdout prints ONLY the final
# "Factory is live: <run URL>" line.
set -euo pipefail

log()  { printf '>> %s\n' "$*" >&2; }
warn() { printf '!! %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }

# --- 1. prereqs --------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "$2"; }
need git     "git is required — install git and re-run"
need node    "node is required — install Node.js 22+ and re-run"
need python3 "python3 is required — install Python 3 and re-run"
need gh      "the GitHub CLI is required — https://cli.github.com then 'gh auth login' and re-run"
need claude  "the claude CLI is required — npm install -g @anthropic-ai/claude-code and re-run"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login' and re-run"

cd "$(dirname "$0")"
[ -f .claude-plugin/plugin.json ] || die "run bootstrap.sh from the repo root (plugin manifest not found)"

OWNER_LOGIN="$(gh api user --jq .login)"
if [ -z "${FACTORY_REPO:-}" ]; then
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  FACTORY_REPO="$(printf '%s' "$origin_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
fi
[ -n "$FACTORY_REPO" ] || die "cannot derive the repo — set FACTORY_REPO=owner/name and re-run"
REPO="$FACTORY_REPO"
log "bootstrapping factory for $REPO (as $OWNER_LOGIN)"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  if [ -t 0 ]; then
    printf 'ANTHROPIC_API_KEY (input hidden): ' >&2
    read -rs ANTHROPIC_API_KEY; printf '\n' >&2
  fi
  [ -n "${ANTHROPIC_API_KEY:-}" ] || die "set ANTHROPIC_API_KEY in the environment and re-run"
fi

MAX_PARALLEL_AGENTS="${MAX_PARALLEL_AGENTS:-3}"
SPRINT_HOURS="${SPRINT_HOURS:-24}"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.218}"
APP_PORT="${FACTORY_APP_PORT:-8927}"

# --- 2. repo: create/confirm, push, protect main -----------------------------
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  log "creating repo $REPO"
  gh repo create "$REPO" --public --source . --remote origin >&2
fi
REPO_ID="$(gh api "repos/$REPO" --jq .id)"
REPO_NODE_ID="$(gh api "repos/$REPO" --jq .node_id)"

# --- 6a. OSS scaffolding (before protection: direct pushes still allowed) ----
scaffold_commits=0
if [ ! -f LICENSE ]; then
  lic="${FACTORY_LICENSE:-apache-2.0}"
  log "creating LICENSE ($lic)"
  gh api "licenses/$lic" --jq .body > LICENSE
  git add LICENSE && git commit -q -m "chore: add $lic LICENSE" && scaffold_commits=1
fi
for f in GOVERNANCE.md SECURITY.md CODE_OF_CONDUCT.md CONTRIBUTING.md MAINTAINERS.md .github/FUNDING.yml; do
  [ -f "$f" ] || warn "$f missing — expected it committed with the scaffolding PR (continuing)"
done
# Fill funding handles from env (uncomment + set the matching lines).
fund_tmp="$(mktemp)"
python3 - "$fund_tmp" <<'PY' >&2
import os, sys
path = ".github/FUNDING.yml"
try:
    lines = open(path).read().splitlines(True)
except FileNotFoundError:
    sys.exit(0)
pairs = {
    "github:": ("FUNDING_GITHUB", lambda v: f"github: [{v}]\n"),
    "buy_me_a_coffee:": ("FUNDING_BUYMEACOFFEE", lambda v: f"buy_me_a_coffee: {v}\n"),
    "ko_fi:": ("FUNDING_KOFI", lambda v: f"ko_fi: {v}\n"),
    "open_collective:": ("FUNDING_OPENCOLLECTIVE", lambda v: f"open_collective: {v}\n"),
}
out, changed = [], False
for line in lines:
    stripped = line.lstrip("# ").rstrip("\n") + " "
    for key, (env, render) in pairs.items():
        val = os.environ.get(env, "")
        if val and stripped.startswith(key):
            new = render(val)
            if line != new:
                line, changed = new, True
            break
    out.append(line)
if changed:
    open(path, "w").writelines(out)
    open(sys.argv[1], "w").write("changed")
PY
if [ -s "$fund_tmp" ]; then
  git add .github/FUNDING.yml && git commit -q -m "chore: set funding handles from bootstrap env" && scaffold_commits=1
fi
rm -f "$fund_tmp"

log "pushing main"
default_branch="$(git rev-parse --abbrev-ref HEAD)"
git push -u origin "$default_branch" >&2 || die "push failed — check repo permissions ($scaffold_commits scaffold commit(s) pending)"

log "protecting main: required check green-gate, PRs required, 0 approvals, admins enforced"
printf '%s' '{
  "required_status_checks": {"strict": true, "contexts": ["green-gate"]},
  "enforce_admins": true,
  "required_pull_request_reviews": {"required_approving_review_count": 0},
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}' | gh api -X PUT "repos/$REPO/branches/main/protection" --input - >/dev/null
gh repo edit "$REPO" --enable-auto-merge >&2 || warn "could not enable auto-merge (on-pr self-merge needs it)"

# --- 3. one GitHub App per agent role ---------------------------------------
ROLES="orchestrator coder reviewer triage qa product-owner planner architect researcher release security efficiency treasurer"

role_perms() {
  # Least privilege per role — mirrors the plugin's guard scopes (docs/security).
  case "$1" in
    orchestrator) printf '{"contents":"write","actions":"write","issues":"write","pull_requests":"write"}' ;;
    coder)        printf '{"contents":"write","issues":"write","pull_requests":"write","workflows":"write"}' ;;
    reviewer)     printf '{"contents":"read","pull_requests":"write","checks":"read","issues":"read"}' ;;
    triage)       printf '{"issues":"write"}' ;;
    qa)           printf '{"contents":"write","issues":"write","actions":"read"}' ;;
    release)      printf '{"contents":"write","pull_requests":"write","issues":"read"}' ;;
    security)     printf '{"contents":"write","issues":"write","security_events":"read"}' ;;
    *)            printf '{"contents":"write","issues":"write"}' ;;
  esac
}

ensure_environment() {
  gh api -X PUT "repos/$REPO/environments/$1" >/dev/null
}

env_has_app() {
  gh api "repos/$REPO/environments/$1/variables/APP_ID" --jq .value 2>/dev/null
}

serve_manifest() {
  # Serves the auto-submitting manifest form; prints the returned code on stdout.
  local role="$1" manifest="$2" srv
  srv="$(mktemp --suffix=.mjs)"
  cat > "$srv" <<'JS'
import http from "node:http";
import { URL } from "node:url";
const [port, role, manifest] = process.argv.slice(2);
const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
const html = `<!doctype html><meta charset="utf-8"><body>
<form id="f" action="https://github.com/settings/apps/new?state=${esc(role)}" method="post">
<input type="hidden" name="manifest" value="${esc(manifest)}"></form>
<script>document.getElementById("f").submit()</script></body>`;
const server = http.createServer((req, res) => {
  const u = new URL(req.url, `http://localhost:${port}`);
  if (u.pathname === "/callback" && u.searchParams.get("code")) {
    res.end(`App for role "${role}" created — return to the terminal.`);
    process.stdout.write(u.searchParams.get("code"));
    setTimeout(() => process.exit(0), 300);
  } else {
    res.setHeader("content-type", "text/html");
    res.end(html);
  }
});
server.listen(Number(port));
setTimeout(() => { console.error(`timed out waiting for the ${role} app callback`); process.exit(1); }, 600000);
JS
  node "$srv" "$APP_PORT" "$role" "$manifest"
  local rc=$?
  rm -f "$srv"
  return $rc
}

create_role_app() {
  local role="$1" app_name manifest code conv app_id slug pem html_url iid
  app_name="dsf-$role-$(printf '%s' "$OWNER_LOGIN" | tr '[:upper:]' '[:lower:]' | cut -c1-12)"
  manifest="$(ROLE_NAME="$app_name" ROLE_PERMS="$(role_perms "$role")" REPO_URL="https://github.com/$REPO" PORT="$APP_PORT" node -e '
    process.stdout.write(JSON.stringify({
      name: process.env.ROLE_NAME.slice(0, 34),
      url: process.env.REPO_URL,
      public: false,
      redirect_url: `http://localhost:${process.env.PORT}/callback`,
      default_permissions: JSON.parse(process.env.ROLE_PERMS),
      default_events: [],
    }));
  ')"
  log "[$role] open http://localhost:$APP_PORT — one click creates app $app_name"
  ( command -v xdg-open >/dev/null 2>&1 && xdg-open "http://localhost:$APP_PORT" >/dev/null 2>&1 ) || \
  ( command -v open >/dev/null 2>&1 && open "http://localhost:$APP_PORT" >/dev/null 2>&1 ) || true
  code="$(serve_manifest "$role" "$manifest")" || die "app-manifest flow failed for $role"
  conv="$(gh api -X POST "app-manifests/$code/conversions")"
  app_id="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).id')"
  slug="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).slug')"
  pem="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).pem')"
  html_url="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).html_url')"

  log "[$role] app #$app_id ($slug) — now install it on $REPO (browser click)"
  ( command -v xdg-open >/dev/null 2>&1 && xdg-open "$html_url/installations/new" >/dev/null 2>&1 ) || \
  ( command -v open >/dev/null 2>&1 && open "$html_url/installations/new" >/dev/null 2>&1 ) || \
    log "[$role] open $html_url/installations/new"
  iid=""
  for _ in $(seq 1 120); do
    iid="$(gh api user/installations --paginate --jq ".installations[] | select(.app_id == $app_id) | .id" 2>/dev/null | head -1)"
    [ -n "$iid" ] && break
    sleep 5
  done
  [ -n "$iid" ] || die "[$role] app never installed — install $html_url and re-run (bootstrap is idempotent)"
  gh api -X PUT "user/installations/$iid/repositories/$REPO_ID" >/dev/null 2>&1 || true

  ensure_environment "$role"
  gh variable set APP_ID --env "$role" --repo "$REPO" --body "$app_id" >&2
  gh secret  set APP_PRIVATE_KEY --env "$role" --repo "$REPO" --body "$pem" >&2
  log "[$role] environment configured (APP_ID + APP_PRIVATE_KEY)"
}

if [ "${FACTORY_APPS_SKIP:-false}" = "true" ]; then
  warn "FACTORY_APPS_SKIP=true — sessions fall back to FACTORY_PAT/GITHUB_TOKEN (pushes may not trigger workflows; see ADR 0002)"
  for role in $ROLES; do ensure_environment "$role"; done
else
  for role in $ROLES; do
    if [ -n "$(env_has_app "$role" || true)" ]; then
      log "[$role] app already configured — skipping"
      continue
    fi
    create_role_app "$role"
  done
fi

# --- 4. secrets + repo variables ---------------------------------------------
log "setting repo secrets and variables"
gh secret set ANTHROPIC_API_KEY --repo "$REPO" --body "$ANTHROPIC_API_KEY" >&2
if [ -n "${FACTORY_PAT:-}" ]; then
  gh secret set FACTORY_PAT --repo "$REPO" --body "$FACTORY_PAT" >&2
else
  warn "FACTORY_PAT not set — Projects v2 board sync will no-op until it is added"
fi
gh variable set FACTORY_HALT         --repo "$REPO" --body "false" >&2
gh variable set MAX_PARALLEL_AGENTS  --repo "$REPO" --body "$MAX_PARALLEL_AGENTS" >&2
gh variable set SPRINT_HOURS         --repo "$REPO" --body "$SPRINT_HOURS" >&2
gh variable set CLAUDE_CODE_VERSION  --repo "$REPO" --body "$CLAUDE_CODE_VERSION" >&2

# --- 5. labels, milestones, Epic 1 backlog -----------------------------------
log "ensuring labels"
ensure_label() { gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null; }
ensure_label P0 b60205 "drop everything"
ensure_label P1 d93f0b "this sprint"
ensure_label P2 fbca04 "soon"
ensure_label P3 c2e0c6 "someday"
ensure_label bug d73a4a "defect — can reopen a frozen milestone, must be fixed not deferred"
ensure_label tech-debt fef2c0 "unfixed review finding (filed by the tech-debt-clerk)"
ensure_label idea a2eeef "feature idea — routed by the product owner"
ensure_label ux 7057ff "CLI/UX, error-message quality, docs readability"
ensure_label research 0e8a16 "market/practice research task or finding"
ensure_label security ee0701 "security finding — outranks everything at equal priority"
ensure_label efficiency 1d76db "token/cost efficiency work"
ensure_label release-blocker b60205 "blocks /ship"
ensure_label external c5def5 "external contribution — security-steward review path"

log "ensuring milestones"
ensure_milestone() {
  gh api "repos/$REPO/milestones?state=all" --paginate --jq '.[].title' | grep -Fxq "$1" || \
    gh api -X POST "repos/$REPO/milestones" -f title="$1" -f description="$2" >/dev/null
}
ensure_milestone v1.0.0 "Epic 1 suite + SDLC hardening + the decidable Release Gate (docs/specs/epic-1/spec.md)"
ensure_milestone v1.1.0 "post-1.0: feature-freeze overflow"

log "seeding the Epic 1 backlog"
ensure_issue() {
  local title="$1" labels="$2" body="$3"
  gh issue list --repo "$REPO" --state all --search "in:title \"$title\"" --json title --jq '.[].title' | grep -Fxq "$title" && return 0
  gh issue create --repo "$REPO" --title "$title" --label "$labels" --milestone v1.0.0 --body "$body" >&2
}
ensure_issue "Epic 1: plugin test suite (tracking)" "P1" \
"Tracking issue for Epic 1 — spec: docs/specs/epic-1/spec.md, plan: docs/specs/epic-1/plan.md, roadmap: docs/ROADMAP.md M1. Owner: qa (suite health) + implementer (code). Done = every acceptance criterion in the spec holds."
ensure_issue "Epic 1.1: static validation layer in the commit gate" "P1" \
"Layer 1 of docs/specs/epic-1/spec.md: manifest + frontmatter schema checks for every command/agent/skill/hook config, \${CLAUDE_PLUGIN_ROOT} path portability, referenced-files-exist, JSON validity — extending tests/scaffold.contract.test.sh, wired into the gate. Owner field: coder."
ensure_issue "Epic 1.2: hook unit tests + >=95% line coverage gate on hooks/scripts" "P1" \
"Layer 2 of docs/specs/epic-1/spec.md: stdin JSON fixtures per event type, exit-code + stderr class-tag assertions ([hard-boundary] vs [heuristic]), matcher edge cases, forgery-guard cases, multi-repo -C/cd binding; coverage >=95% lines on hooks/scripts/** enforced as a failing test. Owner field: coder."
ensure_issue "Epic 1.3: behavioral evals (trigger + outcome) with nightly thresholds" "P1" \
"Layer 3 of docs/specs/epic-1/spec.md: per skill/command trigger evals (8-10 should / 8-10 near-miss shouldn't, >=3 runs, trigger-rate thresholds) and outcome evals with programmatic assertions plus with-vs-without-plugin baseline lift; headless claude -p harness; thresholds enforced in nightly-eval.yml. Owner field: coder + qa."

# --- 6b. repo security posture ----------------------------------------------
log "enabling security features (best-effort per plan availability)"
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" >/dev/null 2>&1 || warn "could not enable private vulnerability reporting"
gh api -X PUT "repos/$REPO/vulnerability-alerts" >/dev/null 2>&1 || warn "could not enable Dependabot alerts"
printf '%s' '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}' \
  | gh api -X PATCH "repos/$REPO" --input - >/dev/null 2>&1 || warn "could not enable secret scanning/push protection"
printf '%s' '{"state":"configured"}' \
  | gh api -X PATCH "repos/$REPO/code-scanning/default-setup" --input - >/dev/null 2>&1 || warn "could not enable CodeQL default setup"

# --- 7. Projects v2 board ----------------------------------------------------
log "ensuring the Factory Board (Projects v2)"
project_id=""
project_number=""
existing="$(gh api graphql -f query='query($login: String!) {
  user(login: $login) { projectsV2(first: 100) { nodes { id number title } } }
}' -f login="$OWNER_LOGIN" --jq '.data.user.projectsV2.nodes[] | select(.title == "Factory Board") | [.id, (.number|tostring)] | join(" ")' 2>/dev/null | head -1 || true)"
if [ -n "$existing" ]; then
  project_id="${existing%% *}"
  project_number="${existing##* }"
  log "Factory Board exists (#$project_number)"
else
  owner_node="$(gh api user --jq .node_id)"
  created="$(gh api graphql -f query='mutation($owner: ID!) {
    createProjectV2(input: {ownerId: $owner, title: "Factory Board"}) { projectV2 { id number } }
  }' -f owner="$owner_node" --jq '.data.createProjectV2.projectV2 | [.id, (.number|tostring)] | join(" ")')" \
    || warn "could not create the Projects v2 board (a PAT with project scope may be required)"
  project_id="${created%% *}"
  project_number="${created##* }"
  if [ -n "$project_id" ]; then
    gh api graphql -f query='mutation($p: ID!, $r: ID!) {
      linkProjectV2ToRepository(input: {projectId: $p, repositoryId: $r}) { repository { id } }
    }' -f p="$project_id" -f r="$REPO_NODE_ID" >/dev/null 2>&1 || true
    add_field() {
      gh api graphql -f query="mutation(\$p: ID!) {
        createProjectV2Field(input: {projectId: \$p, dataType: $2, name: \"$1\"$3}) {
          projectV2Field { ... on ProjectV2FieldCommon { id } }
        }
      }" -f p="$project_id" >/dev/null 2>&1 || warn "field $1 not created (may exist)"
    }
    role_opts=""
    for role in $ROLES; do
      role_opts="$role_opts{name: \"$role\", color: GRAY, description: \"\"},"
    done
    add_field Owner SINGLE_SELECT ", singleSelectOptions: [${role_opts}{name: \"human\", color: BLUE, description: \"\"}]"
    add_field Priority SINGLE_SELECT ', singleSelectOptions: [{name: "P0", color: RED, description: ""},{name: "P1", color: ORANGE, description: ""},{name: "P2", color: YELLOW, description: ""},{name: "P3", color: GREEN, description: ""}]'
    add_field Sprint NUMBER ""
    add_field Cost NUMBER ""
  fi
fi
if [ -n "$project_id" ]; then
  gh variable set PROJECT_ID     --repo "$REPO" --body "$project_id" >&2
  gh variable set PROJECT_NUMBER --repo "$REPO" --body "$project_number" >&2
fi

# --- 8. self-hosted runner (icculus): Dockerized + egress allowlist ----------
RUNNER_OK=false
if [ "${FACTORY_RUNNER_SKIP:-false}" = "true" ]; then
  warn "FACTORY_RUNNER_SKIP=true — factory runs on hosted runners only"
elif ! command -v docker >/dev/null 2>&1; then
  warn "docker not found — skipping the icculus runner; factory degrades to hosted runners"
  ensure_issue "Register the icculus self-hosted runner" "P1,security" \
"bootstrap.sh could not register the Dockerized self-hosted runner (docker missing or skipped). Re-run bootstrap.sh on icculus with docker installed. Until then all stations run on hosted runners."
else
  if gh api "repos/$REPO/actions/runners" --jq '.runners[].name' 2>/dev/null | grep -Fxq icculus; then
    log "runner 'icculus' already registered"
    RUNNER_OK=true
  else
    log "registering Dockerized runner 'icculus' with egress-allowlist proxy"
    docker network inspect factory-net >/dev/null 2>&1 || docker network create factory-net >&2
    if ! docker ps --format '{{.Names}}' | grep -Fxq factory-proxy; then
      proxy_conf="$(mktemp)"
      cat > "$proxy_conf" <<'SQUID'
# Egress allowlist for factory runner traffic: GitHub, Anthropic API, package
# registries only. Everything else is denied at the proxy.
acl allowed dstdomain .github.com github.com .githubusercontent.com .githubassets.com ghcr.io .blob.core.windows.net .anthropic.com registry.npmjs.org .npmjs.org pypi.org files.pythonhosted.org
acl SSL_ports port 443
acl CONNECT method CONNECT
http_access deny CONNECT !SSL_ports
http_access allow allowed
http_access deny all
http_port 3128
SQUID
      docker run -d --restart unless-stopped --name factory-proxy --network factory-net \
        -v "$proxy_conf:/etc/squid/squid.conf:ro" ubuntu/squid:latest >&2
    fi
    if sudo -n true 2>/dev/null; then
      subnet="$(docker network inspect factory-net --format '{{(index .IPAM.Config 0).Subnet}}')"
      proxy_ip="$(docker inspect factory-proxy --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
      sudo iptables -C DOCKER-USER -s "$subnet" -d "$proxy_ip" -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -s "$subnet" -d "$proxy_ip" -j ACCEPT
      sudo iptables -C DOCKER-USER -s "$subnet" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -s "$subnet" -m state --state ESTABLISHED,RELATED -j ACCEPT
      sudo iptables -C DOCKER-USER -s "$subnet" -d "$subnet" -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -s "$subnet" -d "$subnet" -j ACCEPT
      sudo iptables -C DOCKER-USER -s "$subnet" -j DROP 2>/dev/null || sudo iptables -A DOCKER-USER -s "$subnet" -j DROP
      log "egress firewall applied to factory-net (allowlist proxy only)"
    else
      warn "no passwordless sudo — egress enforcement is proxy-config only (direct egress not dropped)"
      ensure_issue "Runner egress firewall not enforced at the network layer" "P1,security" \
"bootstrap.sh had no sudo to install DOCKER-USER iptables rules on the factory-net subnet, so runner egress is restricted only by proxy configuration, not by packet filtering. Apply the drop rules on icculus (see docs/security/README.md gap register)."
    fi
    rtoken="$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token)"
    docker rm -f dsf-runner-icculus >/dev/null 2>&1 || true
    docker run -d --restart unless-stopped --name dsf-runner-icculus --network factory-net \
      -e http_proxy=http://factory-proxy:3128 -e https_proxy=http://factory-proxy:3128 \
      -e no_proxy=localhost,127.0.0.1,factory-proxy \
      ghcr.io/actions/actions-runner:latest \
      /bin/bash -c "./config.sh --url 'https://github.com/$REPO' --token '$rtoken' --name icculus --labels icculus --unattended --replace && ./run.sh" >&2
    for _ in $(seq 1 24); do
      if gh api "repos/$REPO/actions/runners" --jq '.runners[] | select(.name == "icculus") | .status' 2>/dev/null | grep -q .; then
        RUNNER_OK=true
        break
      fi
      sleep 5
    done
    if [ "$RUNNER_OK" = true ]; then
      log "runner 'icculus' registered"
    else
      warn "runner did not appear yet — check 'docker logs dsf-runner-icculus'"
    fi
  fi
fi
if [ "$RUNNER_OK" = true ]; then
  gh variable set FACTORY_RUNNER --repo "$REPO" --body "icculus" >&2
else
  gh variable set FACTORY_RUNNER --repo "$REPO" --body "ubuntu-latest" >&2
fi

# --- 9. first dispatch -------------------------------------------------------
log "dispatching the first factory-run"
gh workflow run factory-run.yml --repo "$REPO" >&2
run_url=""
for _ in $(seq 1 24); do
  sleep 5
  run_url="$(gh run list --repo "$REPO" --workflow=factory-run.yml --limit 1 --json url --jq '.[0].url' 2>/dev/null)"
  [ -n "$run_url" ] && break
done
[ -n "$run_url" ] || run_url="https://github.com/$REPO/actions/workflows/factory-run.yml"

printf 'Factory is live: %s\n' "$run_url"
