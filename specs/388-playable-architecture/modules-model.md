# Responsibilities

- docs/architecture/follow-one-identity.md: the progressive reading path and expected observations.
- docs/architecture/scenarios/: canonical copy/download scenario documents (see data-model.md).
- scripts/check-architecture-scenarios.mjs: validate documentation examples through existing parsers and replay cores (see functions-model.md).
- mkdocs.yml: reusable snippet rendering and chapter navigation.
- .github/workflows/deploy-docs.yml: checks on the built documentation artifact.

Dependency direction: documentation check consumes scenario grammar and simulator cores; neither core depends on documentation. No new runtime dependency.
