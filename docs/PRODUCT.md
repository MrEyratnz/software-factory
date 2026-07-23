# Product — backlog policy (owner: product-owner)

The product is the plugin; the customer is any repo that installs it. Value is
measured against the standing goal: **satisfy the v1.0.0 Release Gate**
(`docs/specs/epic-1/spec.md`).

## Value-ranking rules

1. `security` findings outrank everything at equal priority (first pillar).
2. Work that moves the v1.0.0 Release Gate (Epic 1 suite, gate plumbing,
   release path) outranks work that doesn't.
3. `bug` > `tech-debt` > `efficiency` > `ux` > `idea`/`research` at equal
   gate-relevance.
4. Cost matters second: between two items of equal value, pick the cheaper
   (the efficiency engineer's data decides ties).

Every priority decision gets a one-line rationale on the issue. Re-ranking is
cheap; silent ambiguity is not — decide, record, move.

## Milestones

- **v1.0.0** — Epic 1 suite + autonomous-SDLC hardening + the Release Gate
  (see `docs/ROADMAP.md` M1–M3).
- **v1.1.0** — everything the freeze deflects; re-ranked after 1.0 ships.

## Feature freeze

When the Release Gate is within one sprint of holding, the freeze is ON:
every new `idea`/`research`/retro issue goes to v1.1.0. New scope can never
reopen the v1.0 gate — only a genuine `bug` can enter the frozen milestone,
and it must be fixed, not deferred. Freeze state is recorded here when it
flips, with the date and the gate evidence.

**Freeze state: OFF** (gate not yet within one sprint of holding).
