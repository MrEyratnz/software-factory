#!/usr/bin/env node
// Read a shell command string on stdin; emit JSON describing any `git commit`
// in it: whether it is a commit, whether it uses a bypass flag, and the -m
// message (best-effort, handles "…", '…', and bare tokens). Kept as a file
// (not inline) so the quoting stays sane and it is unit-testable.
let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  const cmd = s;
  const isCommit = /\bgit\b[^\n|&;]*\bcommit\b/.test(cmd);
  const bypass = /(--no-verify|--no-gpg-sign)/.test(cmd);
  const m =
    cmd.match(/-m\s+"((?:[^"\\]|\\.)*)"/) ||
    cmd.match(/-m\s+'([^']*)'/) ||
    cmd.match(/-m\s+(\S+)/);
  process.stdout.write(JSON.stringify({ isCommit, bypass, message: m ? m[1] : '' }));
});
