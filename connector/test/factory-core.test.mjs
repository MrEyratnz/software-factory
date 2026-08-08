import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseRoadmap, indexAdrs, lintTechDebt, lintCommit, planRelease, COMMIT_TYPES,
  fingerprintFinding, techdebtAudit, extractFingerprint, roadmapCheck,
  gateEvaluate, GATE_STAGES,
} from '../src/factory-core.mjs';

/* ── parseRoadmap ──────────────────────────────────────────────────────── */

test('parseRoadmap: milestones, counts, and next unchecked item', () => {
  const md = [
    '# Roadmap',
    '## M0 — Foundation',
    '- [x] vision docs',
    '- [x] scaffold',
    '## M1 — Core',
    '- [x] first feature',
    '- [ ] second feature',
    '- [ ] third feature',
  ].join('\n');
  const r = parseRoadmap(md);
  assert.equal(r.milestones.length, 3); // "# Roadmap" heading has 0 items
  const m1 = r.milestones.find((m) => m.title.startsWith('M1'));
  assert.equal(m1.total, 3);
  assert.equal(m1.done, 1);
  assert.equal(m1.remaining, 2);
  assert.equal(m1.complete, false);
  assert.equal(r.totals.total, 5);
  assert.equal(r.totals.done, 3);
  assert.equal(r.totals.remaining, 2);
  assert.equal(r.totals.percent, 60);
  assert.deepEqual(
    { milestone: r.next.milestone, text: r.next.text },
    { milestone: 'M1 — Core', text: 'second feature' },
  );
});

test('parseRoadmap: all-done roadmap has no next and is 100%', () => {
  const md = '## M0\n- [x] a\n- [x] b\n';
  const r = parseRoadmap(md);
  assert.equal(r.next, null);
  assert.equal(r.totals.percent, 100);
  assert.equal(r.milestones[0].complete, true);
});

test('parseRoadmap: empty input is safe', () => {
  const r = parseRoadmap('');
  assert.deepEqual(r.totals, { total: 0, done: 0, remaining: 0, percent: 0 });
  assert.equal(r.next, null);
});

test('parseRoadmap: rejects non-strings', () => {
  assert.throws(() => parseRoadmap(null), TypeError);
});

/* ── indexAdrs ─────────────────────────────────────────────────────────── */

test('indexAdrs: parses number/title/status/date and next number', () => {
  const entries = [
    { filename: '0002-modular-monolith.md', content: '# ADR 0002 — Modular monolith\n\nStatus: accepted · Date: 2026-07-03\n' },
    { filename: '0001-stack.md', content: '# ADR 0001 — Stack\n\nStatus: accepted\nDate: 2026-07-03\n' },
  ];
  const r = indexAdrs(entries);
  assert.equal(r.adrs[0].number, 1); // sorted ascending
  assert.equal(r.adrs[1].number, 2);
  assert.equal(r.adrs[1].title, 'ADR 0002 — Modular monolith');
  assert.equal(r.adrs[0].status, 'accepted');
  assert.equal(r.adrs[0].date, '2026-07-03');
  assert.equal(r.nextNumber, 3);
  assert.equal(r.nextId, '0003');
});

test('indexAdrs: empty set starts at 0001', () => {
  const r = indexAdrs([]);
  assert.equal(r.nextNumber, 1);
  assert.equal(r.nextId, '0001');
});

test('indexAdrs: derives number from "# ADR N" when filename lacks one', () => {
  const r = indexAdrs([{ filename: 'decision.md', content: '# ADR 7 — Something\n' }]);
  assert.equal(r.adrs[0].number, 7);
  assert.equal(r.nextId, '0008');
});

/* ── lintTechDebt ──────────────────────────────────────────────────────── */

test('lintTechDebt: complete finding passes', () => {
  const r = lintTechDebt({
    title: 'IDOR on preview token',
    location: 'src/app/preview-token.ts:42',
    impact: 'a viewer can read another org preview; tenant isolation break',
    provenance: 'introduced',
    suggestedFix: 'scope the lookup by orgId',
  });
  assert.equal(r.ok, true);
  assert.deepEqual(r.missing, []);
  assert.equal(r.normalized.label, 'tech-debt');
});

test('lintTechDebt: reports every missing required field', () => {
  const r = lintTechDebt({ impact: 'x' });
  assert.equal(r.ok, false);
  assert.deepEqual(r.missing.sort(), ['location', 'provenance', 'suggestedFix'].sort());
});

