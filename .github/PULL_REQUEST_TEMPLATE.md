<!-- Conventional title (feat:/fix:/docs:/chore: …). Suite green at every commit. -->

## What & why

<!-- One paragraph: the change and the concrete failure/cost it addresses. -->

## Checklist

- [ ] Failing test written first; full suite (`bash tests/run-suite.sh`) green
- [ ] Conventional Commit title; suite green at every commit
- [ ] If this PR closes an issue carrying a `fingerprint:` trailer, the
      fingerprint appears in this PR's commit messages, and **whoever
      merges must carry it into the squash/merge commit message** — in
      this squash-only repo a branch-only citation is dropped by the
      squash and does not count (immutable evidence — the nightly
      close-audit's legitimacy bindings, ADR 0006 § D4, do not accept
      the editable PR body; if forgotten, a follow-up default-branch
      commit naming issue + fingerprint remediates)
- [ ] Review findings not fixed here are filed as `tech-debt` issues
