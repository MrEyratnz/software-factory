#!/usr/bin/env node
// tests/static/plugin-schema-check.mjs — Epic 1 layer 1 (full depth): static
// validation for every command/agent/skill/hook config this plugin ships.
// Four checks, matching docs/specs/epic-1/spec.md layer 1:
//   1. manifest + frontmatter schema (required fields, correctly typed)
//   2. ${CLAUDE_PLUGIN_ROOT} path portability (no absolute/repo-relative
//      plugin-file references — they break the moment this plugin is
//      installed into a target repo, where cwd != the plugin's install dir)
//   3. referenced files exist (every ${CLAUDE_PLUGIN_ROOT}/<path> resolves,
//      every hooks.json command target resolves)
//   4. JSON validity (every plugin-shipped .json config parses)
//
// Zero-dep (fs/path only), deterministic, hermetic — no network, no globs
// beyond readdir. Exports runChecks(root) -> string[] (empty = clean) so
// tests/scaffold.contract.test.sh can point it at a corrupted fixture copy
// and prove each check actually fires, not just that the real tree is clean.
// Also runnable directly: `node plugin-schema-check.mjs [root]`.

import fs from "node:fs";
import path from "node:path";

function nonEmptyString(v) {
  return typeof v === "string" && v.trim().length > 0;
}

// Frontmatter here is always flat `key: value` lines between a pair of `---`
// lines (verified against every command/agent/skill file in this repo) — no
// nested YAML, no multi-line folds. A real YAML parser would be overkill and
// would add a dependency this zero-dep suite deliberately avoids.
function readFrontmatter(file) {
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split("\n");
  if (lines[0] !== "---") return null;
  const end = lines.indexOf("---", 1);
  if (end === -1) return null;
  const fm = {};
  for (const line of lines.slice(1, end)) {
    const m = line.match(/^([A-Za-z][A-Za-z0-9_-]*):[ \t]*(.*)$/);
    if (!m) continue;
    let val = m[2].trim();
    if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) val = val.slice(1, -1);
    fm[m[1]] = val;
  }
  return fm;
}

function loadJson(root, relPath, violations, { required = true } = {}) {
  const file = path.join(root, relPath);
  if (!fs.existsSync(file)) {
    if (required) violations.push(`${relPath}: missing (required plugin JSON config)`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    violations.push(`${relPath}: invalid JSON (${e.message})`);
    return null;
  }
}

// --- 1. manifest + frontmatter schema ---------------------------------------

function checkCommands(root, violations) {
  const dir = path.join(root, "commands");
  if (!fs.existsSync(dir)) return;
  for (const name of fs.readdirSync(dir).filter((f) => f.endsWith(".md"))) {
    const rel = path.join("commands", name);
    const fm = readFrontmatter(path.join(root, rel));
    if (!fm) {
      violations.push(`${rel}: missing/malformed frontmatter (must open+close with ---)`);
      continue;
    }
    if (!nonEmptyString(fm.description)) violations.push(`${rel}: frontmatter missing required non-empty "description"`);
    if ("argument-hint" in fm && !nonEmptyString(fm["argument-hint"])) violations.push(`${rel}: "argument-hint" present but empty`);
    if ("allowed-tools" in fm && !nonEmptyString(fm["allowed-tools"])) violations.push(`${rel}: "allowed-tools" present but empty`);
  }
}

function checkAgents(root, violations) {
  const dir = path.join(root, "agents");
  if (!fs.existsSync(dir)) return;
  for (const name of fs.readdirSync(dir).filter((f) => f.endsWith(".md"))) {
    const rel = path.join("agents", name);
    const expectedName = name.slice(0, -3);
    const fm = readFrontmatter(path.join(root, rel));
    if (!fm) {
      violations.push(`${rel}: missing/malformed frontmatter (must open+close with ---)`);
      continue;
    }
    if (!nonEmptyString(fm.name)) violations.push(`${rel}: frontmatter missing required non-empty "name"`);
    else if (fm.name !== expectedName) violations.push(`${rel}: frontmatter name "${fm.name}" does not match filename "${expectedName}"`);
    if (!nonEmptyString(fm.description)) violations.push(`${rel}: frontmatter missing required non-empty "description"`);
  }
}

function checkSkills(root, violations) {
  const dir = path.join(root, "skills");
  if (!fs.existsSync(dir)) return;
  for (const skillDir of fs.readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name)) {
    const rel = path.join("skills", skillDir, "SKILL.md");
    if (!fs.existsSync(path.join(root, rel))) {
      violations.push(`${rel}: skill directory "${skillDir}" has no SKILL.md`);
      continue;
    }
    const fm = readFrontmatter(path.join(root, rel));
    if (!fm) {
      violations.push(`${rel}: missing/malformed frontmatter (must open+close with ---)`);
      continue;
    }
    if (!nonEmptyString(fm.name)) violations.push(`${rel}: frontmatter missing required non-empty "name"`);
    else if (fm.name !== skillDir) violations.push(`${rel}: frontmatter name "${fm.name}" does not match skill directory "${skillDir}"`);
    if (!nonEmptyString(fm.description)) violations.push(`${rel}: frontmatter missing required non-empty "description"`);
  }
}

