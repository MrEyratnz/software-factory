#!/usr/bin/env node
// Read a bash command string on stdin; emit JSON listing any WRITE-TARGET path
// that resolves OUTSIDE the project tree and is not under an allowed carve-out.
//
// This gives guard-bash-writes the Bash-side equivalent of guard-scope's
// editor-tool "no writes outside the project directory" rule (issue #31): that
// ban previously covered Write/Edit/MultiEdit only, so a `cat > /elsewhere`
// slipped straight through. Best-effort by design — it inspects redirect and
// `tee` targets (the clear, common write constructs), not every conceivable
// mutator, and a determined agent can obfuscate. CI is the authoritative
// boundary; this is fail-early UX.
//
// Carve-outs (writing here is fine even though it is outside the repo):
//   - the project tree itself
//   - $HOME/.claude/**            — Claude Code's own state incl. the memory
//                                   feature (~/.claude/projects/**/memory); the
//                                   factory must not silently break a first-party
//                                   feature.
//   - $TMPDIR, /tmp, /private/tmp, /var/folders — scratch/temp space (the
//                                   session scratchpad lives under /tmp).
//   - /dev/**                     — /dev/null, /dev/stdout, /dev/stderr, /dev/fd/*
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

function underAllowedRoot(abs) {
  return allowedRoots.some((root) => abs === root || abs.startsWith(root + path.sep));
}

function unquote(tok) {
  if ((tok.startsWith('"') && tok.endsWith('"')) || (tok.startsWith("'") && tok.endsWith("'"))) {
    return tok.slice(1, -1);
  }
  return tok;
}

function expandHome(p) {
  if (p === '~') return HOME || p;
  if (p.startsWith('~/')) return HOME ? path.join(HOME, p.slice(2)) : p;
  return p;
}

// A target token we cannot statically resolve (contains an unexpanded var or a
// command substitution) is skipped — we never guess, to avoid false positives.
function unresolvable(tok) {
  return /[$`]/.test(tok) || tok.includes('$(');
}

function collectTargets(cmd) {
  const targets = [];
  // Redirects: an unquoted > or >> (optionally fd-prefixed like 2> or &>), NOT
  // a dup (>&), pipe-clobber written as >| is fine, and NOT process substitution
  // >( … ). The following token is the file being written.
  const RED = /(?:^|[\s;&|(){}])(?:[0-9]+|&)?>>?(?![&(])\s*("[^"]*"|'[^']*'|[^\s;&|)(<>]+)/g;
  let m;
  while ((m = RED.exec(cmd)) !== null) targets.push(unquote(m[1]));
  // `tee [OPTS] FILE` — capture the first non-flag operand (the common case).
  const TEE = /(?:^|[\s;&|(])tee\b(?:\s+-[^\s]+)*\s+("[^"]*"|'[^']*'|[^\s;&|)(<>-][^\s;&|)(<>]*)/g;
  while ((m = TEE.exec(cmd)) !== null) targets.push(unquote(m[1]));
  return targets;
}

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  const outside = [];
  for (const raw of collectTargets(s)) {
    if (!raw || unresolvable(raw)) continue;
    const abs = path.resolve(PROJECT_DIR, expandHome(raw));
    if (!underAllowedRoot(abs)) outside.push(abs);
  }
  process.stdout.write(JSON.stringify({ outside }));
});
