# MPF v2.1.0 proof-verification bump

## Outcome

Consume `aiken-lang/merkle-patricia-forestry` v2.1.0 everywhere the
repository resolves or vendors it, and prove that the upgrade repairs the two
known `excluding()` proof shapes without changing the existing cage contract.

## Requirements

- **R1 — coherent pin.** `onchain/aiken.toml`, `onchain/aiken.lock`, the Nix
  fixed-output source, and the generated `packages.toml` mirror all name
  v2.1.0. The Nix source hash covers the restructured root-layout package.
- **R2 — leaf-fork regression.** The frozen upstream `phil` fixture (a leaf
  fork below a non-zero common prefix) fails under v2.0.0 and passes under
  v2.1.0.
- **R3 — terminal-fork regression.** The frozen upstream `edge_case4` fixture
  (a terminal `Fork` with `skip = 1`) fails under v2.0.0 and passes under
  v2.1.0.
- **R4 — permanent repository proof.** Both fixtures remain reachable through
  the checked-in test surface so later pin drift makes CI red.
- **R5 — cage preservation.** Existing `cage.ak` insert, delete, and update
  consumers keep their behavior and the on-chain suite remains green.
- **R6 — byte identity.** Proof roots and serialized `ProofStep` values emitted
  by the hand-written Haskell mirror remain byte-identical to the Aiken
  verifier contract for the frozen cases. Change the mirror only if the new
  contract requires it; otherwise prove it is inert.
- **R7 — miss surface.** Confirm v2.1.0 exposes `miss(self, key, proof)` and
  exercise explicit non-membership where that can be done without broadening
  cage behavior. Do not invent a production caller merely to create a diff.
- **R8 — full verification.** The immutable ticket gate and repository `just
  ci` pass on the accepted commit with a clean worktree.

## Invariants

- **I1 PIN-ONE:** no active v2.0.0 MPF pin or package record remains.
- **I2 CAN-FAIL-TWICE:** the same two fixture sources used for acceptance are
  each observed failing under v2.0.0 for an assertion mismatch, not resolution
  or compilation failure, then passing under v2.1.0.
- **I3 PACKAGE-ROOT:** the vendored v2.1.0 source exposes root `aiken.toml` and
  `lib/aiken/merkle_patricia_forestry.ak` to Aiken's package cache.
- **I4 WIRE-STABLE:** `ProofStep` constructor tags and field order remain
  Branch `0 [skip, neighbors]`, Fork `1 [skip, neighbor]`, Leaf `2 [skip, key,
  value]`.
- **I5 MIRROR:** Haskell-generated roots/proofs agree with the Aiken oracle;
  passing only one implementation's self-test is insufficient.
- **I6 NO-COLLATERAL:** issue/PR #300/#306, PR #305/R1, default branch, and the
  unused `cardano-mpfs-onchain` dependency are unchanged.

## Non-goals

- Occupancy or projection-fidelity design.
- Removing `cardano-foundation/cardano-mpfs-onchain` v0.1.0. It has no `.ak`
  importer and is reported as existing debt only.
- Merge, default-branch mutation, or edits to the #300 and R1 lanes.

## Acceptance

Acceptance requires captured old-fail/new-pass receipts for both fixtures,
the permanent tests, an independent full-diff audit, fresh gate and `just ci`
success on the exact final commit, and a draft PR. Merge remains withheld.
