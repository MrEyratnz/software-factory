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

# --- failed sessions must RESUME on rerun, not re-pay from zero (#725) -------
# Measured 2026-07-29..08-01: seven usage-limit windows each killed 2-3
# in-flight sessions that had already spent $1-12+ and 6-25 minutes; every
# `gh run rerun --failed` started cold and re-paid the full context. The fix
# is checkpoint/resume: persist the session transcript + session id across
# job ATTEMPTS (actions/cache keyed run_id-attempt, restored by same-run
# prefix), and on a rerun invoke `claude -p --resume <session-id>` so the
# parked context is reused, not re-bought.
if [ -f "$SESSION_WF" ] && python3 -c "import yaml" 2>/dev/null; then
  if WF="$SESSION_WF" python3 - <<'PYEOF'
import os, sys, yaml
wf = yaml.safe_load(open(os.environ["WF"]))
steps = wf["jobs"]["session"]["steps"]
# Anchor on the step that actually launches the CLI, not a cosmetic step
# name (#759).
try:
    session_idx = next(i for i, s in enumerate(steps) if "claude -p" in str(s.get("run", "")))
except StopIteration:
    sys.exit(2)
restore = [s for i, s in enumerate(steps)
           if i < session_idx and "actions/cache/restore" in str(s.get("uses", ""))]
save = [s for i, s in enumerate(steps)
        if i > session_idx and "actions/cache/save" in str(s.get("uses", ""))
        and str(s.get("if", "")).strip().startswith("always()")]
if not restore or not save:
    sys.exit(3)
r, s = restore[0], save[0]
r_path = str(r.get("with", {}).get("path", ""))
s_path = str(s.get("with", {}).get("path", ""))
s_key = str(s.get("with", {}).get("key", ""))
if r_path != s_path or not r_path:
    sys.exit(4)
if "run_attempt" not in s_key or "run_id" not in s_key:
    sys.exit(5)
# restore-keys must be a true PREFIX of the save key (#757): presence of
# the tokens alone would stay green if the trailing '-' were dropped and
# resume silently regressed.
r_prefixes = [l.strip() for l in str(r.get("with", {}).get("restore-keys", "")).splitlines() if l.strip()]
if not r_prefixes or not any(s_key.startswith(p) for p in r_prefixes):
    sys.exit(6)
if not any("run_id" in p for p in r_prefixes):
    sys.exit(6)
sess_run = str(steps[session_idx].get("run", ""))
# Both branches must exist: --resume for a parked id, and arm+--session-id
# so a fresh session checkpoints BEFORE launch and survives a SIGKILL that
# never writes a result JSON (#752/#753).
ok_flags = ("--resume" in sess_run and "session-resume.sh" in sess_run
            and "--session-id" in sess_run and " arm " in sess_run)
if not ok_flags:
    sys.exit(7)
# The post CLEAR step must exist BETWEEN the session and the cache save
# (#787): delete or reorder it and a completed station gets re-armed —
# the exact #752 regression this contract exists to pin.
save_idx = next(i for i, s in enumerate(steps)
                if i > session_idx and "actions/cache/save" in str(s.get("uses", "")))
post_steps = [i for i, s in enumerate(steps)
              if session_idx < i < save_idx
              and "session-resume.sh" in str(s.get("run", ""))
              and " post " in str(s.get("run", ""))
              and str(s.get("if", "")).strip().startswith("always()")]
sys.exit(0 if post_steps else 8)
PYEOF
  then
    ok "$SESSION_WF checkpoints session state across attempts and resumes it (restore-before, always-save-after, attempt-scoped prefix keys, arm/--session-id + --resume branches)"
  else
    case $? in
      2) bad "$SESSION_WF: no claude -p step to anchor resume wiring (#725)" ;;
      3) bad "$SESSION_WF: missing cache restore-before-session or always()-guarded save-after-session — a failed attempt's state is lost (#725)" ;;
      4) bad "$SESSION_WF: cache restore/save paths differ or are empty — state saved is not the state restored (#725)" ;;
      5) bad "$SESSION_WF: cache save key must include run_id and run_attempt so each attempt checkpoints separately (#725)" ;;
      6) bad "$SESSION_WF: restore-keys must be a run_id-scoped true prefix of the save key — otherwise resume silently regresses or leaks across runs (#725/#757)" ;;
      7) bad "$SESSION_WF: the session step must arm a pre-assigned --session-id on fresh runs and --resume a parked one via session-resume.sh (#725/#752/#753)" ;;
      *) bad "$SESSION_WF: no always()-guarded session-resume.sh post CLEAR step between the session and the cache save — the #752 completed-station re-arm regression is unpinned (#787)" ;;
    esac
  fi
