<!-- Conventional title (feat:/fix:/docs:/chore: …). Suite green at every commit. -->

## What & why

<!-- One paragraph: the change and the concrete failure/cost it addresses. -->

## Checklist

- [ ] Failing test written first; full suite (`bash tests/run-suite.sh`) green
- [ ] Conventional Commit title; suite green at every commit
- [ ] If this PR closes an issue carrying a `fingerprint:` trailer, that
      fingerprint is cited in a **branch commit message** (not only the
      editable PR body). The repo's squash policy
      (`squash_merge_commit_message: COMMIT_MESSAGES`) carries every
      branch commit message into the default-branch squash commit — the
      immutable evidence the close-audit's fingerprint binding reads
      (ADR 0006 § D4; auditor lands on the M4 track). Forgotten → a
      follow-up default-branch commit naming issue + fingerprint
      remediates.
- [ ] Review findings not fixed here are filed as `tech-debt` issues
