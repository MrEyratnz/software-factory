---
description: Generate, show, reorder, or check off docs/ROADMAP.md milestones and mirror changes to the GitHub meta tracking issue.
argument-hint: "[--from-vision | show | check <item> | reorder]"
---

Manage the roadmap: `$ARGUMENTS`

- **show** (default): read the connector `roadmap_status` and print per-milestone
  completion, overall %, and the next unchecked item.
- **--from-vision**: set `echo architect > .factory/active-agent`, then dispatch
  the **architect** to (re)generate `docs/ROADMAP.md` as milestones `M0..Mn` of
  ordered `- [ ]` items derived from VISION + ARCHITECTURE, worked top-to-bottom.
- **reorder**: set `echo architect > .factory/active-agent`, then dispatch the
  **architect** to reorder items (never pre-check).
- **check <item>**: attempt to flip `- [ ]` → `- [x]`. This is gated: the
  connector `roadmap_check` refuses without a merged-green SHA proof for that
  item, and `guard-roadmap` blocks the edit otherwise (it also blocks the `Write`
  tool, not just `Edit`/`MultiEdit`, so the box can't be flipped by rewriting the
  whole file). A box is checked ONLY when the item merged with green tests —
  never in advance.

  The proof at `.factory/state/roadmap-proof.json` is authoritative only when it
  comes from **CI / the runner**, which has direct filesystem access and is not
  gated — the same trust model as the receipt-signing key. The policed agent is
  deliberately forbidden from writing it (that would make the honesty gate
  theater): CI, after confirming the item's PR merged green, writes the
  item-bound `{mergedGreenSha, item}` proof. In an un-initialized repo the gate
  is advisory (there is nothing to enforce yet).

Mirror any structural change to the GitHub meta tracking issue.
