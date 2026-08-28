# Implementation plan

## P1 — freeze evidence

1. Freeze the two upstream fixtures in the ignored ticket gate.
2. Run each fixture against v2.0.0 and require an assertion-level failure.
3. Run the identical source against v2.1.0 and require success.

## P2 — coherent dependency move

1. Prefetch tag v2.1.0 and replace the fixed-output hash in
   `offchain/flake.nix`.
2. Update `onchain/aiken.toml`, regenerate/verify `onchain/aiken.lock`, and
   update the hermetic `packages.toml` mirror.
3. Prove the cached package root matches the post-restructure Aiken layout.

## P3 — permanent contract tests

1. Add focused on-chain regression tests derived from the frozen fixtures.
2. Add or extend a cross-language test that compares Haskell proof/root bytes
   with Aiken-observed bytes. Prefer no Haskell production change if the mirror
   is semantically unaffected.
3. Assert the `ProofStep` encoding and `miss()` export while preserving cage
   behavior.

## P4 — acceptance

1. Run focused red/green checks and full `just ci`.
2. Obtain a fresh alternate-family audit of the consolidated diff.
3. Apply ticket-owner task stamps only after audit, squash to one accepted
   commit, rerun the immutable gate, push, and leave the PR draft.

## Fence

Production edits are limited to MPF pin metadata, hermetic vendoring, focused
MPF/cage tests, and the Haskell mirror only when required by cross-language
evidence. No default-branch, #300/#306, R1/#305, or unused-dependency cleanup.
