# software-factory — working agreements for Claude

Conventions Claude should follow when working in this repository.

## Code review

- **Unfixed findings become tracked tech-debt.** Any finding from a code
  review — including adversarial reviews and re-reviews of a PR — that is
  **not fixed in the current PR** must be opened as a GitHub issue labeled
  `tech-debt`, so it doesn't get lost. This applies to:
  - pre-existing problems a review happens to surface, and
  - anything deliberately deferred / left out of the current PR's scope.
- When filing such an issue, include: the location (`file:line`), what it is
  and why it matters (a concrete failure or cost), its provenance
  (pre-existing vs. introduced by the change under review), and a suggested
  fix.
- Create the `tech-debt` label if it does not already exist in the repo.
- Do **not** silently drop a finding or bury it only in chat — if it isn't
  being fixed now, it gets an issue.
