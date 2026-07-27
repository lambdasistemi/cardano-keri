# Implementation Plan: rotate a small identity end to end (#142)

**Branch**: `story/142-rotate-small` | **Date**: 2026-07-27
**Spec**: `specs/142-rotate-small/spec.md`

## Summary

Open the small checkpoint validator's fail-closed Advance surface with the
ratified #115 observer-forwarding topology. The checkpoint arm remains thin:
it preserves state/value mechanics and requires the exact zero-lovelace
`observer_advance` claim. The already-deployed observer reference script owns
the heavy `advance_predicate`. Reuse the generated witnessed two-key positive
and rejection vectors unchanged, then add the production-shaped two-pass
off-chain transaction and one Register→Advance PV11 settlement.

## Technical Context

**On-chain**: Aiken, Plutus V3, pinned Aiken toolchain
**Off-chain**: Haskell, GHC 9.12 through Nix/haskell.nix
**Testing**: applied Aiken transaction contexts, generated cross-language
vectors, Haskell unit tests, PV11 withDevnet smoke, `./gate.sh`
**Constraints**: stock 16 KiB transaction size; 14M memory / 10B CPU reference
budget; no new protocol strings or wire layouts; exact value preservation;
no fresh upstream dependency
**Scope**: one witnessed two-key Register→Advance story plus three authority
rejections

## Constitution Check

- **Design before implementation**: PASS — this spec and plan precede GREEN,
  and inherit the ratified #115 design.
- **On-chain/off-chain parity**: PASS by plan — no generated vector changes;
  the live builder consumes the existing shared evidence shape.
- **Frozen strings/layouts**: PASS — no message or domain amendment.
- **Test first**: PASS — the applied positive Advance test is run RED before
  the handler is implemented.
- **Public repository hygiene**: PASS — only public issue, generated fixture,
  code, and reproducible measurements enter the tree.

No new research artifact is needed: all semantic choices and measurements are
ratified in `specs/115-advance/`.

## Source Map

| Path | Change |
| --- | --- |
| `specs/142-rotate-small/spec.md` | story contract |
| `specs/142-rotate-small/plan.md` | this plan |
| `onchain/validators/checkpoint_register_tests.ak` | applied RED/GREEN: exact observer coupling, genuine two-key positive; stolen-current, under-signed, under-witnessed rejections; value preservation |
| `onchain/validators/checkpoint_register.ak` | add thin `Advance` spend branch with the exact observer ran-check |
| `onchain/lib/cardano_keri/checkpoint/observer.ak` | resolve OLD/NEW and run the unchanged heavy rotation predicate |
| `onchain/validators/checkpoint_observer.ak` | open only the `observer_advance` withdrawal family |
| `offchain/e2e/CheckpointTxBuilder.hs` | deploy/register the observer by reference; add the two-redeemer Advance builder with two-pass budget binding and exact submitted/evaluated bytes |
| `offchain/e2e/CheckpointE2ESpec.hs` | one Register→Advance settlement |
| `offchain/flake.nix` | repin blueprint output only if the on-chain program changes it |
| `justfile`, `offchain/cardano-keri.cabal` | only minimal wiring required by the story |

The generated `advance_vectors.ak`, Haskell vector generator, message layout,
and #115 predicates remain byte-unchanged.

## Ordered Work

### Phase 1 — Applied on-chain RED

1. Build the production-shaped ACTIVE input and successor from
   `pos_adv_wit_2key_*`.
2. Assert the positive applied spend accepts and exact value is preserved.
3. Add transaction-level rejection cases for
   `ctrl_stolen_quorum_*`, `ctrl_below_threshold_*`, and
   `v7_receipt_free_*`.
4. Run the focused Aiken test and freeze the expected RED at the missing
   small-Advance handler.

### Phase 2 — Minimal on-chain GREEN

1. Add the bare `Advance` command to the small spend redeemer.
2. Resolve the named ACTIVE input and exactly one ACTIVE successor.
3. Require unchanged complete value, one checkpoint token, no own-policy mint,
   inline V1 datums, the existing bonded floor, and the exact
   `observer_advance` zero-lovelace withdrawal claim.
4. In the observer, reconstruct `SpentCheckpoint` only from deployment
   parameters, the named input, and OLD; require the unchanged
   `advance_predicate` verdict.
5. Run focused and full Aiken suites; measure both applied program sizes and
   execution units.
   If the reference deployment cannot fit stock transaction size, stop rather
   than weakening the predicate.

### Phase 3 — Off-chain transaction and live proof

1. Encode the already-frozen Advance evidence inside the `ObserverEnvelope`;
   keep the checkpoint spend command bare.
2. Deploy the observer reference before certifying its stake credential,
   certify through that resolved reference, then build Advance with checkpoint
   and observer reference inputs, preserve exact state value, and bind both
   budgets in two passes.
3. Re-evaluate the final bytes, prove byte identity, submit, and poll the exact
   successor.
4. Run one PV11 boot: Register settles first, witnessed Advance settles second.

### Phase 4 — Gate and publication

Run focused format/lint checks, stage the exact story set, run `./gate.sh`,
open the issue-backed PR, and await operator authority before any merge. The
standing order explicitly forbids merging #142 while the operator is away.

## Risks and Controls

- **Applied script size**: measure after the minimal handler; use reference
  delivery, never delete checks to fit.
- **Wire drift**: consume the existing generated evidence and keep its file
  hash unchanged.
- **Value leakage**: assert full ledger-value equality, not only lovelace or
  token quantity.
- **False authority**: execute stolen-current, under-signed, and
  under-witnessed packages at the applied boundary.
- **Scope creep**: no Freeze/ClaimFreeze, enforcement, Arm/Claim,
  bond/hunter, or seven-key live work.
