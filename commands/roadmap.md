---
description: Generate, show, reorder, or check off docs/ROADMAP.md milestones and mirror changes to the GitHub meta tracking issue.
argument-hint: "[--from-vision | show | check <item> | reorder]"
---

Manage the roadmap: `$ARGUMENTS`

- **show** (default): read the connector `roadmap_status` and print per-milestone
  completion, overall %, and the next unchecked item.
- **--from-vision**: dispatch the **architect** to (re)generate `docs/ROADMAP.md`
  as milestones `M0..Mn` of ordered `- [ ]` items derived from VISION +
  ARCHITECTURE, worked top-to-bottom.
- **reorder**: dispatch the **architect** to reorder items (never pre-check).
- **check <item>**: attempt to flip `- [ ]` → `- [x]`. This is gated: the
  connector `roadmap_check` refuses without a merged-green SHA proof for that
  item, and `guard-roadmap` blocks the edit otherwise. A box is checked ONLY when
  the item merged with green tests — never in advance.

Mirror any structural change to the GitHub meta tracking issue.
