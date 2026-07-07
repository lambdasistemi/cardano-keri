# cardano-keri

KERI-style self-certifying identifiers (AIDs) on Cardano.

An AID is a 32-byte key that is self-certifying: its value is
`blake2b_256(inception_event)`, where the inception event commits to
the initial public key and the hash of the next key (pre-rotation).

This repository builds a minimal on-chain identity registry that:

- lets anyone register an AID by publishing a self-certifying inception proof
- lets the key holder rotate to a pre-committed key without oracle permission
- lets other on-chain contracts (e.g. MPFS value cages) reference key-state
  via CIP-31 reference inputs — no oracle permission required
- extends to full vLEI ACDC credential verification on-chain

## Documentation

The rendered documentation site:

<https://lambdasistemi.github.io/cardano-keri/>

The same content lives in the repository as an MkDocs site rooted at
[`docs/index.md`](docs/index.md). Start there, or go straight to:

- [`docs/roadmap.md`](docs/roadmap.md) — milestone layout and overall plan
- [`docs/keri-primer.md`](docs/keri-primer.md) — KERI, pre-rotation, Veridian
- [`docs/architecture/overview.md`](docs/architecture/overview.md) — the
  on-chain model
- [`docs/design/business-cases/index.md`](docs/design/business-cases/index.md)
  — the four business cases and the factored core

## Layout

- `onchain/` — Aiken validators (dual-root cage, identity registry)
- `offchain/` — Haskell library and test-vector generator
- `specs/` — per-issue specifications
- `docs/` — MkDocs documentation site
- `vetting/`, `claude/`, `codex/` — adversarial cross-model design analyses
- `discussion.md`, `system-discussion.md` — running design discussions

## Building

- `onchain/`: `aiken build` and `aiken check`
- `offchain/`: `nix build .#checks.x86_64-linux.unit-tests` (or enter
  `nix develop` for a GHC shell); `cabal run gen-vectors` regenerates the
  Aiken test vectors

## Status

Work is planned in five GitHub
[milestones](https://github.com/lambdasistemi/cardano-keri/milestones):
identity core, verification + authorization core, KERI-wallet ↔ Cardano
signing bridge, preprod pilots, and case adapters. The identity foundation
is in progress (dual-root cage landed); every milestone closes with a
runnable end-to-end demo — see the [roadmap](docs/roadmap.md).
