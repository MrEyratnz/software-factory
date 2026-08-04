<!-- Conventional title (feat:/fix:/docs:/chore: …). Suite green at every commit. -->

## What & why

<!-- One paragraph: the change and the concrete failure/cost it addresses. -->

## Checklist

- [ ] Failing test written first; full suite (`bash tests/run-suite.sh`) green
- [ ] If this PR closes an issue carrying a `fingerprint:` trailer, that same
      fingerprint is cited here or in a commit message — the Release Gate's
      close-laundering exemption (`docs/specs/epic-1/spec.md`
      § "Release Gate for v1.0.0") requires it to credit the close as a real
      fix (the PR body stays editable after merge if forgotten)
- [ ] Review findings not fixed here are filed as `tech-debt` issues
