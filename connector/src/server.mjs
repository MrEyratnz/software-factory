#!/usr/bin/env node
/**
 * Dark Software Factory — MCP connector (stdio transport).
 *
 * A zero-dependency Model Context Protocol server that exposes the factory's
 * rule engine (factory-core.mjs) as callable, deterministic tools. It speaks
 * newline-delimited JSON-RPC 2.0 over stdio (the MCP stdio framing: one JSON
 * message per line, no embedded newlines).
 *
 * All tools are READ-ONLY and side-effect free with respect to the repo: the
 * server reads files to feed the pure core, but never writes, deletes, or runs
 * commands. That is a deliberate safety posture — the connector advises; the
 * plugin's commands/agents are what actually change the tree, under the normal
 * permission system.
 *
 * Usage (wired by the plugin's .mcp.json):
 *   node ${CLAUDE_PLUGIN_ROOT}/connector/src/server.mjs
 */

import { readFileSync, readdirSync, realpathSync } from 'node:fs';
import { join, resolve, isAbsolute, dirname, basename, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';
import {
  parseRoadmap, indexAdrs, lintTechDebt, lintCommit, planRelease,
  roadmapCheck, gateEvaluate, techdebtAudit,
} from './factory-core.mjs';

const SERVER_NAME = 'dark-software-factory';
const SERVER_VERSION = '0.1.0';
const PROTOCOL_VERSION = '2024-11-05';

const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

/** Resolve a caller-supplied path against the project dir; reject escapes.
 * Canonicalizes with realpath so a symlink INSIDE the project that points
 * outside it (e.g. .factory/ledger.jsonl -> ~/.ssh/id_rsa) cannot exfiltrate an
 * out-of-tree file — a purely lexical resolve() would follow it. The check is
 * done against realpath(projectDir) so both sides are canonical. */
function safePath(p) {
  const abs = isAbsolute(p) ? resolve(p) : resolve(projectDir, p);
  let root;
  try { root = realpathSync(projectDir); } catch { root = resolve(projectDir); }
  // Canonicalize as far as the path exists — walking up to the DEEPEST existing
  // ancestor, then re-appending the not-yet-created tail — so symlinks anywhere
  // on the path are followed even when several trailing segments don't exist yet.
  let real = abs;
  try {
    real = realpathSync(abs);
  } catch {
    const tail = [];
    let cur = abs;
    real = abs;
    for (let i = 0; i < 64; i += 1) {
      const par = dirname(cur);
      if (par === cur) break;
      tail.unshift(basename(cur));
      cur = par;
      try { real = join(realpathSync(cur), ...tail); break; } catch { /* keep walking up */ }
    }
  }
  if (real !== root && !real.startsWith(root + sep)) {
    throw new Error(`path escapes project directory: ${p}`);
  }
  return real;
}

function readRoadmap(args) {
  return typeof args.markdown === 'string'
    ? args.markdown
    : readFileSync(safePath(args.path || 'docs/ROADMAP.md'), 'utf8');
}

function readAdrDir(dir) {
  const abs = safePath(dir);
  let names;
  try {
    names = readdirSync(abs);
  } catch {
    throw new Error(`cannot read ADR directory: ${dir}`);
  }
  return names
    .filter((n) => n.toLowerCase().endsWith('.md'))
    .map((filename) => ({
      filename,
      content: readFileSync(join(abs, filename), 'utf8'),
    }));
}

/* ── Tool registry: name → { schema, handler } ─────────────────────────── */

const TOOLS = {
  roadmap_status: {
    description:
      'Parse a milestone/checkbox roadmap (like docs/ROADMAP.md) and return ' +
      'per-milestone completion, overall progress, and the next unchecked item ' +
      'to work — the driver of the autonomous top-to-bottom loop.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'roadmap file path (default docs/ROADMAP.md)' },
        markdown: { type: 'string', description: 'raw roadmap text (overrides path)' },
      },
    },
    handler: (args) => parseRoadmap(readRoadmap(args)),
  },

  roadmap_next: {
    description:
      'Return only the next unchecked roadmap item {milestone, text, line} — ' +
      'the single work unit the autonomous loop picks up. null when the ' +
      'roadmap is complete.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string' },
        markdown: { type: 'string' },
      },
    },
    handler: (args) => ({ next: parseRoadmap(readRoadmap(args)).next }),
  },

  roadmap_check: {
    description:
      'Verdict on whether a roadmap item may be checked off. Refuses unless ' +
      'handed a merged-green SHA proof (from CI, not the local tree) — enforces ' +
      '"a box is checked only when merged with green tests". The write itself ' +
      'is done by the command layer.',
    inputSchema: {
      type: 'object',
      required: ['item'],
      properties: {
        item: { type: 'string', description: 'roadmap item text being flipped' },
        proof: {
          type: 'object',
          properties: {
            mergedGreenSha: { type: 'string' },
            item: { type: 'string' },
          },
        },
      },
    },
    handler: (args) => roadmapCheck(args.item, args.proof),
  },

  adr_index: {
    description:
      'Index numbered Architecture Decision Records in a directory: list each ' +
      'ADR (number, title, status, date) and compute the next ADR number.',
    inputSchema: {
      type: 'object',
      properties: {
        dir: { type: 'string', description: 'ADR directory (default docs/adr)' },
        entries: {
          type: 'array',
          description: 'inline [{filename, content}] (overrides dir)',
          items: { type: 'object' },
        },
      },
    },
    handler: (args) => {
      const entries = Array.isArray(args.entries)
        ? args.entries
        : readAdrDir(args.dir || 'docs/adr');
      return indexAdrs(entries);
    },
  },

  techdebt_lint: {
    description:
      'Validate that a deferred review finding carries everything the ' +
      'review→tech-debt convention requires (location file:line, impact, ' +
      'provenance pre-existing|introduced, suggested fix) before it becomes a ' +
      'tracked `tech-debt` issue.',
    inputSchema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        location: { type: 'string', description: 'file:line' },
        impact: { type: 'string', description: 'what it is and why it matters' },
        provenance: { type: 'string', enum: ['pre-existing', 'introduced'] },
        suggestedFix: { type: 'string' },
      },
    },
    handler: (args) => lintTechDebt(args),
  },

  commit_lint: {
    description:
      'Lint a Conventional Commit message and report its type/scope/breaking ' +
      'flag and the semver bump it implies (feat→minor, fix→patch, !→major).',
    inputSchema: {
      type: 'object',
      required: ['message'],
      properties: {
        message: { type: 'string' },
        maxHeader: { type: 'number', description: 'soft header length limit (default 100)' },
      },
    },
    handler: (args) => lintCommit(args.message, { maxHeader: args.maxHeader }),
  },

  release_plan: {
    description:
      'Given commit subjects since the last release and the current version, ' +
      'compute the next version and a grouped changelog (release-please-style). ' +
      'Set preMajor for the pre-1.0 policy (breaking→minor, feat→patch).',
    inputSchema: {
      type: 'object',
      required: ['commits', 'currentVersion'],
      properties: {
        commits: { type: 'array', items: { type: 'string' } },
        currentVersion: { type: 'string' },
        preMajor: { type: 'boolean' },
      },
    },
    handler: (args) =>
      planRelease(args.commits, args.currentVersion, { preMajor: args.preMajor }),
  },

  techdebt_audit: {
    description:
      'Given this session\'s review findings and the open `tech-debt` issues, ' +
      'return which findings are already filed and which are missing — a pure ' +
      'fingerprint set-diff that makes filing idempotent and drop-proof.',
    inputSchema: {
      type: 'object',
      required: ['findings'],
      properties: {
        findings: { type: 'array', items: { type: 'object' } },
        openIssues: {
          type: 'array',
          items: { type: 'object', properties: { title: { type: 'string' }, body: { type: 'string' } } },
        },
      },
    },
    handler: (args) => techdebtAudit(args.findings, args.openIssues || []),
  },

  gate_evaluate: {
    description:
      'Given per-stage suite results and the `git write-tree` hash of the ' +
      'tested tree, return the green/red verdict and the tree-bound receipt the ' +
      'commit gate later verifies. A receipt with no tree hash is never green.',
    inputSchema: {
      type: 'object',
      required: ['stages', 'treeHash'],
      properties: {
        stages: {
          type: 'array',
          items: {
            type: 'object',
            properties: { name: { type: 'string' }, ok: { type: 'boolean' }, exitCode: { type: 'number' } },
          },
        },
        treeHash: { type: 'string' },
      },
    },
    handler: (args) => gateEvaluate(args.stages, args.treeHash),
  },

  ledger_read: {
    description:
      'Read the append-only factory run ledger (.factory/ledger.jsonl) — one ' +
      'JSON object per line ({station, sha, subject}) — for the status ' +
      'dashboard and post-resume recovery. Only successful commits are ' +
      'recorded, so the ledger is survivor-biased.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'ledger path (default .factory/ledger.jsonl)' },
        limit: { type: 'number', description: 'return only the last N entries' },
      },
    },
    handler: (args) => {
      let text = '';
      try {
        text = readFileSync(safePath(args.path || '.factory/ledger.jsonl'), 'utf8');
      } catch {
        return { entries: [], count: 0 };
      }
      const entries = text.split('\n')
        .map((l) => l.trim())
        .filter(Boolean)
        .map((l) => { try { return JSON.parse(l); } catch { return { malformed: l }; } });
      // Guard the tail: slice(-0) is slice(0) (the WHOLE ledger), and a negative
      // limit slices from a positive offset — both wrong. Clamp to a
      // non-negative count so limit:0 returns nothing and limit:N the last N.
      let limited = entries;
      if (typeof args.limit === 'number' && Number.isFinite(args.limit)) {
        const n = Math.max(0, Math.floor(args.limit));
        limited = n === 0 ? [] : entries.slice(-n);
      }
      return { entries: limited, count: entries.length };
    },
  },
};

