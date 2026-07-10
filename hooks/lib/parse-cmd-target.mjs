#!/usr/bin/env node
// Read a bash command on stdin; emit JSON {"cd":<abs|"">,"gitC":<abs|"">} —
// the working directory a git command effectively operates on, resolved against
// the project dir. `cd` is a leading `cd <dir>`; `gitC` is a REAL `git -C <dir>`
// global option (a `-C` that precedes the git subcommand), which overrides the
// cwd per git's own precedence.
//
// Quote-aware and subcommand-aware on purpose: a `git -C /x` merely mentioned
// inside a `-m "…"` message or a heredoc is NOT a git option — the token walk
// stops at the subcommand (`commit`) before ever reaching the message — so it
// cannot be used to point the green gate at the wrong repo (issue #2 and its
// message-injection variant). guard-commit/guard-release then bind the receipt
// to `gitC` when present, else `cd`, else the session PROJECT_DIR.
import path from 'node:path';

const PROJECT_DIR = path.resolve(process.env.HOOK_PROJECT_DIR || process.cwd());
const HOME = process.env.HOME || '';

function expandHome(p) {
  if (p === '~') return HOME || p;
  if (p.startsWith('~/')) return HOME ? path.join(HOME, p.slice(2)) : p;
  return p;
}

// Same quote/backslash-aware tokenizer as parse-bash-writes.mjs: operator tokens
// ({op}) and word tokens ({v} unquoted).
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
    let v = '';
    while (i < n) {
      const c = cmd[i];
      if (/\s/.test(c)) break;
      if (c === '"' || c === "'") { const q = c; i++; while (i < n && cmd[i] !== q) { v += cmd[i]; i++; } i++; continue; }
      if (c === '\\') { if (i + 1 < n) { v += cmd[i + 1]; i += 2; } else { i++; } continue; }
      if (c === '>' || c === '<' || c === '|' || c === '&' || c === ';' || c === '(' || c === ')') break;
      v += c; i++;
    }
    toks.push({ v });
  }
  return toks;
}

const CMD_SEP = new Set(['|', '||', '&&', ';', '&', '(']);
const OPT_WITH_VALUE = new Set(['-c', '--git-dir', '--work-tree', '--namespace', '--exec-path']);

function resolveTarget(cmd) {
  const toks = tokenize(cmd);
  // Effective cwd: track every command-position `cd <dir>` up to the git
  // invocation, not just the first token. `cd a; cd b; git commit` lands in b;
  // `FOO=1 cd sub && git commit` lands in sub (skip the env assignment); `cd -`
  // / a bare `cd` is unresolvable, so it clears the tracked cwd (fall back to
  // PROJECT_DIR) rather than mis-binding to a literal "-".
  let cwd = '';
  for (let k = 0; k < toks.length; k++) {
    const t = toks[k];
    if (t.op) continue;
    const atCmdPos = k === 0 || (toks[k - 1].op && CMD_SEP.has(toks[k - 1].op));
    if (!atCmdPos) continue;
    // Skip leading env assignments (VAR=val) to reach the real command word.
    let c = k;
    while (c < toks.length && !toks[c].op && /^[A-Za-z_][A-Za-z0-9_]*=/.test(toks[c].v)) c++;
    if (c >= toks.length || toks[c].op) continue;
    const word = toks[c].v;
    if (word === 'git') break; // the git command runs with the cwd accumulated so far
    if (word === 'cd') {
      const arg = toks[c + 1];
      if (arg && !arg.op && arg.v !== '-' && arg.v !== '~-') cwd = arg.v;
      else cwd = ''; // `cd -` / bare `cd` (home) — unresolvable, don't guess
    }
  }
  let dashC = '';
  for (let k = 0; k < toks.length && !dashC; k++) {
    const t = toks[k];
    if (t.op) continue;
    const cmdPos = k === 0 || (toks[k - 1].op && CMD_SEP.has(toks[k - 1].op));
    if (t.v !== 'git' || !cmdPos) continue;
    for (let j = k + 1; j < toks.length; j++) {
      const a = toks[j];
      if (a.op) break; // end of this simple command
      if (a.v === '-C' && toks[j + 1] && !toks[j + 1].op) { dashC = toks[j + 1].v; break; }
      if (OPT_WITH_VALUE.has(a.v)) { j++; continue; } // global option that consumes its value
      if (a.v.startsWith('-')) continue; // other global flag
      break; // subcommand token — no global -C precedes it
    }
  }
  return {
    cd: cwd ? path.resolve(PROJECT_DIR, expandHome(cwd)) : '',
    gitC: dashC ? path.resolve(PROJECT_DIR, expandHome(dashC)) : '',
  };
}

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => { process.stdout.write(JSON.stringify(resolveTarget(s))); });
