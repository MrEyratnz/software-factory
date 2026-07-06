---
name: module-boundaries
description: "Playbook for enforcing the modular-monolith architecture — kernel<modules<app layering, one-public-API-per-module, ports/adapters with a shared contract-test-suite-per-port, tenant-first repositories, publish gates, and a CI-enforced dependency-cruiser config. Use when adding/moving a module, wiring cross-module calls, defining a port or adapter, writing a multi-tenant repository, or reviewing boundary violations (reviewer axis-2)."
---

# Module boundaries (modular monolith)

The system is ONE deployable, internally partitioned so boundaries are structural, not
conventional. A violation must be **impossible to write**, not merely discouraged. Confirm
layering and port contracts with `roadmap_check` / `gate_evaluate` — do not eyeball.

## Invariants (non-negotiable)

1. **Layering is a DAG: `kernel < modules < app`.** Kernel depends on nothing internal.
   Modules depend only on kernel + their own port interfaces. App wires modules together.
   No upward, no sideways-by-reach imports. Ever.
2. **One public API per module.** Each module exposes exactly ONE entry file (`index`).
   Cross-module access goes through that surface only — never a deep import into another
   module's internals (`moduleA/src/internal/...` is forbidden from outside `moduleA`).
3. **Ports own the seams; adapters are swappable.** A module talks to the outside world
   (db, http, clock, email, LLM) through a port INTERFACE it defines. Concrete adapters
   live at the app edge and are injected. No module imports a vendor SDK directly.
4. **Every adapter passes the port's shared contract-test-suite.** One suite per port,
   run against every adapter (real + in-memory fake). An adapter that skips the suite does
   not ship.
5. **Multi-tenant repositories take `tenantId` FIRST on every call.** The unscoped query
   does not exist, so you cannot forget the filter. `find(tenantId, id)`, never `find(id)`.
6. **Accessibility / validation is a publish GATE, not a lint warning.** Contrast, schema,
   and required-field checks run as unit tests / `gate_evaluate`, and a failure blocks
   merge and release — it is never a suppressible warning.

## Procedure — adding or changing a module

1. **Place it.** Decide kernel vs module vs app. Shared pure types/utilities → kernel.
   Feature domain → module. Composition/wiring/adapters → app.
2. **Define the public API.** Create/extend the single `index` surface. Nothing outside the
   module may import anything else from it.
3. **Name the seams as ports.** For each external dependency, declare a port interface in
   the module. Write (or reuse) the port's contract-test-suite describing required behavior.
4. **Write adapters at the app edge.** Implement the real adapter + an in-memory fake. Run
   the SAME contract suite against both; both must be green before wiring.
5. **Repositories are tenant-first.** Signatures lead with `tenantId`. There is no method
   that queries across tenants without an explicit, reviewed, separately-named escape hatch.
6. **Gate a11y/validation as tests.** Express contrast/schema rules as unit tests wired into
   the publish gate, not lint config.
7. **Regenerate & enforce the dep graph** (below). Then run TDD ladder:
   `typecheck -> module-boundary -> unit -> BDD -> build -> generated-artifact drift`.
8. **Verify green, commit.** `guard-commit` blocks red; `guard-scope` blocks out-of-path
   edits. An unfixed boundary finding becomes a `tech-debt` issue, never silence.

## dependency-cruiser: generate for the detected stack, let CI enforce

Detect the stack (package.json/tsconfig, pyproject, go.mod...) and emit a config whose rules
encode the invariants above, then wire it into CI as an authoritative gate identical to the
local hook.

```
# .dependency-cruiser.js — rules mirror the layering DAG + one-public-API law
module.exports = {
  forbidden: [
    { name: 'no-upward-kernel',       severity: 'error',
      from: { path: '^src/kernel' },  to: { path: '^src/(modules|app)' } },
    { name: 'modules-no-app',         severity: 'error',
      from: { path: '^src/modules' }, to: { path: '^src/app' } },
    { name: 'no-cross-module-deep',   severity: 'error',
      from: { path: '^src/modules/([^/]+)' },
      to:   { path: '^src/modules/(?!\\1/)[^/]+/(?!index)' } },   // only sibling index
    { name: 'no-vendor-in-module',    severity: 'error', comment: 'use a port',
      from: { path: '^src/modules' }, to: { path: 'node_modules/(pg|axios|nodemailer|openai)' } },
    { name: 'no-orphans',             severity: 'warn',
      from: { orphan: true }, to: {} },
  ],
  options: { doNotFollow: { path: 'node_modules' }, tsConfig: { fileName: 'tsconfig.json' } },
};
```

CI step (same command the local `guard-scope`/module-boundary hook runs — one authority):

```
depcruise src --config .dependency-cruiser.js --output-type err   # nonzero => gate fails
```

For non-JS stacks emit the equivalent (import-linter contracts for Python `layers`/`forbidden`;
`go-arch-lint` / `depguard` for Go). The tool differs; the encoded rules are identical.

## Reviewer axis-2 — boundary check

The adversarial reviewer's second axis inspects structure and names each violation as a fatal
flaw before synthesis:

- [ ] No import crosses the DAG upward or sideways-by-reach (`depcruise` clean, not just green tests).
- [ ] Every cross-module reference resolves to the target's single `index`.
- [ ] Each new external dependency is a port; a real adapter AND a fake both pass the port's
      contract suite.
- [ ] Every repository method leads with `tenantId`; no unscoped query exists.
- [ ] a11y/validation checks are gate tests (block merge), not lint warnings.

Any unfixed axis-2 finding → GitHub issue labeled `tech-debt` with `file:line`, concrete
impact, provenance (pre-existing vs introduced), and a suggested fix.
