#!/usr/bin/env python3
"""security-ceiling-check.py <root> — cross-references the three sources of
truth that must independently agree for the "review is read-only", "triage
never holds contents write" style claims in docs/security/README.md to
actually hold (issue #100):

  1. docs/security/README.md's ceiling table — the claimed GITHUB_TOKEN bound
     per station.
  2. The ACTUAL `permissions:` block + `environment:` input on the job in
     .github/workflows/*.yml that calls claude-session.yml for that station —
     the ceiling and role mapping as they exist in code, not prose.
  3. bootstrap.sh's role_perms() — the App token's OWN scope for that role,
     which is the credential that actually governs once a role App exists.

A workflow `permissions:` block bounds ONLY the GITHUB_TOKEN fallback path.
claude-session.yml prefers a minted role App token, then FACTORY_PAT, before
ever touching GITHUB_TOKEN (see claude-session.yml's token-resolution
comment) — so on the App path the effective authority is whatever
bootstrap.sh grants that role, not the declared ceiling. Making that
alignment machine-checkable means failing when ANY of the three drift apart:
docs vs. the actual job ceiling, the job's `environment:` vs. the role the
doc says that station should hold, or the App scope for that role vs. the
ceiling (in EITHER direction — under-privilege 403s on the App path,
over-privilege means the ceiling never bounded that credential at all, which
is the exact gap #100 opened on).

Exports check(root) -> list[str] (problems; empty = clean) so
tests/scaffold.contract.test.sh can point it at a mutated fixture copy and
prove each direction of drift actually fires, not just that the real tree
(clean today) stays silent. Also runnable directly:
`python3 security-ceiling-check.py [root]`.
"""
import glob
import os
import re
import sys

import yaml

# The doc table's row label is hand-authored English ("QA (nightly)",
# "factory-run (dispatch only)") and does not itself carry the GitHub
# Environment name a job targets — so this maps each row's leading word to
# the `environment:` input that role actually holds. This IS the check's
# model of "the documented role"; review it by hand whenever a row is added.
ROW_TO_ENVIRONMENT = {
    "triage": "triage",
    "review": "reviewer",
    "qa": "qa",
    "factory-run": "coder",
}

# A job's own `with.station:` input is its self-declared identity — distinct
# from `with.environment:` (the credential it actually runs on) so that the
# two can be compared for drift. Station names don't always match the doc
# row's leading word (the QA row's caller is nightly-eval.yml's `station:
# nightly-eval`), so this mapping is maintained separately from
# ROW_TO_ENVIRONMENT and reviewed by hand alongside it.
STATION_TO_ROW = {
    "triage": "triage",
    "review": "review",
    "nightly-eval": "qa",
    "factory-run": "factory-run",
}


def _to_app_perm(perm):
    """GITHUB_TOKEN permission name -> bootstrap.sh role_perms() JSON key."""
    return perm.replace("-", "_")


def _to_ceiling_perm(app_perm):
    """bootstrap.sh role_perms() JSON key -> GITHUB_TOKEN permission name."""
    return app_perm.replace("_", "-")


def parse_doc_ceilings(doc_path):
    """{ row_label: {perm: level} } straight from the markdown table."""
    ceilings = {}
    text = open(doc_path, encoding="utf-8").read()
    for line in text.splitlines():
        m = re.match(r"^\s*\|\s*([a-zA-Z-]+)\s*\(([^)]*)\)\s*\|(.*)\|\s*$", line)
        if not m:
            continue
        label = m.group(1).strip().lower()
        if label not in ROW_TO_ENVIRONMENT:
            continue
        cell = m.group(3)
        perms = {}
        for pm in re.finditer(r"`([a-z-]+):\s*(read|write)`", cell):
            perms[pm.group(1)] = pm.group(2)
        ceilings[label] = perms
    return ceilings


def parse_role_perms(bootstrap_path):
    """{ role: {perm: level} } from bootstrap.sh's role_perms() case arms."""
    text = open(bootstrap_path, encoding="utf-8").read()
    apps = {}
    for m in re.finditer(r"^\s*([a-z-]+)\)\s*printf\s*'(\{.*?\})'", text, re.M):
        try:
            apps[m.group(1)] = yaml.safe_load(m.group(2))
        except yaml.YAMLError:
            continue
    return apps


def discover_session_jobs(workflows_glob):
    """{ "path:job": {"path","job","station","environment","ceiling"} } for
    every job calling claude-session.yml, keyed by its own path:job identity
    — never by `with.station`, which callers choose freely and which two
    jobs could share, silently dropping one from every check below —
    discovered, never hardcoded, so a future station cannot escape this
    check just by not being listed."""
    jobs = {}
    for path in sorted(glob.glob(workflows_glob)):
        wf = yaml.safe_load(open(path, encoding="utf-8"))
        if not isinstance(wf, dict):
            continue
        for name, job in (wf.get("jobs") or {}).items():
            uses = job.get("uses")
            if not (isinstance(uses, str) and "claude-session.yml" in uses):
                continue
            wth = job.get("with") or {}
            station = wth.get("station")
            environment = wth.get("environment")
            ceiling = job.get("permissions") or {}
            jobs[f"{path}:{name}"] = {
                "path": path,
                "job": name,
                "station": station,
                "environment": environment,
                "ceiling": ceiling,
            }
    return jobs


