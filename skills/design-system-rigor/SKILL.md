---
name: design-system-rigor
description: "Enforce design-system integrity as an invariant chain — single-source tokens, a checked-in generated CSS artifact, a CI drift gate, and a WCAG-AA contrast gate implemented as a unit test where declaring a color forces declaring its contrast pairing. Use when adding/changing design tokens, colors, themes, or CSS, or wiring the token pipeline."
---

# Design-System Rigor

A design system is only trustworthy if it cannot silently drift and cannot ship
inaccessible color. Encode both as machine-checked invariants, not review habits.
The product's own accessibility bar (WCAG AA) is applied *to the design system itself*.

## Invariants (never violated)

1. **Single source of truth.** Tokens live in ONE machine-readable file
   (e.g. `tokens/tokens.json`). Nothing downstream hand-edits color/spacing/type.
2. **Generated artifact is checked in.** The CSS/JS the app consumes is emitted by
   a generator from tokens and **committed** — never hand-authored, never gitignored.
3. **Drift is a build break.** Regenerating must produce byte-identical output to
   what is committed. CI proves it; the `check-drift` hook mirrors it locally.
4. **Contrast is a unit test.** Every foreground/background token pairing meets
   WCAG AA (≥ 4.5:1 body text, ≥ 3:1 large text / UI). A failing ratio fails the suite.
5. **Declaring a color forces declaring its pairing.** A new color token cannot land
   without an entry in the contrast manifest — so it is automatically gated, never orphaned.

## Pipeline (token source → generator → drift-check → contrast-test)

```
tokens/tokens.json          # 1. SOURCE OF TRUTH (colors, pairings, scales)
        │  npm run tokens:build      (generator; pure, deterministic)
        ▼
src/generated/tokens.css    # 2. CHECKED-IN ARTIFACT (do not edit by hand)
        │
        ├─ CI drift gate:   npm run tokens:build && git diff --exit-code src/generated/
        │                   (identical local law = check-drift hook, fail-early)
        │
        └─ contrast unit test: reads tokens.json pairings → asserts WCAG AA per pair
```

### 1. Source of truth — `tokens/tokens.json`
Colors AND their required pairings live together, so a color and its contrast
obligation are declared in the same place:

```json
{
  "color": { "text": "#1a1a1a", "bg": "#ffffff", "accent": "#0066cc", "accentOn": "#ffffff" },
  "contrastPairs": [
    { "fg": "text",     "bg": "bg",     "min": 4.5 },
    { "fg": "accentOn", "bg": "accent", "min": 4.5 }
  ]
}
```

### 2. Generator → checked-in CSS
`tokens:build` reads `tokens.json` and writes `src/generated/tokens.css`
(`:root { --color-text: #1a1a1a; ... }`). Deterministic: same input → same bytes.
Header the file: `/* GENERATED FROM tokens/tokens.json — do not edit. Run npm run tokens:build. */`

### 3. Drift gate (CI = authority, hook = fast local mirror)
```bash
npm run tokens:build
git diff --exit-code src/generated/   # nonzero exit = someone hand-edited or forgot to regen
```
Same command runs in CI and in the `check-drift` hook. Never commit generated
output that differs from a fresh build.

### 4 & 5. Contrast gate as a UNIT TEST with the safety net
Iterate `contrastPairs` and assert each ratio. The safety net: also assert that
**every color token appears in at least one pair as fg or bg**, so a new color
that ships without a declared pairing fails the test — you cannot add color and
dodge the contrast bar.

```js
import { color, contrastPairs } from "../tokens/tokens.json";
import { ratio } from "./contrast";

test.each(contrastPairs)("AA contrast %o", ({ fg, bg, min }) => {
  expect(ratio(color[fg], color[bg])).toBeGreaterThanOrEqual(min);  // WCAG AA
});

test("every color token is gated by a contrast pair", () => {
  const paired = new Set(contrastPairs.flatMap(p => [p.fg, p.bg]));
  const ungated = Object.keys(color).filter(k => !paired.has(k));
  expect(ungated).toEqual([]);   // declaring a color forces declaring its pairing
});
```

## Procedure — changing tokens

1. Edit `tokens/tokens.json` ONLY (the source). Add/adjust colors.
2. If you added a color, add its `contrastPairs` entry(ies) — the gate test forces this.
3. Run `npm run tokens:build`; commit `tokens.json` AND regenerated `src/generated/` together.
4. Run the suite: contrast unit tests + `git diff --exit-code src/generated/` (drift).
5. Fit into TDD order (typecheck → module-boundary → unit → BDD → build → drift); the
   contrast test is a unit test, the drift check is the generated-artifact-drift stage.
6. Commit with a Conventional Commit; `guard-commit` blocks a red tree, `check-drift`
   blocks stale generated output. CI re-runs the identical gates as the authority.

## Verify with connector tools (deterministic verdicts)
- `gate_evaluate` — confirm the drift + contrast gates are green before flipping a roadmap box.
- `commit_lint` — Conventional Commit shape.
- Never eyeball ratios or diffs; trust the tools/hooks, which CI mirrors exactly.

## Anti-patterns (each becomes a review finding → `tech-debt` issue if not fixed)
- Hand-editing `src/generated/*` (bypasses the source) — drift gate will catch it, but fix the habit.
- Gitignoring the generated artifact (drift gate can't run; consumers desync).
- Contrast checked only in review or Storybook, not as a failing unit test.
- Adding a color with no `contrastPairs` entry (the ungated-token test blocks it).
- Ratio thresholds softened below AA to make a color "pass."
