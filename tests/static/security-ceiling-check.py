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
    """{ key: {"path","job","environment","ceiling"} } for every job calling
    claude-session.yml, keyed by its `with.station` (falling back to
    path:job if a caller ever omits one) — discovered, never hardcoded, so a
    future station cannot escape this check just by not being listed."""
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
            jobs[station or f"{path}:{name}"] = {
                "path": path,
                "job": name,
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

            # 2. the job's environment must be the role the doc says this
            #    station holds — an inbound station's environment silently
            #    pointing at a different (wider) role is exactly the drift
            #    #100 warns a convention alone cannot catch.
            if info["environment"] != expected_env:
                problems.append(
                    f"{info['path']}:{info['job']} ({row}) targets environment "
                    f"'{info['environment']}', not the documented '{expected_env}' role"
                )

        # 3. the App token's OWN scope for this role must match the ceiling
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
