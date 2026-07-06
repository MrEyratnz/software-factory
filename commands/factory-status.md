---
description: Read-only dashboard — roadmap cursor and % complete, next item, local gate state, open tech-debt count, recent ledger entries, and last release.
argument-hint: "(none)"
allowed-tools: Bash, Read
---

Print the factory dashboard (read-only, no agent dispatch):

- **Roadmap**: connector `roadmap_status` → per-milestone completion, overall %,
  and the next unchecked item.
- **Gate**: is there a green receipt in `.factory/state/gate-receipt.json` whose
  tree matches the working tree (green) or is it stale/absent?
- **Tech-debt**: count of open GitHub issues labeled `tech-debt`.
- **Ledger**: the last few entries from `.factory/ledger.jsonl` (connector
  `ledger_read`) — station, sha, subject.
- **Release**: the latest tag/release.

This is the same view the SessionStart and UserPromptSubmit hooks inject as
context, on demand.
