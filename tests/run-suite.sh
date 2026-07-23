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
bash -n bootstrap.sh hooks/scripts/*.sh hooks/lib/common.sh tests/*.sh

stage "boundaries (scaffold contract: manifests, workflows, config, fences)"
bash tests/scaffold.contract.test.sh

stage "unit (connector: zero-dep node --test)"
( cd connector && node --test test/factory-core.test.mjs test/protocol.test.mjs )

stage "bdd (hermetic hook contract tests)"
bash tests/hooks.contract.test.sh

stage "build (claude plugin validate --strict on both manifests)"
npx --yes "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" plugin validate .claude-plugin/plugin.json --strict
npx --yes "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" plugin validate .claude-plugin/marketplace.json --strict

printf '\nsuite green\n'
