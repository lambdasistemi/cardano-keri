# Models — #355 (docs-only slice; no code modules/data/functions change)

## Modules model

- M355-01 `docs/user/*`: story-family pages + preprod guides. Owned files:
  register, rotate, poison (wherever the poison story lives), close,
  reopen/revival, hunters, consumer checklist, follower, query-endpoint,
  m1-preprod-deployment, discovery-endpoint-board, releases,
  status-backends, preprod-witness-pool. Dependency: may link simulator
  pages and Lean sources by path; never link the deleted triple.
- M355-02 `docs/architecture/*`, `docs/design/*`: system description.
  Owned: observer-architecture, veridian-bridge, amaru-integration,
  operational, aid-model, defi-gate, record-cursor-projection-fidelity,
  business-cases/*, registry-as-mpfs (surveyed, kept consistent).
  Already done: identity-ops, overview, system, super-watcher,
  trust-model, user-experience, key-compromise, vlei, value-auth.
- M355-03 entry pages: `index`, `roadmap`, `story-ladder` (history),
  `why-cardano`, `blog/self-certifying-identities-on-cardano.md`,
  `identity-on-cardano/PROMPT.md`, `vetting/*`, `mkdocs.yml` nav.
- No new abstractions. No code, test, fixture, migration, or shipped-config
  changes. Forbidden: `lean/`, `simulator/`, CI workflows, anything outside
  `docs/`, `mkdocs.yml`, `specs/355-user-guide-m1-return/tasks.md`.

## Data model

See `data-model.md` (nav map only; no schema changes).

## Functions model

See `functions-model.md` (frozen slice gate only; no signatures change).
