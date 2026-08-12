<!-- Conventional title (feat:/fix:/docs:/chore: …). Suite green at every commit. -->

## What & why

<!-- One paragraph: the change and the concrete failure/cost it addresses. -->

## Checklist

- [ ] Failing test written first; full suite (`bash tests/run-suite.sh`) green
- [ ] If this PR closes an issue carrying a `fingerprint:` trailer, that same
      fingerprint is cited in a **commit message** (immutable evidence — the
      nightly close-audit's legitimacy bindings, ADR 0006 § D4, do not
      accept the editable PR body; if forgotten, a follow-up commit naming
      issue + fingerprint remediates)
- [ ] Review findings not fixed here are filed as `tech-debt` issues
