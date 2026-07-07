# Operational Constraints

## Single-UTxO throughput

The identity registry is a single UTxO. Every inception, rotation, close, and duplicity-freeze transaction spends and recreates it, so at most one such transaction can land per block. (Emergency freezes go to the separate low-contention freeze registry precisely to bypass this queue.)

All in-flight [MPF](https://github.com/aiken-lang/merkle-patricia-forestry) inclusion and absence proofs are computed against the current identity root. When a block changes the root (inception or rotation), proofs computed before that block are stale and must be recomputed before resubmission.

**Effective throughput:** approximately one identity operation per 20 seconds (average Cardano block time). Acceptable for v1.

## ADA inception deposit

Each inception locks a minimum ADA deposit in the registry UTxO, recorded in `KeyState.deposit`. It is immutable across rotations and returned only via a close operation signed by `cur_pubkey`.

This deters spam registrations and creates economic pressure to close unused entries.

## Block-ordering coupling

Value-writes take the identity UTxO as a [CIP-31](https://github.com/cardano-foundation/CIPs/tree/master/CIP-0031) reference input (non-consuming). If a rotation and a value-write land in the same block, the block producer controls their order. If the rotation is included first, the value-write references a stale identity root and is invalid in that block.

**Mitigation:** wait for the identity UTxO to be stable for N blocks before submitting a value-write. Optionally, include the expected identity root in the redeemer so failures are explicit.

## Settlement depth

Applications must choose a settlement depth consistent with Cardano's Praos/Genesis finality guarantees. High-value identity operations should wait for deep settlement; low-value or reversible operations may use shorter windows.
