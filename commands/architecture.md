---
description: Draft docs/ARCHITECTURE.md as a modular monolith and emit the matching dependency-cruiser boundary config that CI enforces.
argument-hint: "[--constraints \"...\"]"
---

Draft or refresh `docs/ARCHITECTURE.md`. Extra constraints: `$ARGUMENTS`

Dispatch the **architect** (load `module-boundaries` + `docs-spine`). Describe
the modular monolith: `kernel < modules < app`; one public API per module;
cross-module access only through that API; ports/adapters with a shared
contract-test-suite per port; and the structural safety invariants for this
domain (e.g. tenant-id-first repositories so the unscoped query does not exist;
validation/accessibility as a publish GATE, not a warning). Emit or update the
`.dependency-cruiser.cjs` (or stack equivalent) that encodes these boundaries so
`check:boundaries` enforces them in CI. Keep ARCHITECTURE.md truthful to the
code as it grows.