test('lintTechDebt: warns on malformed location and bad provenance', () => {
  const r = lintTechDebt({
    location: 'somewhere', impact: 'x', provenance: 'maybe', suggestedFix: 'y', title: 't',
  });
  assert.equal(r.ok, true); // present, just shaped oddly
  assert.ok(r.warnings.some((w) => /file:line/.test(w)));
  assert.ok(r.warnings.some((w) => /pre-existing/.test(w)));
});

/* ── lintCommit ────────────────────────────────────────────────────────── */

test('lintCommit: feat → minor', () => {
  const r = lintCommit('feat(publishing): add cmi5 export');
  assert.equal(r.ok, true);
  assert.equal(r.type, 'feat');
  assert.equal(r.scope, 'publishing');
  assert.equal(r.bump, 'minor');
  assert.equal(r.breaking, false);
});

test('lintCommit: fix → patch', () => {
  assert.equal(lintCommit('fix: correct escaping').bump, 'patch');
});

test('lintCommit: bang → major', () => {
  const r = lintCommit('feat!: drop node 18');
  assert.equal(r.breaking, true);
  assert.equal(r.bump, 'major');
});

test('lintCommit: BREAKING CHANGE footer → major', () => {
  const r = lintCommit('refactor: rework api\n\nBREAKING CHANGE: removed v0 routes');
  assert.equal(r.breaking, true);
  assert.equal(r.bump, 'major');
});

test('lintCommit: chore → none', () => {
  assert.equal(lintCommit('chore: bump deps').bump, 'none');
});

test('lintCommit: malformed header fails', () => {
  const r = lintCommit('added a thing');
  assert.equal(r.ok, false);
  assert.ok(r.errors.length >= 1);
  assert.equal(r.bump, 'none');
});

test('lintCommit: unknown type is an error', () => {
  const r = lintCommit('wip: something');
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => /unknown type/.test(e)));
});

test('lintCommit: known type set is the conventional one', () => {
  assert.ok(COMMIT_TYPES.includes('feat') && COMMIT_TYPES.includes('fix'));
});

/* ── planRelease ───────────────────────────────────────────────────────── */

test('planRelease: highest bump wins; changelog grouped', () => {
  const r = planRelease(
    ['feat: a', 'fix: b', 'docs: c', 'feat: d'],
    '1.2.3',
  );
  assert.equal(r.bump, 'minor');
  assert.equal(r.nextVersion, '1.3.0');
  assert.equal(r.releaseNeeded, true);
  const feat = r.sections.find((s) => s.type === 'feat');
  assert.equal(feat.entries.length, 2);
  assert.equal(feat.title, 'Features');
});

test('planRelease: breaking → major', () => {
  const r = planRelease(['feat!: x', 'fix: y'], '2.0.1');
  assert.equal(r.bump, 'major');
  assert.equal(r.nextVersion, '3.0.0');
  assert.deepEqual(r.breaking, ['feat!: x']);
});

test('planRelease: preMajor policy demotes bumps', () => {
  // While 0.x: breaking→minor, feat→patch (matches release-please config).
  assert.equal(planRelease(['feat!: x'], '0.1.2', { preMajor: true }).nextVersion, '0.2.0');
  assert.equal(planRelease(['feat: x'], '0.1.2', { preMajor: true }).nextVersion, '0.1.3');
});

test('planRelease: no releasable commits → no release', () => {
  const r = planRelease(['docs: a', 'chore: b'], '1.0.0');
  assert.equal(r.bump, 'none');
  assert.equal(r.releaseNeeded, false);
  assert.equal(r.nextVersion, '1.0.0');
});

test('planRelease: rejects invalid version', () => {
  assert.throws(() => planRelease(['feat: a'], 'not-a-version'));
});

/* ── fingerprintFinding / techdebtAudit ────────────────────────────────── */

test('fingerprintFinding: stable, and independent of title wording', () => {
  const a = fingerprintFinding({ location: 'src/x.ts:10', impact: 'leaks memory', title: 'Leak' });
  const b = fingerprintFinding({ location: 'src/x.ts:10', impact: 'leaks memory', title: 'Memory leak!' });
  assert.equal(a, b); // title reword does not change identity
  assert.match(a, /^[0-9a-f]{8}$/);
  const c = fingerprintFinding({ location: 'src/y.ts:10', impact: 'leaks memory' });
  assert.notEqual(a, c); // different location → different fingerprint
});