else
  ok "pyyaml unavailable locally — session-resume wiring check deferred to CI"
fi

# Behavioral proof for the resume helper: arm records the pre-assigned id
# (rejecting non-UUIDs), pre answers only when id + transcript both exist,
# and post clears the checkpoint ONLY on a confirmed clean completion —
# every kill shape (is_error, empty result, unparseable result) must keep
# it armed, and a clean run must never leave one behind (#752/#753/#754).
RESUME_HELPER=".github/scripts/session-resume.sh"
if [ -f "$RESUME_HELPER" ]; then
  RH_ABS="$PWD/$RESUME_HELPER"
  RH_STATE="$(mktemp -d)"; RH_HOME="$(mktemp -d)"
  RH_RESULT="$(mktemp)"
  RH_SID="11111111-2222-3333-4444-555555555555"

  if bash "$RH_ABS" arm "$RH_STATE" "$RH_SID" "shaAAAA" && [ "$(cat "$RH_STATE/session-id" 2>/dev/null)" = "$RH_SID" ] && [ "$(cat "$RH_STATE/head-sha" 2>/dev/null)" = "shaAAAA" ]; then
    ok "session-resume.sh arm records the pre-assigned session id + head SHA before launch"
  else
    bad "session-resume.sh arm failed to record the session id + head SHA (#725/#786)"
  fi

  if bash "$RH_ABS" arm "$RH_STATE" "$(printf '%s\nevil' "$RH_SID")" 2>/dev/null; then
    bad "session-resume.sh arm accepted a multi-line id — per-line matching lets an embedded value through (#791)"
  else
    ok "session-resume.sh arm rejects a multi-line id — whole-string UUID match (#791)"
  fi

  if bash "$RH_ABS" arm "$RH_STATE" '*' 2>/dev/null; then
    bad "session-resume.sh arm accepted a non-UUID id — a glob would self-match unrelated transcripts (#756)"
  else
    ok "session-resume.sh arm rejects a non-UUID id (#756)"
  fi

  if [ -z "$(HOME="$RH_HOME" bash "$RH_ABS" pre "$RH_STATE" 2>/dev/null)" ]; then
    ok "session-resume.sh pre stays silent when the transcript is missing — no blind resume into a lost session"
  else
    bad "session-resume.sh pre offered a resume with no transcript on disk — claude would cold-fail (#725)"
  fi

  mkdir -p "$RH_HOME/.claude/projects/-tmp-fixture"
  : > "$RH_HOME/.claude/projects/-tmp-fixture/$RH_SID.jsonl"
  if [ "$(HOME="$RH_HOME" bash "$RH_ABS" pre "$RH_STATE" "shaAAAA")" = "$RH_SID" ]; then
    ok "session-resume.sh pre returns the armed id when transcript exists and the SHA matches — resume is offered"
  else
    bad "session-resume.sh pre did not offer a resume despite id+transcript+matching SHA (#725)"
  fi

  if [ -z "$(HOME="$RH_HOME" bash "$RH_ABS" pre "$RH_STATE" "shaBBBB")" ]; then
    ok "session-resume.sh pre cold-starts on a head-SHA mismatch — a resumed station never acts on a stale diff (#786)"
  else
    bad "session-resume.sh pre offered a resume against a DIFFERENT checkout SHA — a review could approve vanished code (#786)"
  fi

  printf '{"session_id":"%s","is_error":true,"result":"limit"}' "$RH_SID" > "$RH_RESULT"
  if bash "$RH_ABS" post "$RH_STATE" "$RH_RESULT" && [ -f "$RH_STATE/session-id" ]; then
    ok "session-resume.sh post keeps the checkpoint on an is_error result — the limit park stays resumable"
  else
    bad "session-resume.sh post dropped the checkpoint on an error result — the park is unresumable (#725)"
  fi

  printf '' > "$RH_RESULT"
  if bash "$RH_ABS" post "$RH_STATE" "$RH_RESULT" && [ -f "$RH_STATE/session-id" ]; then
    ok "session-resume.sh post keeps the checkpoint on an EMPTY result — the SIGKILL/timeout case stays resumable (#753/#754)"
  else
    bad "session-resume.sh post dropped the checkpoint on an empty result — the flagship hard-kill case cold-starts (#753/#754)"
  fi

  printf 'not json' > "$RH_RESULT"
  if bash "$RH_ABS" post "$RH_STATE" "$RH_RESULT" && [ -f "$RH_STATE/session-id" ]; then
    ok "session-resume.sh post keeps the checkpoint on an unparseable result — a truncated write stays resumable"
  else
    bad "session-resume.sh post mishandled an unparseable result (#725)"
  fi

  printf '{"session_id":"%s","result":"done"}' "$RH_SID" > "$RH_RESULT"
  if bash "$RH_ABS" post "$RH_STATE" "$RH_RESULT" && [ ! -f "$RH_STATE/session-id" ]; then
    ok "session-resume.sh post CLEARS on a result the failure guard calls green (is_error absent/falsy) — one predicate, no divergence (#752/#788)"
  else
    bad "session-resume.sh post kept the checkpoint on a guard-green result — a rerun would resume a finished station (#752/#788)"
  fi
  rm -rf "$RH_STATE" "$RH_HOME" "$RH_RESULT"
