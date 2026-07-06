---
name: tdd-green-gate
description: "Enforce the red-green-refactor law and the exact ordered definition of green (typecheck, module-boundary, unit, BDD, build, artifact-drift) at every commit; use before writing code, before any feat/fix commit, and whenever a commit is blocked as red or for a missing test."
---

# TDD Green Gate

The one law: **never commit red, and never write implementation before a failing test.**
"Green" is not a feeling — it is a fixed, ordered pipeline that must pass in full at
**every** commit. `record-green` mints a receipt bound to the exact working tree; `guard-commit`
refuses any commit whose tree does not match a green receipt.

## Invariants (non-negotiable)

1. **Tests first.** The failing test is written and committed-intent *before* the code that
   makes it pass. A `feat`/`fix` that stages source files with **no** accompanying test is
   blocked by `guard-commit` + `commit_lint`.
2. **Green is ordered.** The stages run in this order and short-circuit on first failure:
   `typecheck -> module-boundary -> unit -> BDD -> build -> generated-artifact drift`.
   A later stage never runs, and never masks, an earlier failure.
3. **Green is tree-bound.** A receipt is valid only for the precise `git write-tree` hash it
   was minted from. Any edit — even whitespace — changes the tree and **invalidates** the
   receipt. Re-run the gate.
4. **Local == CI.** Hooks fail you early; CI re-runs the *identical* gates as the authority.
   Do not tune tests to pass locally-only.
5. **Refactor is green-to-green.** Refactor only from a green receipt to a new green receipt;
   behavior-preserving changes keep every stage passing.

## The stages (what each proves)

| # | Stage | Proves | Fail means |
|---|-------|--------|-----------|
| 1 | typecheck | types sound, no `any`-holes | fix types before anything else |
| 2 | module-boundary | kernel<modules<app, ports/adapters honored (dependency-cruiser) | illegal import; move code or add a port |
| 3 | unit | logic correct in isolation | the failing test you wrote, or a regression |
| 4 | BDD | behavior/contract-per-port holds end-to-behavior | scenario broke; fix impl, not the scenario |
| 5 | build | app + modules compile/bundle | build-only breakage (config, exports) |
| 6 | artifact-drift | generated artifacts (e.g. tokens->CSS) match checked-in | regenerate and commit the generated file |

## Procedure

1. **Resolve the repo's real commands.** Read `.factory/config.json` — it declares the package
   manager and the exact script per stage (do **not** guess `npm`/`pnpm` or script names).
   ```
   .factory/config.json
     { "stack": "node",
       "gates": {
         "typecheck": "...", "boundaries": "...", "unit": "...",
         "bdd": "...", "build": "..." },
       "generators": [ { "sourceRegex": "...", "command": "...", "output": "..." } ] }
   ```
   (Artifact-drift — stage 6 — is the `generators[]` entries, diffed after
   regeneration; see the `factory-config` skill for the full schema.)
2. **Red first.** Write the smallest failing test that pins the new behavior/bug. Run stage 3/4
   and *watch it fail for the right reason*. A test that passes before you write code proves
   nothing — strengthen it.
3. **Green.** Implement the minimum to pass. Run the full ordered gate via the connector:
   `gate_evaluate` runs stages 1->6 and returns a deterministic per-stage verdict. Fix at the
   earliest red stage and re-run; never skip ahead.
4. **Mint the receipt.** With every stage green, `record-green` writes
   `.factory/state/gate-receipt.json` bound to the current `git write-tree`. This survives
   compaction/resume — the proof lives on disk, not in conversation.
5. **Lint the commit.** `commit_lint` checks Conventional Commit type and that a `feat`/`fix`
   carries a test. Fix message/scope before committing.
6. **Commit.** `guard-commit` recomputes the tree hash and compares it to the receipt. Match ->
   allowed. Mismatch (you edited after minting) -> **re-run the gate and re-mint**; do not
   `--no-verify`.

## Connector cheat-sheet

- `gate_evaluate` — run the full ordered pipeline; authoritative green/red per stage. Use this
  instead of eyeballing individual script output.
- `commit_lint` — Conventional Commit + tests-present verdict for the staged change.
- Receipt: `.factory/state/gate-receipt.json` (tree-bound). Never hand-edit it.

## Anti-patterns (will be blocked or bite you)

- Staging `src/` in a `feat` with no test -> blocked (invariant 1).
- Running `unit` before `typecheck` "to save time" -> forbidden ordering; earlier red hides.
- `git commit --no-verify` / editing the receipt JSON -> defeats the tree binding; CI re-runs
  the gate and fails the PR anyway.
- Committing a regenerated build but not the generated artifact -> stage 6 drift red.
- "It passes on my machine": if `.factory/config.json` scripts pass but CI differs, the config
  is wrong — fix the config, not the gate.
