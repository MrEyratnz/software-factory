# Model / effort routing table (owner: efficiency-engineer)

Cheapest model at the lowest effort that clears the bar, per station.
Ultracode is a station-level dial, never blanket: ON where the cost of a miss
exceeds the compute; OFF for mechanical work. Revisit with cost data at every
retro — models change, this table follows. The effectiveness floor (green
gates, eval thresholds) is inviolable; a routing change that dents it reverts.

| Station | Model | Effort | Ultracode | Why |
|---|---|---|---|---|
| triage, labels, standup digest | haiku | low | off | classification; a miss costs one relabel |
| doc chores, checkpoint writes | haiku | low | off | mechanical |
| sprint planning / review / retro | sonnet | medium | off | synthesis over known state |
| implementation (`/next`, factory-run) | sonnet | high | off (explicit workflows at standard effort) | TDD loop with hard gates catching misses |
| PR review (3-lens panel) | opus | high | off | adversarial quality bar |
| judge panels, board sessions | opus | high | **on** | a wrong ruling compounds across sprints |
| security audits | opus | high | **on** | a miss ships a weakness |
| Release Gate verification, `/ship` | opus | high | **on** | a bad release is the costliest miss |
| gnarly implementation epics (flagged by planner) | opus | high | **on** | escalation path, case-by-case |
| nightly eval triage | sonnet | medium | off | threshold comparison + issue filing |

Session cost records land in this directory as `<date>-<run_id>.json`
(station, agent, model, effort, tokens in/out, duration, outcome), written by
each workflow session. North-star metrics reviewed at retro: cost per merged
PR, cost per eval point, cost per sprint — plus workflow-library reuse rate.
