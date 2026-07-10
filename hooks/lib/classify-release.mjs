#!/usr/bin/env node
// Read a shell command on stdin; argv[1] is the release-verb regex. Emit JSON
// { "isRelease": bool } — true only when a release verb appears in COMMAND
// POSITION (the first word of some simple command), quote-aware.
//
// Fixes guard-release false-blocks:
//   - a release verb that only appears as DATA (inside a commit message, an
//     echo, a comment) is not a release: `git commit -m "how to npm publish"`
//     and `echo "run git tag"` no longer trip the gate.
//   - `git tag` is treated as a release only when it CREATES a tag (a tag-name
//     operand, or -a/-s/-m/-f), never for listing/verifying (`git tag`,
//     `git tag -l`, `-n`, `--list`, `--contains`, `-v`) or deletion (`-d`).
//
// Best-effort, quote/command-position aware — CI is the authoritative boundary.

function readWord(cmd, i) {
  const n = cmd.length; let v = '';
  while (i < n) {
    const c = cmd[i];
    if (/\s/.test(c)) break;
    if (c === '"' || c === "'") { const q = c; i++; while (i < n && cmd[i] !== q) { v += cmd[i]; i++; } i++; continue; }
    if (c === '\\') { if (i + 1 < n) { v += cmd[i + 1]; i += 2; } else i++; continue; }
    if (c === '|' || c === ';' || c === '&' || c === '(' || c === ')' || c === '>' || c === '<') break;
    v += c; i++;
  }
  return [v, i];
}
function skipWord(cmd, i) {
  const n = cmd.length;
  while (i < n) {
    const c = cmd[i];
    if (/\s/.test(c)) break;
    if (c === '"' || c === "'") { const q = c; i++; while (i < n && cmd[i] !== q) i++; i++; continue; }
    if (c === '\\') { i += 2; continue; }
    if (c === '|' || c === ';' || c === '&' || c === '(' || c === ')' || c === '>' || c === '<' || c === '#') break;
    i++;
  }
  return i;
}

const PREFIX_WORDS = new Set(['command', 'builtin', 'exec', 'env', 'time', 'nice', 'nohup', 'sudo', 'then', 'do', 'else']);

// Parse into simple commands (arrays of unquoted words), honoring quotes,
// redirects, and `#` comments.
function parse(cmd) {
  const commands = []; const n = cmd.length; let i = 0; let words = [];
  const flush = () => { if (words.length) commands.push(words); words = []; };
  while (i < n) {
    const c = cmd[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === '#') { while (i < n && cmd[i] !== '\n') i++; continue; }
    if (c === '|') { flush(); i += cmd[i + 1] === '|' ? 2 : 1; continue; }
    if (c === ';') { flush(); i++; continue; }
    if (c === '&') { flush(); i += cmd[i + 1] === '&' ? 2 : 1; continue; }
    if (c === '(' || c === ')') { i++; continue; }
    if (c === '>' || c === '<') {
      i++; if (cmd[i] === c) i++; if (cmd[i] === '&') i++;
      while (i < n && /\s/.test(cmd[i])) i++;
      i = skipWord(cmd, i); continue;
    }
    const [v, ni] = readWord(cmd, i);
    if (v !== '') words.push(v);
    i = ni > i ? ni : i + 1;
  }
  flush();
  return commands;
}

// Words of a simple command from its command word onward (skip env/prefix).
function head(words) {
  let k = 0;
  while (k < words.length) {
    const w = words[k];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w)) { k++; continue; }
    if (PREFIX_WORDS.has(w)) { k++; continue; }
    break;
  }
  return words.slice(k);
}

const TAG_LIST_FLAGS = new Set(['-l', '--list', '-n', '--contains', '--no-contains', '--points-at', '-v', '--verify', '--merged', '--no-merged', '--sort', '--format', '-d', '--delete']);
const TAG_CREATE_FLAGS = new Set(['-a', '--annotate', '-s', '--sign', '-m', '--message', '-f', '--force', '-u', '--local-user']);

// Is this git command a tag CREATION (vs list/verify/delete)?
function isGitTagCreate(hw) {
  // hw = ['git', ...global opts..., 'tag', ...args]
  const ti = hw.indexOf('tag');
  if (ti < 0) return false;
  const args = hw.slice(ti + 1);
  let hasPositional = false;
  for (let j = 0; j < args.length; j++) {
    const a = args[j];
    if (TAG_LIST_FLAGS.has(a)) return false;          // listing/verify/delete → not a release
    if (TAG_CREATE_FLAGS.has(a)) return true;         // -a/-s/-m/-f → creating
    if (!a.startsWith('-')) hasPositional = true;      // a tag name
  }
  return hasPositional;                                // `git tag v1.2.3`
}

let re = null;
try { const src = String(process.argv[2] ?? ''); if (src) re = new RegExp('^(?:' + src + ')'); } catch { re = null; }

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  const cmd = s.replace(/\\\r?\n/g, '');
  let isRelease = false;
  for (const words of parse(cmd)) {
    const hw = head(words);
    if (!hw.length) continue;
    // `git … tag …` — decide by create-vs-list, never by the raw regex (which
    // would match `git tag -l`).
    if (hw[0] === 'git' && hw.includes('tag')) { if (isGitTagCreate(hw)) { isRelease = true; break; } continue; }
    if (re && re.test(hw.join(' '))) { isRelease = true; break; }
  }
  process.stdout.write(JSON.stringify({ isRelease }));
});
