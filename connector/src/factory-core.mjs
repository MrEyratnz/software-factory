/**
 * factory-core — the pure, deterministic rule engine of the Dark Software
 * Factory connector.
 *
 * Every export here is a pure function: string / plain-object in, plain-object
 * out, no I/O, no clock, no randomness. That is deliberate — these functions
 * encode the *rules* of the factory (the ones course-creator followed by hand),
 * so they must be trivially unit-testable and give byte-identical results for
 * identical input. All filesystem access lives in the MCP server
 * (`server.mjs`); this module never touches disk.
 *
 * The rules implemented, each traceable to a course-creator practice:
 *   - parseRoadmap    → the milestone/checkbox roadmap worked top-to-bottom
 *   - indexAdrs       → numbered ADRs (Status/Context/Decision/Consequences)
 *   - lintTechDebt    → the review→tech-debt convention (course-creator CLAUDE.md)
 *   - lintCommit      → Conventional Commits (feat→minor, fix→patch, !→major)
 *   - planRelease     → release-please-style version bump + changelog grouping
 */

/* ────────────────────────────────────────────────────────────────────────
 * 1. Roadmap — parse milestones and their checkbox items; find the next item.
 *    Mirrors docs/ROADMAP.md: "## M0 — Foundation" headings over "- [x]"/"- [ ]"
 *    task lines, worked top-to-bottom, an item checked only when merged green.
 * ──────────────────────────────────────────────────────────────────────── */

