# factory-ops — agent-owned operational state

Everything the autonomous SDLC needs to resume from a cold start lives here
(or in GitHub issues/milestones) — **never** in `.factory/`, which is the
plugin's hook-managed trust root and unwritable by agents.

| Path | Owner | Contents |
|---|---|---|
| `state/checkpoint.json` | orchestrator | the resume contract: `version`, `station`, `sprint`, `sprint_ends_at`, `branch`, `issues`, `next_action`, `notes`. Written (and committed, `chore:`) on every parked stop — usage limit, timeout, clean checkpoint. `cron-prod.yml` reads it hourly and dispatches the right workflow. |
| `sprints/<n>/` | planner | `plan.md`, `standup.md`, `review.md`, `retro.md` per sprint |
| `qa/` | qa | eval reports (`<date>.md`), cached baselines, `evals/` harness data |
| `cost/` | efficiency-engineer | per-session cost records keyed by station + agent; `ROUTING.md` (the model/effort routing table) |

Rules: a session may die at any instant — anything not committed here or
visible in GitHub does not exist. Convert relative time to absolute
timestamps (UTC ISO-8601) when writing state. Checkpoint commits are `chore:`
(no source staged) so the tests-first gate does not bind.
