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