const HEADING_RE = /^(#{1,6})\s+(.*\S)\s*$/;
const CHECKBOX_RE = /^\s*[-*]\s+\[([ xX])\]\s+(.*\S)\s*$/;

/**
 * @param {string} markdown  raw ROADMAP.md contents
 * @returns {{
 *   milestones: Array<{title:string, level:number, total:number, done:number,
 *                      remaining:number, complete:boolean,
 *                      items:Array<{done:boolean, text:string, line:number}>}>,
 *   totals: {total:number, done:number, remaining:number, percent:number},
 *   next: {milestone:string, text:string, line:number}|null
 * }}
 */
export function parseRoadmap(markdown) {
  if (typeof markdown !== 'string') {
    throw new TypeError('parseRoadmap expects a string');
  }
  const lines = markdown.split('\n');
  const milestones = [];
  let current = null;
  let next = null;

  lines.forEach((raw, i) => {
    const heading = raw.match(HEADING_RE);
    if (heading) {
      current = {
        title: heading[2],
        level: heading[1].length,
        total: 0,
        done: 0,
        remaining: 0,
        complete: true,
        items: [],
      };
      milestones.push(current);
      return;
    }
    const box = raw.match(CHECKBOX_RE);
    if (box) {
      const done = box[1].toLowerCase() === 'x';
      const item = { done, text: box[2], line: i + 1 };
      // Items before any heading attach to a synthetic "(top)" bucket.
      if (!current) {
        current = {
          title: '(top)',
          level: 0,
          total: 0,
          done: 0,
          remaining: 0,
          complete: true,
          items: [],
        };
        milestones.push(current);
      }
      current.items.push(item);
      current.total += 1;
      if (done) current.done += 1;
      else {
        current.remaining += 1;
        current.complete = false;
        if (!next) next = { milestone: current.title, text: item.text, line: i + 1 };
      }
    }
  });

  const total = milestones.reduce((n, m) => n + m.total, 0);
  const done = milestones.reduce((n, m) => n + m.done, 0);
  const remaining = total - done;
  const percent = total === 0 ? 0 : Math.round((done / total) * 1000) / 10;

  return { milestones, totals: { total, done, remaining, percent }, next };
}

/* ────────────────────────────────────────────────────────────────────────
 * 2. ADR index — parse a set of ADR files, sort by number, compute the next
 *    ADR number. Mirrors docs/adr/NNNN-title.md with a Status: line.
 * ──────────────────────────────────────────────────────────────────────── */

/**
 * @param {Array<{filename:string, content:string}>} entries
 * @returns {{adrs:Array<{number:number, id:string, title:string,
 *            status:string|null, date:string|null, filename:string}>,
 *            nextNumber:number, nextId:string}}
 */
export function indexAdrs(entries) {
  if (!Array.isArray(entries)) throw new TypeError('indexAdrs expects an array');
  const adrs = entries.map((e) => {
    const filename = String(e?.filename ?? '');
    const content = String(e?.content ?? '');
    // Number: prefer the leading NNNN in the filename, else "# ADR NNNN".
    let number = null;
    const fnMatch = filename.match(/(\d{1,4})/);
    if (fnMatch) number = parseInt(fnMatch[1], 10);
    const titleLine = content.split('\n').find((l) => /^#\s+/.test(l)) ?? '';
    const title = titleLine.replace(/^#\s+/, '').trim();
    if (number === null) {
      const inTitle = title.match(/ADR\s+(\d{1,4})/i);
      if (inTitle) number = parseInt(inTitle[1], 10);
    }
    const statusMatch = content.match(/^\s*Status:\s*(.+?)\s*$/im);
    const dateMatch = content.match(/Date:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})/i);
    return {
      number: number ?? 0,
      id: number === null ? '????' : String(number).padStart(4, '0'),
      title,
      status: statusMatch ? statusMatch[1].split('·')[0].trim() : null,
      date: dateMatch ? dateMatch[1] : null,
      filename,
    };
  });
  adrs.sort((a, b) => a.number - b.number);
  const maxNumber = adrs.reduce((m, a) => Math.max(m, a.number), 0);
  const nextNumber = maxNumber + 1;
  return { adrs, nextNumber, nextId: String(nextNumber).padStart(4, '0') };
}

/* ────────────────────────────────────────────────────────────────────────
 * 3. Tech-debt lint — enforce the course-creator review→tech-debt convention:
 *    a deferred finding must carry location (file:line), impact (what & why),
 *    provenance (pre-existing | introduced), and a suggested fix.
 * ──────────────────────────────────────────────────────────────────────── */

const PROVENANCE = new Set(['pre-existing', 'introduced']);

/**
 * Deterministic 32-bit FNV-1a hash → 8 hex chars. Zero-dependency and stable
 * across runs/machines, so a finding always fingerprints to the same value.
 */
function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

const norm = (s) => String(s ?? '').trim().toLowerCase().replace(/\s+/g, ' ');

/**
 * A finding's identity is its location + the invariant substance of the
 * problem (impact), NOT its wording of a title (which a re-review may reword).
 * That keeps the fingerprint stable so the same defect never double-files.
 * @param {{location?:string, impact?:string, title?:string}} finding
 * @returns {string} 8-hex fingerprint
 */
export function fingerprintFinding(finding) {
  const f = finding && typeof finding === 'object' ? finding : {};
  const key = `${norm(f.location)}|${norm(f.impact) || norm(f.title)}`;
  return fnv1a(key);
}

/**
 * @param {{location?:string, impact?:string, provenance?:string,
 *          suggestedFix?:string, title?:string}} finding
 * @returns {{ok:boolean, missing:string[], warnings:string[], normalized:object}}
 */
export function lintTechDebt(finding) {
  const f = finding && typeof finding === 'object' ? finding : {};
  const missing = [];
  const warnings = [];

  const has = (v) => typeof v === 'string' && v.trim().length > 0;
  if (!has(f.location)) missing.push('location');
  else if (!/[^\s:]+:\d+/.test(f.location)) {
    warnings.push('location should be "file:line" (e.g. src/app/server.ts:42)');
  }
  if (!has(f.impact)) missing.push('impact');
  if (!has(f.provenance)) missing.push('provenance');
  else if (!PROVENANCE.has(String(f.provenance).trim().toLowerCase())) {
    warnings.push('provenance should be "pre-existing" or "introduced"');
  }
  if (!has(f.suggestedFix)) missing.push('suggestedFix');
  if (!has(f.title)) warnings.push('a short title helps the issue be findable');

  return {
    ok: missing.length === 0,
    missing,
    warnings,
    normalized: {
      title: has(f.title) ? f.title.trim() : '',
      location: has(f.location) ? f.location.trim() : '',
      impact: has(f.impact) ? f.impact.trim() : '',
      provenance: has(f.provenance) ? String(f.provenance).trim().toLowerCase() : '',
      suggestedFix: has(f.suggestedFix) ? f.suggestedFix.trim() : '',
      label: 'tech-debt',
      fingerprint: fingerprintFinding(f),
    },
  };
}

/* ────────────────────────────────────────────────────────────────────────
 * 3b. Tech-debt audit — the idempotency spine of the review→tech-debt
 *     convention. Given this session's findings and the currently-open
 *     tech-debt issues, return which are already filed and which are missing.
 *     Pure set-diff by fingerprint — powers the Stop debt-reconcile hook so a
 *     finding is never dropped and never double-filed.
 * ──────────────────────────────────────────────────────────────────────── */

/** Pull a fingerprint out of an issue (explicit field or a body/title marker). */
export function extractFingerprint(issue) {
  const i = issue && typeof issue === 'object' ? issue : {};
  if (typeof i.fingerprint === 'string' && /^[0-9a-f]{8}$/.test(i.fingerprint)) {
    return i.fingerprint;
  }
  const hay = `${i.title ?? ''}\n${i.body ?? ''}`;
  const m = hay.match(/fingerprint:\s*([0-9a-f]{8})/i);
  return m ? m[1].toLowerCase() : null;
}

/**
 * @param {Array<object>} findings  this session's review findings
 * @param {Array<{title?:string, body?:string, fingerprint?:string}>} openIssues
 * @returns {{filed:string[], missing:Array<{fingerprint:string, finding:object}>,
 *            all:Array<{fingerprint:string, filed:boolean}>, ok:boolean}}
 */
export function techdebtAudit(findings, openIssues) {
  const list = Array.isArray(findings) ? findings : [];
  const issues = Array.isArray(openIssues) ? openIssues : [];
  const filedSet = new Set(issues.map(extractFingerprint).filter(Boolean));

  const all = [];
  const missing = [];
  const seen = new Set();
  for (const finding of list) {
    const fp = fingerprintFinding(finding);
    const isFiled = filedSet.has(fp);
    if (!seen.has(fp)) {
      all.push({ fingerprint: fp, filed: isFiled });
      seen.add(fp);
      if (!isFiled) missing.push({ fingerprint: fp, finding });
    }
  }
  return {
    filed: [...filedSet],
    missing,
    all,
    ok: missing.length === 0,
  };
}

/* ────────────────────────────────────────────────────────────────────────
 * 3c. Roadmap check — a `- [ ]` → `- [x]` flip is honest only with proof the
 *     item's work merged green. This pure verdict refuses the flip without a
 *     merged-green SHA proof (which comes from CI, never the local tree). The
 *     actual file write is done by the command layer using this verdict.
 * ──────────────────────────────────────────────────────────────────────── */

/**
 * @param {string} item  roadmap item text being checked off
 * @param {{mergedGreenSha?:string, item?:string}} proof
 * @returns {{mayFlip:boolean, reason:string, sha:string|null}}
 */
export function roadmapCheck(item, proof) {
  const p = proof && typeof proof === 'object' ? proof : {};
  const sha = typeof p.mergedGreenSha === 'string' && /^[0-9a-f]{7,40}$/.test(p.mergedGreenSha)
    ? p.mergedGreenSha
    : null;
  if (!sha) {
    return { mayFlip: false, reason: 'no merged-green SHA proof for this item', sha: null };
  }
  if (p.item && norm(p.item) !== norm(item)) {
    return { mayFlip: false, reason: 'proof is for a different item', sha };
  }
  return { mayFlip: true, reason: 'merged-green proof present', sha };
}

/* ────────────────────────────────────────────────────────────────────────
 * 3d. Gate evaluate — the operational definition of "green". Given per-stage
 *     suite results and the `git write-tree` hash of the tested tree, return
 *     the verdict and the receipt the commit gate later verifies. Binding the
 *     receipt to the tree hash (not a timestamp) means any later source edit
 *     changes the tree and silently invalidates the receipt.
 * ──────────────────────────────────────────────────────────────────────── */

/** Canonical order of the green pipeline (informational; missing stages are ok). */
export const GATE_STAGES = ['typecheck', 'boundaries', 'unit', 'bdd', 'build', 'drift'];

/**
 * @param {Array<{name:string, ok?:boolean, exitCode?:number}>} stages
 * @param {string} treeHash  output of `git write-tree`
 * @returns {{ok:boolean, failed:string[], stages:Array<{name:string, ok:boolean}>,
 *            receipt:{tree:string|null, ok:boolean,
 *                     stages:Array<{name:string, ok:boolean}>}}}
 */
export function gateEvaluate(stages, treeHash) {
  const norml = (Array.isArray(stages) ? stages : []).map((s) => ({
    name: String(s?.name ?? '').trim(),
    ok: s?.ok === true || s?.exitCode === 0,
  }));
  const failed = norml.filter((s) => !s.ok).map((s) => s.name);
  const tree = typeof treeHash === 'string' && treeHash.trim() ? treeHash.trim() : null;
  // A receipt with no tree hash is unverifiable → never "green".
  const ok = failed.length === 0 && norml.length > 0 && tree !== null;
  return { ok, failed, stages: norml, receipt: { tree, ok, stages: norml } };
}

/* ────────────────────────────────────────────────────────────────────────
 * 4. Conventional Commit lint — the release-gating contract. Parses the
 *    header, detects breaking changes, and maps to a semver bump.
 * ──────────────────────────────────────────────────────────────────────── */

export const COMMIT_TYPES = [
  'feat', 'fix', 'docs', 'style', 'refactor', 'perf',
  'test', 'build', 'ci', 'chore', 'revert',
];

const HEADER_RE = /^(?<type>[a-z]+)(?:\((?<scope>[^)]+)\))?(?<bang>!)?: (?<subject>.+)$/;

