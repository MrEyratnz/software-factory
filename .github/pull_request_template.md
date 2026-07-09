<!--
This repo dogfoods the factory's own laws (see CONTRIBUTING.md). Keep the PR
title a Conventional Commit (feat: / fix: / chore: / docs: …) — release-please
reads it.
-->

## What & why

<!-- What does this change, and why? Link any issue it closes. -->

Closes #

## The laws

- [ ] Green at every commit — `cd connector && node --test` and
      `bash tests/hooks.contract.test.sh` pass locally.
- [ ] New hook behavior ships with a case in `tests/hooks.contract.test.sh`;
      new connector logic lives in `factory-core.mjs` as tested pure functions.
- [ ] The connector stays pure and read-only (no repo mutation in the MCP
      server); hooks stay POSIX + node-stdlib only (no runtime deps).
- [ ] PR title is a Conventional Commit.

## Review findings → tech-debt

- [ ] Any review finding **not fixed in this PR** is filed as a `tech-debt`
      issue (location, impact, provenance, suggested fix), not dropped.
