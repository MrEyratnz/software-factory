#!/usr/bin/env node
// Collect unresolved review findings from .factory/review/*.json into one JSON
// array. A finding is "unresolved" unless it is explicitly marked fixed
// (status:"fixed"). Files may hold a bare array, a {findings:[…]} object, or a
// single finding object. Malformed files are skipped, never fatal.
import fs from 'node:fs';
import path from 'node:path';
const dir = process.env.REVIEW_DIR || '';
const out = [];
const FINDING_FIELDS = ['location', 'impact', 'severity', 'title', 'suggestedFix'];
try {
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.json')) continue;
    let data;
    try { data = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); } catch { continue; }
    // Guard the shape: a file whose content is literally `null` (or a number,
    // string, …) parses fine but has no `.findings`; the old `data.findings`
    // access threw and the OUTER catch aborted the whole scan, silently dropping
    // every finding in files read AFTER it. Resolve to [] for non-objects.
    const arr = Array.isArray(data)
      ? data
      : (data && typeof data === 'object' && Array.isArray(data.findings)
        ? data.findings
        : (data && typeof data === 'object' ? [data] : []));
    for (const x of arr) {
      if (!x || typeof x !== 'object' || Array.isArray(x)) continue;
      if (x.clean === true) continue;    // honest empty-review sentinel — not a finding
      if (x.status === 'fixed') continue;
      // Must actually look like a fileable finding; a stray/clean object with no
      // finding fields must not be counted as unfixed debt (it would block Stop).
      if (!FINDING_FIELDS.some((k) => typeof x[k] === 'string' && x[k].trim())) continue;
      out.push(x);
    }
  }
} catch { /* no review dir */ }
process.stdout.write(JSON.stringify(out));