test('lintTechDebt: normalized output carries a fingerprint', () => {
  const r = lintTechDebt({ location: 'a.ts:1', impact: 'x', provenance: 'introduced', suggestedFix: 'y' });
  assert.match(r.normalized.fingerprint, /^[0-9a-f]{8}$/);
});

test('extractFingerprint: from explicit field and from body marker', () => {
  assert.equal(extractFingerprint({ fingerprint: 'abcd1234' }), 'abcd1234');
  assert.equal(extractFingerprint({ body: 'blah\nfingerprint: DEADBEEF\nmore' }), 'deadbeef');
  assert.equal(extractFingerprint({ body: 'no marker here' }), null);
});

test('techdebtAudit: splits findings into filed vs missing, dedup by fingerprint', () => {
  const f1 = { location: 'a.ts:1', impact: 'bug one' };
  const f2 = { location: 'b.ts:2', impact: 'bug two' };
  const fp1 = fingerprintFinding(f1);
  const audit = techdebtAudit([f1, f2, { ...f1 }], [{ body: `fingerprint: ${fp1}` }]);
  assert.equal(audit.ok, false);
  assert.equal(audit.missing.length, 1); // only f2 missing; f1 filed; dup f1 collapsed
  assert.equal(audit.missing[0].finding.location, 'b.ts:2');
  assert.ok(audit.filed.includes(fp1));
});

test('techdebtAudit: all filed → ok', () => {
  const f = { location: 'a.ts:1', impact: 'x' };
  const audit = techdebtAudit([f], [{ fingerprint: fingerprintFinding(f) }]);
  assert.equal(audit.ok, true);
  assert.equal(audit.missing.length, 0);
});

// Regression for #471/#688: the tech-debt-clerk (an LLM) hand-derived or
// paraphrased the 8-hex fingerprint instead of copying `techdebt_lint`'s
// `normalized.fingerprint` verbatim, so filed issues carried a WRONG
// fingerprint. techdebtAudit used to treat that as an ordinary "missing"
// finding with no explanation — inviting a duplicate filing instead of a fix
// to the existing issue's trailer. It must now name the divergence loudly:
// which issue, what stale value it carries, and the exact expected value.
test('techdebtAudit: a filed issue with a WRONG (hand-derived) fingerprint is reported as mismatched, not silently missing', () => {
  const finding = { location: 'src/payments/charge.ts:88', impact: 'double-charges on retry' };
  const correctFp = fingerprintFinding(finding);

  // Simulate the clerk's old behavior: it filed an issue clearly ABOUT this
  // finding (the body names the exact location) but paraphrased/mistyped the
  // fingerprint trailer instead of copying the connector's own output.
  const staleFp = 'deadbeef';
  assert.notEqual(staleFp, correctFp);
  const openIssues = [{
    title: 'double-charge risk on retry',
    body: `Location: src/payments/charge.ts:88\nImpact: double-charges on retry\n\nfingerprint: ${staleFp}`,
  }];

  const audit = techdebtAudit([finding], openIssues);

  // Still not cleanly reconciled (the trailer really is wrong) ...
  assert.equal(audit.ok, false);
  assert.equal(audit.missing.length, 1);
  // ... but now diagnosed, not just reported as an unexplained gap.
  assert.equal(audit.mismatched.length, 1);
  const m = audit.mismatched[0];
  assert.equal(m.fingerprint, correctFp); // the exact expected value, named
  assert.ok(m.staleIssue);
  assert.equal(m.staleIssue.fingerprint, staleFp);
  assert.equal(m.staleIssue.title, 'double-charge risk on retry');
  // the same diagnostic is reachable straight off the missing entry too
  assert.deepEqual(audit.missing[0].staleIssue, m.staleIssue);
});

