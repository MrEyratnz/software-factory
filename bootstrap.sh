#!/usr/bin/env bash
# bootstrap.sh — Phase 0 of the autonomous factory: the ONLY human touchpoint.
# Run once, locally, from a checkout of this repo. Idempotent: every step
# checks before it creates, so re-running after a partial failure is safe.
#
# What it does (see docs/adr/0003-event-driven-github-actions-factory.md):
#   1. verify prereqs                      6. OSS scaffolding + funding handles
#   2. create/confirm repo + protect main  7. Projects v2 board + fields
#   3. one GitHub App per agent role       8. Dockerized self-hosted runner
#   4. secrets + repo variables               (label: icculus, egress-allowlisted)
#   5. labels, milestones, Epic 1 backlog  9. dispatch the first factory-run
#
# Env knobs (all optional unless noted):
#   ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN   the Claude credential CI runs
#                          on — either works; prompted for if the repo has
#                          neither already stored
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

# gh_val — capture a gh api value ONLY on exit 0 and only when non-empty.
# gh writes its JSON error body to STDOUT and exits non-zero on 404/403, so any
# `x="$(gh api ...)"` that gates on stdout text mistakes that blob for a real
# value. Route those captures through this helper (or an explicit `if x="$(...)"`)
# so the EXIT STATUS decides, never the error body.
gh_val() {
  local v
  v="$(gh api "$@" 2>/dev/null)" || return 1
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

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

# Claude Code in CI accepts EITHER credential, and a repo set up through the
# Claude GitHub app already holds CLAUDE_CODE_OAUTH_TOKEN. Take whichever is
# offered (existing repo secrets count) rather than insisting on the API key —
# storing the wrong one leaves every station unauthenticated, which the session
# workflow can only report as a hard failure.
CLAUDE_CRED_NAME=""
CLAUDE_CRED_VALUE=""
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  CLAUDE_CRED_NAME=CLAUDE_CODE_OAUTH_TOKEN; CLAUDE_CRED_VALUE="$CLAUDE_CODE_OAUTH_TOKEN"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  CLAUDE_CRED_NAME=ANTHROPIC_API_KEY; CLAUDE_CRED_VALUE="$ANTHROPIC_API_KEY"
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

default_branch="$(git rev-parse --abbrev-ref HEAD)"
# main is protected a few lines down (enforce_admins + required PRs), which
# blocks ALL direct pushes. So only push when there is something to push AND the
# branch is not already protected; if it is protected with commits pending, warn
# and continue (route them via a PR) — never die on a re-run.
git fetch origin "$default_branch" >/dev/null 2>&1 || true
ahead="$(git rev-list --count "@{u}..HEAD" 2>/dev/null || printf '0')"
case "$ahead" in ''|*[!0-9]*) ahead=0 ;; esac
branch_protected=false
if gh api "repos/$REPO/branches/$default_branch/protection" >/dev/null 2>&1; then
  branch_protected=true
fi
if [ "$ahead" -gt 0 ]; then
  if [ "$branch_protected" = true ]; then
    warn "$default_branch is protected and $ahead local commit(s) are pending — route them via a branch + PR (bootstrap will not force a direct push to a protected branch)"
  else
    log "pushing $default_branch ($ahead commit(s))"
    git push -u origin "$default_branch" >&2 \
      || warn "push to $default_branch failed — if it is protected, open a PR for the $scaffold_commits scaffold commit(s); continuing"
  fi
elif [ "$branch_protected" != true ]; then
  log "pushing $default_branch"
  git push -u origin "$default_branch" >&2 \
    || warn "push to $default_branch failed — continuing (check repo permissions)"
