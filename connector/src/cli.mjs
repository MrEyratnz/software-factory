#!/usr/bin/env node
/**
 * factory-core CLI — a thin shell bridge to the SAME pure rule engine the MCP
 * connector exposes. Hook scripts (POSIX sh) and CI call this so the read path
 * (connector tools) and the write/enforcement path (hooks) can never disagree:
 * both compute verdicts from `factory-core.mjs`, the one source of truth.
 *
 *   echo '{"message":"feat: x"}' | node cli.mjs commit-lint
 *   echo '{"stages":[...],"treeHash":"abc"}' | node cli.mjs gate-evaluate
 *
 * Reads a JSON object from stdin (or `{}` if none), prints the JSON result to
 * stdout, exit 0. On bad usage/parse, prints {"error":...} to stderr, exit 1.
 */

import {
  parseRoadmap, indexAdrs, lintTechDebt, lintCommit, planRelease,
  roadmapCheck, gateEvaluate, techdebtAudit, fingerprintFinding,
} from './factory-core.mjs';

function readStdin() {
  return new Promise((res) => {
    let buf = '';
    if (process.stdin.isTTY) { res(''); return; }
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { buf += c; });
    process.stdin.on('end', () => res(buf));
  });
}

const COMMANDS = {
  'parse-roadmap': (a) => parseRoadmap(a.markdown ?? ''),
  'roadmap-status': (a) => parseRoadmap(a.markdown ?? ''),
  'roadmap-next': (a) => ({ next: parseRoadmap(a.markdown ?? '').next }),
  'roadmap-check': (a) => roadmapCheck(a.item ?? '', a.proof ?? {}),
  'adr-index': (a) => indexAdrs(a.entries ?? []),
  'commit-lint': (a) => lintCommit(a.message ?? '', { maxHeader: a.maxHeader }),
  'techdebt-lint': (a) => lintTechDebt(a),
  'techdebt-audit': (a) => techdebtAudit(a.findings ?? [], a.openIssues ?? []),
  'gate-evaluate': (a) => gateEvaluate(a.stages ?? [], a.treeHash ?? ''),
  'release-plan': (a) => planRelease(a.commits ?? [], a.currentVersion ?? '0.0.0', { preMajor: a.preMajor }),
  fingerprint: (a) => ({ fingerprint: fingerprintFinding(a) }),
};

async function main() {
  const cmd = process.argv[2];
  const fn = COMMANDS[cmd];
  if (!fn) {
    process.stderr.write(JSON.stringify({ error: `unknown command: ${cmd}`, commands: Object.keys(COMMANDS) }) + '\n');
    process.exit(1);
  }
  const raw = await readStdin();
  let args = {};
  if (raw.trim()) {
    try { args = JSON.parse(raw); } catch (e) {
      process.stderr.write(JSON.stringify({ error: `invalid JSON on stdin: ${e.message}` }) + '\n');
      process.exit(1);
    }
  }
  try {
    process.stdout.write(JSON.stringify(fn(args)) + '\n');
  } catch (e) {
    process.stderr.write(JSON.stringify({ error: e.message }) + '\n');
    process.exit(1);
  }
}

main();