// Regression for #1056: findStaleIssue used an unanchored substring test, so
// an unfiled finding at "src/a.ts:1" matched a correctly-filed issue about
// "src/a.ts:10" (":1" is a substring of ":10") and got misdiagnosed as a
// stale/hand-derived duplicate of that unrelated issue — which would make
// debt-reconcile instruct the clerk to overwrite a GOOD issue's fingerprint
// trailer and never file the real finding. The location match must be
// anchored on a file:line token boundary.
test('techdebtAudit: prefix collision — unfiled finding at file.ts:1 is not mismatched against an unrelated issue about file.ts:10', () => {
  const filedFinding = { location: 'server.ts:42', impact: 'unrelated, correctly-filed bug' };
  const filedFp = fingerprintFinding(filedFinding);
  const openIssues = [{
    title: 'unrelated bug',
    body: `Location: server.ts:42\n\nfingerprint: ${filedFp}`,
  }];

  const unfiledFinding = { location: 'server.ts:4', impact: 'a completely different problem' };
  const audit = techdebtAudit([unfiledFinding], openIssues);

  assert.equal(audit.missing.length, 1);
  assert.equal(audit.mismatched.length, 0); // must be reported as plain missing, not mismatched
  assert.equal(audit.missing[0].staleIssue, null);
});

// Regression for #1056: two distinct findings at the SAME file:line (routine
// for a 3-lens panel — a line can have more than one problem) must not cause
// the unfiled one to be flagged "mismatched" against the other's correctly
// filed issue just because they share a location.
test('techdebtAudit: same-location collision — a correctly-filed sibling finding does not mark another finding at the same line as mismatched', () => {
  const findingA = { location: 'src/payments/charge.ts:88', impact: 'double-charges on retry' };
  const findingB = { location: 'src/payments/charge.ts:88', impact: 'also leaks a DB connection' };
  const fpA = fingerprintFinding(findingA);

  const openIssues = [{
    title: 'double-charge risk on retry',
    body: `Location: src/payments/charge.ts:88\nImpact: double-charges on retry\n\nfingerprint: ${fpA}`,
  }];

  const audit = techdebtAudit([findingA, findingB], openIssues);

  assert.equal(audit.missing.length, 1);
  assert.equal(audit.missing[0].finding.impact, 'also leaks a DB connection');
  assert.equal(audit.mismatched.length, 0); // B is genuinely unfiled, not a stale duplicate of A's issue
  assert.equal(audit.missing[0].staleIssue, null);
});

// A finding correctly filed with the CANONICAL fingerprint (i.e. the clerk
// followed the fixed instructions and copied techdebt_lint's output verbatim)
// must reconcile cleanly on a re-run — no mismatch flagged, no duplicate.
test('techdebtAudit: a re-run against a correctly-filed finding is clean (no mismatch, no re-file)', () => {
  const finding = { location: 'src/payments/charge.ts:88', impact: 'double-charges on retry' };
  const correctFp = fingerprintFinding(finding);
  const openIssues = [{
    title: 'double-charge risk on retry',
    body: `Location: src/payments/charge.ts:88\nImpact: double-charges on retry\n\nfingerprint: ${correctFp}`,
  }];

  const audit = techdebtAudit([finding], openIssues);

  assert.equal(audit.ok, true);
  assert.equal(audit.missing.length, 0);
  assert.equal(audit.mismatched.length, 0);
  assert.ok(audit.filed.includes(correctFp));
});

// Regression for #1183: hasLocationToken's leading boundary regex
// (?:^|[^a-z0-9_]) treats '/', '.', '-' as valid boundary characters, so a
// location that is a path/filename SUFFIX of a longer one in an open issue
// false-matches — "utils.ts:10" matches inside "test-utils.ts:10" because
// '-' is (wrongly) accepted immediately before the token.
test('techdebtAudit: filename-suffix collision — finding at utils.ts:10 is not mismatched against an issue about test-utils.ts:10', () => {
  const filedFinding = { location: 'test-utils.ts:10', impact: 'unrelated, correctly-filed bug' };
  const filedFp = fingerprintFinding(filedFinding);
  const openIssues = [{
    title: 'unrelated bug',
    body: `Location: test-utils.ts:10\n\nfingerprint: ${filedFp}`,
  }];

  const unfiledFinding = { location: 'utils.ts:10', impact: 'a completely different problem' };
  const audit = techdebtAudit([unfiledFinding], openIssues);

  assert.equal(audit.missing.length, 1);
  assert.equal(audit.mismatched.length, 0); // must be reported as plain missing, not mismatched
  assert.equal(audit.missing[0].staleIssue, null);
});