else
  bad "$RESUME_HELPER missing — no checkpoint/resume capability; every failed run re-pays from zero (#725)"
fi

# --- the cron heartbeat must be able to actually WAKE the factory ------------
# cron-prod's only job is to POST a repository_dispatch (event_type
# factory-resume) that starts factory-run. Two GitHub facts make the bare
# GITHUB_TOKEN wrong for that call, and both fail silently-ish (a 403 the loop
# swallows, or a dispatch that no-ops):
#   1. creating a repository_dispatch needs `contents: write`; the job ceiling
#      is `contents: read`, so github.token 403s ("Resource not accessible by
#      integration") every hour and the factory never resumes;
#   2. even WITH write, a repository_dispatch raised by GITHUB_TOKEN does NOT
#      trigger another workflow run (GitHub's recursion guard) — so the wake
#      must be sent with an App token or a PAT, never github.token.
# Pin: cron-prod mints an App token (or uses FACTORY_PAT) and the dispatch runs
# under that identity, not github.token.
CRON_WF=".github/workflows/cron-prod.yml"
if [ -f "$CRON_WF" ]; then
  if grep -q 'create-github-app-token' "$CRON_WF" || grep -q 'FACTORY_PAT' "$CRON_WF"; then
    ok "$CRON_WF resolves a dispatch identity beyond github.token"
  else
    bad "$CRON_WF dispatches factory-resume with the bare github.token — 403s hourly and cannot trigger a run"
  fi
  # The step that actually posts the dispatch must not bind GH_TOKEN to
  # github.token; it must use the resolved app/PAT token.
  if python3 -c "import yaml" 2>/dev/null; then
    if WF="$CRON_WF" python3 -c '
import os, sys, yaml
wf = yaml.safe_load(open(os.environ["WF"]))
steps = wf["jobs"]["resume"]["steps"]
disp = [s for s in steps if "dispatches" in str(s.get("run", ""))]
if not disp:
    sys.exit(1)
bad = [s for s in disp
       if str((s.get("env") or {}).get("GH_TOKEN", "")).strip() in
          ("${{ github.token }}", "${{ secrets.GITHUB_TOKEN }}")]
sys.exit(1 if bad else 0)
    '; then
      ok "$CRON_WF posts the dispatch with the resolved token, not github.token"
    else
      bad "$CRON_WF posts the repository_dispatch under github.token — the wake will not fire"
    fi
  else
    ok "pyyaml unavailable locally — cron-prod dispatch-token check deferred to CI"
  fi
else
  bad "$CRON_WF missing"
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
  # The review station must be able to FILE what it does not fix. Without
  # issues:write it 403s on the tech-debt filing and then either drops findings
  # (breaking the iron rule) or cannot end its session at all, because its own
  # debt-reconcile Stop hook blocks on an unfiled finding — observed live on #99.
  if WF="$PR_WF" python3 -c '