/**
 * @param {string} message  full commit message (header + optional body/footer)
 * @param {{maxHeader?:number}} [opts]
 * @returns {{ok:boolean, type:string|null, scope:string|null, breaking:boolean,
 *            subject:string|null, bump:'major'|'minor'|'patch'|'none',
 *            errors:string[], warnings:string[]}}
 */
export function lintCommit(message, opts = {}) {
  const maxHeader = opts.maxHeader ?? 100;
  const text = String(message ?? '');
  const header = text.split('\n', 1)[0] ?? '';
  const errors = [];
  const warnings = [];

  const m = header.match(HEADER_RE);
  if (!m) {
    errors.push(
      'header must match "type(scope)?!?: subject" (Conventional Commits)',
    );
    return { ok: false, type: null, scope: null, breaking: false, subject: null, bump: 'none', errors, warnings };
  }
  const { type, scope, bang, subject } = m.groups;
  if (!COMMIT_TYPES.includes(type)) {
    errors.push(`unknown type "${type}" (allowed: ${COMMIT_TYPES.join(', ')})`);
  }
  if (header.length > maxHeader) {
    warnings.push(`header is ${header.length} chars (soft limit ${maxHeader})`);
  }
  if (/[.]$/.test(subject)) warnings.push('subject should not end with a period');
  if (/^[A-Z]/.test(subject)) warnings.push('subject should start lower-case');

  // Breaking = "!" in header OR a "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer.
  const breakingFooter = /^BREAKING[ -]CHANGE:/im.test(text);
  const breaking = Boolean(bang) || breakingFooter;

  let bump = 'none';
  if (breaking) bump = 'major';
  else if (type === 'feat') bump = 'minor';
  else if (type === 'fix') bump = 'patch';

  return {
    ok: errors.length === 0,
    type,
    scope: scope ?? null,
    breaking,
    subject,
    bump,
    errors,
    warnings,
  };
}

