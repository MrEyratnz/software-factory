---
name: working-within-dsf
description: "Operate correctly under the Dark Software Factory hooks without reverse-engineering their source — what each role may write and why a guard-scope denial fires, the commit contract (Conventional Commits + tests-first + a tree-bound green receipt), the green-receipt and release lifecycles, the enforcement levers (per-gate config toggles + a session pause), and how to orient with /factory-status. Use whenever a DSF hook blocks you, before a commit or release, or when a green receipt goes missing or stale."
---

# Working within the Dark Software Factory (DSF)

DSF enforces its laws with **PreToolUse / PostToolUse / Stop hooks** locally and **re-runs the
identical checks in CI** as the authoritative boundary. The local hooks are fast, fail-early UX;
several are explicitly best-effort. This doc is the operating model, so you can anticipate a denial
instead of decoding `hooks/scripts/*.sh` every session.

**A denial looks like** an exit-2 block with a line on stderr prefixed
`dark-software-factory:` — followed by a class tag:

- **`[hard-boundary]`** — a real boundary (a `--no-verify` bypass, a trust-root write, a write
  outside the project tree, an invalid proof signature). Do not route around it.
- **`[heuristic]`** — a best-effort match on command *text* (commit/release detection, lint,
  tests-first) that can misfire. Satisfying the requirement **or** rephrasing so the heuristic no
  longer matches is expected and legitimate — not evasion. CI re-runs the authoritative gate.

That prefix is a DSF gate, not a Claude Code safety block.

## Orient first

- **Run `/factory-status`** before doing anything — a read-only dashboard (roadmap cursor + %,
  next unchecked item, local gate state, open `tech-debt` count, recent ledger, last release). No
  agent is dispatched.
- The **SessionStart** hook (`bootstrap`) creates `.factory/{state,review,panel}` and injects the
  status once; if there is no `.factory/config.json` it appends *"run /factory-init"*.
- The **UserPromptSubmit** hook (`inject-status`) shows the status banner —
  `Dark Software Factory — roadmap X% done; next: … | local gate: green|stale/red|unknown | open tech-debt: N`.
  It is **throttled**: silent in an uninitialized repo, silent while paused, and re-injected only
  when the line actually changes — so it does not repeat every turn.

## Roles and write scope (why guard-scope / guard-bash-writes deny you)

The **active role** is the string in `.factory/active-agent`; `/next`, `/review`, `/ship`,
`/design` set it. Empty/absent = the **conductor**, scoped like the implementer. `guard-scope`
gates `Write`/`Edit`/`MultiEdit`; `guard-bash-writes` closes the Bash write path (redirects, `tee`,
`cp`/`mv`/`dd`/`install`/`ln`/`truncate`/`rm`/`patch`, `sed -i`, and the git mutators).

| Role | May write | Rationale |
|---|---|---|
| **implementer** / conductor | `src/`, tests, docs — anything except the universal fences | the only role that writes source and commits |
| **reviewer** | **nothing** — no editor writes, and no tree-mutating Bash at all | "read-only by construction"; findings go to its return artifact under `.factory/review/<ref>.json` |
| **architect** | `docs/**` only | owns the docs spine + ADRs; never source, never commits |
| **design-lead** | the design dir (`designDir`) and `docs/**` | owns design-system tokens/CSS/contrast tests |
| **proposer** | `.factory/panel/**` only | writes one partisan proposal file |
| **panelist** | `.factory/panel/**` only | writes one ballot file |
| **release-captain** | `docs/**` and `.factory/state/release-intent.json` only | cuts releases via the gated path; never edits source |
| **tech-debt-clerk** | `.factory/review/**` only | files GitHub issues; touches no source |

**Universal fences (every role, including the conductor):**
- Editor **and** Bash writes to `.factory/state/**`, `.factory/review/**`, `.factory/config.json`
  are denied — hook-managed trust roots (receipt, proofs, and the command allowlist cannot be
  hand-forged). The one sanctioned carve-out: the **release-captain** writes
  `.factory/state/release-intent.json` (only that file, only that role).
- Writes **outside the project directory** (`../…` or an absolute path escaping the tree) are
  denied on **both** surfaces — editor tools and Bash redirect/`tee` targets. Carved out:
  `~/.claude/**` (incl. the memory feature), temp dirs, and `/dev`.

**How to accomplish X when fenced:** if you are a doc/review role and need code changed, describe
the change for the implementer — don't route around the fence. Config changes go through
`/factory-init` or a human.

## The commit contract (`guard-commit`, on `git commit` via Bash)

A `git commit` is **denied** unless all hold (each hard gate is on by default; see Enforcement
levers to relax one deliberately):

1. **No bypass flags** — `--no-verify` / `--no-gpg-sign` refused outright (`[hard-boundary]`).
2. **Conventional Commit** — a visible `-m` message must lint (`feat`/`fix`/`chore`/…). Toggle:
   `enforcement.conventionalCommitLint`.
3. **Tests-first for `feat`/`fix`** — if the change stages source (`sourceRegex`, default `^src/`)
   it must also stage a test (`testRegex`). `commit -a/-am` is handled via `git diff HEAD`. Toggle:
   `enforcement.requireTestsFirst`.
4. **Green receipt bound to the current tree** — a receipt for the target repo must exist, be
   `ok:true`, and its `tree` must equal the current `git write-tree` hash. Fail-closed if the hash
   can't be computed. Toggle: `enforcement.requireGreenReceiptOnCommit`.

