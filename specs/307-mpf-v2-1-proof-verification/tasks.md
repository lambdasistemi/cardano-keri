# Tasks

## Dependency and layout

- [x] **T307-001** Update all active MPF declarations/cache records to v2.1.0
  with a freshly prefetched fixed-output hash and root-layout proof.

## Can-fail regressions

- [x] **T307-002** Preserve the leaf-fork fixture and its v2.0.0 assertion-red
  / v2.1.0 green evidence.
- [x] **T307-003** Preserve the terminal-fork fixture and its v2.0.0
  assertion-red / v2.1.0 green evidence.
- [x] **T307-004** Wire both fixtures into permanent repository tests.

## Compatibility

- [x] **T307-005** Prove cage insert/delete/update behavior remains green and
  `miss()` is present without manufacturing an unrelated production caller.
- [x] **T307-006** Prove Haskell/Aiken roots and proof encoding remain
  byte-identical; keep the mirror unchanged if it is unaffected.
- [x] **T307-007** Verify the local `ProofStep` encoding remains wire-compatible
  and report the unused `cardano-mpfs-onchain` dependency without removing it.

## Acceptance

- [x] **T307-008** Pass independent audit, immutable final gate, full `just ci`,
  and leave the pushed PR draft with merge withheld.