/* ────────────────────────────────────────────────────────────────────────
 * 5. Release plan — given commit subjects and the current version, compute the
 *    next version and a grouped changelog. Pure re-implementation of the slice
 *    of release-please the factory relies on (ADR/README: feat→minor,
 *    fix→patch, !→major; gated so a release is never cut from red code — that
 *    gate lives in CI, this only computes the plan).
 * ──────────────────────────────────────────────────────────────────────── */

const BUMP_RANK = { none: 0, patch: 1, minor: 2, major: 3 };
const SECTION_TITLES = {
  feat: 'Features',
  fix: 'Bug Fixes',
  perf: 'Performance Improvements',
  revert: 'Reverts',
  docs: 'Documentation',
  refactor: 'Code Refactoring',
  build: 'Build System',
  ci: 'Continuous Integration',
  test: 'Tests',
  style: 'Styles',
  chore: 'Chores',
};

function parseSemver(v) {
  const m = String(v ?? '').trim().replace(/^v/, '').match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!m) throw new Error(`invalid semver: "${v}"`);
  return { major: +m[1], minor: +m[2], patch: +m[3] };
}

/**
 * @param {string[]|Array<{subject:string}>} commits
 * @param {string} currentVersion  e.g. "0.1.2"
 * @param {{preMajor?:boolean}} [opts]  preMajor mirrors course-creator's
 *   release-please config (bump-minor-pre-major + bump-patch-for-minor-pre-major):
 *   while major===0, a breaking change bumps minor and a feature bumps patch.
 * @returns {{currentVersion:string, nextVersion:string,
 *            bump:'major'|'minor'|'patch'|'none', releaseNeeded:boolean,
 *            sections:Array<{type:string, title:string, entries:string[]}>,
 *            breaking:string[]}}
 */
