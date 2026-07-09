---
description: Gated release — assert full-suite green + Conventional-Commit clean + no open release-blocker, build and smoke-test the ACTUAL artifact, then cut the tag/Release.
argument-hint: "[--dry-run]"
---

Cut a release, gated: `$ARGUMENTS`

1. Signal a release is in progress: `echo release-captain > .factory/active-agent`
   and write `.factory/state/release-intent.json` (so `guard-release` also gates
   the github-MCP push/merge paths, not just Bash). The **release-captain** is
   the sanctioned writer of `release-intent.json` — guard-scope/guard-bash-writes
   permit that one file for that one role, and no other trust-root path.
2. Dispatch the **release-captain** (load `conventional-release`) to:
   compute the next version + changelog (connector `release_plan`); confirm the
   suite is green; confirm no open `release-blocker` issue; **build the actual
   production artifact and smoke-test the built thing** (boot it, assert it
   serves/validates — the packaged closure differs from source). When that
   build+smoke command (matching `releaseProofCommandRegex`) exits 0 on the
   release branch, the `record-release-proof` hook mints
   `.factory/state/release-proof.json` — the proof is never hand-written. Then
   drive release-please and cut the `vX.Y.Z` tag + GitHub Release.

Every mutating step is adjudicated by `guard-release` — it needs a green
release-gate proof (minted by the build+smoke above) plus a fresh tree-bound
green receipt, on the configured release branch. Never releases from red.

**Lifecycle.** `release-intent.json` and `release-proof.json` are cleared at
session/turn end by the `release-cleanup` Stop hook, so a completed or aborted
release never leaves the session stuck in the release regime. A later `/ship`
re-establishes them via the producers above.

`--dry-run`: produce the plan and the version/changelog, cut nothing.
