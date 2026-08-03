# Story 226: first-run funding wall — two plain UTxOs required, nowhere said why

**Created**: 2026-08-03
**Status**: Draft
**Input**: ckeri 0.2.0 funded-lifecycle experiment on preprod (feedback F1).

## Outcome

A controller arriving with a normal, consolidated wallet (one plain ADA-only
UTxO) can run `ckeri register` without first discovering an unstated UTxO
invariant by hand. Today the first attempt fails with:

```
user error (hash-proof premint needs two distinct plain funding UTxOs)
```

and nothing in `register --help`, the README, or the error itself explains
what the second UTxO is for or how to produce one.

## Root cause (verified in 0.2.0 sources)

`selectFundingPair` picks **two** distinct plain UTxOs from the funding
wallet: the largest as the funding input and the second-largest as the
**Plutus collateral** input:

- `offchain/deployment/Cardano/KERI/Deployment/Registration.hs:639-655`
- duplicated in `AdvanceTransaction.hs:508`, `CloseTransaction.hs:291`,
  `EndpointBoardTransaction.hs:536`

Every funded verb therefore needs ≥ 2 plain UTxOs (register twice: once for
the hash-proof premint at ≥ 8 tADA, again for registration at
escrow + 5 tADA; advance/close/board at ≥ 5 tADA). The requirement is real
(collateral must be a plain UTxO distinct from the funding input), but the
error message names the symptom ("two distinct plain funding UTxOs") and not
the cause (collateral) or the remedy (self-transfer split).

## Acceptance scenarios

1. **Given** a funding address holding one plain UTxO, **When**
   `ckeri register` runs, **Then** the error names the missing collateral
   input and the remedy ("split one UTxO into two plain UTxOs with a
   self-transfer"), and `register --help` states the invariant and the
   minimum funding sizes.
2. **Given** the same wallet, **When** the operator reruns after a manual
   split, **Then** the flow succeeds exactly as it does today.

## Optional extension (separate decision)

`ckeri` may offer to perform the split itself (one extra self-transfer
transaction) when only one plain UTxO exists. This changes funds movement
and deserves its own decision; the documentation/error-message outcome above
stands without it.

## Out of scope

- Changing collateral selection strategy (see Story 232).
- Witness-receipt or manifest concerns.
