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
- [ ] Coverage gate ≥95% lines fails the suite when unmet, over exactly
      the scope Release-Gate criterion 7 names below — one scope, one
      copy, defined there only (#1384, #1408)
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
   replaced with `P2`/`P3` since the **2026-07-29 baseline** (the
   same fixed baseline criteria 3/5 and the D6 report ledger use —
   NOT the epoch anchor, which advances on every re-pin and would
   silently un-count any down-rank older than the newest pin, #1363)
   **counts as still `P0`/`P1` for this criterion** unless a
   pin-covered human disposition record **whose `event` field names
   the down-rank** (`event: down-rank` — a disposition filed for a
   contested close of the same issue clears criterion 9 only, never
   this criterion, #1391) covers it — a relabel the day before
   release must not create a pass no fix earned; the report-only
   down-rank row is display, not the brake (#1152).
3. Zero open issues that have **ever carried** `security` (timeline
   membership computed at gate time — a label stripped an hour before
   the gate must not create a pass window the nightly auditor has not
   yet repaired, #1190), at any priority (ADR 0005's cross-priority
   security precedence).
4. Zero open `tech-debt` issues lacking a valid `P0`–`P3` label —
   fail-closed on untriaged; legacy `priority:*`/`high`/`medium`/`low`
   labels do not count (#510 clears this).
   **Membership rule for criteria 2 and 4 (#1417):** an open issue
   that has **ever carried** `tech-debt` since the 2026-07-29
   baseline counts as a `tech-debt` issue for both criteria
   regardless of current labels — stripping the label from an open
   P0/P1 is a strictly stronger form of the down-rank criterion 2
   brakes, and gets the same brake — unless a pin-covered human
   disposition record with `event: label-strip` covers the removal.
   The auditor's floor-strip watch includes `tech-debt` unlabel
   events on open issues (ADR 0006 § D4).
5. Zero open issues that have **ever carried** `gate:confirmed-high`
   (clerk-applied floor; timeline membership at gate time, same
   rationale as criterion 3 — the auditor's re-application is repair
   hygiene, not the safety mechanism, #1190).
6. Auditor liveness: a successful `close-audit` run within 24 hours of
   **wall-clock `now` at the verdict of record** — never the snapshot
   clock: criterion 6 is **evaluated live at every gate run and
   excluded from the acked/masked digest exactly as criterion 8 is**
   (masked to `"pending-ack"` in the acked canonical form), because a
   frozen liveness result would self-satisfy forever (a snapshot from
   the auditor's last living night still passing weeks later) and a
   wall-clock check bound into the signed bytes would expire the
   signature ~24h after signing — both horns of #1377. Recorded audit
   windows must cover [2026-07-29, the end of that run's window]
   gapless, where each steady-state window's START equals the
   previous **successful** run's END (an attempted-but-failed run
   advances nothing, #1379); a gap — from a mid-run failure, a
   workflow rotation, anything — is repaired by an explicit
   **backfill re-sweep** (a run whose window is the gap itself;
   closed-issue history is queryable indefinitely, so any gap is
   curable), never by amnesty.
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
   per release, both checkable (#1301): (a) the pin's digest key set
   **exactly equals** the set of files existing under the pinned
   globs at the gate SHA — coverage is bidirectional (#1378): a file
   on disk with no pin entry is FAIL just as a mismatched digest is,
   otherwise an empty or partial `digests` map passes custody while
   pinning nothing and an omitted file stays permanently
   agent-editable — every listed digest equals the SHA-256 of the
   corresponding pinned file at the gate SHA, the live
   `## Human maintainers` section hashes to the pin's `rosterHash`,
   and every commit **touching the custody-lane files**
   (`trust-pin.json`, `gate.ack`, the disposal allowlist, and
   `factory-ops/release/dispositions/**`) since the epoch anchor
   satisfies ALL custody properties (#1365): GitHub signature
   verification state `VALID`; `signature.signer.login` — never the
   settable author/committer email (#1080) — present on the roster
   whose hash the pin carries; author = committer = signer; a
   non-merge commit not associated with any merged PR (a squash
   merge is web-flow-signed and must not satisfy custody); and a
   diff touching only the sanctioned custody-lane paths — any
   violation is FAIL. The custody walk is
   scoped to the custody lane ONLY: gate code and fixtures merge
   through the normal autonomous PR flow, and their integrity is
   enforced solely by the digest-match clause above (a change takes
   release effect only after a human re-pin) — a walk over all pinned
   paths would FAIL uncurably on the first ordinary gate-code PR, the
   brickability #1123 forbids; (b) `factory-ops/release/<version>/
   gate-report.json` exists as the **frozen report snapshot** —
   committed canonical bytes; the ack verification of this clause
   reads the snapshot, never a re-emitted report — and `factory-ops/release/
   <version>/gate.ack` exists on the release branch, in a commit
   satisfying the same signature rules, whose single line equals the
   SHA-256 of that snapshot's **acked canonical form** (snapshot
   bytes with the criterion-8 **and criterion-6** entries masked to
   `"pending-ack"` — a report cannot attest its own acknowledgment,
   and liveness is evaluated live at the verdict of record, #1377).
   Absent or mismatched is FAIL. **The snapshot binds the ack; it
   does not substitute for the predicate (#1392):** every
   current-state criterion (1–7, 9) is evaluated **live at the
   verdict of record** — a `bug` or `security` issue opened, or a
   close contested, in the snapshot→`/ship` window still FAILs the
   live verdict; the snapshot is the human-witnessed evidence record
   this clause verifies byte-for-byte, so live divergence never
   flips the ack digest and the #1317 livelock does not return.
   Autonomous activity between snapshot and `/ship` therefore cannot
   invalidate the signature — it can only, correctly, fail the gate.
   Rationale and custody mechanism: ADR 0006 §§ D5–D6.
9. Zero standing contested closes, checkable (#1301): the parked
   bucket of the latest successful close-audit run (criterion 6's run)
   is empty. A parked entry exits ONLY by the issue being reopened and
   re-closed with a qualifying fix (the auditor reclassifies it), or
   by a human disposition record at
   `factory-ops/release/dispositions/<issue>.json` covered by the
   trust pin **whose `event` equals `contested-close`** (#1416 — the
   same discriminator rule as criterion 2, in this direction: a
   `down-rank` or `label-strip` disposition for the same issue clears
   its own criterion only and never exits the parked bucket; one
   signature never clears two event kinds). FAIL names every standing
   entry. Rationale: ADR 0006 § D4.

Then `/ship` on the release branch — never from red, release-proof
minted on the built artifact.