fi

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
    coder)        printf '{"contents":"write","issues":"write","pull_requests":"write","workflows":"write","actions":"read"}' ;;
    reviewer)     printf '{"contents":"read","pull_requests":"write","checks":"read","issues":"write"}' ;;
    triage)       printf '{"issues":"write","contents":"read"}' ;;
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
  # Gate on gh's EXIT STATUS, not its stdout: on a 404 gh writes the JSON error
  # body to stdout AND exits 1, so a text-only check would treat that blob as a
  # configured APP_ID and skip every role. Self-contained (the contract test
  # sources this function in isolation) so it must not call gh_val.
  local v
  v="$(gh api "repos/$REPO/environments/$1/variables/APP_ID" --jq .value 2>/dev/null)" || return 1
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

APP_STATE_DIR="factory-ops/state/.bootstrap-apps"
# Host-local runner artifacts (the egress proxy's squid.conf) that outlive the
# run: the proxy restarts unless-stopped, so its config must not sit in /tmp.
RUNNER_STATE_DIR="factory-ops/state/.bootstrap-runner"

# mint_app_jwt <app_id> <pem_file> — an RS256-signed App JWT (iat/exp/iss), so
# we can call the App-authenticated `GET /repos/$REPO/installation` to VERIFY the
# app is actually installed on THIS repo. No installation id needed — the CI
# token minter resolves it from app-id + private key at runtime.
mint_app_jwt() {
  APP_JWT_ID="$1" APP_JWT_PEM="$2" node -e '
    const crypto = require("node:crypto"), fs = require("node:fs");
    const pem = fs.readFileSync(process.env.APP_JWT_PEM, "utf8");
    const now = Math.floor(Date.now() / 1000);
    const b64 = o => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
    const head = b64({ alg: "RS256", typ: "JWT" });
    const body = b64({ iat: now - 60, exp: now + 540, iss: process.env.APP_JWT_ID });
    const data = head + "." + body;
    const sig = crypto.sign("RSA-SHA256", Buffer.from(data), pem).toString("base64url");
    process.stdout.write(data + "." + sig);
  '
}

# Assert the app is installed on THIS repo before storing its credentials, so a
# human who picked the wrong repo in the install selector fails loudly HERE
# rather than silently at runtime weeks later.
verify_repo_install() {
  local role="$1" app_id="$2" pem="$3" html_url="$4" pemfile jwt cov
  pemfile="$(mktemp)"; chmod 600 "$pemfile"; printf '%s' "$pem" > "$pemfile"
  cov=""
  for _ in $(seq 1 120); do
    jwt="$(mint_app_jwt "$app_id" "$pemfile")" || break
    cov="$(gh api -H "Authorization: Bearer $jwt" "repos/$REPO/installation" --jq .app_id 2>/dev/null || true)"
    [ "$cov" = "$app_id" ] && break
    cov=""
    sleep 5
  done
  rm -f "$pemfile"
  [ "$cov" = "$app_id" ] || die "[$role] app #$app_id is not installed on $REPO — open $html_url/installations/new, pick $REPO, then re-run (bootstrap is idempotent)"
}

serve_manifest() {
  # Serves the auto-submitting manifest form and captures the returned code into
  # $codefile. Binds 127.0.0.1 only, validates a per-run random state nonce, and
  # signals readiness (after listen) via $readyfile so the browser is opened only
  # once the port is actually accepting connections.
  local role="$1" manifest="$2" state="$3" codefile="$4" readyfile="$5" srv
  srv="$(mktemp --suffix=.mjs)"
  cat > "$srv" <<'JS'
import http from "node:http";
import { URL } from "node:url";
import fs from "node:fs";
const [port, role, manifest, state, codefile, readyfile] = process.argv.slice(2);
const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
const html = `<!doctype html><meta charset="utf-8"><body>
<form id="f" action="https://github.com/settings/apps/new?state=${esc(state)}" method="post">
<input type="hidden" name="manifest" value="${esc(manifest)}"></form>
<script>document.getElementById("f").submit()</script></body>`;
const server = http.createServer((req, res) => {
  const u = new URL(req.url, `http://127.0.0.1:${port}`);
  if (u.pathname === "/callback" && u.searchParams.get("code")) {
    if (u.searchParams.get("state") !== state) { res.statusCode = 400; res.end("bad state"); return; }
    res.end(`App for role "${role}" created — return to the terminal.`);
    fs.writeFileSync(codefile, u.searchParams.get("code"));
    setTimeout(() => process.exit(0), 300);
  } else {
    res.setHeader("content-type", "text/html");
    res.end(html);
  }
});
server.on("error", e => { console.error(`port ${port} unavailable (${e.code}) — set FACTORY_APP_PORT and re-run`); process.exit(2); });
server.listen(Number(port), "127.0.0.1", () => {
  fs.writeFileSync(readyfile, "ready");
  console.error(`[${role}] manifest server listening on 127.0.0.1:${port}`);
});
setTimeout(() => { console.error(`timed out waiting for the ${role} app callback`); process.exit(1); }, 600000);
JS
  node "$srv" "$APP_PORT" "$role" "$manifest" "$state" "$codefile" "$readyfile"
  local rc=$?
  rm -f "$srv"
  return $rc
}

