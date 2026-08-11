# Epic 1 — the plugin test suite (spec)

Tracking issue: created by `bootstrap.sh` (milestone v1.0.0). Owner: qa
(suite health) + implementer (all code). This spec is the definition of
"covered" for this plugin, and the first sprint's scope.

## Why

The plugin enforces discipline on other repos; its own hooks, commands, and
skills are currently validated only by contract tests and manifest checks. A
factory that ships enforcement tooling with untested enforcement is not
credible — and the suite is what makes the v1.0.0 Release Gate decidable.

## What (three layers)

1. **Static validation** (commit-gate speed): manifest + frontmatter schema
   checks for every command/agent/skill/hook config; path portability
   (`${CLAUDE_PLUGIN_ROOT}` only — no absolute or repo-relative plugin paths);
   referenced files exist; JSON validity. Fails the gate on any violation.
   Seed exists in `tests/scaffold.contract.test.sh`; this layer extends it to
   full schema depth.
2. **Unit tests for every hook script**: stdin JSON fixtures per event type;
   assertions on exit codes AND stderr class tags (`[hard-boundary]` vs
   `[heuristic]`); matcher edge cases; forgery-guard cases; multi-repo
   `-C`/`cd` binding. **Coverage ≥95% lines on `hooks/scripts/**`, enforced as
   a failing test** — that is what makes "no uncovered cases"
   machine-decidable.
3. **Behavioral evals** (nightly): per skill/command, trigger evals — 8–10
   should-trigger and 8–10 near-miss shouldn't-trigger prompts, ≥3 runs each,
   trigger-rate thresholds — and outcome evals with programmatic assertions
   plus with-vs-without-plugin baseline lift. Headless `claude -p` harness;
   results to `factory-ops/qa/`; thresholds enforced in `nightly-eval.yml`.

Layers 1–2 run in the commit-gate suite (`tests/run-suite.sh`); layer 3 is
nightly. All layers are wired into `.factory/config.json` green stages so the
receipt/commit contract enforces them forever.

## Acceptance criteria

- [ ] Every command/agent/skill/hook config passes layer-1 checks in the gate
- [ ] Every hook script has fixture-driven unit tests incl. both stderr classes
- [ ] Coverage gate ≥95% lines on `hooks/scripts/**` fails the suite when unmet
- [ ] Trigger + outcome evals exist for every skill and command, with
      thresholds that fail `nightly-eval.yml`
- [ ] `.factory/config.json` gates run all deterministic layers; nightly runs
      layer 3
- [ ] Three consecutive nightly runs green on `main` (feeds the Release Gate)

## Release Gate for v1.0.0