def check(root):
    problems = []
    doc_path = os.path.join(root, "docs/security/README.md")
    bootstrap_path = os.path.join(root, "bootstrap.sh")
    if not os.path.isfile(doc_path) or not os.path.isfile(bootstrap_path):
        return [f"missing docs/security/README.md or bootstrap.sh under {root}"]

    doc_ceilings = parse_doc_ceilings(doc_path)
    if not doc_ceilings:
        return ["docs/security/README.md ceiling table did not parse — check the row format"]

    role_perms = parse_role_perms(bootstrap_path)
    session_jobs = discover_session_jobs(os.path.join(root, ".github/workflows/*.yml"))

    # Fail closed on any caller whose station isn't one this check knows how
    # to audit at all — a real-but-undocumented role (release, orchestrator,
    # security, ...) must not silently escape every check below just because
    # ROW_TO_ENVIRONMENT/STATION_TO_ROW has no entry for it.
    for info in session_jobs.values():
        if info["station"] not in STATION_TO_ROW:
            problems.append(
                f"{info['path']}:{info['job']} declares station "
                f"'{info['station']}' which has no documented ceiling row — "
                f"add one to docs/security/README.md and STATION_TO_ROW, or "
                f"this check cannot bound its permissions"
            )

    # A station name is meant to identify one job. Two jobs sharing a
    # station string collide in any station-keyed view — including this
    # check's own history of keying `discover_session_jobs` by station —
    # and would silently drop one job from every check that follows.
    stations_seen = {}
    for info in session_jobs.values():
        station = info["station"]
        if station is None:
            continue
        prior = stations_seen.get(station)
        if prior is not None:
            problems.append(
                f"{info['path']}:{info['job']} and {prior} both declare "
                f"station '{station}' — duplicate station names collide in "
                f"any station-keyed audit of these jobs"
            )
        else:
            stations_seen[station] = f"{info['path']}:{info['job']}"

    # A job's own declared station says which documented role it claims to
    # be; its `environment:` is the credential it actually runs on. Checked
    # over every discovered job (not just ones that already landed under
    # their expected environment) so a station silently pointed at a wider
    # role's environment cannot hide by construction.
    for info in session_jobs.values():
        row = STATION_TO_ROW.get(info["station"])
        if row is None:
            continue  # already flagged above as an unmapped station
        expected_env = ROW_TO_ENVIRONMENT.get(row)
        if expected_env is not None and info["environment"] != expected_env:
            problems.append(
                f"{info['path']}:{info['job']} declares station "
                f"'{info['station']}' but targets environment "
                f"'{info['environment']}', not the documented '{expected_env}' role"
            )

    jobs_by_env = {}
    for key, info in session_jobs.items():
        jobs_by_env.setdefault(info["environment"], []).append((key, info))

    for row, expected_env in ROW_TO_ENVIRONMENT.items():
        if row not in doc_ceilings:
            problems.append(f"docs/security/README.md no longer documents a '{row}' ceiling row")
            continue
        doc_ceiling = doc_ceilings[row]

        matches = jobs_by_env.get(expected_env, [])
        if not matches:
            problems.append(
                f"no claude-session.yml caller targets environment '{expected_env}' "
                f"(the role docs/security/README.md's '{row}' row documents)"
            )
        for _key, info in matches:
            job_ceiling = info["ceiling"]

            # 1. doc <-> actual job permissions: block, drift in EITHER direction.
            for perm, level in doc_ceiling.items():
                if job_ceiling.get(perm) != level:
                    problems.append(
                        f"{info['path']}:{info['job']} ({row}) declares "
                        f"{perm}:{job_ceiling.get(perm, 'MISSING')} but "
                        f"docs/security/README.md's ceiling table says {perm}:{level}"
                    )
            for perm, level in job_ceiling.items():
                if perm not in doc_ceiling:
                    problems.append(
                        f"{info['path']}:{info['job']} ({row}) grants {perm}:{level} that "
                        f"docs/security/README.md's ceiling table does not document"
                    )

            # (station-vs-environment drift is checked once, over every
            # discovered job, above — `matches` here is already pre-filtered
            # by `expected_env` so re-checking it against the same value
            # here can never fire.)

        # 2. the App token's OWN scope for this role must match the ceiling
        #    EXACTLY, not just cover it: under-privilege 403s on the App
        #    path; over-privilege means the ceiling never bounded that
        #    credential at all — the App path is the one every station
        #    actually runs on once bootstrap.sh has provisioned it.
        scope = role_perms.get(expected_env)
        if scope is None:
            problems.append(
                f"bootstrap.sh role_perms() mints no App scope for role '{expected_env}' ({row})"
            )
            continue
        for perm, level in doc_ceiling.items():
            app_perm = _to_app_perm(perm)
            have = scope.get(app_perm)
            if have != level:
                problems.append(
                    f"{expected_env} App scope has {app_perm}:{have or 'MISSING'} but the "
                    f"'{row}' ceiling documents {perm}:{level} — the App path is not bound "
                    f"by the declared ceiling"
                )
        for app_perm, level in scope.items():
            if app_perm == "workflows":
                continue  # not a GITHUB_TOKEN scope; never appears in a ceiling
            perm = _to_ceiling_perm(app_perm)
            if perm not in doc_ceiling:
                problems.append(
                    f"{expected_env} App scope grants {app_perm}:{level} beyond anything the "
                    f"'{row}' ceiling documents — the App path holds undocumented authority"
                )

    return problems


if __name__ == "__main__":
    root_arg = sys.argv[1] if len(sys.argv) > 1 else "."
    found = check(root_arg)
    for line in found:
        print(line)
    sys.exit(1 if found else 0)
