# ADR 0003 — Run the factory as event-driven GitHub Actions with per-role GitHub App identities

Status: accepted · Date: 2026-07-23

## Context

This plugin must build, test, review, and ship itself with zero human input
after a single bootstrap run. That requires: an orchestrator that survives any
single machine dying; sessions that can hit usage limits and resume exactly
where they stopped; attributable, least-privilege identity per agent role; and
triggers that actually fire (pushes made with the default `GITHUB_TOKEN` do
not trigger workflows, which would deadlock CI and review on the factory's own
PRs). Claude Desktop or any interactive surface as a dependency would make the
whole system as reliable as one laptop.

## Decision

- **GitHub Actions is the orchestrator.** All control flow is event-driven
  workflows (`cron-prod` hourly resume, `on-issue`, `on-pr`, `factory-run`,
  `nightly-eval`); all state lives in the repo or GitHub (issues, milestones,
  `docs/ROADMAP.md`, `.factory/ledger.jsonl`, `factory-ops/`). A session may
  die at any instant; a fresh one reconstructs everything from
  `factory-ops/state/checkpoint.json` and the repo alone.
- **Sessions are headless CLI**: `claude -p` with `--plugin-dir .` so the
  factory dogfoods its own hooks; the marketplace copy of the plugin is
  disabled in-session to avoid double-loading.
- **One GitHub App per agent role**, created by `bootstrap.sh` via the
  manifest flow, each with a least-privilege permission set and its private
  key stored as an environment-scoped secret only the matching workflow can
  read. Agent pushes use app tokens so CI and review runs fire; every action
  is attributable to `<agent>[bot]`. GitHub cannot assign issues to apps, so
  work ownership lives in the project board's `Owner` field while authorship
  comes from the app identity.
- **`icculus` (self-hosted, Dockerized, egress-allowlisted) is preferred
  muscle; hosted runners are the fallback** — the factory degrades, it never
  depends on one host.

Rejected: a long-lived daemon on icculus (single point of failure), one shared
bot identity (no attribution, no least privilege, and `GITHUB_TOKEN` pushes
would not trigger workflows), and interactive sessions anywhere in the loop.

## Consequences

- Any workflow, agent, or prompt change ships like product code — same PR
  gates, reviewed by the factory itself (decision owner: architect; security
  posture: security-steward).
- The hourly cron is the universal retry: usage limits become checkpoint +
  resume, never red exits.
- Cost: ~a dozen one-time browser clicks during bootstrap for app creation,
  and per-app key rotation becomes an operational duty (security-steward's
  audit covers drift).
- The board (`GOVERNANCE.md`) exists to change THIS decision too — via
  judge-panel and a superseding ADR, never silently.