create_role_app() {
  local role="$1" app_name manifest state code conv app_id slug pem html_url
  local statefile codefile readyfile srv_pid rc
  statefile="$APP_STATE_DIR/$role.json"

  if [ -f "$statefile" ]; then
    # Resume: the one-time pem was persisted the instant it was minted, so a
    # retry after any later failure recreates nothing (the app name is globally
    # unique) — it reads app_id/slug/pem back and resumes at install-verify.
    log "[$role] resuming from persisted app state ($statefile)"
    app_id="$(node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).app_id' < "$statefile")"
    slug="$(node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).slug' < "$statefile")"
    pem="$(node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).pem' < "$statefile")"
    html_url="https://github.com/apps/$slug"
  else
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
    state="$(node -e 'process.stdout.write(require("node:crypto").randomUUID())')"
    codefile="$(mktemp)"; readyfile="$(mktemp)"; rm -f "$readyfile"
    # Start the manifest server FIRST; only open the browser after it has bound
    # and written its ready sentinel, or the first GET races a not-yet-listening
    # port and the human sees ERR_CONNECTION_REFUSED.
    serve_manifest "$role" "$manifest" "$state" "$codefile" "$readyfile" &
    srv_pid=$!
    for _ in $(seq 1 100); do [ -f "$readyfile" ] && break; sleep 1; done
    log "[$role] open http://localhost:$APP_PORT — one click creates app $app_name"
    ( command -v xdg-open >/dev/null 2>&1 && xdg-open "http://localhost:$APP_PORT" >/dev/null 2>&1 ) || \
    ( command -v open >/dev/null 2>&1 && open "http://localhost:$APP_PORT" >/dev/null 2>&1 ) || true
    wait "$srv_pid"; rc=$?
    code="$(cat "$codefile" 2>/dev/null || true)"
    rm -f "$codefile" "$readyfile"
    case "$rc" in
      0) [ -n "$code" ] || die "[$role] app-manifest flow returned no code" ;;
      2) die "[$role] manifest server port $APP_PORT unavailable — set FACTORY_APP_PORT and re-run" ;;
      *) die "[$role] app-manifest flow timed out for $role" ;;
    esac
    conv="$(gh api -X POST "app-manifests/$code/conversions")" || die "[$role] manifest conversion failed"
    app_id="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).id')"
    slug="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).slug')"
    pem="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).pem')"
    html_url="$(printf '%s' "$conv" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).html_url')"
    # Persist the one-time pem the INSTANT the conversion returns (0600), before
    # any step that can fail under set -e. Deleted only after the secret+variable
    # are confirmed stored below.
    mkdir -p "$APP_STATE_DIR"
    ( umask 077; printf '%s' "$conv" | node -e '
      const fs=require("node:fs");
      const c=JSON.parse(require("fs").readFileSync(0,"utf8"));
      fs.writeFileSync(process.argv[1], JSON.stringify({app_id:c.id, slug:c.slug, pem:c.pem}));
    ' "$statefile" )
    chmod 600 "$statefile"
  fi

  log "[$role] app #$app_id ($slug) — now install it on $REPO (browser click)"
  ( command -v xdg-open >/dev/null 2>&1 && xdg-open "$html_url/installations/new" >/dev/null 2>&1 ) || \
  ( command -v open >/dev/null 2>&1 && open "$html_url/installations/new" >/dev/null 2>&1 ) || \
    log "[$role] open $html_url/installations/new"
  verify_repo_install "$role" "$app_id" "$pem" "$html_url"

  ensure_environment "$role"
  # Write the SECRET first and the APP_ID VARIABLE last: env_has_app keys off
  # APP_ID, so "APP_ID present" must mean the key is genuinely there too.
  gh secret  set APP_PRIVATE_KEY --env "$role" --repo "$REPO" --body "$pem" >&2
  gh variable set APP_ID --env "$role" --repo "$REPO" --body "$app_id" >&2
  rm -f "$statefile"
  log "[$role] environment configured (APP_PRIVATE_KEY + APP_ID)"
}