// Regression for #1183: same boundary bug, path-prefix form — "index.ts:5"
// matches inside "src/pages/index.ts:5" because '/' is (wrongly) accepted
// immediately before the token.
test('techdebtAudit: path-suffix collision — finding at index.ts:5 is not mismatched against an issue about src/pages/index.ts:5', () => {
  const filedFinding = { location: 'src/pages/index.ts:5', impact: 'unrelated, correctly-filed bug' };
  const filedFp = fingerprintFinding(filedFinding);
  const openIssues = [{
    title: 'unrelated bug',
    body: `Location: src/pages/index.ts:5\n\nfingerprint: ${filedFp}`,
  }];

  const unfiledFinding = { location: 'index.ts:5', impact: 'a completely different problem' };
  const audit = techdebtAudit([unfiledFinding], openIssues);

  assert.equal(audit.missing.length, 1);
  assert.equal(audit.mismatched.length, 0); // must be reported as plain missing, not mismatched
  assert.equal(audit.missing[0].staleIssue, null);
});

// Regression for #1184: siblingFps is built only from THIS session's
// findings (list.map(fingerprintFinding)), so findStaleIssue's guard only
// protects against same-session collisions. A genuinely different finding
// filed at the same file:line by a PRIOR session (correctly, with the
// correct fingerprint for ITS OWN finding) must not be misdiagnosed as a
// stale/hand-derived duplicate of THIS session's unrelated finding just
// because they share a location — location co-location alone is not proof
// of "same finding, wrong fingerprint".
test('techdebtAudit: cross-session same-location — a genuinely different finding is not mismatched against a correctly-filed PRIOR finding at the same location', () => {
  const priorFinding = { location: 'src/payments/charge.ts:88', impact: 'double-charge on retry' };
  const priorFp = fingerprintFinding(priorFinding);
  const openIssues = [{
    title: 'double-charge risk on retry',
    body: `Location: src/payments/charge.ts:88\nImpact: double-charge on retry\n\nfingerprint: ${priorFp}`,
  }];

  // This session sees ONLY the new, different finding at the same line — the
  // prior finding is not in `list` (a different, earlier session filed it),
  // so the same-session siblingFps guard alone cannot protect this case.
  const newFinding = { location: 'src/payments/charge.ts:88', impact: 'leaks a DB connection' };
  const audit = techdebtAudit([newFinding], openIssues);

  assert.equal(audit.missing.length, 1);
  assert.equal(audit.missing[0].finding.impact, 'leaks a DB connection');
  assert.equal(audit.mismatched.length, 0); // must remain plain missing, not misdiagnosed as mismatched
  assert.equal(audit.missing[0].staleIssue, null);
});

/* ── roadmapCheck ──────────────────────────────────────────────────────── */

test('roadmapCheck: refuses without a merged-green SHA proof', () => {
  const r = roadmapCheck('build the thing', {});
  assert.equal(r.mayFlip, false);
  assert.match(r.reason, /no merged-green/i);
});

test('roadmapCheck: allows only an item-bound proof that matches', () => {
  const sha = 'a1b2c3d4e5f6';
  // Fail closed: a proof with no item binding is a reusable skeleton key.
  assert.equal(roadmapCheck('item x', { mergedGreenSha: sha }).mayFlip, false);
  assert.equal(roadmapCheck('item x', { mergedGreenSha: sha, item: 'item x' }).mayFlip, true);
  assert.equal(roadmapCheck('item x', { mergedGreenSha: sha, item: 'item y' }).mayFlip, false);
});

/* ── gateEvaluate ──────────────────────────────────────────────────────── */

test('gateEvaluate: all stages green with a tree hash → green receipt', () => {
  const r = gateEvaluate(
    [{ name: 'typecheck', exitCode: 0 }, { name: 'unit', ok: true }],
    'deadbeefcafe',
  );
  assert.equal(r.ok, true);
  assert.deepEqual(r.failed, []);
  assert.equal(r.receipt.tree, 'deadbeefcafe');
  assert.equal(r.receipt.ok, true);
});

test('gateEvaluate: any failing stage → red, names the failures', () => {
  const r = gateEvaluate(
    [{ name: 'typecheck', exitCode: 0 }, { name: 'unit', exitCode: 1 }],
    'abc123',
  );
  assert.equal(r.ok, false);
  assert.deepEqual(r.failed, ['unit']);
});

test('gateEvaluate: no tree hash is never green (unverifiable receipt)', () => {
  const r = gateEvaluate([{ name: 'unit', ok: true }], '');
  assert.equal(r.ok, false);
  assert.equal(r.receipt.tree, null);
});

