---
name: factory-config
description: "Author and validate .factory/config.json — the per-stack adapter (regexes + a command allowlist) that makes the plugin language-agnostic; use when onboarding a new repo/stack, when a hook reports a missing/invalid config field, or when adding a generator or wiring the green stages for node, python, or go."
---

# factory-config

`.factory/config.json` is the **single source of truth** the hooks read to become
language-agnostic. Every command a gate runs is looked up here by key — hooks never
eval an arbitrary string a model produced. Ports the plugin to a new stack by writing
regexes + a command allowlist, not by changing hook code.

## Invariants (non-negotiable)

1. **Commands come only from this validated config — never blind-eval.** Each hook
   resolves its command by *fixed key* (`green.typecheck`, `generators[i].command`,
   …) from the parsed, schema-validated config. A string that is not one of these
   declared values is never executed. The config is a **command allowlist**.
2. **The agent is fenced OUT of writing config.json.** `guard-scope` denies the
   autonomous loop write access to `.factory/config.json` (and all of `.factory/`
   except its designated state outputs). This is what stops a model from *poisoning
   the gate* — it cannot rewrite `green.unit` to `true` or point `build` at a no-op.
   Config changes are a human/privileged act, reviewed like any other PR.
3. **Malformed config fails closed; structure is validated at author time + CI.**
   A present-but-**unparseable** `.factory/config.json` blocks the denying
   workflow gates (`guard-commit`, `guard-release`) at runtime — a corrupt
   contract would otherwise silently revert this repo's gates to the built-in
   defaults, a fail-*open* for any repo that configured stricter-than-default
   gates. **Structural** validity (required keys present, `gates.*`/
   `generators[].command` are strings) is validated when `/factory-init`
   authors the config against `factory.config.schema.json`, and re-checked by
   CI — the authoritative boundary — not on every hook. So: fix a broken config
   (do not `--no-verify`); a key you *omit* degrades to its documented default,
   and CI is where a structurally-invalid-but-parseable config is caught.
4. **Local == CI.** CI reads the identical `config.json`; the same commands run in
   both places. Tuning a command to pass locally-only just moves the red to CI.

## Schema — fields the hooks read

```jsonc
{
  "stack":             "node", // node|python|go|custom — selects the adapter defaults
  "sourceRegex":       "…",   // guard-commit/guard-scope: which paths are product source
  "testRegex":         "…",   // guard-commit: a feat/fix touching source MUST also touch a test
  "testCommandRegex":  "…",   // recognizes a test-run invocation (for commit_lint heuristics)
  "roadmapPath":       "…",   // guard-roadmap: file holding the M0..Mn milestone checkboxes
  "releaseBranch":     "main",// guard-release: releases are legal only from this branch
  "releaseVerbRegex":  "…",   // guard-release: matches publish/tag/release verbs to gate
  "designDir":         "…",   // check-drift/DesignSync: single-source design-token dir
  "maxIterations":     25,    // loop-guard: hard cap on the lights-out loop (bounded autonomy)
  "generators": [             // drift gate: regenerate + compare against checked-in output
    { "sourceRegex": "…", "command": "…", "output": "…" }
  ],
  "gates": {                  // gate_evaluate/record-green run these IN THIS ORDER, short-circuit on red
    "typecheck":  "…",        // 1
    "boundaries": "…",        // 2  module-boundary (kernel<modules<app, ports/adapters)
    "unit":       "…",        // 3
    "bdd":        "…",        // 4
    "build":      "…"         // 5  (artifact-drift = the generators[] above = stage 6)
  }
}
```

Every value in `gates.*` and `generators[].command` is an entry in the allowlist:
the ONLY strings the gate is permitted to shell out to.

## Per-stack adapters

### node
```json
{
  "sourceRegex": "^src/.*\\.[jt]sx?$",
  "testRegex": "\\.(test|spec)\\.[jt]sx?$",
  "testCommandRegex": "vitest|jest",
  "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main",
  "releaseVerbRegex": "npm publish|release-please|gh release create|git tag v",
  "designDir": "design/tokens",
  "maxIterations": 25,
  "generators": [
    { "sourceRegex": "^design/tokens/.*\\.json$", "command": "pnpm tokens:build", "output": "src/styles/tokens.css" }
  ],
  "gates": {
    "typecheck": "pnpm tsc --noEmit",
    "boundaries": "pnpm depcruise src",
    "unit": "pnpm vitest run",
    "bdd": "pnpm cucumber-js",
    "build": "pnpm build"
  }
}
```

### node — workspaces / monorepo

