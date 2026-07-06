---
description: The lights-out loop — chain /next → /review → (auto file tech-debt), and /ship at each milestone close, for up to N iterations or until the roadmap is done, stopping only at clean checkpoints.
argument-hint: "[--max N] [--until Mn] [--stop-on-red]"
---

Run the factory lights-out: `$ARGUMENTS`

1. Arm the loop: write `.factory/state/loop.json` =
   `{"active":true,"iterations":0,"maxIterations":<N or config default>}`.
2. Repeat, one roadmap item per iteration:
   - `/next` — TDD-implement the next item, open its PR.
   - `/review` — 3-lens adversarial panel; fix findings in the diff or file them
     as `tech-debt` (the clerk).
   - When a PR is merged green, let its roadmap box flip (merged-green proof).
   - At a milestone close, `/ship` a gated release.
3. Stop only at a **clean checkpoint** (PR green + reviewed + tech-debt filed).

The `loop-guard` Stop hook re-blocks Stop to advance station-to-station and is
hard-capped by `maxIterations`, so it cannot run away; it deactivates when the
roadmap is complete or the cap is hit. Pair with the `/loop` skill to fire this
on a schedule (e.g. hourly) for true unattended operation. When done, clear
`loop.json` (`active:false`).