import os, sys, yaml
jobs = yaml.safe_load(open(os.environ["WF"]))["jobs"]
review = [j for j in jobs.values()
          if isinstance(j.get("uses"), str) and "claude-session.yml" in j["uses"]]
sys.exit(0 if review and all((j.get("permissions") or {}).get("issues") == "write" for j in review) else 1)
  '; then
    ok "$PR_WF review job's GITHUB_TOKEN ceiling grants issues:write"
  else
    bad "$PR_WF review station cannot file tech-debt (needs issues:write) — findings get dropped or the session jams"
  fi
  # …but claude-session.yml prefers the App token when present, so a caller's
  # GITHUB_TOKEN ceiling only bounds the FALLBACK path. The App bootstrap mints
  # for each station is the effective authority on the normal path, so its scope
  # must COVER that station's ceiling — every time, for every station, or a role
  # ships a token that 403s on work its ceiling says it can do. Checking one
  # role/scope pair at a time just moves the gap to the next role (reviewer/issues
  # #103, then coder/actions #115). This proves the whole class at once: for each
  # claude-session caller, bootstrap's App scope for its environment must grant
  # every ceiling permission (write satisfies read), mapping the GITHUB_TOKEN
  # hyphen names to the App underscore names, ignoring `workflows` (not a
  # GITHUB_TOKEN scope, so it never appears in a ceiling). (#104/#116)
  if python3 -c '
import glob, re, sys, yaml

# bootstrap role_perms arms: `role) printf {json} ;;` -> {role: {perm: level}}.
apps = {}
for m in re.finditer(r"^\s*([a-z-]+)\)\s*printf\s*'"'"'(\{.*?\})'"'"'", open("bootstrap.sh").read(), re.M):
    apps[m.group(1)] = yaml.safe_load(m.group(2))
RANK = {"read": 1, "write": 2}
H2U = {"pull-requests": "pull_requests", "security-events": "security_events"}  # GITHUB_TOKEN → App name

problems = []
for path in sorted(glob.glob(".github/workflows/*.yml")):
    wf = yaml.safe_load(open(path))
    if not isinstance(wf, dict):
        continue
    for name, job in (wf.get("jobs") or {}).items():
        uses = job.get("uses")
        if not (isinstance(uses, str) and "claude-session.yml" in uses):
            continue
        # The role env is a reusable-workflow INPUT (with.environment), which
        # claude-session.yml applies to its own job — not a top-level job key.
        env = (job.get("with") or {}).get("environment")
        ceiling = job.get("permissions") or {}
        if not env:
            problems.append(f"{path}:{name} calls the session with no environment (cannot map to an App)")
            continue
        scope = apps.get(env)
        if scope is None:
            problems.append(f"{path}:{name} targets environment {env!r} that bootstrap role_perms does not mint")
            continue
        for perm, lvl in ceiling.items():
            app_perm = H2U.get(perm, perm)
            if app_perm == "workflows":
                continue  # not a GITHUB_TOKEN scope; never in a ceiling anyway
            have = scope.get(app_perm)
            if have is None or RANK.get(have, 0) < RANK.get(lvl, 0):
                problems.append(f"{env} App is missing {app_perm}:{lvl} that {path}:{name} needs (has {have})")
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
  '; then
    ok "every station's App scope covers its caller ceiling (App-token path can do its ceiling work)"
  else
    bad "a station App scope does not cover its ceiling — the App-token path will 403 on work the ceiling allows"
  fi
  # A hardcoded merge method fails outright on any repo whose policy differs —
  # this one allows squash only, so the original `--auto --merge` could never
  # have merged anything (#98).
  #
  # The first version of this guard matched `--auto (--merge|--squash|--rebase)`
  # and was trivially defeated (the review station reproduced both vectors): a
  # command with no `--auto`, or with the method BEFORE `--auto`, sailed through
  # while a leftover mention of merge-method.mjs satisfied the other clause. So
  # assert positively that the resolved method is what gets passed, and reject a
  # literal method flag anywhere in the merge invocation regardless of order.
  if WF="$PR_WF" python3 -c '
