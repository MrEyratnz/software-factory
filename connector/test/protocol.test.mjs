import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVER = join(__dirname, '..', 'src', 'server.mjs');

/**
 * Drive the server over stdio: write each request as a JSON line, collect
 * response lines, and resolve once we've seen a response for every request id.
 * Notifications (no id) get no response, so we only wait on id-bearing calls.
 */
function rpc(requests, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [SERVER], {
      stdio: ['pipe', 'pipe', 'inherit'],
      env: opts.env ? { ...process.env, ...opts.env } : process.env,
    });
    const wantIds = new Set(requests.filter((r) => r.id != null).map((r) => r.id));
    const responses = [];
    let buf = '';
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error('server timed out'));
    }, 10000);

    child.stdout.on('data', (chunk) => {
      buf += chunk.toString();
      let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line) continue;
        const msg = JSON.parse(line);
        responses.push(msg);
        wantIds.delete(msg.id);
        if (wantIds.size === 0) {
          clearTimeout(timer);
          child.stdin.end();
          child.kill();
          resolve(responses);
        }
      }
    });
    child.on('error', reject);
    for (const r of requests) child.stdin.write(JSON.stringify(r) + '\n');
  });
}

test('initialize returns protocol version and server info', async () => {
  const [res] = await rpc([{ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }]);
  assert.equal(res.id, 1);
  assert.equal(res.result.serverInfo.name, 'dark-software-factory');
  assert.ok(res.result.protocolVersion);
  assert.ok(res.result.capabilities.tools);
});

test('tools/list advertises the full factory tool set', async () => {
  const [res] = await rpc([{ jsonrpc: '2.0', id: 2, method: 'tools/list' }]);
  const names = res.result.tools.map((t) => t.name).sort();
  assert.deepEqual(names, [
    'adr_index', 'commit_lint', 'gate_evaluate', 'ledger_read', 'release_plan',
    'roadmap_check', 'roadmap_next', 'roadmap_status', 'techdebt_audit', 'techdebt_lint',
  ]);
  for (const t of res.result.tools) {
    assert.ok(t.description && t.inputSchema, `${t.name} missing description/schema`);
  }
});

test('tools/call roadmap_status parses inline markdown', async () => {
  const [res] = await rpc([{
    jsonrpc: '2.0', id: 3, method: 'tools/call',
    params: { name: 'roadmap_status', arguments: { markdown: '## M0\n- [x] a\n- [ ] b\n' } },
  }]);
  const payload = JSON.parse(res.result.content[0].text);
  assert.equal(payload.totals.total, 2);
  assert.equal(payload.next.text, 'b');
  assert.ok(!res.result.isError);
});

test('tools/call commit_lint reports the bump', async () => {
  const [res] = await rpc([{
    jsonrpc: '2.0', id: 4, method: 'tools/call',
    params: { name: 'commit_lint', arguments: { message: 'feat!: big change' } },
  }]);
  const payload = JSON.parse(res.result.content[0].text);
  assert.equal(payload.bump, 'major');
  assert.equal(payload.breaking, true);
});

test('unknown tool returns a JSON-RPC error', async () => {
  const [res] = await rpc([{
    jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'nope', arguments: {} },
  }]);
  assert.ok(res.error);
  assert.equal(res.error.code, -32602);
});

test('unknown method returns method-not-found', async () => {
  const [res] = await rpc([{ jsonrpc: '2.0', id: 6, method: 'bogus/method' }]);
  assert.ok(res.error);
  assert.equal(res.error.code, -32601);
});

test('a tool that throws is reported in-band as isError', async () => {
  // roadmap_status with a path that escapes the project dir must fail safely.
  const [res] = await rpc([{
    jsonrpc: '2.0', id: 7, method: 'tools/call',
    params: { name: 'roadmap_status', arguments: { path: '/etc/passwd' } },
  }]);
  assert.equal(res.result.isError, true);
  assert.match(res.result.content[0].text, /escapes project directory/);
});

/* ── bug-hunt regressions (server robustness) ─────────────────────────── */

import { mkdtempSync, writeFileSync, mkdirSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

test('ledger_read: limit is clamped (0 → none, N → last N, none → all)', async () => {
  const proj = mkdtempSync(join(tmpdir(), 'dsf-ledger-'));
  mkdirSync(join(proj, '.factory'), { recursive: true });
  writeFileSync(join(proj, '.factory', 'ledger.jsonl'),
    ['{"sha":"a"}', '{"sha":"b"}', '{"sha":"c"}'].join('\n') + '\n');
  const call = (limit) => rpc([{
    jsonrpc: '2.0', id: 1, method: 'tools/call',
    params: { name: 'ledger_read', arguments: limit === undefined ? {} : { limit } },
  }], { env: { CLAUDE_PROJECT_DIR: proj } }).then(([r]) => JSON.parse(r.result.content[0].text));
  try {
    assert.equal((await call(0)).entries.length, 0);   // was slice(-0) === all
    assert.equal((await call(2)).entries.length, 2);
    assert.equal((await call(undefined)).entries.length, 3);
    assert.equal((await call(0)).count, 3);            // count is the full total
  } finally { rmSync(proj, { recursive: true, force: true }); }
});

test('safePath: an in-project symlink pointing outside the tree cannot exfiltrate', async () => {
  const proj = mkdtempSync(join(tmpdir(), 'dsf-proj-'));
  const outside = mkdtempSync(join(tmpdir(), 'dsf-out-'));
  writeFileSync(join(outside, 'secret.jsonl'), '{"secret":"exfiltrated"}\n');
  mkdirSync(join(proj, '.factory'), { recursive: true });
  symlinkSync(join(outside, 'secret.jsonl'), join(proj, '.factory', 'ledger.jsonl'));
  try {
    const [res] = await rpc([{
      jsonrpc: '2.0', id: 1, method: 'tools/call',
      params: { name: 'ledger_read', arguments: {} },
    }], { env: { CLAUDE_PROJECT_DIR: proj } });
    const text = res.result.content[0].text;
    assert.doesNotMatch(text, /exfiltrated/); // the outside file's content must not leak
  } finally {
    rmSync(proj, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  }
});
