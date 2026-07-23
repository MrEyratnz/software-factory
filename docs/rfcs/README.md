# RFC flow (owner: architect)

Decision standards for this repo, per the mission's spec discipline: intents,
decisions, and specs are repo artifacts, never just comments.

## When to use what

| Instrument | Use for | Lives at |
|---|---|---|
| **ADR** | a settled decision (or one to settle) with lasting shape impact | `docs/adr/NNNN-*.md` — house format per ADR 0001, numbering via `adr_index` |
| **RFC** | anything cross-cutting that needs proposal + review before it is decidable | `docs/rfcs/NNNN-<slug>.md` |
| **Spec-per-epic** | what/why + acceptance criteria before an epic starts | `docs/specs/<epic>/spec.md` + `plan.md`, linked from the epic's tracking issue |

## RFC lifecycle

`draft → review → accepted | rejected`

1. **Draft**: any agent writes `docs/rfcs/NNNN-<slug>.md` with frontmatter-style
   header lines: `Status: draft`, `Owner: <role>`, `Date: YYYY-MM-DD`, then
   Problem / Proposal / Alternatives / Impact sections. Number monotonically.
2. **Review**: the owning roles named in Impact comment on the RFC's PR;
   contested RFCs go to the judge-panel.
3. **Resolution**: `accepted` RFCs conclude in an ADR recording the decision
   (the RFC is the reasoning, the ADR is the record); `rejected` RFCs keep
   their status and stay — rejection reasons are knowledge.

The architect may adopt community formats (e.g. MADR) by writing the ADR that
says so; until then the house ADR format of ADR 0001 is the standard.
