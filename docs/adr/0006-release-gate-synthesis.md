# ADR 0006 — v1.0.0 Release Gate: thin current-state gate, fixture-tested cores, human-pinned trust anchors

Status: accepted · Date: 2026-08-06

## Context

PR #444's Release Gate section grew to ~280 normative lines over 26
adversarial review rounds while open tech-debt went 289 → 754 in six days
(~2.6x manufacture-vs-resolve — the sprint-4 headline finding, #980,
recorded in `docs/PRODUCT.md`). The sprint-4 plan froze ordinary review
rounds on #444 and routed the contested gate design to a judge panel
(the judge-panel method: stance-pinned proposals, adversarial ballots, synthesized ADR). Three stance-pinned proposals
(committed as the record of decision at `docs/adr/0006-panel/proposal-*.json`; originals were produced under the gitignored `.factory/panel/` working dir)
were judged by three adversarial panelists
(`docs/adr/0006-panel/ballot-*.json`, committed alongside).
Every proposal drew a CONFIRMED fatal flaw on every axis — nine confirmed
flaws in total — yet the three ballots' `best_spine` fields converge on
the same synthesis:

- **dx-first's backbone** — a small current-state gate plus ONE verified
  human acknowledgment per release — is the only shape with demonstrated
  release liveness that this loop can build and run.
- **contract-first's discipline** — pure, fixture-tested reference
  implementations, findings-as-failing-fixtures, PASS/FAIL/BLOCKED
  verdicts — is the only mechanism that structurally ends prose
  ping-pong.
- **security-first's principle** — mechanical evidence is necessary but
  never sufficient; the only trust anchor outside any agent's reach is a
  GitHub-verified human signature with custody over its own roster — is
  the only idea that places a principal outside the agents' write set.

