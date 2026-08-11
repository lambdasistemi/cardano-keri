# Feature specification — #232 bounded phase-2 collateral loss

Artifact ceiling: 6,000 bytes and 150 lines.

## Outcome

Every ckeri Plutus transaction declares exact protocol-required total
collateral and returns the unused input to the funding address. A phase-2
failure can seize at most **5,000,000 lovelace** (5 ADA), independent of the
wallet's UTxO layout.

## Current-state correction

The operator's 2026-08-03 story predates #181's in-process builder. At this
ticket's base, pinned `cardano-tx-tools` derives Conway `total_collateral` and
`collateral_return` during balancing, but ckeri neither enforces the resulting
body fields nor requires the funding address as the return destination. The
upstream balancer may also omit return and declare the whole collateral input
when its remainder is below min-UTxO. This ticket makes the funds-safety rule a
ckeri-owned boundary rather than an upstream implementation assumption.

## Requirements

- **RQ-232-01 — protocol amount:** for a final fee `f` and the queried protocol
  collateral percentage `p`, declared total collateral is exactly
  `ceiling(f * p / 100)` lovelace.
- **RQ-232-02 — absolute loss ceiling:** the exact protocol amount must not
  exceed **5,000,000 lovelace**. A transaction above that ceiling is rejected
  before signing or submission.
- **RQ-232-03 — return destination:** the collateral-return output pays the
  unused ADA-only remainder to the operation's funding address, including
  `close` and board operations whose ordinary change address may differ.
- **RQ-232-04 — complete conservation:** declared total collateral plus the
  returned lovelace equals the resolved collateral input lovelace. The return
  output is present and min-UTxO-valid.
- **RQ-232-05 — fail closed:** missing, mismatched, oversized, non-returning, or
  underfunded collateral is a named collateral-safety build rejection. No
  fallback signs or submits an unbounded transaction.
- **RQ-232-06 — complete Plutus surface:** registration premint/register,
  advance (with and without observer registration), close, and endpoint-board
  post/update/retire all use the shared bounded kernel. Script-free reference
  publication remains explicitly outside the collateral rule.
- **RQ-232-07 — retained selection:** retain #181's shared deterministic
  `selectFundingPair` policy, which reserves the smallest eligible UTxO as
  collateral. The cap is the primary guarantee; no #229 coin-selection or
  change-routing behavior is added.
- **RQ-232-08 — no regression:** local build/sign/submit paths still work;
  #240's no-provider boundary and #262's sole ChainQuery acquisition route
  remain enforced.

## Invariants

- **INV-232-BOUNDED (BLOCKING):** every ckeri-built Plutus transaction carries
  explicit total collateral equal to the protocol requirement and a present
  collateral-return output. An unbounded body is rejected before signing.
- **INV-232-FAILS-CLOSED (BLOCKING):** any collateral input or final body that
  cannot satisfy the exact amount, 5,000,000-lovelace ceiling, min-UTxO return,
  conservation, and funding-address destination fails with a named
  collateral-safety error; there is no permissive fallback.
- **INV-232-FALSIFIABLE (BLOCKING):** a mutation removing or weakening the cap
  makes the lasting proof RED; restored code makes it GREEN, with both receipts
  retained.
- **INV-232-LOSS-BOUND (BLOCKING):** the executable proof states
  **5,000,000 lovelace** and proves every accepted Plutus body has
  `total_collateral <= 5,000,000`.
- **INV-232-NO-REGRESSION (BLOCKING):** every write verb still builds and
  reaches its mocked submit boundary, while #240's no-provider and #262's
  sole-route properties remain GREEN.

## Rejection behavior

- A protocol-required amount above 5,000,000 lovelace names the required and
  maximum amounts and stops before signing.
- A collateral input unable to fund both the exact total and a valid return
  names required and available value and stops before signing.
- Missing or inconsistent final body fields name the violated collateral
  property and stop before signing.
- No failure path substitutes the full collateral input as total collateral.

## Non-goals

- No live-chain submission or deliberate phase-2 failure is authorized in this
  ticket campaign.
- No change to the #181 funding/collateral selection ordering.
- No #229 ordinary change-address or fee-input ergonomics.
- No dependency-pin, protocol-parameter source, ChainQuery, or provider change.
