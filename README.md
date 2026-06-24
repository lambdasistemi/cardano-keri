# cardano-aid

KERI-style self-certifying identifiers (AIDs) on Cardano.

An AID is a 32-byte key that is self-certifying: its value is
`blake2b_256(inception_event)`, where the inception event commits to
the initial public key and the hash of the next key (pre-rotation).

This repository explores a minimal on-chain identity registry that:

- lets anyone register an AID by publishing a self-certifying inception proof
- lets the key holder rotate to a pre-committed key with a single Ed25519 signature
- lets other on-chain contracts (e.g. MPFS value cages) reference key-state
  via CIP-31 reference inputs — no oracle permission required

## Design documents

- [`docs/aid-ops.md`](docs/aid-ops.md) — AID operations and cryptographic bindings
- [`docs/on-chain-model.md`](docs/on-chain-model.md) — on-chain representation and script design

## Status

Early design / cryptographic vetting phase. No code yet.