if [ "${FACTORY_APPS_SKIP:-false}" = "true" ]; then
  warn "FACTORY_APPS_SKIP=true — sessions fall back to FACTORY_PAT/GITHUB_TOKEN (pushes may not trigger workflows; see ADR 0003)"
  for role in $ROLES; do ensure_environment "$role"; done
else
  for role in $ROLES; do
    if env_has_app "$role" >/dev/null; then
      log "[$role] app already configured — skipping"
      continue
    fi
    create_role_app "$role"
  done
fi

# --- 4. secrets + repo variables ---------------------------------------------
log "setting repo secrets and variables"
existing_cred=""
if [ -z "$CLAUDE_CRED_NAME" ]; then
  # Nothing in the environment. A previous run — or the Claude GitHub app — may
  # already have stored a credential on the repo; that is a complete setup, so
  # reuse it silently instead of re-prompting a human we promised to ask once.
  existing_cred="$(gh secret list --repo "$REPO" 2>/dev/null | awk '{print $1}' \
    | grep -E '^(CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY)$' | head -1 || true)"
  if [ -n "$existing_cred" ]; then
    log "reusing the repo's existing $existing_cred"
  elif [ -t 0 ]; then
    printf 'Claude credential — ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN (input hidden): ' >&2
    read -rs CLAUDE_CRED_VALUE; printf '\n' >&2
    case "$CLAUDE_CRED_VALUE" in
      sk-ant-oat*) CLAUDE_CRED_NAME=CLAUDE_CODE_OAUTH_TOKEN ;;
      ?*)          CLAUDE_CRED_NAME=ANTHROPIC_API_KEY ;;
    esac
  fi
fi
if [ -n "$CLAUDE_CRED_NAME" ]; then
  gh secret set "$CLAUDE_CRED_NAME" --repo "$REPO" --body "$CLAUDE_CRED_VALUE" >&2
  log "stored $CLAUDE_CRED_NAME"
elif [ -z "$existing_cred" ]; then
  die "no Claude credential — set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in the environment and re-run"
fi
if [ -n "${FACTORY_PAT:-}" ]; then
  gh secret set FACTORY_PAT --repo "$REPO" --body "$FACTORY_PAT" >&2
  # The Projects v2 workflows (project-pickup.yml, claude-issue-triage.yml) read
  # secrets.PROJECT_TOKEN, not FACTORY_PAT — store the same PAT under both names.
  gh secret set PROJECT_TOKEN --repo "$REPO" --body "$FACTORY_PAT" >&2
else
  warn "FACTORY_PAT not set — Projects v2 board sync (needs secrets.PROJECT_TOKEN) will no-op until it is added"