So: **run the full suite to green on the exact tree, then commit** a conventional message with a
test staged for any `feat`/`fix`. Commit detection is best-effort (`parse-git-commit.mjs`:
fail-conservative on aliases/indirection; a `git` inside a path/filename like `parse-git-commit.mjs`
is *not* treated as a command). CI re-runs the identical gate.

The gate binds to the **repo the command actually targets** — a leading `cd <dir> &&` or
`git -C <dir>` — so a commit to a sibling repo in a multi-repo session is checked against *that*
repo, with its own receipt keyed under the session's `.factory/state`.

Related gates: **`guard-mcp-commit`** denies the github-MCP content-write tools
(`create_or_update_file`/`push_files`/`delete_file`) outside a release — commit through local
`git commit`. **`ledger-record`** appends `{station, sha, subject}` to `.factory/ledger.jsonl`
after a successful commit. **`guard-roadmap`** denies flipping a roadmap `- [ ]` to `- [x]` without
a merged-green proof — never check a box yourself; it flips on merge.

## Green-receipt lifecycle

- **Minted by `record-green`** (PostToolUse on Bash): when a command matches `testCommandRegex`
  and **exits 0**, it writes the receipt bound to `tree_hash` (a `git write-tree` over tracked +
  untracked files, **excluding `.factory/`**, via a throwaway index). Forgery guards reject
  `echo`/`printf`/`:`/`true` prefixes, `|| true` / `; true` / `&& true`, and any `#` comment.
  When the tool response carries **no exit code**, record-green invokes the repo's allowlisted
  `testCommand` (from config only) and takes its real exit code — it never re-executes the
  arbitrary already-run command. With no `testCommand` configured it fails safe (no receipt).
- **Invalidated automatically:** bound to the write-tree hash (not a timestamp), so **any later
  edit to source invalidates it** — no separate invalidation hook. Editing `.factory/` does not.
- **"Stale"** = the receipt's `tree` no longer equals the current tree hash, or `ok:false`. Fix:
  **re-run the full suite**. Don't hand-edit the receipt — it is a trust root, blocked on both
  surfaces, and (if a signing key is set) signature-checked.
- **Optional signing (hardening):** if the runner sets `FACTORY_RECEIPT_KEY` (or
  `FACTORY_RECEIPT_KEYFILE`), receipts/proofs are HMAC-signed and an unsigned/mis-signed one is
  rejected — a hand-written receipt can't certify green. Off by default; when unset, no signature
  is required.

## Release regime (`guard-release`)

`guard-release` gates release verbs on **both** substrates: **Bash** matching `releaseVerbRegex`,
and the **github-MCP** merge/push/create/delete tools **while `.factory/state/release-intent.json`
exists** ("release in progress"). It denies unless: on the configured `releaseBranch`; a
`release-proof.json` with `ok:true` (green on the **built artifact**); **and** a fresh green
receipt bound to the current tree.

`/ship` drives the lifecycle:
1. The release-captain writes `release-intent.json` (its one sanctioned trust-root write). While it
   exists, `guard-mcp-commit` steps aside and `guard-release` owns the MCP write paths; absent it,
   `guard-mcp-commit` denies them.
2. The build+smoke command (matching `releaseProofCommandRegex`) exiting 0 on the release branch
   makes **`record-release-proof`** mint `release-proof.json` — the proof is never hand-written.
3. At turn/session end, **`release-cleanup`** (Stop) clears `release-intent.json` and
   `release-proof.json`, so a finished or aborted release never leaves the session stuck in the
   release regime.

Use `/ship`; don't assemble release verbs by hand.

## Enforcement levers (relaxing gates deliberately)

Between "fully gated" and the all-or-nothing plugin toggle:

- **Per-gate config** — an `enforcement` block in `.factory/config.json` (committed, reviewable);
  each key defaults `true`: `requireGreenReceiptOnCommit`, `requireTestsFirst`,
  `conventionalCommitLint`, `requireReleaseProof`, `enforceProjectDirScope`, `protectTrustRoots`.
  Set one `false` to opt a single repo out of that gate.
- **Session pause** — a human (or CI) drops `.factory/state/paused` (`touch`) to make **every**
  hard gate step aside for that worktree, independent of settings hot-reload. The agent cannot
  forge it (trust root). Remove the file to resume.

## Session-end and loop gates

- **`validate-handoff`** (SubagentStop for reviewer/proposer/panelist): blocks stop unless a
  schema-valid artifact exists under `.factory/review` or `.factory/panel`. Emit it before ending.
- **`debt-reconcile`** (Stop): a session **cannot end** while a review finding is neither
  `status:"fixed"` in `.factory/review` nor filed as an open `tech-debt` issue (matched by content
  fingerprint). Run `/debt sync` or mark it fixed.
- **`loop-guard`** (Stop): during an active `/factory-run`, re-blocks stop to advance
  station-to-station, hard-capped by `maxIterations`; deactivates when the roadmap is complete.
- **`check-drift`** (advisory, PostToolUse): editing a generator source reminds you to regenerate +
  stage the output (CI enforces `git diff --exit-code`); it never runs the command.

## Residual limits (by design — CI is authoritative)

Local gates are best-effort. Static command-text parsing can still be defeated by deliberate shell
obfuscation (quote-splitting the `git` token, base64, etc.), and the proofs live in the repo the
agent can write — the optional signing key only closes hand-forgery to the extent the secret is
kept private from the agent's shell. None of this is a security boundary: **CI re-runs every gate
and is the authoritative boundary**. A `[heuristic]` local deny is fail-early UX; treat it as such.
