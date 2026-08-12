<!-- Conventional title (feat:/fix:/docs:/chore: …). Suite green at every commit. -->

## What & why

<!-- One paragraph: the change and the concrete failure/cost it addresses. -->

## Checklist

- [ ] Conventional Commit title; full suite (`bash tests/run-suite.sh`) green
- [ ] Code changes: failing test written first (docs/chore-only PR: N/A)
- [ ] If this PR closes an issue carrying a `fingerprint:` trailer, that
      fingerprint is cited in a **branch commit message**
      <!-- Why a branch commit message: the repo's squash policy carries it
           into the default-branch squash commit, where it becomes the
           immutable evidence the close-audit's fingerprint binding reads —
           mechanism owned by ADR 0006 § D4 (auditor not yet built; the
           squash-policy pin is tracked in #1483). Forgot? A follow-up
           default-branch commit naming issue + fingerprint remediates. -->
- [ ] Review findings not fixed here are filed as `tech-debt` issues
