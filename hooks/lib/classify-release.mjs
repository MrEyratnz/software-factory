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

const PREFIX_WORDS = new Set(['then', 'do', 'else']);
// Command wrappers (run another command later in argv). A release verb wrapped
// in `timeout … gh release create` / `nice … npm publish` must still be seen, or
// the release gate is bypassed — the pre-rewrite whole-line grep caught these.
const WRAPPERS = new Set([
  'timeout', 'nice', 'nohup', 'sudo', 'doas', 'env', 'stdbuf', 'ionice', 'chrt',
  'setsid', 'unbuffer', 'time', 'command', 'builtin', 'exec', 'xargs',
]);
// Value-taking flags PER WRAPPER (not a global union): the same flag letter is
// boolean for one wrapper and value-taking for another (`time -p`/`env -i`/
// `sudo -i` are boolean), so a union wrongly swallows the wrapped command word —
// e.g. `sudo -i gh release create` would then miss the release verb (a bypass).
const WRAPPER_VALUE_FLAGS_BY = {
  timeout: new Set(['-s', '--signal', '-k', '--kill-after']),
  nice: new Set(['-n', '--adjustment']),
  sudo: new Set(['-u', '--user', '-g', '--group', '-C', '--close-from', '-p', '--prompt', '-U', '--other-user', '-r', '--role', '-t', '--type', '-h', '--host', '-R', '--chroot', '-D', '--chdir']),
  doas: new Set(['-u', '-C']),
  env: new Set(['-u', '--unset', '-C', '--chdir', '-S', '--split-string']),
  stdbuf: new Set(['-i', '--input', '-o', '--output', '-e', '--error']),
  ionice: new Set(['-c', '--class', '-n', '--classdata', '-p', '--pid']),
  time: new Set(['-o', '--output', '-f', '--format']),
  exec: new Set(['-a']),
  xargs: new Set(['-I', '-i', '-n', '--max-args', '-P', '--max-procs', '-s', '--max-chars', '-L', '-l', '-d', '--delimiter', '-E', '-e', '-a', '--arg-file']),
};
const WRAPPER_POSITIONALS = { timeout: 1, chrt: 1 };
// Shells whose `-c <string>` arg is itself a command line (a release verb hidden
// in `sh -c 'gh release create v1'` must still be gated).
const SHELL_WORDS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh']);

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

// Words of a simple command from its EFFECTIVE command word onward: skip env
// assignments and shell-keyword prefixes, then unwrap command wrappers (past
// their flags/values/positionals) so `timeout 60 gh release create` resolves to
// `gh release create`.
function head(words) {
  let w = words;
  for (let guard = 0; guard < 6; guard += 1) {
    let k = 0;
    while (k < w.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w[k]) || PREFIX_WORDS.has(w[k]))) k += 1;
    if (k >= w.length) return [];
    if (!WRAPPERS.has(w[k])) return w.slice(k);
    const vflags = WRAPPER_VALUE_FLAGS_BY[w[k]] || new Set();
    let j = k + 1;
    let pos = WRAPPER_POSITIONALS[w[k]] || 0;
    while (j < w.length) {
      const t = w[j];
      if (t.startsWith('-')) { j += 1; if (vflags.has(t) && j < w.length && !w[j].startsWith('-')) j += 1; continue; }
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) { j += 1; continue; }
      if (pos > 0) { pos -= 1; j += 1; continue; }
      break;
    }
    w = w.slice(j);
  }
  return w;
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

function analyze(rawCmd, depth) {
  const cmd = rawCmd.replace(/\\\r?\n/g, '');
  for (const words of parse(cmd)) {
    const hw = head(words);
    if (!hw.length) continue;
    // `sh -c '<payload>'` / `bash -c …` / `eval '<payload>'`: recurse into the
    // payload (bounded depth) so a release verb hidden there is still detected.
    if (depth < 4 && (SHELL_WORDS.has(hw[0]) || hw[0] === 'eval')) {
      let payload = '';
      if (hw[0] === 'eval') payload = hw.slice(1).join(' ');
      else { const ci = hw.indexOf('-c'); if (ci >= 0 && hw[ci + 1]) payload = hw[ci + 1]; }
      if (payload && analyze(payload, depth + 1)) return true;
      continue;
    }
    // `git … tag …` — decide by create-vs-list, never by the raw regex (which
    // would match `git tag -l`).
    if (hw[0] === 'git' && hw.includes('tag')) { if (isGitTagCreate(hw)) return true; continue; }
    if (re && re.test(hw.join(' '))) return true;
  }
  return false;
}

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  process.stdout.write(JSON.stringify({ isRelease: analyze(s, 0) }));
});
