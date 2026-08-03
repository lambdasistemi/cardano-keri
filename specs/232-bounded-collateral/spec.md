# Story 232: collateral exposure is unbounded — a failed script can seize a large UTxO

**Created**: 2026-08-03
**Status**: Draft
**Input**: source review during the ckeri 0.2.0 funded-lifecycle experiment
(found while grounding feedback F1/F3).

## Outcome

A phase-2 script failure after submission can never seize more than a small,
stated amount from the operator's wallet, regardless of their UTxO layout.

## Observed risk (verified in 0.2.0 sources)

- `selectFundingPair` (all four transaction modules) picks the
  **second-largest** plain UTxO of the funding wallet as the collateral
  input. With a consolidated wallet this can be thousands of tADA: in the
  2026-08-03 round the collateral candidate was a ~4993 tADA UTxO on every
  Plutus transaction.
- No build argument list anywhere in `offchain/deployment/` sets
  `--tx-total-collateral` or `--tx-out-return-collateral` (verified by
  repository-wide search).
- Conway semantics: without a declared total collateral, a phase-2 failure
  seizes the **entire** collateral input. The happy path never hits this —
  every validation that can fail locally does so before submission — but any
  failure that only surfaces during ledger script evaluation (stale state
  races, acceptance-test redeemer variants, future regressions) would
  destroy the collateral UTxO.

## Acceptance scenarios

1. **Given** any funded verb, **When** ckeri builds a Plutus transaction,
   **Then** the transaction declares a total collateral bounded by a small
   published multiple of the fee (e.g. 2× the estimated fee), so a phase-2
   failure can seize at most that amount.
2. **Given** the same build, **When** collateral return is supported by the
   era/tooling, **Then** the unused collateral remainder is routed back to
   the funding address rather than left exposed.
3. **Given** the acceptance validator-test flags
   (`--validator-test-*`), **When** they deliberately drive failing script
   evaluation, **Then** the seized amount observed on chain is the bounded
   total collateral, not the whole collateral UTxO (this becomes a live
   proof of the bound).

## Notes

- cardano-cli 10.x supports both `--tx-total-collateral` and
  `--tx-out-return-collateral` under `conway transaction build`.
- This also reduces the severity of Story 229's selection concern: with a
  bounded total, which UTxO carries collateral matters far less.

## Out of scope

- Changing which UTxO is picked as collateral (Story 229 covers selection
  ergonomics for funding inputs).