/* ── JSON-RPC plumbing ─────────────────────────────────────────────────── */

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function reply(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function replyError(id, code, message) {
  send({ jsonrpc: '2.0', id, error: { code, message } });
}

function handle(msg) {
  const { id, method, params } = msg;
  const isNotification = id === undefined || id === null;

  switch (method) {
    case 'initialize':
      reply(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      });
      return;

    case 'notifications/initialized':
    case 'initialized':
      return; // no response to notifications

    case 'ping':
      if (!isNotification) reply(id, {});
      return;

    case 'tools/list':
      reply(id, {
        tools: Object.entries(TOOLS).map(([name, t]) => ({
          name,
          description: t.description,
          inputSchema: t.inputSchema,
        })),
      });
      return;

    case 'tools/call': {
      const name = params?.name;
      const tool = TOOLS[name];
      if (!tool) {
        replyError(id, -32602, `unknown tool: ${name}`);
        return;
      }
      try {
        const result = tool.handler(params?.arguments ?? {});
        reply(id, {
          content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
        });
      } catch (err) {
        // Tool-level failure is reported in-band (isError) per MCP, so the
        // model sees the message rather than a transport error.
        reply(id, {
          content: [{ type: 'text', text: `Error: ${err.message}` }],
          isError: true,
        });
      }
      return;
    }

    default:
      if (!isNotification) replyError(id, -32601, `method not found: ${method}`);
  }
}

function main() {
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    let msg;
    try {
      msg = JSON.parse(trimmed);
    } catch {
      replyError(null, -32700, 'parse error');
      return;
    }
    try {
      handle(msg);
    } catch (err) {
      if (msg && msg.id != null) replyError(msg.id, -32603, `internal error: ${err.message}`);
    }
  });
  rl.on('close', () => process.exit(0));
}

// Export the pieces for in-process testing; only run stdio loop when invoked
// directly as a server.
export { TOOLS, handle };

// Compare DECODED filesystem paths. import.meta.url is a file:// URL whose
// .pathname percent-encodes special characters (a space -> %20, '[' -> %5B), so
// against the raw process.argv[1] the equality would fail whenever the plugin's
// install path contains a space or bracket — and the server would start, read
// nothing, and exit 0, exposing zero tools with no diagnostic. fileURLToPath
// decodes correctly.
const invokedDirectly =
  process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (invokedDirectly) main();