fi
# FACTORY_HALT is a human kill-switch: initialize it only when it does not exist.
# A re-run must never silently un-halt a factory a human deliberately stopped.
FACTORY_HALTED=false
halt_state="$(gh variable get FACTORY_HALT --repo "$REPO" 2>/dev/null || true)"
if [ "$halt_state" = "true" ]; then
  FACTORY_HALTED=true
  warn "FACTORY_HALT=true — a human halted this factory; leaving it halted and NOT dispatching a run"
elif [ -z "$halt_state" ]; then
  gh variable set FACTORY_HALT       --repo "$REPO" --body "false" >&2
fi
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
  # De-dup against the AUTHORITATIVE REST issue list, not the eventually-consistent
  # search index (a prompt re-run does not see just-created issues in search and
  # duplicates the backlog). Capture to a variable first, then grep the variable —
  # a `... | grep -Fxq` pipeline can surface 141 from grep's early exit under
  # pipefail.
  local title="$1" labels="$2" body="$3" existing
  existing="$(gh api "repos/$REPO/issues?state=all&per_page=100" --paginate --jq '.[] | select(.pull_request==null) | .title' 2>/dev/null || true)"
  if grep -Fxq "$title" <<<"$existing"; then return 0; fi
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
# Branch on EXIT STATUS: with no project scope gh prints the GraphQL error
# document to stdout and exits 1; a stdout-text check would slice that blob into
# PROJECT_ID and write it as a repo variable.
if existing="$(gh api graphql -f query='query($login: String!) {
  user(login: $login) { projectsV2(first: 100) { nodes { id number title } } }
}' -f login="$OWNER_LOGIN" --jq '.data.user.projectsV2.nodes[] | select(.title == "Factory Board") | [.id, (.number|tostring)] | join(" ")' 2>/dev/null | head -1)"; then
  :
else
  existing=""
  warn "projects query failed (needs a PAT with read:project) — will attempt to create the board"
fi
if [ -n "$existing" ]; then
  project_id="${existing%% *}"
  project_number="${existing##* }"
  case "$project_id" in PVT_*) log "Factory Board exists (#$project_number)" ;; *) project_id=""; project_number="" ;; esac
fi
if [ -z "$project_id" ]; then
  owner_node="$(gh api user --jq .node_id)"
  if created="$(gh api graphql -f query='mutation($owner: ID!) {
    createProjectV2(input: {ownerId: $owner, title: "Factory Board"}) { projectV2 { id number } }
  }' -f owner="$owner_node" --jq '.data.createProjectV2.projectV2 | [.id, (.number|tostring)] | join(" ")' 2>/dev/null)"; then
    :
  else
    created=""
    warn "could not create the Projects v2 board (a PAT with project scope may be required)"
  fi
  if [ -n "$created" ]; then
    project_id="${created%% *}"
    project_number="${created##* }"
    case "$project_id" in PVT_*) ;; *) project_id=""; project_number="" ;; esac
  fi
  if [ -n "$project_id" ]; then
    gh api graphql -f query='mutation($p: ID!, $r: ID!) {
      linkProjectV2ToRepository(input: {projectId: $p, repositoryId: $r}) { repository { id } }
    }' -f p="$project_id" -f r="$REPO_NODE_ID" >/dev/null 2>&1 || true
  fi
