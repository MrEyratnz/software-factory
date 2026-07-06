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
3. **Validated before use.** Malformed JSON, a missing required key, or a command
   that is not a string fails the hook **closed** (blocks), never open. Fix the
   config; do not `--no-verify`.
4. **Local == CI.** CI reads the identical `config.json`; the same commands run in
   both places. Tuning a command to pass locally-only just moves the red to CI.

## Schema — fields the hooks read

```jsonc
{
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
  "green": {                  // gate_evaluate/record-green run these IN THIS ORDER, short-circuit on red
    "typecheck":  "…",        // 1
    "boundaries": "…",        // 2  module-boundary (kernel<modules<app, ports/adapters)
    "unit":       "…",        // 3
    "bdd":        "…",        // 4
    "build":      "…"         // 5  (artifact-drift = the generators[] above = stage 6)
  }
}
```

Every value in `green.*` and `generators[].command` is an entry in the allowlist:
the ONLY strings the gate is permitted to shell out to.

## Per-stack adapters

### node
```json
{
  "sourceRegex": "^src/.*\\.ts$",
  "testRegex": "\\.(test|spec)\\.ts$",
  "testCommandRegex": "vitest|jest",
  "roadmapPath": "docs/ROADMAP.md",
  "releaseBranch": "main",
  "releaseVerbRegex": "npm publish|release-please|gh release create|git tag v",
  "designDir": "design/tokens",
  "maxIterations": 25,
  "generators": [
    { "sourceRegex": "^design/tokens/.*\\.json$", "command": "pnpm tokens:build", "output": "src/styles/tokens.css" }
  ],
  "green": {
    "typecheck": "pnpm tsc --noEmit",
    "boundaries": "pnpm depcruise src",
    "unit": "pnpm vitest run",
    "bdd": "pnpm cucumber-js",
    "build": "pnpm build"
  }
}
```

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
  "green": {
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
  "green": {
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
3. **Prove each command by hand once**, then let the connector own it — run
   `gate_evaluate`; it executes `green.*` in order and returns a per-stage verdict.
   Fix at the earliest red stage.
4. **Register generators** so the drift stage regenerates `output` from
   `sourceRegex` inputs and diffs against the checked-in file (contract: generated
   artifact is committed; CI re-runs and fails on drift).
5. **Land it as a privileged PR.** Because `guard-scope` fences the agent out of
   `.factory/`, config edits go through human review — this is intentional.

## Anti-patterns (blocked or will bite you)

- Putting a raw shell command in a hook/prompt instead of a `green.*` key — the hook
  will not run it; only allowlisted config values execute.
- Letting the autonomous loop edit `config.json` to weaken a gate — `guard-scope`
  denies the write; a green from a poisoned config is void.
- `green.unit: "true"` / pointing `build` at a no-op to force green — CI runs the
  same config and the lie surfaces there.
- `testRegex` that matches nothing → `feat`s ship untested; `sourceRegex` too broad →
  guard-scope false-blocks edits. Validate against `git ls-files`.
- Omitting a generator whose output is checked in → stage-6 drift red on every CI run.
