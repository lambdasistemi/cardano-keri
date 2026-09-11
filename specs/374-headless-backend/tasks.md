# Tasks — #374 headless simulator backends

Artifact ceiling: 3,000 bytes and 90 lines.

## S374-1 — importable backends, CLIs, generated pages, and proof

- [x] **T374-01** Implement the pure checkpoint backend and complete story,
  fork, challenge, and free-play boundary. Covers REQ-374-01, REQ-374-03..05,
  INV-374-PURE, INV-374-PARITY, INV-374-FREE.
- [x] **T374-02** Implement the pure registry backend with the same capability
  shape and separate machine semantics. Covers REQ-374-02..05,
  INV-374-PURE, INV-374-PARITY, INV-374-FREE.
- [x] **T374-03** Ship both deterministic Node CLIs for trunk and fork replay
  with closed argument/error behavior. Covers REQ-374-06, INV-374-CLI.
- [x] **T374-04** Add `@@BACKEND@@` source/page reconciliation and executable
  stale/fork/missing-slice controls to both build checks. Covers REQ-374-07,
  INV-374-BUILD.
- [x] **T374-05** Refactor both pages to render backend-owned trees while
  retaining controls, branch behavior, and minidom smoke. Covers REQ-374-08,
  REQ-374-09, INV-374-RENDER.
- [x] **T374-06** Add discovered, non-vacuous behavioral controls for all
  stories/forks, free-play operations, purity, CLI refusal, and exact baseline
  signatures. Covers INV-374-EXTENT and all other executable invariants.
- [x] **T374-07** Document the stable backend and CLI consumer surface and prove
  forbidden scenario/core/grammar bytes are unchanged. Covers REQ-374-10,
  INV-374-SCOPE.