fi
# Ensure the board's fields whenever we have a valid board — NOT only on the run
# that created it — so a board left with fields missing gets completed later.
if [ -n "$project_id" ]; then
  existing_fields="$(gh api graphql -f query='query($id: ID!) {
    node(id: $id) { ... on ProjectV2 { fields(first: 50) { nodes { ... on ProjectV2FieldCommon { name } } } } }
  }' -f id="$project_id" --jq '.data.node.fields.nodes[]?.name' 2>/dev/null || true)"
  add_field() {
    # A real skip when the field already exists, not a swallowed "may exist" warn.
    if grep -Fxq "$1" <<<"$existing_fields"; then return 0; fi
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

  gh variable set PROJECT_ID            --repo "$REPO" --body "$project_id" >&2
  gh variable set PROJECT_NUMBER        --repo "$REPO" --body "$project_number" >&2
  # project-pickup.yml / claude-issue-triage.yml read vars.TRIAGE_PROJECT_NUMBER.
  gh variable set TRIAGE_PROJECT_NUMBER --repo "$REPO" --body "$project_number" >&2
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

    # The config lives in a stable, gitignored state dir — NOT mktemp: the proxy
    # runs `--restart unless-stopped`, so a /tmp sweep or reboot would remount a
    # vanished path and squid would come back configless.
    mkdir -p "$RUNNER_STATE_DIR"
    proxy_conf="$(cd "$RUNNER_STATE_DIR" && pwd)/squid.conf"
    # dstdomain entries must not shadow one another: squid >=6 rejects an ACL
    # that lists both `.github.com` and `github.com` as a FATAL config error, and
    # a leading dot already matches the bare domain plus every subdomain.
    cat > "$proxy_conf" <<'SQUID'
# Egress allowlist for factory runner traffic: GitHub, Anthropic API, package
# registries only. Everything else is denied at the proxy.
acl allowed dstdomain .github.com .githubusercontent.com .githubassets.com .ghcr.io .blob.core.windows.net .anthropic.com .npmjs.org .pypi.org .pythonhosted.org
acl SSL_ports port 443
acl CONNECT method CONNECT
http_access deny CONNECT !SSL_ports
http_access allow allowed
http_access deny all
http_port 3128
SQUID
    # Recreate every run rather than skipping when the name exists: a
    # crash-looping container still lists in `docker ps`, so presence is not
    # health, and a name check would pin a broken proxy forever and stop a fixed
    # config from ever landing.
    docker rm -f factory-proxy >/dev/null 2>&1 || true
    docker run -d --restart unless-stopped --name factory-proxy --network factory-net \
      -v "$proxy_conf:/etc/squid/squid.conf:ro" ubuntu/squid:latest >&2

    # A runner pointed at a dead proxy retries forever and never registers, so
    # prove the proxy serves BEFORE spending a registration token on it.
    proxy_healthy=false
    for _ in $(seq 1 20); do
      # bash, not sh: /dev/tcp is a bash builtin and does not exist in a POSIX
      # shell, so probing under sh fails against a perfectly healthy proxy.
      if [ "$(docker inspect factory-proxy --format '{{.State.Running}}' 2>/dev/null)" = "true" ] &&
         docker exec factory-proxy bash -c 'exec 3<>/dev/tcp/127.0.0.1/3128' 2>/dev/null; then
        proxy_healthy=true
        break
      fi
      sleep 3
    done
    if [ "$proxy_healthy" != true ]; then
      warn "egress proxy is not serving on :3128 — refusing to register a runner that cannot reach it"
      docker logs --tail 30 factory-proxy >&2 2>&1 || true
      ensure_issue "Egress proxy failed to start on the self-hosted runner host" "P1,security" \
"bootstrap.sh started factory-proxy but it never served on :3128, so the icculus runner was not registered and the factory is running on hosted runners. Check 'docker logs factory-proxy' on the runner host."
    fi

    if [ "$proxy_healthy" = true ] && sudo -n iptables -L DOCKER-USER -n >/dev/null 2>&1; then
      subnet="$(docker network inspect factory-net --format '{{(index .IPAM.Config 0).Subnet}}')"
      proxy_ip="$(docker inspect factory-proxy --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
      # `docker inspect` prints the literal string "invalid IP" (not an empty
      # one) for a container with no live network, which would otherwise be
      # handed to `iptables -d` and silently leave the firewall unapplied.
      case "$proxy_ip" in
        *[!0-9.]*|'') die "could not read factory-proxy's IP on factory-net (got '${proxy_ip}')" ;;
      esac
      # The proxy lives in the same subnet the DROP rule covers, so without an
      # explicit ACCEPT for it squid cannot reach anything either and every
      # CONNECT ends in a 60s timeout and a TCP_TUNNEL/503. Packet-level egress
      # for the proxy host is intended: the allowlist is enforced inside squid.
      sudo iptables -C DOCKER-USER -s "$proxy_ip" -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -s "$proxy_ip" -j ACCEPT
      sudo iptables -C DOCKER-USER -s "$subnet" -d "$proxy_ip" -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -s "$subnet" -d "$proxy_ip" -j ACCEPT
      sudo iptables -C DOCKER-USER -s "$subnet" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -s "$subnet" -m state --state ESTABLISHED,RELATED -j ACCEPT
      sudo iptables -C DOCKER-USER -s "$subnet" -d "$subnet" -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -s "$subnet" -d "$subnet" -j ACCEPT
      sudo iptables -C DOCKER-USER -s "$subnet" -j DROP 2>/dev/null || sudo iptables -A DOCKER-USER -s "$subnet" -j DROP
      log "egress firewall applied to factory-net (allowlist proxy only)"
    elif [ "$proxy_healthy" = true ]; then
      # The probe above exercises iptables itself rather than some unrelated
      # command: a correctly scoped `NOPASSWD: /usr/sbin/iptables` rule permits
      # only iptables, so probing anything else reports "no sudo" and skips the
      # firewall on a host that in fact allows it.
      warn "no passwordless sudo for iptables — egress enforcement is proxy-config only (direct egress not dropped)"
      ensure_issue "Runner egress firewall not enforced at the network layer" "P1,security" \
