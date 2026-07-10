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

const PREFIX_WORDS = new Set(['command', 'builtin', 'exec', 'env', 'time', 'nice', 'nohup', 'sudo', 'then', 'do', 'else']);

// Parse into simple commands, honoring quotes, redirections (which do NOT split
// commands and whose '&' in `2>&1`/`>&` is not a background separator), and
// comments (`#` at a word boundary begins a comment to end of line).
function parse(cmd) {
  const commands = []; // each: array of unquoted words
  const n = cmd.length; let i = 0; let words = [];
  const flush = () => { if (words.length) commands.push(words); words = []; };
  while (i < n) {
    const c = cmd[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === '#') { while (i < n && cmd[i] !== '\n') i++; continue; } // comment
    if (c === '|') { flush(); i += cmd[i + 1] === '|' ? 2 : 1; continue; }
    if (c === ';') { flush(); i++; continue; }
    if (c === '&') { if (cmd[i + 1] === '&') { flush(); i += 2; } else { flush(); i++; } continue; }
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
  return commands;
}

// The command word of a simple command, skipping env assignments (VAR=val) and
// prefix words (command/env/sudo/…). Returns the reconstructed "word arg arg…"
// from that command word onward, or '' if none.
function commandFrom(words) {
  let k = 0;
  while (k < words.length) {
    const w = words[k];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w)) { k++; continue; }
    if (PREFIX_WORDS.has(w)) { k++; continue; }
    break;
  }
  return k < words.length ? words.slice(k).join(' ') : '';
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
    const commands = parse(cmd).map(commandFrom).filter(Boolean);
    for (const c of commands) if (re.test(c)) { testCommand = true; break; }
    if (commands.length) cleanInvocation = re.test(commands[commands.length - 1]);
  }
  process.stdout.write(JSON.stringify({ testCommand, cleanInvocation }));
});
