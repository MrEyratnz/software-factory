---
description: Run a design-system session or verify its gates — single-source tokens → generated CSS checked in → drift gate → contrast-gate implemented as a unit test.
argument-hint: "[--check | --session \"scope\"]"
---

Design-system work: `$ARGUMENTS`

- **--check**: the local mirror of the CI gates — regenerate the CSS/tokens
  artifact from its single source and `git diff --exit-code` it (drift gate), and
  run the contrast unit test (every declared fg/bg pairing meets its WCAG AA
  threshold). Report pass/fail; change nothing.
- **--session "scope"**: set the write-fence (`echo design-lead > .factory/active-agent`) and dispatch the
  **design-lead** (load `design-system-rigor`,
  fenced to the design dirs) to evolve the design system — keeping ONE token
  source of truth, a checked-in generated artifact with a byte-equality test, and
  the contrast-gate-as-unit-test with its declare-a-color-forces-you-to-gate-it
  safety net. For a contested design-contract decision, run `/judge-panel`.

The `check-drift` hook already regenerates and diffs the moment a token source is
edited, so drift is caught at edit time, not only in CI.