import os, re, sys
text = open(os.environ["WF"]).read()
calls = re.findall(r"gh pr merge[^\n]*", text)
if not calls:
    sys.exit(1)
for call in calls:
    if re.search(r"--(merge|squash|rebase)\b", call):   # a literal method
        sys.exit(1)
    if not re.search(r"\"--\$\{?method\}?\"", call):    # the resolved one
        sys.exit(1)
sys.exit(0)
  '; then
    ok "$PR_WF passes only the merge method the repository allows"
  else
    bad "$PR_WF hardcodes a merge method instead of passing the resolved one"
  fi
fi

# --- ceiling vs. actual credential alignment (#100) --------------------------
# The check above proves the App-token path can do at least as much as the
# ceiling requires (no 403s). It says nothing about the other direction: a
# `permissions:` block bounds ONLY the GITHUB_TOKEN fallback, so once a role
# App exists the credential every station actually runs on can hold MORE than
# its ceiling — silently breaking claims like "review is read-only" or
# "triage never holds contents write" that docs/security/README.md states as
# the security boundary. tests/static/security-ceiling-check.py cross-
# references three sources that must independently agree: the doc's ceiling
# table, the job's actual `permissions:`/`environment:` in
# .github/workflows/*.yml, and bootstrap.sh's role_perms() App scope — and
# fails on drift in EITHER direction (under- or over-privilege), plus an
# inbound station's `environment:` pointing at an undocumented role.
SECURITY_CEILING_CHECK="tests/static/security-ceiling-check.py"
if [ ! -f "$SECURITY_CEILING_CHECK" ]; then
  bad "$SECURITY_CEILING_CHECK missing — the ceiling-vs-actual-credential check (#100) is not wired"