`^src/` matches ONLY a top-level `src/`. In an npm-workspaces or monorepo
layout, source also lives under `packages/*/src/**` and `apps/*/src/**` — a
`feat`/`fix` touching only those roots is invisible to a single-root
`sourceRegex`, so `guard-commit` never requires a co-staged test and the
tests-first gate silently under-fires. Cover every real root (only the keys
that change from the `node` adapter above are shown — keep the rest):

```json
{
  "sourceRegex": "^(src|packages/[^/]+/src|apps/[^/]+/src)/.*\\.[jt]sx?$",
  "testRegex": "\\.(test|spec)\\.[jt]sx?$",
  "gates": {
    "typecheck": "pnpm -r tsc --noEmit",
    "boundaries": "pnpm depcruise src packages apps",
    "unit": "pnpm -r vitest run",
    "build": "pnpm -r build"
  }
}
```

(The `python` adapter's `^src/.*\\.py$` has the same single-root assumption —
apply the same treatment for `src/` layouts with multiple package roots.)

### python
```json
{
  "sourceRegex": "^src/.*\\.py$",
  "testRegex": "(^tests/|_test\\.py$|^test_.*\\.py$)",
  "testCommandRegex": "pytest",
  "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main",
  "releaseVerbRegex": "twine upload|python -m build|gh release create|git tag v",
  "designDir": "design/tokens",
  "maxIterations": 25,
  "generators": [
    { "sourceRegex": "^design/tokens/.*\\.yaml$", "command": "python -m tools.tokens", "output": "src/app/static/tokens.css" }
  ],
  "gates": {
    "typecheck": "mypy src",
    "boundaries": "import-linter --config .importlinter",
    "unit": "pytest -q tests/unit",
    "bdd": "behave",
    "build": "python -m build"
  }
}
```

### go
```json
{
  "sourceRegex": "\\.go$",
  "testRegex": "_test\\.go$",
  "testCommandRegex": "go test",
  "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main",
  "releaseVerbRegex": "goreleaser|gh release create|git tag v",
  "designDir": "design/tokens",
  "maxIterations": 25,
  "generators": [
    { "sourceRegex": "^design/tokens/.*\\.json$", "command": "go run ./tools/tokens", "output": "web/static/tokens.css" }
  ],
  "gates": {
    "typecheck": "go vet ./...",
    "boundaries": "go-arch-lint check",
    "unit": "go test ./...",
    "bdd": "godog",
    "build": "go build ./..."
  }
}
```

## Procedure — onboard / change a stack

1. **Draft the config** from the adapter above; keep the five `green` keys and the
   ordered semantics identical across stacks — only the commands change.
2. **Pin the regexes to reality.** Confirm `sourceRegex`/`testRegex` actually match
   the repo's tree (a wrong `testRegex` lets a `feat` land with no test — invariant
   broken silently). Confirm `roadmapPath` is the file with the `[ ]`/`[x]` boxes.
   Two proven under-fire pitfalls to check explicitly against `git ls-files`:
   an extension anchor that misses `.tsx`/`.jsx` (React is squarely "node" —
   `src/Foo.tsx` must count as source and `Foo.test.tsx` as a test), and a
   single-root `^src/` in a workspaces/monorepo layout (source under
   `packages/*/src` or `apps/*/src` silently escapes the tests-first gate).
3. **Prove each command by hand once**, then let the connector own it — run
   `gate_evaluate`; it executes `gates.*` in order and returns a per-stage verdict.
   Fix at the earliest red stage.
4. **Register generators** so the drift stage regenerates `output` from
   `sourceRegex` inputs and diffs against the checked-in file (contract: generated
   artifact is committed; CI re-runs and fails on drift).
5. **Land it as a privileged PR.** Because `guard-scope` fences the agent out of
   `.factory/`, config edits go through human review — this is intentional.

## Anti-patterns (blocked or will bite you)

- Putting a raw shell command in a hook/prompt instead of a `gates.*` key — the hook
  will not run it; only allowlisted config values execute.
- Letting the autonomous loop edit `config.json` to weaken a gate — `guard-scope`
  denies the write; a green from a poisoned config is void.
- `green.unit: "true"` / pointing `build` at a no-op to force green — CI runs the
  same config and the lie surfaces there.
- `testRegex` that matches nothing → `feat`s ship untested; `sourceRegex` too broad →
  guard-scope false-blocks edits. Validate against `git ls-files`.
- A `sourceRegex`/`testRegex` that misses `.tsx`/`.jsx` or non-`src` workspace
  roots (`packages/*/src`, `apps/*/src`) → a `feat`/`fix` ships untested: the
  source isn't seen as source, and its test isn't seen as a test.
- Omitting a generator whose output is checked in → stage-6 drift red on every CI run.
