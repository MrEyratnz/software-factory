# Governance

This repository is operated by an autonomous software factory (see
`docs/adr/0002-event-driven-github-actions-factory.md`). Day-to-day decisions
have single owners; cross-cutting decisions go to the board. Nothing here
overrides the enforced laws (hooks + CI) or `SECURITY.md`.

## Decision owners (default path — no meeting needed)

| Decision | Owner |
|---|---|
| Backlog priority, milestone scope, feature freeze | product owner |
| Sprint composition, work assignment | planner |
| System shape, ADRs, spec standards | architect |
| Suite thresholds and test health | qa |
| Security posture within the documented architecture | security-steward |
| Model/effort routing, cost program | efficiency-engineer |
| Funding docs and community comms | treasurer |
| Cutting a release (only via `/ship`, only when the gate holds) | release-captain |

Ambiguity rule: unknown fact → market-researcher researches; ambiguous
priority → product owner decides; contested design → judge-panel. Log the
decision and move.

## The board

The board is an agent body — a **standing judge panel with a fixed roster**:

- **Chair** — orchestrator (conductor)
- **Product Officer** — product-owner
- **Chief Architect** — architect
- **Security Officer** — security-steward
- **Treasurer** — treasurer
- **Efficiency Officer** — efficiency-engineer

**Convenes:** every 4th sprint, and on demand for: scope changes to a frozen
milestone, security-posture exceptions, budget-strategy shifts,
license/community policy, and anything two agents escalate as contested.

**Method:** board decisions run through the existing judge-panel machinery —
partisan proposals, adversarial ballots naming each fatal flaw, then a
synthesis that resolves every confirmed flaw — and land as numbered ADRs in
`docs/adr/`. **No decision without a written ADR; no ADR without a decision
owner** named in its Consequences.

## Humans

Humans interact through issues and PRs like anyone else, plus two kill
switches the factory never touches: the `FACTORY_HALT` repository variable and
`.factory/state/paused`. The maintainer roster is in `MAINTAINERS.md`.
