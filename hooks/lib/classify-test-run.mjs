#!/usr/bin/env node
// Read a shell command string on stdin; argv[1] is the test-command regex.
// Emit JSON: { "testCommand": bool, "cleanInvocation": bool }
//
//   testCommand    — a test invocation appears in COMMAND POSITION somewhere in
//                    the line (the first word of some simple command matches the
//                    regex), so record-green should engage. This is NOT a bare
//                    substring scan: `grep -rn "npm test" README` and
//                    `echo "npm test passed"` do NOT count (the test text is an
//                    argument, not the command word).
//   cleanInvocation — the LAST simple command executed is that test command, so
//                    the shell's reported exit status actually certifies the
//                    SUITE. This is false for `npm test | tail` (status is
//                    tail's), `npm test || echo x` / `npm test; echo x` (status
//                    is echo's), and any forgery where the final command is not
//                    the suite. record-green only trusts a reported exit code
//                    when this is true.
//
// Fixes the false-green vectors (pipeline/list exit-status masking, test text
// used as data, echo/printf/env-prefix forgery) and the over-broad guards (a
// bare '#' anywhere, a '||'/';' anywhere) with one command-position analysis.
// Quote-aware and redirect-aware so `npm test 2>&1` (a clean run with stderr
// redirected) still mints, while `npm test 2>&1 | tail` does not.

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

// Read one word token's UNQUOTED value starting at i; returns [value, nextIndex].
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

// Shell keywords that merely precede a command word.
const PREFIX_WORDS = new Set(['then', 'do', 'else']);
// Command wrappers (run another command later in argv) — the test binary is the
// WRAPPED command, so `timeout 300 npm test` / `nice -n 5 npm test` must resolve
// to `npm test` or a legit green suite mints no receipt (a false-block the
// pre-rewrite whole-line grep did not have).
const WRAPPERS = new Set([
  'timeout', 'nice', 'nohup', 'sudo', 'doas', 'env', 'stdbuf', 'ionice', 'chrt',
  'setsid', 'unbuffer', 'time', 'command', 'builtin', 'exec', 'xargs',
]);
// Value-taking flags PER WRAPPER (not a global union): the same flag letter is
// boolean for one wrapper and value-taking for another (`time -p` is boolean but
// `sudo -p` takes a prompt; `env -i` is boolean but `stdbuf -i` takes a mode), so
// a union wrongly swallows the wrapped command word — misclassifying the run.
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

// Drop leading env assignments, shell-keyword prefixes, and command wrappers
// (with their flags/values/positionals), returning the wrapped command's words.
function stripLeadingWrappers(words) {
  let w = words;
  for (let guard = 0; guard < 6; guard += 1) {
    let i = 0;
    while (i < w.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w[i]) || PREFIX_WORDS.has(w[i]))) i += 1;
    if (i >= w.length) return [];
    if (!WRAPPERS.has(w[i])) return w.slice(i);
    const vflags = WRAPPER_VALUE_FLAGS_BY[w[i]] || new Set();
    let j = i + 1;
    let pos = WRAPPER_POSITIONALS[w[i]] || 0;
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

// Parse into simple commands, honoring quotes, redirections (which do NOT split
// commands and whose '&' in `2>&1`/`>&` is not a background separator), and
// comments (`#` at a word boundary begins a comment to end of line).
function parse(cmd) {
  const commands = []; // each: array of unquoted words
  const n = cmd.length; let i = 0; let words = [];
  // `masked` = the reported exit code does NOT certify the whole line: a pipe
  // (`|`), an or-list (`||`), a sequence (`;`), or a background (`&`) all detach
  // the final status from an earlier command. Only `&&` (and no connector) keeps
  // exit 0 == "every command, including the suite, passed".
  let masked = false;
  const flush = () => { if (words.length) commands.push(words); words = []; };
  while (i < n) {
    const c = cmd[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === '#') { while (i < n && cmd[i] !== '\n') i++; continue; } // comment
    if (c === '|') { flush(); masked = true; i += cmd[i + 1] === '|' ? 2 : 1; continue; } // | and ||
    if (c === ';') { flush(); masked = true; i++; continue; }
    if (c === '&') { if (cmd[i + 1] === '&') { flush(); i += 2; } else { flush(); masked = true; i++; } continue; } // && ok; bare & (background) masks
    if (c === '(' || c === ')') { i++; continue; }
    if (c === '>' || c === '<') {
      i++; if (cmd[i] === c) i++;          // >> or <<
      if (cmd[i] === '&') i++;             // >& / 2>&1 / >&2
      while (i < n && /\s/.test(cmd[i])) i++;
      i = skipWord(cmd, i);                // consume the redirect target
      continue;
    }
    const [v, ni] = readWord(cmd, i);
    if (v !== '') words.push(v);
    i = ni > i ? ni : i + 1;
  }
  flush();
  return { commands, masked };
}

// The wrapped command of a simple command (env/prefix/wrapper stripped),
// reconstructed as "word arg arg…" for anchored regex matching, or '' if none.
function commandFrom(words) {
  const w = stripLeadingWrappers(words);
  return w.length ? w.join(' ') : '';
}

let re = null;
try { const src = String(process.argv[2] ?? ''); if (src) re = new RegExp('^(?:' + src + ')'); } catch { re = null; }

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  // Strip line continuations, same as the shell.
  const cmd = s.replace(/\\\r?\n/g, '');
  let testCommand = false; let cleanInvocation = false;
  if (re) {
    const { commands, masked } = parse(cmd);
    const heads = commands.map(commandFrom).filter(Boolean);
    for (const c of heads) if (re.test(c)) { testCommand = true; break; }
    // The exit code certifies the SUITE only when a test command is present and
    // nothing masks the status: a pure `&&` chain (or a lone command) means exit
    // 0 implies every command — including the suite — passed. Any |, ||, ;, or
    // background & means the reported status describes something else.
    cleanInvocation = testCommand && !masked;
  }
  process.stdout.write(JSON.stringify({ testCommand, cleanInvocation }));
});
