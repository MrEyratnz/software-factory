# Changelog

## [0.1.5](https://github.com/MrEyratnz/software-factory/compare/dark-software-factory-v0.1.4...dark-software-factory-v0.1.5) (2026-07-09)


### Features

* **hooks:** config-driven per-gate toggles and a session-local pause ([f851d89](https://github.com/MrEyratnz/software-factory/commit/f851d89e8a39157cdbf5a5aceef146a77b98df1d))
* **hooks:** optionally HMAC-sign gate receipts so hand-written proofs are rejected ([f5d2430](https://github.com/MrEyratnz/software-factory/commit/f5d243093d289c77f1949ca3788681d7ac7de7e7))
* **hooks:** tag heuristic denials distinctly from hard boundaries ([4735290](https://github.com/MrEyratnz/software-factory/commit/47352902d9d4137cfcf1aed9b4a863968e474d62))
* **release:** give the release-state files a real lifecycle ([a880c27](https://github.com/MrEyratnz/software-factory/commit/a880c27bf89cdc0ee3d3add16a21182cc980352d))


### Bug Fixes

* **guard-scope,guard-bash-writes:** out-of-project write parity + ~/.claude carve-out ([2a9e6e4](https://github.com/MrEyratnz/software-factory/commit/2a9e6e4a7f3fbcc4884b4abddf8128ad251d60b4))
* **hooks:** bind the green gate to the repo the command targets ([b681fd7](https://github.com/MrEyratnz/software-factory/commit/b681fd7bd9dabeb5e4486865bd768c96c622f52c))
* **hooks:** close 6 findings from the branch's adversarial self-review ([a338f7e](https://github.com/MrEyratnz/software-factory/commit/a338f7e8d59c0a2b4953e455d07232c2cd6a2272))
* **hooks:** resolve the git target dir with a quote-aware tokenizer ([32dc119](https://github.com/MrEyratnz/software-factory/commit/32dc1190ea482f8be1356722eeb8fc1239203728))
* **inject-status:** throttle the status banner instead of nagging every turn ([e4e9925](https://github.com/MrEyratnz/software-factory/commit/e4e9925d1ecf487c88d13e29493416a54cc21b15))
* **parse-git-commit:** a git-in-a-path substring is not a commit ([a02d4cc](https://github.com/MrEyratnz/software-factory/commit/a02d4ccb9ab5863740f28dbb0a904c8996d14b46))
* **record-green:** invoke the configured testCommand, never re-exec the matched command ([094f317](https://github.com/MrEyratnz/software-factory/commit/094f317402ad81dc5231d9fc0ccdae6298c8cae3))

## [0.1.4](https://github.com/MrEyratnz/software-factory/compare/dark-software-factory-v0.1.3...dark-software-factory-v0.1.4) (2026-07-09)


### Bug Fixes

* **marketplace:** use canonical ./ relative source for plugin entry ([51ffeb1](https://github.com/MrEyratnz/software-factory/commit/51ffeb1adc543d78844d555f2b10fa18524d6417))
* **marketplace:** use canonical ./ relative source for plugin entry ([78708ed](https://github.com/MrEyratnz/software-factory/commit/78708edbd8b0302a4175a30e90a51a0e54f32e96))

## [0.1.3](https://github.com/MrEyratnz/software-factory/compare/dark-software-factory-v0.1.2...dark-software-factory-v0.1.3) (2026-07-06)


### Features

* **otel:** opt-in push-based factory metrics (collector-only MVP) ([#9](https://github.com/MrEyratnz/software-factory/issues/9)) ([8d73641](https://github.com/MrEyratnz/software-factory/commit/8d7364172a934b733a4c3b5390da8451a3629494))


### Bug Fixes

* **connector:** correct ledger_read docstring to match the written ledger shape ([#18](https://github.com/MrEyratnz/software-factory/issues/18)) ([85777f0](https://github.com/MrEyratnz/software-factory/commit/85777f017c8998851ac89db139493f90d2e2cbb4))
* **hooks:** re-execute the gate when the harness omits tool_response.exitCode ([#22](https://github.com/MrEyratnz/software-factory/issues/22)) ([049bdfe](https://github.com/MrEyratnz/software-factory/commit/049bdfe1fd8aa0d43a5a313535a39c44a3aa77c2))

## [0.1.2](https://github.com/MrEyratnz/software-factory/compare/dark-software-factory-v0.1.1...dark-software-factory-v0.1.2) (2026-07-06)


### Bug Fixes

* **ci:** gate the release tag on a pre-tag artifact smoke and pin the validator ([#5](https://github.com/MrEyratnz/software-factory/issues/5)) ([167648e](https://github.com/MrEyratnz/software-factory/commit/167648ef518f09dd061a9a1e35ce169104ba5e87))
* **hooks:** enforce least-privilege for reviewer/release-captain/tech-debt-clerk ([#3](https://github.com/MrEyratnz/software-factory/issues/3)) ([37b26f9](https://github.com/MrEyratnz/software-factory/commit/37b26f9e28a0b99c4fc2c85b2020d64729b209ac))
* **hooks:** fail-conservative commit detection — close alias/newline/indirect evasions ([#6](https://github.com/MrEyratnz/software-factory/issues/6)) ([60d51f5](https://github.com/MrEyratnz/software-factory/commit/60d51f5ca91a3009234d8c7a6848a870a0a7720a))
* **hooks:** gate the github-MCP write path so commits can't bypass guard-commit ([#4](https://github.com/MrEyratnz/software-factory/issues/4)) ([9f3e890](https://github.com/MrEyratnz/software-factory/commit/9f3e890d2a01bd0e464060bdb38b9c14a0c7d917))

## [0.1.1](https://github.com/MrEyratnz/software-factory/compare/dark-software-factory-v0.1.0...dark-software-factory-v0.1.1) (2026-07-06)


### Features

* **commands,agents,skills:** complete the factory surface, templates, CI + gated release ([9a4ce43](https://github.com/MrEyratnz/software-factory/commit/9a4ce43178ef980b7d8cab07fff515c286176af0))
* dark-software-factory — lights-out Claude Code plugin ([#1](https://github.com/MrEyratnz/software-factory/issues/1)) ([aa524cc](https://github.com/MrEyratnz/software-factory/commit/aa524cce568e4e6596013b7a88c92a811167173d))
* **hooks,connector:** governance hooks + extended rule engine ([e9485b4](https://github.com/MrEyratnz/software-factory/commit/e9485b494bf602094e8c4b285c0d80d558aac73e))
* scaffold dark-software-factory plugin with MCP connector ([b2de336](https://github.com/MrEyratnz/software-factory/commit/b2de3366e3a1f53cc3d858842fe0ffb5409a31a3))


### Bug Fixes

* address adversarial-review findings — harden gates, close bypass paths ([2333748](https://github.com/MrEyratnz/software-factory/commit/23337480f40f08ae930cca03d7a8eaf314e32325))
* **release:** work without the repo PR-creation toggle; document the setting ([854b764](https://github.com/MrEyratnz/software-factory/commit/854b764cc97a6697c8a226d0d1552a9c51fba823))
* **release:** work without the repo PR-creation toggle; document the setting ([#7](https://github.com/MrEyratnz/software-factory/issues/7)) ([0dcbbbf](https://github.com/MrEyratnz/software-factory/commit/0dcbbbf7fcd7f5106756f0ba4cb6f4d706a3748d))

## Changelog

All notable changes to `dark-software-factory` are documented here. This project
adheres to [Semantic Versioning](https://semver.org) and
[Conventional Commits](https://www.conventionalcommits.org); releases are
automated by release-please.
