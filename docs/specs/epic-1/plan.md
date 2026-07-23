# Epic 1 — station breakdown (plan)

How the suite gets built, mapped to roadmap M1 items (`docs/ROADMAP.md`).
Each item is one `/next` cycle: failing test first, minimal green, one
Conventional Commit, PR, review, merge — the box flips on merged-green.

## Stations

1. **Static validation layer** (implementer; reviewer axis-1 verifies)
   Extend `tests/scaffold.contract.test.sh` → a `tests/static/` layer:
   frontmatter schema per component type, `${CLAUDE_PLUGIN_ROOT}` portability
   scan over hooks.json + commands, referenced-file existence, JSON validity
   for every manifest/schema/template. Wire into `gates.boundaries`.

2. **Hook unit-test harness** (implementer)
   `tests/hooks/` — a fixture runner that feeds synthetic event JSON on stdin
   to each `hooks/scripts/*.sh` and asserts exit code + stderr class tag.
   Reuse the hermetic patterns of `tests/hooks.contract.test.sh` (throwaway
   repos, gh shim). One fixture file per event type per hook; forgery-guard
   and `-C`/`cd` binding cases explicitly enumerated.

3. **Coverage gate** (implementer; qa owns the threshold)
   Line coverage over `hooks/scripts/**` via `bashcov`-style instrumentation
   or kcov (decision: cheapest tool that runs in CI — researcher confirms
   current options first). Threshold ≥95% enforced as a failing test in
   `tests/run-suite.sh`.

4. **Eval harness** (implementer builds; qa owns thresholds + flake triage)
   `factory-ops/qa/evals/` — per skill/command: trigger prompts
   (should/near-miss shouldn't), ≥3 runs, trigger-rate thresholds; outcome
   evals with programmatic assertions; with-vs-without-plugin baseline lift.
   Headless `claude -p --output-format json`; cached baselines; incremental
   runs on touched surfaces, full suite in `nightly-eval.yml`.

5. **Config wiring** (implementer; config lands as a reviewed PR — trust root)
   `.factory/config.json` gates updated so layers 1–2 gate every commit and
   the receipt/commit contract enforces the whole suite permanently.

## Sequencing & risks

- 1 → 2 → 3 are strictly ordered (the coverage gate needs the harness).
- 4 can proceed in parallel after 1 (its own harness, nightly-only).
- Risk: coverage tooling for bash in CI is the least-known quantity — the
  market-researcher resolves the tool choice before station 3 starts.
- Risk: eval flake — thresholds are rates over ≥3 runs, and qa triages flakes
  as test bugs rather than loosening bars.