function checkPluginManifests(root, violations) {
  const plugin = loadJson(root, ".claude-plugin/plugin.json", violations);
  if (plugin) {
    for (const key of ["name", "version", "description"]) {
      if (!nonEmptyString(plugin[key])) violations.push(`.claude-plugin/plugin.json: missing required non-empty "${key}"`);
    }
    if (nonEmptyString(plugin.version) && !/^\d+\.\d+\.\d+/.test(plugin.version)) {
      violations.push(`.claude-plugin/plugin.json: "version" is not semver-shaped (${plugin.version})`);
    }
  }

  const marketplace = loadJson(root, ".claude-plugin/marketplace.json", violations);
  if (marketplace) {
    for (const key of ["name", "owner", "plugins"]) {
      if (!(key in marketplace)) violations.push(`.claude-plugin/marketplace.json: missing required "${key}"`);
    }
    if (Array.isArray(marketplace.plugins)) {
      if (marketplace.plugins.length === 0) violations.push(`.claude-plugin/marketplace.json: "plugins" must not be empty`);
      marketplace.plugins.forEach((p, i) => {
        for (const key of ["name", "source", "version"]) {
          if (!nonEmptyString(p?.[key])) violations.push(`.claude-plugin/marketplace.json: plugins[${i}] missing required non-empty "${key}"`);
        }
      });
    } else if ("plugins" in marketplace) {
      violations.push(`.claude-plugin/marketplace.json: "plugins" must be an array`);
    }
  }
}

// --- 2 + 3. hooks.json: command portability + referenced-file-exists --------

function checkHooksManifest(root, violations) {
  const rel = "hooks/hooks.json";
  const manifest = loadJson(root, rel, violations);
  if (!manifest) return;
  const hooks = manifest.hooks;
  if (typeof hooks !== "object" || hooks === null) {
    violations.push(`${rel}: missing top-level "hooks" object`);
    return;
  }
  for (const [event, entries] of Object.entries(hooks)) {
    if (!Array.isArray(entries)) {
      violations.push(`${rel}: hooks.${event} must be an array`);
      continue;
    }
    entries.forEach((entry, i) => {
      const list = entry?.hooks;
      if (!Array.isArray(list)) {
        violations.push(`${rel}: hooks.${event}[${i}] missing "hooks" array`);
        return;
      }
      list.forEach((h, j) => {
        const loc = `hooks.${event}[${i}].hooks[${j}]`;
        if (!nonEmptyString(h.type)) violations.push(`${rel}: ${loc} missing "type"`);
        if (!nonEmptyString(h.command)) {
          violations.push(`${rel}: ${loc} missing "command"`);
          return;
        }
        const cmd = h.command;
        // Portability: a hook command is invoked with cwd = the TARGET repo,
        // not this plugin's install location, so any path it references must
        // be anchored at ${CLAUDE_PLUGIN_ROOT} — never absolute (only valid on
        // the machine that authored it) and never repo-relative (resolves
        // against the wrong tree entirely once installed elsewhere).
        if (/^\//.test(cmd)) {
          violations.push(`${rel}: ${loc} command "${cmd}" is an absolute path — use \${CLAUDE_PLUGIN_ROOT}/...`);
        } else if (/^\.\.?\//.test(cmd)) {
          violations.push(`${rel}: ${loc} command "${cmd}" is a repo-relative path — use \${CLAUDE_PLUGIN_ROOT}/...`);
        } else if (cmd.includes("/") && !cmd.startsWith("${CLAUDE_PLUGIN_ROOT}/")) {
          violations.push(`${rel}: ${loc} command "${cmd}" references a path without \${CLAUDE_PLUGIN_ROOT}`);
        }
        if (cmd.startsWith("${CLAUDE_PLUGIN_ROOT}/")) {
          const target = cmd.slice("${CLAUDE_PLUGIN_ROOT}/".length).split(/\s+/)[0];
          if (!fs.existsSync(path.join(root, target))) {
            violations.push(`${rel}: ${loc} references ${target}, which does not exist`);
          }
        }
      });
    });
  }
}

