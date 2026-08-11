# Tasks — #266 GHC-derived public export surface

Artifact ceiling: 4,000 bytes and 110 lines.

## S266-1 — compiler-owned public surface guard

- [x] **T266-S1-01** Add the isolated GHC compiler-surface test-support
  boundary and closed failure type.
- [x] **T266-S1-02** Enumerate every Cabal-exposed library module through one
  GHC session, retaining route and defining identities.
- [x] **T266-S1-03** Replace the #262 guard's source-derived export/signature
  enumeration without changing its behavioral property.
- [x] **T266-S1-04** Permanently cover nested comments/fake headers,
  Haddock/comments/strings containing `module`, and byte-zero or unavailable
  source/module inputs.
- [x] **T266-S1-05** Permanently cover multiline wildcard-record fields,
  operators, local/imported/module re-exports, defining-module types, and
  capabilities nested under containers.
- [x] **T266-S1-06** Remove obsolete export-list, signature, record-field, and
  comment/string scanning from the public-surface enumeration path.
- [x] **T266-S1-07** Demonstrate a qualifying unsafe export RED and restored
  GREEN with compiled, retained receipts.
- [x] **T266-S1-08** Keep #262 behavioral proofs untouched and green; retain a
  named proof-removal RED control.
- [x] **T266-S1-09** Run focused gates, `ci-offchain`, final root CI, format,
  HLint, and exact path/tree verification within budget.

## Orchestration

- [ ] **O-266-01** Freeze mandate, gate, negative controls, fences, and owner
  packet.
- [ ] **O-266-02** Accept a hash-bound submission through a fresh independent
  auditor with every blocking campaign row terminal.
- [ ] **O-266-03** Stamp tasks and mechanically verify the audited candidate
  plus only the task stamp.
- [ ] **O-266-04** Obtain the operator's push decision, refresh the draft PR,
  complete finalization audit, and hand off ready for review.