"bootstrap.sh had no sudo to install DOCKER-USER iptables rules on the factory-net subnet, so runner egress is restricted only by proxy configuration, not by packet filtering. Grant 'NOPASSWD: /usr/sbin/iptables' on icculus and re-run, or apply the drop rules by hand (see docs/security/README.md gap register)."
    fi

    if [ "$proxy_healthy" = true ]; then
      rtoken="$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token)"
      docker rm -f dsf-runner-icculus >/dev/null 2>&1 || true
      docker run -d --restart unless-stopped --name dsf-runner-icculus --network factory-net \
        -e http_proxy=http://factory-proxy:3128 -e https_proxy=http://factory-proxy:3128 \
        -e no_proxy=localhost,127.0.0.1,factory-proxy \
        -e NODE_USE_ENV_PROXY=1 \
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
        warn "runner did not register — check 'docker logs dsf-runner-icculus'"
        docker logs --tail 30 dsf-runner-icculus >&2 2>&1 || true
      fi
    fi
  fi
fi
if [ "$RUNNER_OK" = true ]; then
  gh variable set FACTORY_RUNNER --repo "$REPO" --body "icculus" >&2
else
  gh variable set FACTORY_RUNNER --repo "$REPO" --body "ubuntu-latest" >&2
fi

# --- 9. first dispatch -------------------------------------------------------
run_url="https://github.com/$REPO/actions/workflows/factory-run.yml"
if [ "$FACTORY_HALTED" = true ]; then
  warn "factory is halted (FACTORY_HALT=true) — skipping the first factory-run dispatch"
else
  log "dispatching the first factory-run"
  gh workflow run factory-run.yml --repo "$REPO" >&2
  for _ in $(seq 1 24); do
    sleep 5
    # `|| true`: gh exits 1 when the workflow is not yet on the default branch or
    # on a transient error; under set -e that would kill a fully-successful
    # bootstrap with NO output, violating the "only Factory is live" contract.
    run_url="$(gh run list --repo "$REPO" --workflow=factory-run.yml --limit 1 --json url --jq '.[0].url' 2>/dev/null || true)"
    [ -n "$run_url" ] && break
  done
  [ -n "$run_url" ] || run_url="https://github.com/$REPO/actions/workflows/factory-run.yml"
fi

printf 'Factory is live: %s\n' "$run_url"