export function planRelease(commits, currentVersion, opts = {}) {
  const list = (Array.isArray(commits) ? commits : []).map((c) =>
    typeof c === 'string' ? c : String(c?.subject ?? ''),
  );
  const cur = parseSemver(currentVersion);
  const preMajor = opts.preMajor ?? false;

  let highest = 'none';
  const sections = new Map();
  const breaking = [];

  for (const subject of list) {
    const parsed = lintCommit(subject);
    if (!parsed.type) continue;
    if (BUMP_RANK[parsed.bump] > BUMP_RANK[highest]) highest = parsed.bump;
    if (parsed.breaking) breaking.push(subject);
    const arr = sections.get(parsed.type) ?? [];
    arr.push(subject);
    sections.set(parsed.type, arr);
  }

  // Effective bump, honoring the pre-1.0 policy.
  let effective = highest;
  if (preMajor && cur.major === 0) {
    if (highest === 'major') effective = 'minor';
    else if (highest === 'minor') effective = 'patch';
  }

  const next = { ...cur };
  if (effective === 'major') { next.major += 1; next.minor = 0; next.patch = 0; }
  else if (effective === 'minor') { next.minor += 1; next.patch = 0; }
  else if (effective === 'patch') { next.patch += 1; }

  // Emit sections in a stable, conventional order.
  const ordered = Object.keys(SECTION_TITLES)
    .filter((t) => sections.has(t))
    .map((t) => ({ type: t, title: SECTION_TITLES[t], entries: sections.get(t) }));

  return {
    currentVersion: `${cur.major}.${cur.minor}.${cur.patch}`,
    nextVersion: `${next.major}.${next.minor}.${next.patch}`,
    bump: effective,
    releaseNeeded: effective !== 'none',
    sections: ordered,
    breaking,
  };
}