// --- 2 + 3. free-text scan over docs: portability + referenced-file-exists --

// A plugin-shipped path hardcoded as an absolute host path or a dot-relative
// escape, in prose/examples inside a command, agent, or skill file — the same
// class of bug as an unportable hooks.json command, just in Markdown instead
// of JSON.
const ABSOLUTE_HOST_PATH = /(^|[\s"'`(])(\/(?:home|Users|root)\/[A-Za-z0-9_./-]*)/g;
const DOT_RELATIVE_PLUGIN_PATH = /(^|[\s"'`(])(\.\.?\/(?:hooks|scripts|connector|templates|schemas)\/[A-Za-z0-9_./*-]*)/g;
const PLUGIN_ROOT_REF = /\$\{CLAUDE_PLUGIN_ROOT\}\/([A-Za-z0-9_./*-]+)/g;

function scanTextFile(root, relPath, violations) {
  const file = path.join(root, relPath);
  if (!fs.existsSync(file)) return;
  const text = fs.readFileSync(file, "utf8");

  for (const m of text.matchAll(ABSOLUTE_HOST_PATH)) {
    violations.push(`${relPath}: hardcoded absolute path "${m[2]}" — use \${CLAUDE_PLUGIN_ROOT}/... instead`);
  }
  for (const m of text.matchAll(DOT_RELATIVE_PLUGIN_PATH)) {
    violations.push(`${relPath}: repo-relative path "${m[2]}" — use \${CLAUDE_PLUGIN_ROOT}/... instead`);
  }
  for (const m of text.matchAll(PLUGIN_ROOT_REF)) {
    let target = m[1];
    if (target.includes("*")) continue; // a glob description (e.g. hooks/scripts/**), not a literal path
    if (target.endsWith("/")) target = target.slice(0, -1);
    if (!fs.existsSync(path.join(root, target))) {
      violations.push(`${relPath}: references \${CLAUDE_PLUGIN_ROOT}/${target}, which does not exist`);
    }
  }
}

function walkMarkdown(root, dir, violations) {
  const abs = path.join(root, dir);
  if (!fs.existsSync(abs)) return;
  for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
    const rel = path.join(dir, entry.name);
    if (entry.isDirectory()) walkMarkdown(root, rel, violations);
    else if (entry.name.endsWith(".md")) scanTextFile(root, rel, violations);
  }
}

// --- 4. JSON validity for every remaining plugin-shipped .json config -------

function checkRemainingJson(root, violations) {
  loadJson(root, ".mcp.json", violations, { required: false });
  const schemasDir = path.join(root, "schemas");
  if (fs.existsSync(schemasDir)) {
    for (const f of fs.readdirSync(schemasDir).filter((n) => n.endsWith(".json"))) {
      loadJson(root, path.join("schemas", f), violations);
    }
  }
}

export function runChecks(root) {
  const violations = [];
  checkCommands(root, violations);
  checkAgents(root, violations);
  checkSkills(root, violations);
  checkPluginManifests(root, violations);
  checkHooksManifest(root, violations);
  checkRemainingJson(root, violations);
  walkMarkdown(root, "commands", violations);
  walkMarkdown(root, "agents", violations);
  walkMarkdown(root, "skills", violations);
  scanTextFile(root, ".mcp.json", violations);
  return violations;
}

const isMain = process.argv[1] && import.meta.url === `file://${path.resolve(process.argv[1])}`;
if (isMain) {
  const root = process.argv[2] || process.cwd();
  const violations = runChecks(root);
  if (violations.length) {
    for (const v of violations) console.error(v);
    console.error(`${violations.length} static-validation violation(s)`);
    process.exit(1);
  }
  console.log("plugin static validation: clean");
}
