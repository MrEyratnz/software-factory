#!/usr/bin/env node
// Read a shell command string on stdin; emit JSON describing any `git commit`
// in it: whether it is a commit, whether it uses a bypass flag, and the commit
// message (best-effort). Kept as a file (not inline) so the quoting stays sane
// and it is unit-testable.
//
// Parsing is QUOTE-AWARE and COMMAND-POSITION-AWARE (the tokenizer is shared in
// spirit with parse-cmd-target.mjs / parse-bash-writes.mjs). We split the line
// into simple commands on shell separators, then for each segment look only at
// its command word. That single design choice fixes a cluster of defects the
// old raw-regex scan had:
//   - a `git commit` sitting inside a quoted string / commit message / echo is
//     an ARGUMENT, not a command, so it is not treated as a real invocation
//     (no more spurious blocks of `echo "...git commit..."`).
//   - a `git`/`commit` substring glued into a path or filename
//     (`/home/user/git/x`, `parse-git-commit.mjs`, `.git/config`) is likewise
//     an argument of some other command, never the command word — so the #26
//     false-positive class stays fixed without special path-glue heuristics.
//   - bypass flags (--no-verify/--no-gpg-sign) are read ONLY from the commit's
//     OWN argument span, so a message that merely mentions `--no-verify`, or a
//     chained `git push --no-verify`, no longer hard-blocks a clean commit.
//
// isCommit stays fail-conservative: any git subcommand token that is not on the
// small allow-list of clearly-non-commit porcelain is treated as a possible
// commit (an alias like `git ci`, or a bare `git` whose subcommand is supplied
// indirectly via xargs/eval/sh -c/command-substitution, fails toward "engage
// the gate" rather than skipping it).
//
// This is BEST-EFFORT, local, fail-early UX, not a security boundary — CI
// re-runs this identical gate and is the authoritative boundary.

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
// git global options that consume the NEXT token as their value (so the
// subcommand walk must skip that value too).
const GIT_OPT_WITH_VALUE = new Set(['-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path']);
// Command WRAPPERS — programs that run ANOTHER command given later in their argv
// (`timeout 60 git commit`, `nice -n 5 git commit`, `sudo -u ci git commit`,
// `env X=1 git commit`, `time -p git commit`). The wrapped `git` is found by
// SCANNING the segment for the first unquoted `git` command token, NOT by
// precisely skipping the wrapper's flags/values: a global value-flag list is
// unsafe because the same flag letter is boolean for one wrapper and
// value-taking for another (e.g. `time -p`, `env -i`, `sudo -i`), and wrongly
// consuming the wrapped `git` reopens the commit gate (incl. the hard
// --no-verify block). The scan needs no per-flag knowledge and is
// fail-conservative: over-engaging on a stray `git` token is safe; missing a
// real wrapped `git commit` is not.
const WRAPPERS = new Set([
  'timeout', 'nice', 'nohup', 'sudo', 'doas', 'env', 'stdbuf', 'ionice', 'chrt',
  'setsid', 'unbuffer', 'time', 'command', 'builtin', 'exec', 'xargs',
]);
// Constructs that can supply a git subcommand (or whole invocation) out of
// static view — a bare `git` alongside one of these fails toward the gate.
const INDIRECTION_RE = /\bxargs\b|\beval\b|\bsh\s+-c\b|\bbash\s+-c\b|`|\$\(/;

// Tokenize honoring single/double quotes and backslash escapes. Emits operator
// tokens ({op}) for the shell separators we care about, and word tokens
// ({v, quoted}) whose v is the UNQUOTED text and quoted=true if ANY part of the
// word came from inside quotes (so a quoted `git` is never a command word).
function tokenize(cmd) {
  const toks = [];
  let i = 0; const n = cmd.length;
  while (i < n) {
    const ch = cmd[i];
    if (/\s/.test(ch)) { i++; continue; }
    if (ch === '|') { if (cmd[i + 1] === '|') { toks.push({ op: '||' }); i += 2; } else { toks.push({ op: '|' }); i++; } continue; }
    if (ch === '&') { if (cmd[i + 1] === '&') { toks.push({ op: '&&' }); i += 2; } else { toks.push({ op: '&' }); i++; } continue; }
    if (ch === ';') { toks.push({ op: ';' }); i++; continue; }
    if (ch === '(' || ch === ')') { toks.push({ op: ch }); i++; continue; }
    if (ch === '>' || ch === '<') { toks.push({ op: ch }); i++; continue; }
    let v = ''; let quoted = false;
    while (i < n) {
      const c = cmd[i];
      if (/\s/.test(c)) break;
      if (c === '"' || c === "'") { const q = c; quoted = true; i++; while (i < n && cmd[i] !== q) { v += cmd[i]; i++; } i++; continue; }
      if (c === '\\') { if (i + 1 < n) { v += cmd[i + 1]; i += 2; } else { i++; } continue; }
      if (c === '|' || c === '&' || c === ';' || c === '(' || c === ')' || c === '>' || c === '<') break;
      v += c; i++;
    }
    toks.push({ v, quoted });
  }
  return toks;
}

const SEG_SEP = new Set(['|', '||', '&&', ';', '&', '(', ')']);
// Shells whose `-c <string>` argument is itself a command line to execute — the
// payload must be analyzed too, or `sh -c 'git commit …'` would hide the commit
// behind a quoted string the top-level tokenizer treats as opaque.
const SHELL_WORDS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh']);

// Split a token list into simple-command segments on shell separators.
function segments(toks) {
  const segs = []; let cur = [];
  for (const t of toks) {
    if (t.op && SEG_SEP.has(t.op)) { if (cur.length) segs.push(cur); cur = []; }
    else cur.push(t);
  }
  if (cur.length) segs.push(cur);
  return segs;
}

// The command-word index: skip leading VAR=val assignments only. Command
// wrappers are handled in analyze() by scanning for the wrapped command, so this
// deliberately does NOT try to unwrap them here. Returns -1 if none.
function commandWordIndex(seg) {
  let k = 0;
  while (k < seg.length && (seg[k].op || (!seg[k].quoted && /^[A-Za-z_][A-Za-z0-9_]*=/.test(seg[k].v)))) k += 1;
  return k < seg.length ? k : -1;
}

// The index of the first unquoted `git` command token at or after `from`, or -1.
function firstGitIndex(seg, from) {
  for (let j = from; j < seg.length; j += 1) { const t = seg[j]; if (!t.op && !t.quoted && t.v === 'git') return j; }
  return -1;
}
// The index of the first unquoted shell/eval command token at or after `from`.
function firstShellIndex(seg, from) {
  for (let j = from; j < seg.length; j += 1) { const t = seg[j]; if (!t.op && !t.quoted && (SHELL_WORDS.has(t.v) || t.v === 'eval')) return j; }
  return -1;
}

// Given the git segment and the index of the `git` word, find the subcommand
// token index (skipping global options), or -1 if none is visible.
function gitSubcommandIndex(seg, gitIdx) {
  for (let j = gitIdx + 1; j < seg.length; j++) {
    const t = seg[j];
    if (t.op) return -1;
    if (GIT_OPT_WITH_VALUE.has(t.v)) { j++; continue; }
    if (t.v.startsWith('-')) continue; // other global flag
    return j;
  }
  return -1;
}

// Extract a commit message from a heredoc form — Claude Code's own default
// commit style is `git commit -m "$(cat <<'EOF' … EOF)"`. The tokenizer would
// otherwise capture the literal `$(cat <<'EOF'…)` text as the message; here we
// pull the heredoc BODY so the conventional-commit lint sees the real subject.
function heredocMessage(cmd) {
  const m = cmd.match(/-m\b[^\n]*<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n([\s\S]*?)\n[ \t]*\2\b/);
  return m ? m[3] : null;
}

// Parse the commit invocation's own argument tokens (everything after the
// `commit` subcommand token, within the segment) for bypass flags, the -a/--all
// flag, and the message.
function parseCommitArgs(seg, commitIdx) {
  let bypass = false;
  let all = false;
  let message = '';
  let fromFile = false;
  for (let j = commitIdx + 1; j < seg.length; j++) {
    const t = seg[j];
    if (t.op) break;
    if (t.quoted) continue; // a quoted arg is never an option flag
    const v = t.v;
    if (v === '--no-verify' || v === '--no-gpg-sign') { bypass = true; continue; }
    if (v === '--all') { all = true; continue; }
    // long message forms
    let mm = v.match(/^--message=(.*)$/s);
    if (mm) { if (!message) message = mm[1]; continue; }
    if (v === '--message' || v === '--reedit-message' || v === '--reuse-message') {
      const nxt = seg[j + 1]; if (nxt && !nxt.op && !message) message = nxt.v; j++; continue;
    }
    if (v === '-F' || v === '--file' || /^--file=/.test(v) || /^-F.+/.test(v)) { fromFile = true; continue; }
    // short-flag cluster ending in `m` (e.g. -m, -am, -vam): message is next token
    if (/^-[A-Za-z]*m$/.test(v)) {
      if (/a/.test(v)) all = true;
      const nxt = seg[j + 1]; if (nxt && !nxt.op && !message) message = nxt.v; j++; continue;
    }
    // attached short message: -m<msg> or -m=<msg>
    mm = v.match(/^-m=?(.+)$/s);
    if (mm) { if (!message) message = mm[1]; continue; }
    // any short-flag cluster containing `a` (e.g. -a, -av, -sa): sets --all
    if (/^-[A-Za-z]*a[A-Za-z]*$/.test(v)) { all = true; continue; }
  }
  return { bypass, all, message, fromFile };
}

function analyze(rawCmd, depth = 0) {
  // The shell removes backslash-newline line continuations before parsing, so
  // `git \<newline>status` is just `git status`. Do the same before tokenizing,
  // or the subcommand token would carry a stray newline and never match the
  // safe-subcommand allow-list (spuriously engaging the gate).
  const cmd = rawCmd.replace(/\\\r?\n/g, '');
  const hasIndirection = INDIRECTION_RE.test(cmd);
  const toks = tokenize(cmd);
  const segs = segments(toks);
  let isCommit = false;
  let bypass = false;
  let all = false;
  let message = '';
  let fromFile = false;

  // Analyze a `git` invocation whose `git` token is at gitIdx.
  const analyzeGitAt = (seg, gitIdx) => {
    const subIdx = gitSubcommandIndex(seg, gitIdx);
    if (subIdx < 0) {
      // bare `git` with no visible subcommand: only commit-ish if the line can
      // supply one indirectly (xargs/eval/sh -c/`…`/$(…)).
      if (hasIndirection) isCommit = true;
      return;
    }
    const sub = seg[subIdx].v;
    if (SAFE_SUBCOMMANDS.has(sub)) return; // clearly not a commit
    isCommit = true;
    if (sub === 'commit') {
      const a = parseCommitArgs(seg, subIdx);
      bypass = bypass || a.bypass;
      all = all || a.all;
      fromFile = fromFile || a.fromFile;
      if (!message && a.message) message = a.message;
    }
  };
  // `sh -c '<payload>'` / `bash -c …` / `eval '<payload>'` at shellIdx: the
  // payload is a command line — recurse (bounded depth) so a commit hidden there
  // still engages the gate.
  const recurseShell = (seg, shellIdx) => {
    if (depth >= 4) return;
    const w = seg[shellIdx];
    let payload = '';
    if (w.v === 'eval') payload = seg.slice(shellIdx + 1).filter((t) => !t.op).map((t) => t.v).join(' ');
    else {
      for (let j = shellIdx + 1; j < seg.length; j += 1) {
        if (seg[j].op) break;
        if (seg[j].v === '-c') { const nxt = seg[j + 1]; if (nxt && !nxt.op) payload = nxt.v; break; }
      }
    }
    if (!payload) return;
    const inner = analyze(payload, depth + 1);
    if (inner.isCommit) {
      isCommit = true;
      bypass = bypass || inner.bypass;
      all = all || inner.all;
      fromFile = fromFile || inner.messageFromFile;
      if (!message && inner.message) message = inner.message;
    }
  };

  for (const seg of segs) {
    const cwi = commandWordIndex(seg);
    if (cwi < 0) continue;
    const word = seg[cwi];
    if (word.quoted) continue; // a quoted command word is not a real invocation
    if (SHELL_WORDS.has(word.v) || word.v === 'eval') { recurseShell(seg, cwi); continue; }
    if (word.v === 'git') { analyzeGitAt(seg, cwi); continue; }
    // A command WRAPPER (timeout/nice/sudo/env/…): scan for the wrapped `git`
    // (no per-flag-value knowledge — see the WRAPPERS comment), else a wrapped
    // shell whose payload we can recurse into.
    if (WRAPPERS.has(word.v)) {
      const gi = firstGitIndex(seg, cwi + 1);
      if (gi >= 0) { analyzeGitAt(seg, gi); continue; }
      const si = firstShellIndex(seg, cwi + 1);
      if (si >= 0) recurseShell(seg, si);
      continue;
    }
  }
  // Heredoc message wins over any literal $(cat <<…) token text — but ONLY when
  // the commit's OWN -m argument is a heredoc (its extracted value still carries
  // the `<<`). Otherwise an UNRELATED chained heredoc (`git commit -m "feat: x"
  // && cat <<EOF > notes`) would overwrite the real message and fail the lint.
  if (isCommit && /<</.test(message)) {
    const hd = heredocMessage(cmd);
    if (hd != null) message = hd;
  }
  return { isCommit, bypass, all, message, messageFromFile: fromFile };
}

let s = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { s += c; });
process.stdin.on('end', () => {
  process.stdout.write(JSON.stringify(analyze(s)));
});
