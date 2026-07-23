# Vision

## Problem

Agentic coding tools drift: they skip tests under pressure, commit red, check
roadmap boxes early, and release unverified artifacts — and every team
re-invents ad-hoc process to stop them. The discipline exists as prose, not as
enforcement, so it erodes exactly when it matters (long sessions, autonomy,
no human watching).

## Outcome

A Claude Code plugin you drop into any repository that runs it as a
**lights-out software factory**: docs spine, TDD roadmap loop, adversarial
review that auto-files tech-debt, judge-panel design, gated
Conventional-Commit releases — with the laws enforced by hooks locally and
re-enforced by CI as the authoritative boundary. This repo is also the proof:
the factory builds, tests, reviews, and ships the plugin itself, autonomously,
in GitHub Actions, with humans reduced to one bootstrap run and two kill
switches.

## Principles

- **Enforced beats documented** — a law that isn't a denied precondition is a
  suggestion; hooks + CI, never prose alone.
- **CI is the authoritative boundary** — local gates are fail-early UX.
- **Security is the first pillar** — nothing ships that weakens it.
- **Effectiveness floor, then efficiency** — green gates and eval thresholds
  are inviolable; within them, drive cost-per-outcome down relentlessly.
- **Dogfood or it doesn't count** — the factory's improvements flow through
  its own backlog, gates, and releases.

## Non-goals

- A general CI platform or runner fleet — GitHub Actions is the substrate.
- Multi-repo orchestration (one factory per repository).
- Replacing human judgment where GitHub requires a human (account creation,
  KYC/banking, app-install clicks) — those stay one-time bootstrap acts.
- Model training or evaluation infrastructure beyond this plugin's own evals.
