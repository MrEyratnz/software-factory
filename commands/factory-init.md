---
description: Scaffold the Dark Software Factory into the current repo — docs spine, .factory/config.json, CI + release workflows, dependency-cruiser, and the tech-debt/release-blocker labels.
argument-hint: "[--stack node|python|go|auto] [--plan]"
---

Set up this repository as a lights-out software factory. Arguments: `$ARGUMENTS`
(default `--stack auto`; `--plan` = dry run that writes nothing and makes no
network calls).

Do this, idempotently (never clobber authored docs — refresh templates and
config only):

1. **Detect the stack** (package manager, and the real commands for typecheck,
   module-boundary check, unit, BDD, build, and generated-artifact drift). Use
   the templates under `${CLAUDE_PLUGIN_ROOT}/templates/stacks/` as the starting
   map. Write the resolved commands + `sourceRegex`/`testRegex`/`roadmapPath`/
   `releaseBranch`/`generators`/`maxIterations` to `.factory/config.json`
   (validate it against `${CLAUDE_PLUGIN_ROOT}/schemas/factory.config.schema.json`).
2. **Stamp the docs spine** from `${CLAUDE_PLUGIN_ROOT}/templates/docs/` if
   absent: `docs/VISION.md`, `docs/ARCHITECTURE.md`,
   `docs/adr/0001-record-architecture-decisions.md`, `docs/ROADMAP.md`, and a
   `CLAUDE.md` carrying the review→tech-debt convention.
3. **Generate CI + release** from `${CLAUDE_PLUGIN_ROOT}/templates/github/` and a
   stack-appropriate `.dependency-cruiser` (or equivalent) boundary config. Tell
   the user to enable branch protection + required status checks on the release
   branch — that is where "merged with green tests" is truly enforced.
4. **Labels**: ensure `tech-debt` and `release-blocker` GitHub labels exist
   (create if missing), and open/refresh a meta tracking issue mirroring the
   roadmap.

Under `--plan`, print exactly what you *would* write/create and stop.
Dispatch the **architect** for the docs; load the `factory-config` and
`docs-spine` skills.

**Source control for `.factory/` (commit the config, ignore the runtime
state).** `.factory/config.json` is the per-repo enforcement contract — the
committed, reviewable source of truth for this repo's gates (testCommand, the
regexes, the `enforcement` toggles). It MUST be committed, or a teammate's clone
and CI run with the hardcoded defaults instead of the repo's intended settings,
so the factory "sometimes" behaves differently per checkout. The runtime state
under `.factory/` (green receipts, the ledger, review/panel artifacts, the
active-agent marker) is session-local and regenerated, so it must NOT be
committed. Add exactly these lines to `.gitignore` (do NOT ignore all of
`.factory/`, which would un-track the config):

```gitignore
.factory/state/
.factory/review/
.factory/panel/
.factory/ledger.jsonl
.factory/active-agent
```

Then `git add .factory/config.json` so the enforcement contract is tracked.
