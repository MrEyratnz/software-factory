# Dark Software Factory — connector

A **zero-dependency [Model Context Protocol](https://modelcontextprotocol.io)
server** that exposes the factory's rule engine as deterministic, read-only
tools. It is bundled with the `dark-software-factory` plugin and wired up by the
plugin's [`.mcp.json`](../.mcp.json); you do not run it by hand.

## Why a connector

The factory's *rules* — which roadmap item is next, what the next ADR number is,
whether a review finding is complete enough to file, whether a commit message is
release-shaped, what version the next release should be — are the kind of thing
that is far more reliable as **code** than as prose an agent re-derives each time.
So they live here as pure functions (`src/factory-core.mjs`), unit-tested to
byte-identical output, and are surfaced to Claude as MCP tools by a thin stdio
server (`src/server.mjs`).

Every tool is **side-effect free**: the server reads files to feed the pure core
but never writes, deletes, or executes anything. The connector *advises*; the
plugin's commands and agents are what change the tree, under Claude Code's normal
permission system.

## Tools

| Tool | What it does |
|---|---|
| `roadmap_status` | Parse a milestone/checkbox roadmap; return per-milestone completion, overall progress, and the **next unchecked item** — the driver of the autonomous top-to-bottom loop. |
| `adr_index` | Index numbered ADRs (number, title, status, date) and compute the **next ADR number**. |
| `techdebt_lint` | Check a deferred review finding carries everything the review→tech-debt convention needs (location `file:line`, impact, provenance, suggested fix) before it becomes a `tech-debt` issue. |
| `commit_lint` | Lint a Conventional Commit and report the semver **bump** it implies (`feat`→minor, `fix`→patch, `!`→major). |
| `release_plan` | From commit subjects + current version, compute the **next version** and a grouped changelog (release-please-style; `preMajor` for the pre-1.0 policy). |

## Transport

Newline-delimited JSON-RPC 2.0 over stdio (MCP stdio framing: one JSON message
per line, no embedded newlines). Path arguments are resolved against
`CLAUDE_PROJECT_DIR` and rejected if they escape it.

## Develop

```bash
cd connector
npm test          # node --test — pure-core unit tests + a real stdio handshake
```

No install step: the server and its tests use only the Node standard library
(`node >= 18`).
