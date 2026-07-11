# Architecture — software-factory

## Shape: a Claude Code plugin that polices its own construction

This repository **builds** the `dark-software-factory` plugin — a lights-out
software factory for Claude Code — and, per ADR-0002, **dogfoods it from the
working tree**: `.claude/settings.json` declares the marketplace with a
`directory` source (`"./"`), so a session in this repo is governed by the very
hooks under edit, and `.factory/config.json` is this repo's own committed
enforcement contract. There is no app to deploy; the "deployable" is the plugin
itself, cut as a git tag by release-please.

```
.claude-plugin/  plugin.json + marketplace.json (the installable identity)
commands/        slash-command stations (/factory-init, /next, /review, /ship, /factory-run, …)
agents/          least-privilege crew (implementer, reviewer ×3, architect, release-captain, …)
skills/          methodology references (tdd-green-gate, adversarial-review, factory-config, …)
hooks/           enforcement: hooks.json wiring + scripts/ (guards) + lib/ (parsers, common.sh)
connector/       zero-dependency read-only MCP server; factory-core.mjs is the pure rule engine
schemas/         factory.config.schema.json (per-repo command-allowlist contract), finding.schema.json
templates/       what /factory-init stamps into target repos (docs spine, config, CI, stacks)
.factory/        config.json committed (the contract); state/ runtime, gitignored
.github/         validate.yml (authoritative CI), release-plugin.yml, claude triage/review/pickup
docs/adr/        numbered decisions (the default adrDir); tests/ hermetic hook contract tests
```

## Layer responsibilities & allowed dependencies

| Layer | Owns | May depend on |
|---|---|---|
| `connector/src/factory-core.mjs` | every rule *verdict* (roadmap, commit lint, gates, release plan, tech-debt audit) as pure functions — no I/O, clock, or randomness | nothing |
| `connector/src/server.mjs` (MCP) / `cli.mjs` | read-only tool exposure over stdio; the shell bridge hooks and CI call | factory-core, node stdlib |
| `hooks/lib` | event-JSON plumbing (`common.sh`), quote-aware parsers, OTEL emit | node stdlib, `cli.mjs` |
| `hooks/scripts` | allow/deny decisions at tool-use time (exit 0 / exit 2) | `hooks/lib`, `cli.mjs`, git, POSIX sh |
| `commands/`, `agents/`, `skills/` | the workflow prose: stations, roles, methodology | connector tools, hook-visible state |
| `templates/`, `schemas/` | what gets stamped into target repos; the config contract | nothing at runtime |
| `.github/workflows` | the authoritative re-enforcement boundary | the same test commands, pinned CLI |

Rules (each one enforced, not aspirational):

1. **Verdicts come only from factory-core.** Hooks call it via `cli.mjs`
   (`fc …` in `common.sh`); the MCP read path and the enforcement path share
   one implementation and can never disagree.
2. **The connector never mutates.** `server.mjs` reads files to feed the pure
   core — no writes, no command execution. All mutation lives in the
   command/agent/hook layer under normal permissions.
3. **Hooks are POSIX + node stdlib only.** No runtime dependencies anywhere in
   `hooks/` or `connector/` (OTEL is hand-built OTLP/HTTP, opt-in, fire-and-forget).
4. **Gates run only allowlisted commands.** Hooks resolve commands from
   `.factory/config.json` (whose contract is `schemas/factory.config.schema.json`,
   validated when `/factory-init` stamps it); they never eval a string a model produced.

## Trust model

The policed agent is **fenced out of the trust roots** it could use to excuse
itself: `.factory/config.json` and `.factory/state/**` are denied to
Write/Edit/MultiEdit by `guard-scope` (symlink-canonicalized, so a link into a
trust root cannot smuggle a write) and to Bash write-constructs
(redirect/tee/cp/sed -i/…) by `guard-bash-writes`. Role fences narrow further:
`reviewer` is read-only (findings to `.factory/review/` only, plus a full Bash
mutation fence), `proposer`/`panelist` write only `.factory/panel/`,
`architect` docs-only, `design-lead` the design dir plus docs,
`release-captain` docs plus the one sanctioned `release-intent.json`,
`tech-debt-clerk` `.factory/review/` only.

Green is a **receipt, not a claim**: `record-green` mints
`.factory/state/gate-receipt.json` bound to `git write-tree` from a recognized,
un-masked full-suite run's real exit code (green only on exit 0); `guard-commit`
refuses any commit whose current tree hash doesn't match a green receipt (plus
Conventional-Commit lint, tests-first for feat/fix, and no `--no-verify`). Any
edit changes the tree and silently invalidates the receipt. `guard-roadmap`
lets a checkbox flip only with merged-green proof; `guard-release` gates release
verbs on both Bash and github-MCP substrates; `guard-mcp-commit` closes the
remote-commit side door except mid-release, when `guard-release` is sole
arbiter. `debt-reconcile` blocks session Stop while any review finding is
neither fixed nor filed as a `tech-debt` issue (it reads files + GitHub, so it
survives compaction); `loop-guard` hard-caps `/factory-run` at `maxIterations`.

Hooks are deliberately best-effort — a determined agent can obfuscate — which
is why **CI is the authoritative boundary**: `validate.yml` re-runs the
identical gates on every push/PR with an explicit `contents: read` token, and
`release-plugin.yml` refuses to let release-please cut a tag until the built
artifact on that exact commit validates and smoke-tests.

## Structural safety invariants

- Every guard **fails closed**: no computable tree hash → deny; unset `$HOME`
  under `set -u` → the carve-out doesn't match rather than the hook erroring open;
  a blanked `testCommandRegex` disables receipt-minting rather than matching everything.
- Event JSON travels on **stdin, never env** (a >128 KB event would E2BIG every child).
- Command classification is **quote-aware and command-position-aware**
  (`parse-git-commit.mjs`, `classify-release.mjs`, `parse-bash-writes.mjs`):
  `git commit -m "npm publish"` is not a release; `-m "the -a flag"` is not `-a`.
- `parseRoadmap` ignores fenced code blocks, so example checkboxes can't hijack
  totals or the "next" item; `safePath` in the connector realpath-canonicalizes
  against the project root so a symlinked ledger cannot exfiltrate out-of-tree files.

## Testing strategy

- **Connector:** `cd connector && node --test` — unit tests for the pure core
  plus a stdio JSON-RPC protocol test. Zero dependencies keeps it hermetic.
- **Hooks:** `bash tests/hooks.contract.test.sh` — synthetic event JSON piped
  into every script inside throwaway git repos with a `gh` PATH shim, asserting
  exact exit codes (0 allow / 2 block). New hook behavior ships with a case here.
- **Shell hygiene:** `shellcheck -S warning` over `hooks/scripts`, `hooks/lib/common.sh`,
  `scripts/`, and the contract test itself; the triage wrapper scripts get
  hermetic argument-contract tests (they are the triage workflow's injection fence).
- **Plugin integrity:** `claude plugin validate --strict` (pinned CLI version)
  over both manifests, plus structural CI checks — duplicate-key-free YAML for
  every workflow, all JSON manifests/schemas parse, every command/agent/skill
  has frontmatter, every `hooks.json` script exists and is executable.

The first two of these are this repo's own `.factory/config.json` gates
(`unit`: the connector suite; `bdd`: the hook contract tests); shellcheck, the
triage-script tests, and plugin/structural validation are enforced in CI only.
The factory's laws — never commit red, tests-first, gated releases — still
apply to the factory itself at every commit.
