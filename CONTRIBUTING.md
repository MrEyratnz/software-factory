# Contributing to software-factory

This repository builds the `dark-software-factory` Claude Code plugin, and it
dogfoods the plugin's own laws.

## The laws (this repo)

- **Tests are the gate.** The connector has a zero-dependency suite
  (`cd connector && node --test`), and the hooks have hermetic contract tests
  (`bash tests/hooks.contract.test.sh`). Both are green at every commit; CI
  (`.github/workflows/validate.yml`) re-runs them plus
  `claude plugin validate --strict` and `shellcheck` as the authority.
- **Conventional Commits.** `feat:`→minor, `fix:`→patch, `!`/`BREAKING CHANGE`→
  major. release-please cuts releases; never release from red.
- **The connector stays pure and read-only.** All repo mutation happens in the
  command/agent/hook layer, never in the MCP server. Correctness-critical logic
  lives in `connector/src/factory-core.mjs` as pure functions so it is
  hermetically testable and shared as one source of truth by hooks and CI.
- **Hooks are POSIX + node stdlib only.** No runtime dependencies. New hook
  behavior ships with a case in `tests/hooks.contract.test.sh`.

## Code review → tech-debt

Any finding from a review — including adversarial reviews and re-reviews of a
PR — that is **not fixed in the current PR** must be opened as a GitHub issue
labeled `tech-debt`. Include the location (`file:line`), what it is and why it
matters (a concrete failure or cost), its provenance (pre-existing vs.
introduced), and a suggested fix. Create the `tech-debt` label if it does not
exist. Do not silently drop a finding or bury it only in chat.
