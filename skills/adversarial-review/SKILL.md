---
name: adversarial-review
description: "Run the 3-axis adversarial review (correctness+security, architecture+boundaries, product+accessibility), write findings to .factory/review/<ref>.json with CONFIRMED-vs-PLAUSIBLE discipline, and turn every unfixed finding into a tracked tech-debt GitHub issue. Use when reviewing a PR, diff, or design before it can merge or ship."
---

# adversarial-review

Review is an **adversary hunting for the failure**, not a reader nodding along. The job is to name
concrete failures on three axes, record each as a structured finding, and guarantee nothing is lost:
every finding either gets fixed in this PR or becomes a tracked tech-debt issue. Verdicts come from
the connector — do not eyeball state.

## Invariants (never violate)

1. **Every finding is written to `.factory/review/<ref>.json`** (ref = PR number or commit sha), in
   the exact shape below — never left only in chat. Runtime state survives compaction; conversation does not.
2. **CONFIRMED requires a concrete failing scenario.** Claim `verdict: CONFIRMED` only when you can
   state the exact input/state and the wrong output/crash it produces. Otherwise it is `PLAUSIBLE`.
3. **The iron rule: any finding not fixed in this PR becomes a GitHub issue labeled `tech-debt`.**
   No silent drops, no burying in chat. Enforced by the `debt-reconcile` Stop hook — the loop cannot
   end with an `open` finding that has no tracked issue.
4. **All three axes are covered every time.** A clean axis is an explicit "no findings", not a skip.
5. **Provenance is honest.** Mark whether the change introduced the defect or merely surfaced a
   pre-existing one — it drives blame-free triage, not the fix.

## The 3-axis rubric

| Axis | You are hunting for | Anchor gates |
|------|---------------------|--------------|
| 1. Correctness + security | Wrong results, unhandled edges, race/ordering, injection, authz gaps, secret leakage, unsafe deserialization | typecheck, unit, BDD |
| 2. Architecture + module-boundaries | Dependency-direction violations (kernel<modules<app), port/adapter leaks, missing contract test, god-module, hidden coupling | dependency-cruiser, contract-test-suite-per-port |
| 3. Product + accessibility-gate | Broken/incomplete user journey, spec drift, token drift, **contrast-gate-as-unit-test** failures, keyboard/ARIA gaps | generated-artifact drift, contrast-gate unit test |

Walk each axis in order. For each, either record findings or note "axis N: no findings".

## Finding shape (`.factory/review/<ref>.json`)

The file is a JSON array of findings. Each finding:

```json
{
  "location":    "src/kernel/pricing.ts:142",
  "impact":      "Negative quantity underflows to a huge unsigned total; order charges $0.",
  "provenance":  "introduced",
  "suggestedFix":"Reject qty < 1 in the port contract test and validate at the adapter edge.",
  "severity":    "high",
  "verdict":     "CONFIRMED",
  "status":      "open"
}
```

Field rules:
- `location` — `file:line`, the tightest span that proves the defect.
- `impact` — a **concrete failure or cost**, not "could be risky". Name the input and the damage.
- `provenance` — `pre-existing` | `introduced`.
- `suggestedFix` — the smallest change that removes the failure (often "add the failing test first").
- `severity` — `high` | `medium` | `low` (does it block merge, cost later, or annoy).
- `verdict` — `CONFIRMED` | `PLAUSIBLE` (see discipline below).
- `status` — `open` | `fixed`. Flip to `fixed` only when the fix is committed green in this PR.

## Procedure

1. **Scope the diff.** Identify `<ref>` and the changed surface. Read the ADRs/ARCHITECTURE the
   change touches so axis-2 findings cite the decision they violate.
2. **Hunt all three axes.** Be adversarial: try the malicious input, the boundary value, the empty
   set, the concurrent caller, the screen-reader path. Reproduce before you write.
3. **Record each finding** to `.factory/review/<ref>.json` in the shape above.
4. **Assign verdicts** using CONFIRMED-vs-PLAUSIBLE discipline.
5. **Triage:** for each finding, fix-now (→ `status: fixed`, green) or defer.
6. **Reconcile debt:** every finding still `open` → hand to the **tech-debt-clerk**, which opens/updates
   a `tech-debt` GitHub issue **idempotently by fingerprint** (location + normalized impact), so
   re-reviews never duplicate. Create the `tech-debt` label if absent.
7. **Verify with the connector:** run `techdebt_lint` (finding shape + every open finding tracked) and
   `techdebt_audit` (issues ↔ findings reconciled). The `debt-reconcile` Stop hook re-runs this as the
   authority; a red audit blocks the loop from ending.

## CONFIRMED-vs-PLAUSIBLE discipline

- **CONFIRMED** — you have a reproduction: "With `qty=-1`, `total()` returns `4294967295`, not a
  rejection." A CONFIRMED high blocks merge.
- **PLAUSIBLE** — a real smell you could not yet trigger: "This unbounded loop *may* not terminate on
  cyclic input; no failing case constructed." PLAUSIBLE findings are still recorded and still become
  tech-debt when unfixed — they just never masquerade as proven.
- Never inflate PLAUSIBLE to CONFIRMED to force a block; never downgrade a real reproduction to dodge
  the fix. The distinction is what makes the review trustworthy to the next agent.

## Definition of done

- [ ] All 3 axes walked; each has findings or an explicit "no findings".
- [ ] Every finding written to `.factory/review/<ref>.json` in the exact shape.
- [ ] Every `CONFIRMED` cites a concrete failing scenario in `impact`.
- [ ] Every `open` finding has a tracked `tech-debt` issue (idempotent by fingerprint).
- [ ] `techdebt_lint` and `techdebt_audit` pass; `debt-reconcile` Stop hook is green.
