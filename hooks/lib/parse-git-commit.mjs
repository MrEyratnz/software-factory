#!/usr/bin/env node
// Read a shell command string on stdin; emit JSON describing any `git commit`
// in it: whether it is a commit, whether it uses a bypass flag, and the -m
// message (best-effort, handles "…", '…', and bare tokens). Kept as a file
// (not inline) so the quoting stays sane and it is unit-testable.
//
// isCommit is fail-conservative: it inspects the actual git subcommand token
// rather than a loose "git ... commit" text adjacency (a static regex like
// that is trivially evaded by an alias (`git ci`), a wrapper, or the commit
// falling on the far side of an intervening newline). Any subcommand that is
// not on the small allow-list of clearly-non-commit porcelain commands is
// treated as a possible commit, so an unknown token or alias fails toward
// "engage the gate" rather than "skip it". When a `git` token has no
// parseable subcommand at all (e.g. it is the last token on the line) AND
// the command uses a construct that can hand it a subcommand out of static
// view (`xargs`, `eval`, `sh -c`/`bash -c`, command substitution), that is
// exactly "mentions git and cannot be confidently parsed as a non-commit" —
// see hasIndirection() below — so it also fails toward "engage the gate".
//
// This is BEST-EFFORT, local, fail-early UX, not a security boundary: a
// determined agent can still obfuscate a commit past static text inspection
// (shell quote-splitting the literal `git` token itself, base64, etc.).
// That class is deliberately out of scope here — CI re-runs this identical
// gate and is the authoritative boundary.
const SAFE_SUBCOMMANDS = new Set([
  'status', 'diff', 'log', 'show', 'add', 'branch', 'checkout', 'switch',
  'fetch', 'pull', 'push', 'remote', 'config', 'blame', 'grep', 'ls-files',
  'rev-parse', 'describe', 'init', 'clone', 'mv', 'rm', 'reflog', 'shortlog',
  'whatchanged', 'help', 'version', 'stash', 'tag', 'ls-remote', 'ls-tree',
  'cat-file', 'rev-list', 'submodule', 'worktree', 'notes', 'clean', 'restore',
  'gc', 'fsck', 'prune', 'repack', 'var', 'count-objects', 'check-ignore',
  'update-index', 'difftool', 'credential', 'apply', 'format-patch',
  'request-pull', 'archive', 'bundle', 'instaweb', 'daemon', 'verify-tag',
  'name-rev', 'merge-base',
]);
// Global options that take their value as a separate following token (as
// opposed to `--foo=bar`, which is already one token).
const OPTIONS_WITH_VALUE = new Set(['-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path']);

// Literal markers of a construct that can supply a git subcommand (or an
// entire git invocation) out of static view: piping tokens to `git` via
// `xargs`, running a string through `eval`/`sh -c`/`bash -c`, or command
// substitution. Deliberately a small, readable set of indicators rather than
// real shell parsing — see the file header for why that's the right amount
// of effort here.
const INDIRECTION_RE = /\bxargs\b|\beval\b|\bsh\s+-c\b|\bbash\s+-c\b|`|\$\(/;
function hasIndirection(cmd) {
  return INDIRECTION_RE.test(cmd);
}

// Find every `git` subcommand token in the command string and report whether
// any of them is a commit (or an unrecognized stand-in for one).
function detectGitCommit(cmd) {
  const gitTok = /\bgit\b/g;
  let match;
  while ((match = gitTok.exec(cmd)) !== null) {
    let i = match.index + match[0].length;
    const len = cmd.length;
    let subcommand = null;
    while (i < len) {
      while (i < len && /\s/.test(cmd[i])) i++; // skip whitespace, incl. newlines
      if (cmd[i] === '\\' && cmd[i + 1] === '\n') { i += 2; continue; } // line continuation
      if (i >= len) break;
      const start = i;
      while (i < len && !/\s/.test(cmd[i])) i++;
      const token = cmd.slice(start, i).replace(/^["']|["']$/g, '');
      if (token === '') break;
      if (token.startsWith('-')) {
        if (OPTIONS_WITH_VALUE.has(token)) {
          while (i < len && /\s/.test(cmd[i])) i++;
          while (i < len && !/\s/.test(cmd[i])) i++; // skip the option's value token
        }
        continue; // keep looking for the subcommand
      }
      subcommand = token;
      break;
    }
    if (subcommand !== null && !SAFE_SUBCOMMANDS.has(subcommand)) return true;
    // Bare `git`: no subcommand token is visible at all for this occurrence.
    // If the command also carries an indirection construct, the real
    // subcommand may be supplied elsewhere (xargs, eval, sh -c, ...) — that
    // is "cannot be confidently parsed as a non-commit", so treat it as one.
    if (subcommand === null && hasIndirection(cmd)) return true;
  }
  return false;
}

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  const cmd = s;
  const isCommit = detectGitCommit(cmd);
  const bypass = /(--no-verify|--no-gpg-sign)/.test(cmd);
  const m =
    cmd.match(/-m\s+"((?:[^"\\]|\\.)*)"/) ||
    cmd.match(/-m\s+'([^']*)'/) ||
    cmd.match(/-m\s+(\S+)/);
  process.stdout.write(JSON.stringify({ isCommit, bypass, message: m ? m[1] : '' }));
});
