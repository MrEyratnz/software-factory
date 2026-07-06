---
description: Gated release — assert full-suite green + Conventional-Commit clean + no open release-blocker, build and smoke-test the ACTUAL artifact, then cut the tag/Release.
argument-hint: "[--dry-run]"
---

Cut a release, gated: `$ARGUMENTS`

1. Signal a release is in progress: `echo release-captain > .factory/active-agent`
   and write `.factory/state/release-intent.json` (so `guard-release` also gates
   the github-MCP push/merge paths, not just Bash).
2. Dispatch the **release-captain** (load `conventional-release`) to:
   compute the next version + changelog (connector `release_plan`); confirm the
   suite is green; confirm no open `release-blocker` issue; **build the actual
   production artifact and smoke-test the built thing** (boot it, assert it
   serves/validates — the packaged closure differs from source); then drive
   release-please and cut the `vX.Y.Z` tag + GitHub Release.

Every mutating step is adjudicated by `guard-release` — it needs a green
release-gate proof, on the configured release branch. Never releases from red.
`--dry-run`: produce the plan and the version/changelog, cut nothing.
