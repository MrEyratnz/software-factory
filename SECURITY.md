# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
pull requests, or discussions.**

Report privately through GitHub's **[private vulnerability
reporting](https://github.com/MrEyratnz/software-factory/security/advisories/new)**
(the **Security** tab → **Report a vulnerability**). This opens a private
advisory visible only to you and the maintainers.

Please include as much of the following as you can:

- The component affected (a hook in `hooks/`, the MCP connector in
  `connector/`, a command/agent, or the CI workflows).
- A description of the issue and its impact — for this project, the most
  relevant classes are **gate bypass** (a way to get a red commit, an
  unmerged roadmap check-off, or a release-from-red past the hooks/CI),
  **path-fence escape** (a role writing outside its least-privilege scope),
  and **command/receipt forgery** in the guard scripts.
- Reproduction steps or a proof-of-concept, and the affected version or commit.

You can expect an initial acknowledgement within **5 business days**. We will
keep you informed as we investigate, and will credit you in the advisory when a
fix ships unless you prefer to remain anonymous.

## Scope

This is a Claude Code plugin: enforcement hooks, a zero-dependency read-only MCP
connector, commands/agents/skills, and CI. It ships **no runtime dependencies**
and stores **no secrets**. In-scope reports concern the integrity of the
factory's invariants and the safety of the code it runs on a contributor's
machine or in CI.

Out of scope: vulnerabilities in Claude Code itself (report those to Anthropic),
in Node.js, or in third-party GitHub Actions (report to their maintainers; we
track their updates via Dependabot).

## Supported versions

This project releases from `main` via automated Conventional-Commit releases.
Only the **latest released version** is supported; fixes ship forward in a new
release rather than as backports.
