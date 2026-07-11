#!/usr/bin/env node
// validate-config — a zero-dependency structural validator for a populated
// .factory/config.json against schemas/factory.config.schema.json (issue #80).
//
// Why this exists: a malformed-JSON config now fails the hooks closed at runtime
// (issue #65's require_config_sane), but a *structurally* invalid but parseable
// one (a dropped required key, a `gates.build` that became a number) silently
// degrades to the built-in defaults per key — there was no automated backstop.
// CI (validate.yml) runs this so a structural drift in the committed config
// fails the build, making CI the authoritative structural boundary the
// factory-config skill can point at.
//
// Scope: implements the JSON-Schema draft-07 subset the factory schema actually
// uses — type (object/string/integer/number/boolean/array), required, enum,
// properties, additionalProperties:false, items, minimum, and integer-ness.
// Annotation keywords (default/description/title/$schema/$id) are ignored. Not a
// general-purpose validator; kept deliberately small and dependency-free
// (matching the repo's "no runtime deps, hand-rolled JSON logic" rule) so it can
// run anywhere node runs, with no install step.
//
// Usage: node scripts/validate-config.mjs <config.json> <schema.json>
//   exit 0 + "ok  <config>" when valid; exit 1 + one error per line otherwise.
import { readFileSync } from 'node:fs';

// validate(value, schema, path, errors) — accumulate human-readable errors.
export function validate(value, schema, path = '$', errors = []) {
  if (schema == null || typeof schema !== 'object') return errors;

  // type
  if (schema.type) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => typeMatches(value, t))) {
      errors.push(`${path}: expected type ${types.join('|')}, got ${jsonType(value)}`);
      return errors; // further checks assume the type held
    }
  }

  // enum
  if (Array.isArray(schema.enum) && !schema.enum.some((e) => deepEqual(e, value))) {
    errors.push(`${path}: ${JSON.stringify(value)} is not one of ${JSON.stringify(schema.enum)}`);
  }

  // number/integer bounds
  if (typeof value === 'number') {
    if (schema.type === 'integer' && !Number.isInteger(value)) {
      errors.push(`${path}: expected an integer, got ${value}`);
    }
    if (typeof schema.minimum === 'number' && value < schema.minimum) {
      errors.push(`${path}: ${value} is below the minimum ${schema.minimum}`);
    }
  }

  // object
  if (jsonType(value) === 'object' && (schema.properties || schema.required || schema.additionalProperties === false)) {
    for (const key of schema.required || []) {
      if (!(key in value)) errors.push(`${path}: missing required property "${key}"`);
    }
    const props = schema.properties || {};
    for (const [key, val] of Object.entries(value)) {
      if (props[key]) validate(val, props[key], `${path}.${key}`, errors);
      else if (schema.additionalProperties === false) {
        errors.push(`${path}: unexpected property "${key}" (additionalProperties is false)`);
      }
    }
  }

  // array
  if (Array.isArray(value) && schema.items) {
    value.forEach((item, i) => validate(item, schema.items, `${path}[${i}]`, errors));
  }

  return errors;
}

function jsonType(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  if (Number.isInteger(v)) return 'integer'; // report the most specific type
  return typeof v;
}

function typeMatches(v, t) {
  switch (t) {
    case 'object': return jsonType(v) === 'object';
    case 'array': return Array.isArray(v);
    case 'string': return typeof v === 'string';
    case 'boolean': return typeof v === 'boolean';
    case 'integer': return typeof v === 'number' && Number.isInteger(v);
    case 'number': return typeof v === 'number';
    case 'null': return v === null;
    default: return true;
  }
}

function deepEqual(a, b) {
  return a === b || JSON.stringify(a) === JSON.stringify(b);
}

// CLI entry — only when run directly, not when imported by the test.
const invokedDirectly = process.argv[1] && process.argv[1].endsWith('validate-config.mjs');
if (invokedDirectly) {
  const [configPath, schemaPath] = process.argv.slice(2);
  if (!configPath || !schemaPath) {
    process.stderr.write('usage: validate-config.mjs <config.json> <schema.json>\n');
    process.exit(2);
  }
  let config; let schema;
  try { config = JSON.parse(readFileSync(configPath, 'utf8')); }
  catch (e) { process.stderr.write(`${configPath}: not valid JSON — ${e.message}\n`); process.exit(1); }
  try { schema = JSON.parse(readFileSync(schemaPath, 'utf8')); }
  catch (e) { process.stderr.write(`${schemaPath}: not valid JSON — ${e.message}\n`); process.exit(1); }
  const errors = validate(config, schema);
  if (errors.length) {
    process.stderr.write(`${configPath}: does not match ${schemaPath}\n`);
    for (const e of errors) process.stderr.write(`  - ${e}\n`);
    process.exit(1);
  }
  process.stdout.write(`ok  ${configPath}\n`);
}