The ballots also established three hard facts the synthesis must obey:
all three proposals fall to **agent-editable gate code** (the agents
author, review, and autonomously merge every PR; no in-tree path fence
covers the gate's own code); **signer-login checks cannot work through
squash merges** (GitHub's web-flow key signs squash-merged commits, so
`signature.signer.login` never resolves to a roster human on the default
branch's ordinary history); and **hand-invented evidence fixtures** are
self-referential (a gate that has never executed cannot have "recorded"
fixtures unless they are actually recorded).

The one real laundering incident on record (#120: falsely closed
`completed` for a week) was healed by a single reopen — evidence that
detection-and-repair protects every day, while a release-time predicate
protects one instant. ADR 0005 (carried in THIS PR so the normative chain exists at merge — PR #444 subsequently conforms only the spec and PRODUCT.md,
`docs/adr/0005-m4-tech-debt-gate-scope.md`) already settled the gate's
*scope*: fail-closed triage, security precedence across priority levels,
the M5 deferral home, and the coverage-floor widening to
`hooks/lib/common.sh`. This ADR settles the gate's *mechanism*.

## Decision

We will define the v1.0.0 Release Gate as a **thin current-state gate**
with **pure, fixture-tested decision cores**, a **blocking-liveness
nightly close auditor**, and **human custody over the gate's own trust
anchors**. `docs/specs/epic-1/spec.md` § "Release Gate for v1.0.0"
shrinks to a short normative statement of the criteria below plus
pointers to the executable definitions; no other document restates the
predicate (ADR 0005's single-copy rule stands).

### D1 — The gate criteria (all over current state, fully paginated)

1. Zero open issues labeled `bug`.
2. Zero open `tech-debt` issues currently labeled `P0` or `P1`
   (most-severe governs when several `P0`–`P3` labels are present).
3. Zero open issues labeled `security`, at any priority (ADR 0005's
   cross-priority security precedence).
4. Zero open `tech-debt` issues lacking a valid `P0`–`P3` label —
   **fail-closed on untriaged**; legacy
   `priority:*`/`high`/`medium`/`low` labels do not count (#510 clears
   this).
5. Zero open issues labeled `gate:confirmed-high` (clerk-applied at
   filing time as a severity floor; the nightly auditor re-applies any
   stripped floor label — see D4 — which is what makes a current-state
   read safe here).
6. **Auditor liveness (blocking):** a successful `close-audit` run
   completed **within 24 hours** of the gate run, and the union of all
   recorded audit windows covers **[2026-07-29, the end of that most
   recent successful run's window] with no gaps** — the tail between
   that run and gate time is bounded by the 24-hour freshness bound,
   not an unreachable "no gaps to gate time" literalism that would fail
   every daytime release after a midnight audit (#1137). A stale,
   failed, or gappy auditor fails the gate. This is a standing
   criterion evaluated at every gate run — never a one-time "deployed"
   check.
7. Mechanical artifact checks: coverage ≥95% lines on
   `hooks/scripts/**`, `hooks/lib/common.sh`, and (new — see
   Consequences) `connector/src/release-gate/**` (a peer verdict module under `connector/src/`, admitted into ARCHITECTURE's layer table alongside `factory-core.mjs` — Rule 1 broadens to "verdicts come only from `connector/src` verdict modules via `cli.mjs`", #1144), measured at the exact SHA
   `/ship` builds; three consecutive green `nightly-eval.yml` runs on
   `main` (thresholds per #511); the single-line
   `**Freeze state: ON**` marker in `docs/PRODUCT.md`; prerequisite
   issues **#419, #420, #510, #511 closed** (canonical set — #649 is
   rescoped, see D8); zero unresolved `.factory/review` findings; every
   v1.0.0 roadmap item merged-green except M4's own two terminal boxes
   (#527 carve-out).
8. **Trust-anchor custody intact** (D5) and **one verified human
   acknowledgment** (D6). Both are pass/fail criteria, not ceremonies.
9. **Zero standing contested closes** (D4's parked bucket, #1142): an
   issue the auditor reopened once and an agent re-closed counts here
   until a human disposition or a qualifying fix close resolves it —
   this is the criterion that makes close→reopen→re-close a blocking
   state rather than an escape, wired into the gate itself.

### D2 — Verdict vocabulary

The gate returns `PASS`, `FAIL` (naming the failed criteria with
evidence references), or `BLOCKED` (naming the open prerequisite
issues). "Not evaluable until #X" prose meta-states are abolished; every
criterion is evaluable on day one, some as `BLOCKED`.

### D3 — Pure cores, real-evidence fixtures, fixture-only amendments

The gate's `decide(evidence) → verdict` core and the auditor's
`closeLegitimacy(closeEvidence) → legitimate | illegitimate | contested`
predicate are **pure reference implementations** in
the `release-gate` verdict module, a peer of `factory-core.mjs` under `connector/src/` (`connector/src/release-gate/`, no I/O, no clock, no env; exposed to scripts via `cli.mjs` like every verdict — Rule 1 broadened per this ADR), fed by a thin
evidence collector that is the only component touching the network.
`tests/fixtures/release-gate/` holds one fixture per adversarial
scenario, named for the review finding that motivated it; the fixture
suite runs in `tests/run-suite.sh` on every commit.

**Fixture provenance rule (binding):** every fixture's evidence file is
**recorded from a real collector run** — against this repo's history or
against a scratch repo where the scenario is deliberately staged — with
the recording command and source noted in the fixture's `why.md`.
Hand-edits are permitted only as documented minimal mutations of a
recorded base. Hand-invented evidence shapes are inadmissible; the
collector itself is contract-tested against recorded API responses.

**Amendment protocol:** a finding against gate or auditor *semantics* is
admissible only as a **failing fixture** plus the code change that
greens it — never as a prose amendment. Findings about producer
conventions route to the producer's charter file; opinions close. Gate
*scope* changes require a new ADR (ADR 0005's owner rules). And no
gate-code change is self-sealing: it does not take release effect until
a human re-pins it (D5).

### D4 — Close-auditing is a nightly repair job with an executable legitimacy predicate

A nightly `close-audit` workflow scans every close since its last run
(since 2026-07-29 on the bootstrap run) of issues that carry **or ever
carried** `bug`/`tech-debt`/`security`/`gate:confirmed-high` — the
ever-carried timeline algebra, interval-computed P0/P1 presence
(#887/#922), duplicate-chain resolution with floor inheritance (#939),
fingerprint-in-squash-commit citation (#941), and the anchored
location/hunk-overlap bindings (#997/#942/#1031/#923) all survive the
26 rounds **here**, inside `closeLegitimacy`, as classification logic —
not as release-time pass/fail predicates. Actions:

- `illegitimate` close (e.g. `not planned` on gate-relevant work; a
  floor label stripped from an open issue) → **reopen once per close
  event** with a comment / re-apply the label. A re-closed issue is
  never reopened again for the same event (no reopen wars) — but it
  becomes a **standing contested close**, and any nonzero
  standing-contested-close count is itself a **blocking gate
  criterion** until a human disposition (via the signed ack's
  disposition lane) or a qualifying fix close resolves it. Close →
  auditor-reopen → re-close therefore parks an issue in a blocking
  bucket, never past the gate (#1124); it also lands in the report's
  **contested closes** section.
- `contested` close (e.g. a merged closing PR whose diff fails the
  fingerprint/location bindings — the "Fixes #X on an unrelated PR"
  laundering shape) → reopened once, and if re-closed, surfaced as
  contested. Bindings decide *classification*; the #894 remediation
  commit remains the honest cure for a genuine fix with broken linkage.
- closes on the **disposal allowlist** (D7) → `legitimate` by
  authorization; displayed in the report, never reopened.

The auditor repairs **state**, so dashboards and `/factory-status` stay
truthful (the #120 lesson); the worst laundering window is one nightly
cycle, and criterion 6 guarantees the auditor was actually alive to
provide it.

### D5 — Custody of the gate's own trust anchors (the trust pin)

**What is pinned:** SHA-256 digests of (a) the gate's code paths —
`connector/src/release-gate/**` (a peer verdict module under `connector/src/`, admitted into ARCHITECTURE's layer table alongside `factory-core.mjs` — Rule 1 broadens to "verdicts come only from `connector/src` verdict modules via `cli.mjs`", #1144), `hooks/scripts/release-gate.sh`,
`hooks/scripts/close-audit.sh`; (b) the fixture trees —
`tests/fixtures/release-gate/**`; (c) the `## Human maintainers` section
of `MAINTAINERS.md` (the roster hash); and (d) the disposal-allowlist
files (D7).

**Where the pin lives:** `factory-ops/release/trust-pin.json` —
`{ pinnedAtCommit, digests: {path → sha256}, rosterHash }` — on the
default branch.

**How a human updates it:** by a **directly-pushed, locally-signed
commit to the default branch** touching **only**
`factory-ops/release/trust-pin.json` (and, for D6/D7, the
`factory-ops/release/**` ack/disposal files). GitHub verifies local
GPG/SSH signatures on directly-pushed commits as the signer's own —
this is the one artifact a human can produce that squash-merging cannot
launder (the web-flow-key fact). This narrow direct-push lane is
**explicitly sanctioned as the sole exception** to PR-only flow,
because it is the entire point: a commit no agent can forge. CI still
runs on the push; the gate itself rejects any pin-chain commit that
touches paths outside the sanctioned set.

**What the gate checks (all fail-closed):**

1. Recompute the pinned paths' digests at the release SHA; any mismatch
   with `trust-pin.json` → FAIL ("gate code changed since last human
   pin"). Gate-code and fixture changes therefore merge through the
   normal autonomous PR flow, but **take release effect only after a
   human re-pins**, having reviewed the diff-since-last-pin that the
   gate report lists (the custody section). A weakened predicate cannot
   green a release by greening its own tests.
2. Walk the commit history of `trust-pin.json` **from the most recent
   epoch anchor forward** — the epoch anchor is the newest commit
   touching the pin that satisfies all custody properties below; only
   commits AFTER it are audited. This makes the walk unbrickable
   (#1123): a violating commit (a stray squash-merge, an innocent
   codemod) fails the gate only until the human pushes a fresh
   epoch-anchoring re-pin that supersedes it — history before an epoch
   is out of scope by construction, and the epoch commit itself proves
   human review of everything it pins. Custody properties: GitHub
   signature verification state `VALID`, `signature.signer.login`
   (never the settable author/committer email, #1080) on the roster
   whose hash the pin itself carries, author = committer = signer, a
   non-merge commit not associated with any merged PR, and a
   sanctioned-paths-only diff. Any post-epoch violation → FAIL until
   re-pinned.
3. The live `## Human maintainers` section's hash equals the pin's
   `rosterHash` → otherwise FAIL. Roster changes ride the same re-pin
   mechanism; the unsatisfiable MAINTAINERS.md-history signature walk
   is **rejected** and replaced by this pin.

**Genesis:** the first pin commit self-declares the roster it hashes;
its authenticity rests on the cryptographic signature of the operator's
account (currently the sole entry under `## Human maintainers`), which
no agent holds keys for. Residual risk is stated in Consequences.

### D6 — One verified human acknowledgment per release, unconditional

The gate script emits `gate-report.json` — canonical JSON (sorted keys,
LF, UTF-8), SHA-256 over exact bytes — containing: the per-criterion
results and counts; **every close of a gate-relevant issue since
2026-07-29 with its `closeLegitimacy` classification** (not only floored
or contested ones — the full ledger); all contested closes; every
`P0`/`P1` → `P2`/`P3` down-rank since baseline, by name (#909); mass
down-rank and mass-close events; the disposal-allowlist contents in
force; the auditor-liveness evidence; and the **custody section**
(pinned digests, pin-chain verification results, and the list of every
commit touching pinned paths since `pinnedAtCommit`).

The gate FAILS unless `factory-ops/release/<version>/gate.ack` exists on
the release branch containing exactly that SHA-256 digest as its only
line, in a **directly-pushed commit satisfying the same signature rules
as the pin chain** (D5.2). The acknowledgment is **unconditional — it
fires on every release, including one with an empty ledger** — so no
agent-computed trigger can route around the witness. Agent
self-acknowledgment tiers (`gateReportHash` written by the
release-captain into `.factory/state/release-intent.json`) are demoted
to bookkeeping; they satisfy no criterion.

### D7 — Disposal lanes for authorized mass-dispositions

- **ADR-referenced disposal allowlist:** a numbered ADR may authorize
  closing a named set of issues without a fix (e.g. design-superseded).
  The authorization is recorded as
  `factory-ops/release/disposals/<adr>-<slug>.json` (issue numbers +
  authorizing ADR + reason), the file's digest joins the trust pin
  (D5), and the auditor treats listed closes as `legitimate` — so an
  authorized migration **cannot reopen itself on night one**. The
  report displays every allowlist in force under the human ack.
- **One-time lane for the review-loop backlog:** the ~465 findings
  filed against superseded drafts of the Release Gate spec prose get
  exactly one disposition pass: each is either (a) closed
  `not planned` referencing this ADR and listed in
  `factory-ops/release/disposals/0006-superseded-spec-findings.json`,
  or (b) — if it describes a real defect in shipped code rather than in
  superseded prose — kept open and triaged to a `P0`–`P3` label like
  any issue. The disposal file is covered by a **one-time human-signed
  pin update** (D5), so the incident's audit cost is paid once, on the
  record, with per-row provenance — closing security-first's
  bindings-vs-disposition deadlock without any override lane on the
  bindings themselves.

### D8 — PR #444 disposition and sequencing

- **This ADR merges first**, as the board decision of record; the
  sprint-4 review freeze holds and the panel is the review of record —
  no further ordinary adversarial rounds on the gate design.
- **PR #444 then reduces to conform, docs-only:** ADR 0005 lands
  unchanged (its scope decisions — fail-closed triage, cross-priority
  security, the M5 deferral home, the `common.sh` coverage widening,
  the joint-lane rule — all **stand**); the spec's "Release Gate for
  v1.0.0" section shrinks from ~280 lines to the short normative form
  of D1–D7 with pointers to the executable definitions;
  `docs/PRODUCT.md` keeps rationale and points at the spec. The
  accreted close-audit prose is **superseded by this ADR**, and its
  26-round finding ledger becomes the requirements source the fixtures
  are transcribed from (per D3's provenance rule).
- **Implementation lands as separate small PRs** on the M4 track (gate
  script + cores + fixtures; auditor + fixtures; `/ship` wiring), each
  governed by the fixture-only amendment protocol — never folded back
  into #444.
- **#649 is rescoped:** the standalone backfill-audit ceremony is
  replaced by the auditor's bootstrap run (floor-label backfill,
  trailer and location normalization where possible, first full-window
  audit) plus the D7 disposition lane; #649 closes when that bootstrap
  run succeeds.

**Explicitly rejected:** ever-carried timeline algebra as release-time
pass/fail predicates (it survives as auditor classification logic); the
fixture-governs-itself amendment loop without human custody
(contract-first's confirmed flaw); a ledger-conditional human witness
and per-exemption witnessing (security-first's confirmed flaws); a
MAINTAINERS.md signed-history walk (unsatisfiable through squash
merges); heuristic-only close auditing with advisory-only bindings and
a one-time liveness check (dx-first's confirmed flaws); and any
signature-override lane on failed mechanical bindings.

### Flaws resolved

Every panel-CONFIRMED fatal flaw, and how this synthesis closes it:

| # | Proposal | Ballot | Confirmed fatal flaw | Closed by |
|---|----------|--------|----------------------|-----------|
| 1 | contract-first | correctness-security | Spec-as-code is agent-amendable and self-sealing: weaken gate-core + fixtures in one green PR, autonomously merged, and the weakened verdict becomes normative with de-weakening findings inadmissible | D5: gate code and fixtures are pinned; any change fails the gate at release until a human re-pins after reviewing the diff-since-last-pin listed in the signed report. Merging green never makes a change release-effective; D3 keeps fixtures but strips their self-sealing authority |
| 2 | contract-first | implementability | Fixtures hand-invented from prose, never validated against real API shapes; the collector bends silently to fit them; largest-ever single PR | D3's fixture provenance rule (fixtures recorded from real collector runs, staged where history lacks the scenario; collector contract-tested against recorded responses) and D8's phased small-PR delivery |
| 3 | contract-first | product-operability | The loop is re-hosted, not ended: the full implementation moves INTO frozen PR #444, growing the attack surface while the manufacture engine (#471/#688) runs | D8: #444 shrinks to docs-only and merges under the freeze; implementation is separate small PRs under the fixture-only admissibility rule; #471/#688 stay on their own P0 track, decoupled from gate evaluability |
| 4 | security-first | correctness-security | The universal witness has an agent-computed trigger: an agent-edited gate script empties the ledger and the `(ledger empty)` branch passes with zero human signatures | D6: the acknowledgment is unconditional per release — it fires on an empty ledger too — and D5 pins the gate script itself, so ledger-enumeration tampering fails the digest check |
| 5 | security-first | implementability | Roster chain-of-custody is unsatisfiable: in a squash-only repo every MAINTAINERS.md commit is signed by GitHub's web-flow key, never a roster human; no remediation path — the gate bricks | D5: custody binds to what a human can actually produce — a directly-pushed, locally-signed commit to the pin file, GitHub-verified as the signer's own; the roster is protected via its pinned hash, and the MAINTAINERS.md history walk is dropped |
| 6 | security-first | product-operability | Internal contradiction deadlocks the first release: bindings "can never be signed into exemption" vs. the ~465 findings "witnessed in one signed ack"; plus per-close human witnessing converts the factory to human cadence permanently | D7's explicit, human-signed, ADR-referenced disposal lane gives the superseded-prose backlog a legal one-time path (no override of bindings — a distinct authorization class); D6 keeps the human cost at exactly one signature per release |
| 7 | dx-first | correctness-security | The cheapest laundering path (link any merged PR via "Fixes #X") is invisible to every predicate, every heuristic, and the report the human signs | D4: `closeLegitimacy` applies the fingerprint/location/hunk bindings as classification — a merged-but-unbound close is `contested`, reopened once, and surfaced; D6: the report carries **every** close since baseline with its classification, so the human backstop actually sees the row |
| 8 | dx-first | implementability | Auditor liveness never verified: "≥1 successful run" is a one-time historical check, so the gate greens with the auditor dead since deployment and a stale last-good summary | D1 criterion 6: a fresh successful auditor run within 24 hours of the gate run AND gapless window coverage since 2026-07-29 is a standing, blocking gate criterion evaluated at every run |
| 9 | dx-first | product-operability | "Legitimately closed" is undefined, forcing fail-open (no anti-laundering) or fail-closed (nightly mass false reopens + a contested-blob rubber stamp); the migration's own mass-close gets reopened on night one | D3+D4: close-legitimacy is a pure, fixture-tested reference predicate (the executable-contract discipline applied where the adversarial semantics actually live); D7's disposal allowlist makes the ADR-authorized mass-disposition `legitimate` by construction, so the design cannot reopen itself |

## Consequences

- **Decision owner: architect** (gate *mechanism* — this ADR's subject;
  the board synthesis is architect-lane work per GOVERNANCE.md), with
  the **product-owner** owning gate *scope* per ADR 0005, and the panel
  artifacts at `docs/adr/0006-panel/` as the review of record. Convened
  by the conductor under the sprint-4 plan's board directive.
- **Easier:** the gate becomes implementable this sprint (search-API
  queries + file checks + two small pure modules); every criterion is
  evaluable day one; disputes about gate semantics terminate in a red or
  green fixture run instead of a 27th review round; PR #444 becomes
  mergeable in one round because almost no predicate prose remains to
  attack; the 26 rounds already paid for become a permanent regression
  suite; dashboards stay truthful because the auditor repairs state.
- **Harder / new obligations:** the human operator gains two standing
  duties — re-pinning after any gate-code/fixture/roster/allowlist
  change (reviewing the custody diff) and one signed ack per release.
  Human availability is a release dependency, deliberately, at a bounded
  once-per-release cost. The direct-push lane must be configured
  (branch protection permitting roster humans to push; the gate rejects
  any pin-chain commit touching unsanctioned paths). The auditor is now
  release-critical infrastructure with a liveness SLO.
- **Coverage floor widens** to `connector/src/release-gate/**` (a peer verdict module under `connector/src/`, admitted into ARCHITECTURE's layer table alongside `factory-core.mjs` — Rule 1 broadens to "verdicts come only from `connector/src` verdict modules via `cli.mjs`", #1144) and the two
  new scripts (`release-gate.sh`, `close-audit.sh`) — recorded here per
  the ADR 0005 precedent; qa owns the threshold.
- **Accepted residual risks, stated:** a laundered close can be
  false-green for up to one nightly cycle before repair (bounded, and
  the full close ledger reaches the signing human regardless). A fully
  compromised gate binary plus a rubber-stamping human defeats the
  custody check — the mitigation is that the custody section is small
  and diffable, and the pin means the human reviews gate-code deltas,
  not the whole tree. Genesis trust rests on the operator's own signed
  first pin (an agent cannot produce a VALID signature for a roster
  account, and repo admin — branch protection, App permissions —
  remains human-held). Fixture recording against staged scratch-repo
  scenarios is more work than inventing JSON; that cost is the point.
- **Supersession:** this ADR supersedes the close-laundering criterion,
  the two-tier/per-exemption acknowledgment machinery, and the
  "not evaluable until #X" meta-states of the in-flight spec text on
  PR #444. It does **not** supersede ADR 0005, whose scope decisions
  stand and whose spec-single-copy rule this ADR obeys.
- Follow-ups: the M4 implementation PRs (gate script + cores +
  fixtures; auditor; `/ship` wiring); the #649 rescope note on that
  issue; the D7 one-time disposition pass; branch-protection
  configuration for the direct-push lane; ARCHITECTURE.md reflects the
  new `connector/src/release-gate/` seam (peer verdict module, Rule 1 as broadened by ADR 0006) in the same PR as this ADR.