This section is the **single maintainable copy of the gate predicate**
(ADR 0005's single-copy rule; the spec governs on any divergence).
Mechanism and rationale: ADR 0006 (`docs/adr/0006-release-gate-synthesis.md`,
the sprint-4 board decision); scope: ADR 0005. Criteria range over
currently-**open** issues, from fully-paginated queries —
timeline-computed where a criterion says **ever carried** (criteria 3
and 5 examine label history at gate time, #1266), current-label
otherwise; the gate returns PASS,
FAIL (naming failed criteria with evidence), or BLOCKED (naming open
prerequisites) — no "not evaluable" meta-states.

1. Zero open issues labeled `bug`.
2. Zero open `tech-debt` issues currently labeled `P0` or `P1`
   (most-severe governs when several `P0`–`P3` labels are present).
   An open `tech-debt` issue whose `P0`/`P1` label was removed or
   replaced with `P2`/`P3` since the epoch anchor **counts as still
   `P0`/`P1` for this criterion** unless a pin-covered human
   disposition record (criterion 9's lane) covers the down-rank — a
   relabel the day before release must not create a pass no fix
   earned; the report-only down-rank row is display, not the brake
   (#1152).
3. Zero open issues that have **ever carried** `security` (timeline
   membership computed at gate time — a label stripped an hour before
   the gate must not create a pass window the nightly auditor has not
   yet repaired, #1190), at any priority (ADR 0005's cross-priority
   security precedence).
4. Zero open `tech-debt` issues lacking a valid `P0`–`P3` label —
   fail-closed on untriaged; legacy `priority:*`/`high`/`medium`/`low`
   labels do not count (#510 clears this).
5. Zero open issues that have **ever carried** `gate:confirmed-high`
   (clerk-applied floor; timeline membership at gate time, same
   rationale as criterion 3 — the auditor's re-application is repair
   hygiene, not the safety mechanism, #1190).
6. Auditor liveness: a successful `close-audit` run within 24 hours of
   the gate run, with recorded audit windows covering [2026-07-29, the
   end of that run's window] gapless; the tail to gate time is bounded
   by the freshness rule.
7. Mechanical artifact checks: coverage ≥95% lines on
   `hooks/scripts/**`, `hooks/lib/common.sh`, and
   `connector/src/release-gate/**`, measured at the exact SHA `/ship`
   builds; three consecutive green `nightly-eval.yml` runs on `main`
   (thresholds per #511); a line in `docs/PRODUCT.md` that **begins
   with** the marker token `**Freeze state: ON**` (leading-token match:
   the date and gate evidence PRODUCT.md's convention appends after the
   token are allowed and expected — a whole-line exact match would fail
   a correctly-frozen repo, #1250); zero unresolved `.factory/review` findings
   (prerequisite issues #419, #420, #510, #511 are NOT part of this
   criterion's FAIL set — while any is open the verdict is **BLOCKED**,
   naming them, per the precedence rule: BLOCKED beats FAIL beats PASS,
   #1213); every v1.0.0
   roadmap item merged-green except M4's own two terminal boxes.
8. Trust-anchor custody intact and one verified human acknowledgment
   per release, both checkable (#1301): (a) every digest in
   `factory-ops/release/trust-pin.json` equals the SHA-256 of the
   corresponding pinned file at the gate SHA, the live
   `## Human maintainers` section hashes to the pin's `rosterHash`,
   and every commit **touching the custody-lane files**
   (`trust-pin.json`, `gate.ack`, the disposal allowlist, and
   `factory-ops/release/dispositions/**`) since the epoch anchor is a
   directly-pushed, roster-key-signed commit touching only those
   sanctioned paths — any mismatch is FAIL. The custody walk is
   scoped to the custody lane ONLY: gate code and fixtures merge
   through the normal autonomous PR flow, and their integrity is
   enforced solely by the digest-match clause above (a change takes
   release effect only after a human re-pin) — a walk over all pinned
   paths would FAIL uncurably on the first ordinary gate-code PR, the
   brickability #1123 forbids; (b) `factory-ops/release/<version>/
   gate-report.json` exists as the **frozen report snapshot** —
   committed canonical bytes; the verdict of record reads the
   snapshot, never a re-emitted report — and `factory-ops/release/
   <version>/gate.ack` exists on the release branch, in a commit
   satisfying the same signature rules, whose single line equals the
   SHA-256 of that snapshot's **acked canonical form** (snapshot
   bytes with the criterion-8 entry masked to `"pending-ack"` — a
   report cannot attest its own acknowledgment). Absent or mismatched
   is FAIL. Autonomous activity between snapshot and `/ship` cannot
   flip the digest (the snapshot is frozen, #1317); what happens
   after the snapshot is witnessed by the nightly auditor and the
   next release's ledger, and the snapshot itself must satisfy
   criterion 6's freshness bound at gate time.
   Rationale and custody mechanism: ADR 0006 §§ D5–D6.
9. Zero standing contested closes, checkable (#1301): the parked
   bucket of the latest successful close-audit run (criterion 6's run)
   is empty. A parked entry exits ONLY by the issue being reopened and
   re-closed with a qualifying fix (the auditor reclassifies it), or
   by a human disposition record at
   `factory-ops/release/dispositions/<issue>.json` covered by the
   trust pin. FAIL names every standing entry. Rationale: ADR 0006
   § D4.

Then `/ship` on the release branch — never from red, release-proof
minted on the built artifact.
