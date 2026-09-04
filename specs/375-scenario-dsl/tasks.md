# Tasks — #375 scenario DSL

Artifact ceiling: 3,000 bytes and 90 lines.

## S375-1 — shared grammar, runnable compiler, pages, and proof

- [ ] **T375-01** Implement the single versioned shared grammar/parser and
  consumer mismatch assertion. Covers REQ-375-01, REQ-375-02,
  INV-375-ONE.
- [ ] **T375-02** Ship the documented Node DSL-to-JSON and JSON-to-DSL command.
  Covers REQ-375-03, INV-375-RUNNABLE.
- [ ] **T375-03** Author DSL sources for the discovered 30-scenario corpus and
  prove complete lossless round-trip. Covers REQ-375-04, REQ-375-05,
  INV-375-LOSSLESS, INV-375-EXTENT.
- [ ] **T375-04** Add checkpoint page paste/file admission through the shared
  grammar and existing story runner. Covers REQ-375-06, INV-375-PLAY.
- [ ] **T375-05** Add registry page paste/file admission through the shared
  grammar and existing story runner. Covers REQ-375-06, INV-375-PLAY.
- [ ] **T375-06** Add current-branch DSL copy/download export to both pages and
  prove recompilation/replay parity. Covers REQ-375-07, INV-375-EXPORT.
- [ ] **T375-07** Add whole-document file:line refusal and atomic page/CLI
  negative controls. Covers REQ-375-08, INV-375-ATOMIC.
- [ ] **T375-08** Document the grammar and workflows; retain deterministic
  page/build identity and all exact ticket gates. Covers REQ-375-09,
  REQ-375-10, INV-375-SCOPE.
