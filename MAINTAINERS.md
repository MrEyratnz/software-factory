# Maintainers

## Human maintainers

| Name | GitHub | Role |
|---|---|---|
| Ryan (MrEyratnz) | [@MrEyratnz](https://github.com/MrEyratnz) | Owner; holds the kill switches (`FACTORY_HALT`, `.factory/state/paused`) and the accounts (funding handles, GitHub Apps) only a human can create |

## Agent maintainers

Day-to-day maintenance is performed by the factory's agent roles under
`agents/`, each acting through its own least-privilege GitHub App identity
(`<agent>[bot]`) — see `GOVERNANCE.md` for who owns which decision and
`docs/security/README.md` for the permission model.

## Becoming a maintainer

External contributions are welcome via PRs (see `CONTRIBUTING.md`); they are
reviewed by the factory and never receive secrets. Human maintainership is
granted by the repository owner.
