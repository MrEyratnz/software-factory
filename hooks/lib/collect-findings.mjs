#!/usr/bin/env node
// Collect unresolved review findings from .factory/review/*.json into one JSON
// array. A finding is "unresolved" unless it is explicitly marked fixed
// (status:"fixed"). Files may hold a bare array, a {findings:[…]} object, or a
// single finding object. Malformed files are skipped, never fatal.
import fs from 'node:fs';
import path from 'node:path';
const dir = process.env.REVIEW_DIR || '';
const out = [];
try {
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.json')) continue;
    let data;
    try { data = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); } catch { continue; }
    const arr = Array.isArray(data) ? data : (Array.isArray(data.findings) ? data.findings : [data]);
    for (const x of arr) {
      if (x && typeof x === 'object' && x.status !== 'fixed') out.push(x);
    }
  }
} catch { /* no review dir */ }
process.stdout.write(JSON.stringify(out));
