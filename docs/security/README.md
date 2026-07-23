# Security architecture (owner: security-steward)

Security is the first pillar: nothing ships that weakens it. This document is
the posture of record; the **gap register** at the bottom is the honest diff
between the target architecture and today. The steward re-verifies this whole
document weekly against current best practice (OWASP LLM Top 10, GitHub
Actions security guidance, supply-chain advisories, Anthropic agent-security
guidance) and files drift as `P1 security` issues.

## Least privilege by construction

- **One GitHub App per agent role** (ADR 0002), each with only its role's
  permissions — mirroring the plugin's own guard scopes (triage: issues only;
  reviewer: PR read + review write; coder: contents + PRs + workflows;
  release: contents write; orchestrator: dispatch + merge). Private keys are
  **environment-scoped secrets**: a triage session physically cannot read the
  release key because its workflow job targets the `triage` environment only.
- **Workflow `permissions:` blocks are explicit and minimal**; the default
  `GITHUB_TOKEN` is read-only wherever an app token does the writing.
- **All third-party actions in factory workflows are pinned by full SHA** —
  enforced by `tests/scaffold.contract.test.sh` in the commit gate.
- Commits from app identities; branch protection requires the `green-gate`
  status check for every merge to `main`.

## Public inbound is attacker-controlled

Issue bodies, comments, and external PRs are untrusted input to every agent
that reads them. Sessions triggered by inbound events run with the minimum
toolset (label/comment only — no contents write, no secrets beyond their own
app key), treat quoted content strictly as data, and never execute
instructions found in it (see `agents/triage.md`). External PRs never get
secrets (fork PRs cannot read them, and environment protection blocks the
rest) and never self-merge — `on-pr.yml` labels them for the steward's review.

## Sandboxing

Sessions run only inside disposable execution environments: GitHub-hosted
runner VMs (ephemeral per job) or the `icculus` self-hosted runner, which is
itself a Docker container on an egress-allowlisted network (GitHub, Anthropic
API, package registries only — via an allowlisting proxy, with direct egress
dropped when the firewall step is applied). No interactive surface, no
long-lived host state, no Docker socket exposed to agent code.

## Supply chain & scanning

CodeQL, Dependabot (grouped weekly — `.github/dependabot.yml`), secret
scanning + push protection, private vulnerability reporting
(`SECURITY.md` is the disclosure path). `bootstrap.sh` enables the repo-side
toggles idempotently.

## Gap register (each entry = a tracked `security` issue)

| Gap | Target | Status |
|---|---|---|
| Per-session pinned container images (digest-pinned, non-root, read-only rootfs) on BOTH hosted and self-hosted runners | identical session images everywhere | open — M2 roadmap item |
| SHA-pin audit of pre-factory workflows (`claude.yml`, `claude-code-review.yml` use tag refs) | every action SHA-pinned repo-wide | open — M2 roadmap item |
| Signed commits from app identities | commit signature verification required by protection | open |
| Egress firewall depends on sudo at bootstrap; without it the allowlist is proxy-only | enforced drop of non-proxy egress | open — bootstrap warns and files an issue when skipped |