elif python3 -c "import yaml" 2>/dev/null; then
  if python3 "$SECURITY_CEILING_CHECK" . >/dev/null 2>&1; then
    ok "declared permissions: blocks, environment: role mapping, and bootstrap.sh App scopes all match docs/security/README.md's ceiling table"
  else
    bad "ceiling-vs-actual-credential drift: $(python3 "$SECURITY_CEILING_CHECK" . 2>&1 | tr '\n' ' ')"
  fi

  # Regression proof: each direction of drift must actually FIRE against a
  # mutated fixture copy, not just stay silent on an already-clean tree. Work
  # on throwaway copies of only the three inputs the check reads.
  CEILING_FIXTURE="$(mktemp -d)"
  mkdir -p "$CEILING_FIXTURE/docs/security" "$CEILING_FIXTURE/.github/workflows"
  cp docs/security/README.md "$CEILING_FIXTURE/docs/security/README.md"
  cp bootstrap.sh "$CEILING_FIXTURE/bootstrap.sh"
  cp .github/workflows/*.yml "$CEILING_FIXTURE/.github/workflows/"

  if python3 "$SECURITY_CEILING_CHECK" "$CEILING_FIXTURE" >/dev/null 2>&1; then
    ok "ceiling-check fixture baseline (uncorrupted copy) is clean"
  else
    bad "ceiling-check fixture baseline is not clean — the regression cases below prove nothing"
  fi

  # 1. Over-privilege: the triage App scope grows contents:write, beyond the
  # doc's contents:read ceiling for that (inbound) role.
  cp "$CEILING_FIXTURE/bootstrap.sh" "$CEILING_FIXTURE/bootstrap.sh.orig"
  sed -i 's/triage)       printf '"'"'{"issues":"write","contents":"read"}'"'"'/triage)       printf '"'"'{"issues":"write","contents":"write"}'"'"'/' \
    "$CEILING_FIXTURE/bootstrap.sh"
  CASE_OUT="$(python3 "$SECURITY_CEILING_CHECK" "$CEILING_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q 'not bound by the declared ceiling'; then
    ok "ceiling-check catches an over-privileged App scope (regression fixture: triage App scope gains contents:write)"
  else
    bad "ceiling-check MISSED an App scope exceeding its documented ceiling — over-privilege gap (#100)"
  fi
  cp "$CEILING_FIXTURE/bootstrap.sh.orig" "$CEILING_FIXTURE/bootstrap.sh"

  # 2. Doc drift: the security doc stops documenting a permission the review
  # job's actual `permissions:` block still grants (checks:read).
  cp "$CEILING_FIXTURE/docs/security/README.md" "$CEILING_FIXTURE/docs/security/README.md.orig"
  sed -i 's/, `checks: read` |/ |/' "$CEILING_FIXTURE/docs/security/README.md"
  CASE_OUT="$(python3 "$SECURITY_CEILING_CHECK" "$CEILING_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q 'does not document'; then
    ok "ceiling-check catches the security doc drifting from the job's actual permissions (regression fixture: review row drops checks:read)"
  else
    bad "ceiling-check MISSED the security doc's ceiling table drifting from the actual permissions: block"
  fi
  cp "$CEILING_FIXTURE/docs/security/README.md.orig" "$CEILING_FIXTURE/docs/security/README.md"

  # 3. Environment mismatch: an inbound station's job silently targets a
  # different role than the one docs/security/README.md documents for it.
  cp "$CEILING_FIXTURE/.github/workflows/on-issue.yml" "$CEILING_FIXTURE/.github/workflows/on-issue.yml.orig"
  sed -i 's/environment: triage/environment: qa/' "$CEILING_FIXTURE/.github/workflows/on-issue.yml"
  CASE_OUT="$(python3 "$SECURITY_CEILING_CHECK" "$CEILING_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q "no claude-session.yml caller targets environment 'triage'"; then
    ok "ceiling-check catches an inbound station's environment drifting from its documented role (regression fixture: on-issue.yml -> qa)"
  else
    bad "ceiling-check MISSED an inbound station's environment pointing at the wrong role"
  fi
  # Same mutation also proves the station-vs-environment check is not dead
  # code: it must fire even though `on-issue.yml`'s station ('triage') is
  # still mapped and no OTHER job took the 'triage' environment slot (#100
  # review finding: the old check was pre-filtered by expected_env and could
  # never observe a mismatch).
  if printf '%s' "$CASE_OUT" | grep -q "declares station 'triage' but targets environment 'qa', not the documented 'triage' role"; then
    ok "ceiling-check's station-vs-environment check fires on its own (not dead code)"
  else
    bad "ceiling-check's station-vs-environment check MISSED the same drift its own dedicated message should catch"
  fi
  cp "$CEILING_FIXTURE/.github/workflows/on-issue.yml.orig" "$CEILING_FIXTURE/.github/workflows/on-issue.yml"

  # 4. Unmapped role escape: a caller on a real-but-undocumented role
  # (release/orchestrator/security-style) must not silently pass just
  # because ROW_TO_ENVIRONMENT/STATION_TO_ROW has no row for it.
  cat > "$CEILING_FIXTURE/.github/workflows/release-session.yml" <<'YAML'
name: release-session
on:
  workflow_dispatch: {}
jobs:
  release:
    permissions:
      contents: write
    uses: ./.github/workflows/claude-session.yml
    secrets: inherit
    with:
      station: release
      environment: release
YAML
  CASE_OUT="$(python3 "$SECURITY_CEILING_CHECK" "$CEILING_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q "declares station 'release' which has no documented ceiling row"; then
    ok "ceiling-check catches a caller on an undocumented role (regression fixture: release-session.yml)"
  else
    bad "ceiling-check MISSED a caller on an undocumented role — unmapped-role escape (#100)"
  fi
  rm -f "$CEILING_FIXTURE/.github/workflows/release-session.yml"

  # 5. Station-key collision: two jobs sharing a station string must not
  # silently drop one from the audit (the old station-keyed dict overwrote
  # on collision).
  cat > "$CEILING_FIXTURE/.github/workflows/review-mirror.yml" <<'YAML'
name: review-mirror
on:
  pull_request_target: {}
jobs:
  review-mirror:
    permissions:
      contents: write
    uses: ./.github/workflows/claude-session.yml
    secrets: inherit
    with:
      station: review
      environment: coder
YAML
  CASE_OUT="$(python3 "$SECURITY_CEILING_CHECK" "$CEILING_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q "both declare station 'review'"; then
    ok "ceiling-check catches two jobs sharing a station name (regression fixture: review-mirror.yml)"
  else
    bad "ceiling-check MISSED a station-name collision — one job could silently vanish from the audit (#100)"
  fi
  if printf '%s' "$CASE_OUT" | grep -q "declares station 'review' but targets environment 'coder'"; then
    ok "ceiling-check still examines the colliding job's own environment instead of dropping it"
  else
    bad "ceiling-check dropped the colliding job instead of still auditing its environment"
  fi
  rm -f "$CEILING_FIXTURE/.github/workflows/review-mirror.yml"

  rm -rf "$CEILING_FIXTURE"
else
  ok "pyyaml unavailable locally — ceiling-vs-credential check deferred to CI"
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

  # Every station that calls it must say what it needs, or it runs on the
  # repository default rather than a considered least-privilege set — and the
  # callers are DISCOVERED, not listed, so a future fifth station cannot escape
  # least-privilege enforcement by simply not being in a hardcoded list.
  #
  # The inbound rule is derived the same way. A station is inbound if its
  # workflow triggers on attacker-controlled events, and no inbound station may
  # hold contents:write. Hardcoding that check to on-issue.yml missed on-pr.yml's
  # review job, which reads the PR diff and is every bit as inbound.
  if python3 -c '
import glob, sys, yaml

INBOUND = {"issues", "issue_comment", "pull_request", "pull_request_target",
           "pull_request_review", "pull_request_review_comment", "discussion",
           "discussion_comment", "fork", "watch", "public"}
problems, checked = [], 0

for path in sorted(glob.glob(".github/workflows/*.yml")):
    wf = yaml.safe_load(open(path))
    if not isinstance(wf, dict):
        continue
    # PyYAML reads a bare `on:` key as the boolean True.
    triggers = wf.get("on", wf.get(True)) or {}
    if isinstance(triggers, str):
        triggers = {triggers: None}
    if isinstance(triggers, list):
        triggers = {t: None for t in triggers}
    inbound = bool(INBOUND & set(triggers))

    for name, job in (wf.get("jobs") or {}).items():
        uses = job.get("uses")
        if not (isinstance(uses, str) and "claude-session.yml" in uses):
            continue
        checked += 1
        perms = job.get("permissions") or {}
        if not perms:
            problems.append(path + ":" + name + " calls claude-session.yml without declaring permissions")
        if inbound and perms.get("contents") == "write":
            problems.append(path + ":" + name + " is inbound-triggered yet holds contents:write")

if not checked:
    problems.append("no caller of claude-session.yml was found — the discovery is broken, not the config")
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
  '; then
    ok "every discovered session caller declares its ceiling; no inbound station holds contents write"
  else
    bad "a session caller lacks its permission set, or an inbound station can write repository contents"
  fi
else
  # Never skip silently: these are the invariants that keep #97 from returning,
  # and a runner that happens to lack pyyaml would otherwise stop checking them
  # with no trace in the output. CI installs pyyaml for this job so the
  # authoritative run always enforces them.
  ok "pyyaml unavailable locally — #97 permission invariants deferred to CI"
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

# --- static validation layer (Epic 1 layer 1, full depth) --------------------
# The agents loop above is the seed; tests/static/plugin-schema-check.mjs is
# the full-depth extension the spec calls for: manifest + frontmatter schema
# for every command/agent/skill/hook config, ${CLAUDE_PLUGIN_ROOT} path
# portability, referenced-files-exist, and JSON validity — for every file the
# plugin actually ships, not just agents/*.md.
STATIC_CHECK="tests/static/plugin-schema-check.mjs"
if [ -f "$STATIC_CHECK" ]; then
  STATIC_OUT="$(node "$STATIC_CHECK" . 2>&1)"
  if [ $? -eq 0 ]; then
    ok "plugin static validation (frontmatter/manifest schema, \${CLAUDE_PLUGIN_ROOT} portability, referenced-files-exist, JSON validity) is clean"
  else
    bad "plugin static validation found violations: $(printf '%s' "$STATIC_OUT" | grep -v '^(node:' | grep -v 'trace-warnings' | tr '\n' ' ')"
  fi

  # Regression proof: each of the four check categories must actually FIRE on
  # a genuine violation, not just stay silent on an already-clean tree. Work
  # on a throwaway copy of just the plugin-shipped dirs (small, no
  # node_modules) so corrupting it never touches the real tree.
  STATIC_FIXTURE="$(mktemp -d)"
  for d in commands agents skills hooks .claude-plugin schemas templates connector; do
    [ -d "$d" ] && cp -r "$d" "$STATIC_FIXTURE/$d"
  done
  [ -f .mcp.json ] && cp .mcp.json "$STATIC_FIXTURE/.mcp.json"

  if node "$STATIC_CHECK" "$STATIC_FIXTURE" >/dev/null 2>&1; then
    ok "static-validation fixture baseline (uncorrupted copy) is clean"
  else
    bad "static-validation fixture baseline is not clean — the regression cases below prove nothing"
  fi

  # Each regression case captures node's output into a variable FIRST and
  # greps the variable — not `node ... | grep -q`, which under `pipefail` can
  # report a false MISS: grep -q exits the instant it matches, closing the
  # pipe, and node can catch SIGPIPE trying to write more, so pipefail sees a
  # nonzero from node and reports pipeline failure even though grep matched.

  # 1. JSON validity: truncate hooks.json into invalid JSON.
  cp "$STATIC_FIXTURE/hooks/hooks.json" "$STATIC_FIXTURE/hooks/hooks.json.orig"
  printf '{ "hooks": ' > "$STATIC_FIXTURE/hooks/hooks.json"
  CASE_OUT="$(node "$STATIC_CHECK" "$STATIC_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q 'invalid JSON'; then
    ok "static check catches malformed JSON (regression fixture: truncated hooks.json)"
  else
    bad "static check MISSED malformed hooks/hooks.json — JSON-validity gap"
  fi
  cp "$STATIC_FIXTURE/hooks/hooks.json.orig" "$STATIC_FIXTURE/hooks/hooks.json"

  # 2. manifest + frontmatter schema: strip a command's required description.
  cp "$STATIC_FIXTURE/commands/adr.md" "$STATIC_FIXTURE/commands/adr.md.orig"
  sed -i '/^description:/d' "$STATIC_FIXTURE/commands/adr.md"
  CASE_OUT="$(node "$STATIC_CHECK" "$STATIC_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q 'commands/adr.md.*description'; then
    ok "static check catches a command missing required frontmatter (regression fixture: adr.md sans description)"
  else
    bad "static check MISSED a command with no description frontmatter — schema gap"
  fi
  cp "$STATIC_FIXTURE/commands/adr.md.orig" "$STATIC_FIXTURE/commands/adr.md"

  # 3. ${CLAUDE_PLUGIN_ROOT} portability: hardcode a hook command to an
  # absolute path instead.
  cp "$STATIC_FIXTURE/hooks/hooks.json" "$STATIC_FIXTURE/hooks/hooks.json.orig"
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    const j = JSON.parse(fs.readFileSync(f, "utf8"));
    j.hooks.SessionStart[0].hooks[0].command = "/home/runner/evil/bootstrap.sh";
    fs.writeFileSync(f, JSON.stringify(j, null, 2));
  ' "$STATIC_FIXTURE/hooks/hooks.json"
  CASE_OUT="$(node "$STATIC_CHECK" "$STATIC_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q 'absolute path'; then
    ok "static check catches a hardcoded absolute path instead of \${CLAUDE_PLUGIN_ROOT} (regression fixture)"
  else
    bad "static check MISSED a hook command hardcoded to an absolute path — portability gap"
  fi
  cp "$STATIC_FIXTURE/hooks/hooks.json.orig" "$STATIC_FIXTURE/hooks/hooks.json"

  # 4. referenced-files-exist: delete a script a hook command points at.
  rm -f "$STATIC_FIXTURE/hooks/scripts/bootstrap.sh"
  CASE_OUT="$(node "$STATIC_CHECK" "$STATIC_FIXTURE" 2>&1)"
  if printf '%s' "$CASE_OUT" | grep -q 'does not exist'; then
    ok "static check catches a hook referencing a script that does not exist (regression fixture)"
  else
    bad "static check MISSED a hook referencing a missing script — referenced-file gap"
  fi

  rm -rf "$STATIC_FIXTURE"
else
  bad "$STATIC_CHECK missing — layer-1 static validation (manifest/frontmatter schema, path portability, referenced-files-exist, JSON validity) not wired"
fi

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
