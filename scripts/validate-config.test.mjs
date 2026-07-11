// Tests for scripts/validate-config.mjs — the zero-dep structural validator
// (issue #80). Run: node --test scripts/validate-config.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { validate } from './validate-config.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const schema = JSON.parse(readFileSync(join(ROOT, 'schemas/factory.config.schema.json'), 'utf8'));

// A minimal config that satisfies the schema's required keys.
const base = () => ({
  stack: 'node',
  roadmapPath: 'docs/ROADMAP.md',
  releaseBranch: 'main',
  gates: { unit: 'npm test' },
});

test("this repo's own committed .factory/config.json validates", () => {
  const cfg = JSON.parse(readFileSync(join(ROOT, '.factory/config.json'), 'utf8'));
  assert.deepEqual(validate(cfg, schema), []);
});

test('all three stack templates would validate (well-formed baseline)', () => {
  assert.deepEqual(validate(base(), schema), []);
});

test('a missing required key is reported', () => {
  const cfg = base();
  delete cfg.gates;
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('missing required property "gates"')), errs.join('\n'));
});

test('a gates.* command that is not a string is reported', () => {
  const cfg = base();
  cfg.gates = { build: 123 };
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('$.gates.build') && e.includes('string')), errs.join('\n'));
});

test('an out-of-enum stack is reported', () => {
  const cfg = base();
  cfg.stack = 'rust';
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('$.stack') && e.includes('not one of')), errs.join('\n'));
});

test('an unexpected top-level property is reported (additionalProperties:false)', () => {
  const cfg = base();
  cfg.notAKey = true;
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('unexpected property "notAKey"')), errs.join('\n'));
});

test('maxIterations below the minimum is reported', () => {
  const cfg = base();
  cfg.maxIterations = 0;
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('$.maxIterations') && e.includes('minimum')), errs.join('\n'));
});

test('a non-integer maxIterations is reported', () => {
  const cfg = base();
  cfg.maxIterations = 2.5;
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('$.maxIterations')), errs.join('\n'));
});

test('a generators[] entry missing a required key is reported with its index', () => {
  const cfg = base();
  cfg.generators = [{ sourceRegex: '^x$', command: 'build' }]; // missing "output"
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('$.generators[0]') && e.includes('output')), errs.join('\n'));
});

test('an unknown enforcement toggle is reported (nested additionalProperties:false)', () => {
  const cfg = base();
  cfg.enforcement = { requireGreenReceiptOnCommit: true, bogusToggle: false };
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('$.enforcement') && e.includes('bogusToggle')), errs.join('\n'));
});

test('a boolean enforcement toggle given a string is reported', () => {
  const cfg = base();
  cfg.enforcement = { requireTestsFirst: 'yes' };
  const errs = validate(cfg, schema);
  assert.ok(errs.some((e) => e.includes('$.enforcement.requireTestsFirst') && e.includes('boolean')), errs.join('\n'));
});
