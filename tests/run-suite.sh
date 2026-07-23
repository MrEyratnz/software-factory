#!/usr/bin/env bash
# run-suite.sh — the full ordered green gate for THIS repo (the plugin itself),
# runnable as one command locally and in CI. Stage order is the tdd-green-gate
# law: typecheck → boundaries → unit → BDD → build. Keep these stages in sync
# with .factory/config.json `gates` — that config is what the hooks and
# gate_evaluate run; this script is the same pipeline as a single testCommand.
set -euo pipefail
cd "$(dirname "$0")/.."

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.218}"

stage() { printf '\n== suite: %s\n' "$1"; }

stage "typecheck (bash -n over every shell entrypoint)"
bash -n bootstrap.sh hooks/scripts/*.sh hooks/lib/common.sh tests/*.sh scripts/*.sh

stage "boundaries (scaffold contract + config schema + triage-script contracts)"
bash tests/scaffold.contract.test.sh
node --test scripts/validate-config.test.mjs scripts/pr-review-state.test.mjs scripts/merge-method.test.mjs
node scripts/validate-config.mjs .factory/config.json schemas/factory.config.schema.json
node scripts/validate-config.mjs templates/factory/config.json.tmpl schemas/factory.config.schema.json
./scripts/test-triage-scripts.sh

stage "unit (connector: zero-dep node --test)"
( cd connector && node --test 'test/**/*.test.mjs' )

stage "bdd (hermetic hook contract tests)"
bash tests/hooks.contract.test.sh

stage "build (claude plugin validate --strict on both manifests)"
npx --yes "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" plugin validate .claude-plugin/plugin.json --strict
npx --yes "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" plugin validate .claude-plugin/marketplace.json --strict

printf '\nsuite green\n'
