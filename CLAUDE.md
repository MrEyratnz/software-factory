# dark-software-factory — working agreement for Claude

This repo is the **source of the Dark Software Factory plugin itself** — the
hooks, the connector, the commands/agents/skills, and the templates it stamps
into *other* repos. Read this before changing anything here.

## The one architectural invariant

Rule **verdicts** come from the pure engine (`connector/src/factory-core.mjs`,
reached from bash via the `fc` bridge in `hooks/lib/common.sh` →
`connector/src/cli.mjs`). The bash hooks do **I/O, git plumbing, and decision
emission only** — they must never re-implement a rule, or the enforcement path
and the connector's read path can silently disagree. New rule logic goes in
`factory-core.mjs` with a connector test; the hook just calls it.

## How to validate locally (mirror CI exactly)

CI (`.github/workflows/validate.yml`) is four independent gates. Run the same
commands before you push:

- **hooks contract + shellcheck**
  `shellcheck -S warning hooks/scripts/*.sh hooks/lib/common.sh tests/hooks.contract.test.sh`
  then `bash tests/hooks.contract.test.sh` (hermetic: synthetic stdin, throwaway
  repos, a `gh` shim — needs a `git config user.*`).
- **connector (unit + stdio protocol)**
  `cd connector && node --test "test/**/*.test.mjs"` (zero-dependency).
- **manifest validation**
  `npx @anthropic-ai/claude-code@<pinned> plugin validate .claude-plugin/plugin.json --strict`
  (and `marketplace.json`); keep the version pin in sync with the workflows.
- **structural checks** — every workflow YAML parses (duplicate-key-free), every
  JSON manifest/schema parses, every command/agent/skill starts with `---`
  frontmatter, and every `hooks.json` script exists and is executable.

**Every hook fix needs a regression test in `tests/hooks.contract.test.sh`, and
every engine fix a case in `connector/test/`.** That is how a fix is proven here
— see the next section for why you can't prove it by running the live plugin.

## You cannot dogfood the *live* hooks while editing them

When this plugin is enabled in a session, the **active hooks are the published
build the marketplace serves — not your working tree.** Editing
`hooks/**` or `connector/**` does not hot-reload the running hooks, so a change
can never be validated by "just committing and watching the gate." Validate
changes two ways instead:

1. the **contract/connector test suites** above, and
2. a **fixture dogfood** — init a throwaway repo under a temp dir, drive the hook
   scripts directly with the event JSON on **stdin** and
   `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PROJECT_DIR` in the env (this is exactly how
   Claude Code invokes them), and assert the receipt/verdict.

Corollary: **this repo is intentionally *not* factory-initialized** (no
`.factory/config.json`), so the workflow gates (commit/release/roadmap) stay
**advisory** here. That is deliberate — self-gating the factory's own source
would judge your commits against the *published* hook logic, misfiring exactly
when you are mid-fix on a hook bug. Use plain `git`; the CI gates above are the
authoritative boundary for this repo.

## Review → tech-debt (this applies here too)

Any review finding — including adversarial-review findings — **not fixed in the
current PR** must be opened as a GitHub issue labeled `tech-debt`: location
(`file:line`), the concrete failure or cost, provenance (pre-existing vs.
introduced), and a suggested fix. Never silently drop a finding or bury it in
chat.

## Commits & releases

Conventional Commits are required — releases are automated by release-please off
`main` and smoke-tested on the built plugin artifact. Keep the CLI version pins
in `validate.yml` and `release-plugin.yml` identical.

## `.factory/` source-control policy (what we stamp into adopters)

Commit **`.factory/config.json`** (the per-repo enforcement contract, so clones
and CI share the same gates); ignore the runtime state
(`.factory/state/`, `review/`, `panel/`, `ledger.jsonl`, `active-agent`). This
repo's `.gitignore` already encodes that split; `commands/factory-init.md`
stamps it into adopting repos.