test('gateEvaluate: empty stage list is not green', () => {
  assert.equal(gateEvaluate([], 'abc').ok, false);
});

test('GATE_STAGES lists the canonical pipeline order', () => {
  assert.deepEqual(GATE_STAGES, ['typecheck', 'boundaries', 'unit', 'bdd', 'build', 'drift']);
});

/* ── bug-hunt regressions ─────────────────────────────────────────────── */

test('parseRoadmap: headings/checkboxes inside a fenced code block are ignored', () => {
  const md = [
    '## M0',
    '- [x] real done',
    '',
    '```markdown',
    '## Example milestone',
    '- [ ] example item in a fence',
    '```',
    '',
    '## M1',
    '- [ ] real next',
  ].join('\n');
  const r = parseRoadmap(md);
  // Only the two real milestones (M0, M1), not the fenced "Example milestone".
  assert.deepEqual(r.milestones.map((m) => m.title), ['M0', 'M1']);
  assert.equal(r.totals.total, 2); // one real done + one real todo, fence excluded
  assert.equal(r.next.text, 'real next');
});

test('parseRoadmap: ~~~ fences are also honored', () => {
  const md = ['## M0', '~~~', '- [ ] fenced', '~~~', '- [ ] real'].join('\n');
  const r = parseRoadmap(md);
  assert.equal(r.totals.total, 1);
  assert.equal(r.next.text, 'real');
});

test('indexAdrs: number anchored to a leading prefix, not any digit run', () => {
  const r = indexAdrs([
    { filename: '0001-stack.md', content: '# ADR 0001' },
    { filename: 'use-http2-push.md', content: '# Use HTTP/2 push' }, // embedded digit, not a number
    { filename: '2024-01-15-use-postgres.md', content: '# Use Postgres' }, // date prefix, not a number
  ]);
  const byName = Object.fromEntries(r.adrs.map((a) => [a.filename, a.number]));
  assert.equal(byName['0001-stack.md'], 1);
  assert.equal(byName['use-http2-push.md'], 0);      // NOT 2
  assert.equal(byName['2024-01-15-use-postgres.md'], 0); // NOT 2024
  assert.equal(r.nextNumber, 2); // max real number (1) + 1, not 2025
});

test('lintCommit: a CRLF-authored header is still valid', () => {
  const r = lintCommit('feat: add thing\r\n\r\nbody\r\n');
  assert.equal(r.ok, true);
  assert.equal(r.type, 'feat');
  assert.equal(r.subject, 'add thing');
});

test('lintCommit: a lowercase "breaking change:" prose line is NOT a breaking change', () => {
  const r = lintCommit('docs: notes\n\nBreaking change: none — internal only');
  assert.equal(r.breaking, false);
  assert.equal(r.bump, 'none');
});

test('lintCommit: an uppercase BREAKING CHANGE: footer still bumps major', () => {
  const r = lintCommit('feat: x\n\nBREAKING CHANGE: drops the old API');
  assert.equal(r.breaking, true);
  assert.equal(r.bump, 'major');
});

test('gateEvaluate: exit code is authoritative when present', () => {
  // stringified "0" reads as pass
  assert.equal(gateEvaluate([{ name: 'unit', exitCode: '0' }], 'abc').ok, true);
  // ok:true cannot override a failing exit code
  assert.equal(gateEvaluate([{ name: 'unit', ok: true, exitCode: 1 }], 'abc').ok, false);
  // an explicit ok:false is not masked by a passing exit code
  assert.equal(gateEvaluate([{ name: 'unit', ok: false, exitCode: 0 }], 'abc').ok, false);
  // ok flag still used when there is no exit code
  assert.equal(gateEvaluate([{ name: 'unit', ok: true }], 'abc').ok, true);
});

test('extractFingerprint: an explicit uppercase-hex fingerprint is normalized', () => {
  assert.equal(extractFingerprint({ fingerprint: 'DEADBEEF' }), 'deadbeef');
  assert.equal(extractFingerprint({ body: 'fingerprint: DEADBEEF' }), 'deadbeef');
  // and the two forms now agree, so a filed issue dedupes against a finding
  const finding = { location: 'src/a.ts:1', impact: 'x' };
  const fp = fingerprintFinding(finding);
  const audit = techdebtAudit([finding], [{ title: 't', fingerprint: fp.toUpperCase() }]);
  assert.equal(audit.ok, true); // recognized as already filed despite uppercase
});
