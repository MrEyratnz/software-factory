#!/usr/bin/env node
// Read a bash command string on stdin; emit JSON classifying any WRITE-TARGET
// path a redirect (`>`, `>>`) or `tee` would create, resolved against the
// command's effective working directory:
//   { "outside":   [abs, …],   // resolves OUTSIDE the project tree (issue #31)
//     "trustRoot": [abs, …] }  // resolves INTO a .factory trust root (issue #3/#14)
//
// This gives guard-bash-writes the Bash-side equivalent of guard-scope's editor
// "no writes outside the project directory" rule, and closes the `cd <dir> &&
// > file` blind spots the earlier raw-regex version had:
//   - QUOTE-AWARE: a `>` inside single/double quotes (a commit message, an
//     `echo`, an `awk '$1 > x'`) is NOT a redirect, so it is not a false
//     positive (issues #1, #6).
//   - cd-AWARE: a leading `cd <dir>` sets the base the target resolves against,
//     so `cd /etc && > hosts` is correctly seen as writing /etc/hosts (issue
//     #4), and `cd .factory/state && > paused` is seen as a trust-root write
//     (issue #3), neither of which the PROJECT_DIR-relative version caught.
//
// Best-effort by design (it inspects redirect/tee targets, not every mutator,
// and a determined agent can obfuscate). CI is the authoritative boundary.
//
// Carve-outs for `outside` (writing here is fine even though it is outside the
// repo): the project tree, $HOME/.claude/** (Claude Code state incl. the memory
// feature), $TMPDIR, /tmp, /private/tmp, /var/folders, /dev/**.
import path from 'node:path';

const PROJECT_DIR = path.resolve(process.env.HOOK_PROJECT_DIR || process.cwd());
const HOME = process.env.HOME || '';
const TMPDIR = process.env.TMPDIR || '';

const allowedRoots = [
  PROJECT_DIR,
  HOME ? path.join(HOME, '.claude') : '',
  TMPDIR ? path.resolve(TMPDIR) : '',
  '/tmp', '/private/tmp', '/var/folders', '/dev',
].filter(Boolean);

const TRUST_STATE = path.join(PROJECT_DIR, '.factory', 'state');
const TRUST_REVIEW = path.join(PROJECT_DIR, '.factory', 'review');
const TRUST_CONFIG = path.join(PROJECT_DIR, '.factory', 'config.json');

function underAllowedRoot(abs) {
  return allowedRoots.some((r) => abs === r || abs.startsWith(r + path.sep));
}
function underTrustRoot(abs) {
  return abs === TRUST_CONFIG
    || abs === TRUST_STATE || abs.startsWith(TRUST_STATE + path.sep)
    || abs === TRUST_REVIEW || abs.startsWith(TRUST_REVIEW + path.sep);
}
function expandHome(p) {
  if (p === '~') return HOME || p;
  if (p.startsWith('~/')) return HOME ? path.join(HOME, p.slice(2)) : p;
  return p;
}

// Tokenize honoring single/double quotes and backslash escapes. Emits operator
// tokens ({op}) for > >> | || & && ; ( ) < and word tokens ({v, unresolvable})
// whose v is the UNQUOTED text; unresolvable flags an unquoted $ / ` / $( that
// we cannot statically resolve (so we never guess).
function tokenize(cmd) {
  const toks = [];
  let i = 0; const n = cmd.length;
  while (i < n) {
    const ch = cmd[i];
    if (/\s/.test(ch)) { i++; continue; }
    if (ch === '>') { if (cmd[i + 1] === '>') { toks.push({ op: '>>' }); i += 2; } else { toks.push({ op: '>' }); i++; } continue; }
    if (ch === '<') { toks.push({ op: '<' }); i++; continue; }
    if (ch === '|') { if (cmd[i + 1] === '|') { toks.push({ op: '||' }); i += 2; } else { toks.push({ op: '|' }); i++; } continue; }
    if (ch === '&') { if (cmd[i + 1] === '&') { toks.push({ op: '&&' }); i += 2; } else { toks.push({ op: '&' }); i++; } continue; }
    if (ch === ';') { toks.push({ op: ';' }); i++; continue; }
    if (ch === '(' || ch === ')') { toks.push({ op: ch }); i++; continue; }
    // word
    let v = ''; let unresolvable = false;
    while (i < n) {
      const c = cmd[i];
      if (/\s/.test(c)) break;
      if (c === '"' || c === "'") { const q = c; i++; while (i < n && cmd[i] !== q) { v += cmd[i]; i++; } i++; continue; }
      if (c === '\\') { if (i + 1 < n) { v += cmd[i + 1]; i += 2; } else { i++; } continue; }
      if (c === '>' || c === '<' || c === '|' || c === '&' || c === ';' || c === '(' || c === ')') break;
      if (c === '$' || c === '`') unresolvable = true;
      v += c; i++;
    }
    toks.push({ v, unresolvable });
  }
  return toks;
}

function collect(cmd) {
  const toks = tokenize(cmd);
  const targets = [];
  // effective cwd from a leading `cd <dir>` (the first word of the command).
  let cwd = null;
  for (let k = 0; k < toks.length; k++) {
    if (toks[k].op) continue;
    if (toks[k].v === 'cd' && toks[k + 1] && !toks[k + 1].op) cwd = toks[k + 1];
    break;
  }
  // `tee` is the tee command only in command position (first token, or right
  // after a pipe/`;`/`&&`/`||`/`&`/`(`); as a bare argument (`grep tee f`) it is
  // not a write construct.
  const CMD_SEP = new Set(['|', '||', '&&', ';', '&', '(']);
  const cmdPos = (k) => k === 0 || (toks[k - 1].op && CMD_SEP.has(toks[k - 1].op));
  for (let k = 0; k < toks.length; k++) {
    const t = toks[k];
    if (t.op === '>' || t.op === '>>') {
      const nxt = toks[k + 1];
      if (nxt && !nxt.op) targets.push(nxt); // an operator after > (e.g. >&1, >(…)) is not a file
    } else if (!t.op && t.v === 'tee' && cmdPos(k)) {
      for (let j = k + 1; j < toks.length; j++) {
        const w = toks[j];
        if (w.op) break;
        if (w.v.startsWith('-')) continue; // skip flags
        targets.push(w); break;
      }
    }
  }
  return { targets, cwd };
}

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  const { targets, cwd } = collect(s);
  let base = PROJECT_DIR;
  if (cwd && !cwd.unresolvable && cwd.v) base = path.resolve(PROJECT_DIR, expandHome(cwd.v));
  const outside = []; const trustRoot = [];
  for (const t of targets) {
    if (!t.v || t.unresolvable) continue;
    const abs = path.resolve(base, expandHome(t.v));
    if (underTrustRoot(abs)) trustRoot.push(abs);
    else if (!underAllowedRoot(abs)) outside.push(abs);
  }
  process.stdout.write(JSON.stringify({ outside, trustRoot }));
});
