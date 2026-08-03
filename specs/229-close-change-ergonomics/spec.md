# Story 229: close moves the whole fee-UTxO remainder to the change address

**Created**: 2026-08-03
**Status**: Draft
**Input**: ckeri 0.2.0 funded-lifecycle experiment on preprod (feedback F3).

## Outcome

An operator running `ckeri close` understands, before signing anything,
exactly where their fee-funding remainder goes, and the amount moved there
is as small as practical.

## Observed behavior (0.2.0, verified on preprod)

In the 2026-08-03 round, `close` selected a ~4992 tADA plain UTxO from the
funding address to pay a 0.516 tADA fee, and the entire remainder
(4991.80 tADA) moved to `CKERI_CHANGE_ADDRESS`. The refund target (`--to`)
received only the 1007 tADA escrow.

## Root cause (verified in sources)

- `CloseTransaction.hs:242` — `selectFundingPair 5_000_000 "checkpoint close"`
  picks the **largest** plain UTxO as fee funding (descending sort in
  `selectFundingPair`) and the second-largest as collateral.
- `CloseTransaction.hs:203-204` — the build passes the caller's change
  address to `--change-address`; cardano-cli returns the full remainder of
  all consumed inputs there.
- `CloseTransaction.hs:234-236` — guard: change address must differ from
  the refund target (`CLI.hs:1691` makes `--change-address` mandatory).
- Contrast: `Registration.hs:286,347` and `AdvanceTransaction.hs:234,266`
  hard-code change back to the **funding address**. Close is the only verb
  that routes change to a caller-chosen address.

The distinct-change requirement exists because the refund target is usually
the funding address itself, and cardano-cli needs change distinct from
outputs that carry special roles in the same transaction — so "default
change to the funding address" is not available in the common case. The
ergonomic problems are the selection strategy (largest UTxO) and the
surprise factor, not the existence of the change address.

## Acceptance scenarios

1. **Given** a funding wallet with several plain UTxOs, **When** `close`
   builds its fee input, **Then** it prefers the smallest UTxO that covers
   fee + collateral headroom, minimizing value routed through the change
   address.
2. **Given** phase 1 of `close`, **When** the command reports the planned
   transaction, **Then** it states the selected fee UTxO, the fee, and the
   exact lovelace amount that will land at the change address.
3. **Given** `close --help`, **When** an operator reads the
   `--change-address` option, **Then** it says the address receives the
   entire remainder of the consumed fee UTxO and must be operator-owned.

## Open decisions

- Whether change == funding address should be permitted when it differs
  from the refund target (relaxing `requireCloseSetting`), for symmetry
  with register/advance.
- Whether the fee input should additionally exclude UTxOs above a size
  threshold unless no smaller one suffices.

## Out of scope

- Collateral exposure (see Story 232).
