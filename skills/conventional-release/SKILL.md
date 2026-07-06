---
name: conventional-release
description: "Cut a semver release from Conventional Commits — lint messages with commit_lint, compute the next version and changelog with release_plan, author release-please config, and obey the two hard laws (never release from red; smoke-test the actual built artifact) before publishing."
---

# conventional-release

Turn a stream of Conventional Commits into a correct, safe semver release. Every
message is graded by the connector, the version is computed deterministically,
and the release is blocked unless the tree is green AND the packaged artifact
boots. Do not eyeball versions or trust source-tree tests as proof.

## Invariants (non-negotiable)

1. **Never release from red.** `guard-release` blocks every release verb —
   `npm publish`, `git tag vX`, `gh release create`, `release-please` promotion,
   and the equivalent github-MCP calls — unless `.factory/state/gate-receipt.json`
   holds a fresh green receipt bound to the current tree SHA. No green proof, no
   release. This applies across **both** Bash and github-MCP paths.
2. **Smoke-test the ACTUAL built/packaged artifact.** The `--omit=dev` /
   `npm pack` / bundled closure differs from the source tree (missing deps,
   wrong entry, stripped files). Build it, unpack it in a clean dir, boot it,
   and assert it works — source-tree green is necessary but not sufficient.
3. **Version is computed, never chosen.** The bump comes from `release_plan`
   over the commit range, not from human judgment.

## Conventional Commits grammar

```
<type>(<optional scope>)<optional !>: <subject>

<optional body>

<optional footer(s)>   # e.g. BREAKING CHANGE: <desc>, Refs: #123
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`. Subject is imperative, lower-case, no trailing period.

### Type → semver bump

| Signal in commit | Bump | Notes |
|---|---|---|
| `feat` | **minor** | new user-visible capability |
| `fix` | **patch** | bug fix |
| `perf` | patch | (project may map to minor; see config) |
| `!` after type/scope | **major** | breaking, e.g. `feat(api)!: drop v1` |
| `BREAKING CHANGE:` footer | **major** | overrides everything above |
| `docs`/`style`/`refactor`/`test`/`build`/`ci`/`chore` | none | no release on their own |

The highest bump across the range wins. A single `!` or `BREAKING CHANGE`
forces major even amid many `fix`es.

## Procedure

1. **Lint each message** — run connector `commit_lint` on every commit message
   in the release range. Reject non-conforming subjects, wrong types, or a
   breaking change hidden in the body without a `!`/`BREAKING CHANGE` footer.
   Do not proceed while `commit_lint` is red; fix the history first.
2. **Compute the plan** — run connector `release_plan` over the range. It
   returns the next version, the categorized changelog (Features / Bug Fixes /
   BREAKING CHANGES), and the tag name. Treat its version as authoritative.
3. **Confirm green** — run connector `gate_evaluate`; require a green
   `gate-receipt.json` bound to the current tree SHA. If red, stop — releasing
   is impossible by law until the gate is green.
4. **Build + package** — produce the real artifact (`npm pack`, prod build, or
   the project's package step with `--omit=dev`).
5. **Smoke-test the artifact** — unpack into a clean temp dir, install prod-only
   deps, boot the packaged entrypoint, and assert a real success signal (starts,
   `--version` matches, a core command returns). Failure here aborts the release.
6. **Promote** — let release-please open/merge the release PR; on merge it tags
   and creates the GitHub release from the computed changelog. `guard-release`
   re-checks the green receipt at tag/publish time.
7. **Record** — the release, tag, and artifact digest land in
   `.factory/ledger.jsonl` via `ledger-record`; verify with `ledger_read`.

## release-please config (single package)

`release-please-config.json`:

```json
{
  "packages": {
    ".": {
      "release-type": "node",
      "changelog-sections": [
        { "type": "feat", "section": "Features" },
        { "type": "fix",  "section": "Bug Fixes" },
        { "type": "perf", "section": "Performance" }
      ],
      "bump-minor-pre-major": true
    }
  },
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
}
```

Use `"release-type": "node"` for an npm package (bumps `package.json` +
`package-lock.json`); use `"generic"` with `extra-files` version markers for a
non-node artifact. `.release-please-manifest.json` pins the current version:
`{ ".": "1.4.2" }`. Keep both files checked in; CI runs release-please as the
authority.

## Do-not

- Do **not** hand-edit `CHANGELOG.md` or the version — let `release_plan` /
  release-please generate them from commits.
- Do **not** tag or publish while any gate is red, even "just docs" — the law
  is unconditional.
- Do **not** accept source-tree `npm test` as the smoke test — boot the
  packaged closure.
- Do **not** squash a breaking change into a `fix:`/`chore:` subject to dodge a
  major bump; encode it with `!` / `BREAKING CHANGE:`.
