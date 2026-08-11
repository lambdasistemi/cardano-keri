# Modules model — #232 bounded phase-2 collateral loss

Artifact ceiling: 5,000 bytes and 130 lines.

## Changed responsibilities

### MOD-232-RUNTIME — shared transaction safety boundary

- Owns the fixed 5,000,000-lovelace product ceiling and exact protocol-relative
  collateral validation after transaction convergence.
- Owns the named collateral-safety rejection family and guarantees rejection
  occurs before signing and submission.
- Receives the resolved collateral input and funding-address return destination
  explicitly for Plutus builds.
- Keeps script-free building available without inventing collateral fields.

### MOD-232-WRITES — Plutus operation builders

- Registration, advance, close, and endpoint-board operations supply their
  funding address and resolved shared-selector collateral to
  **MOD-232-RUNTIME**.
- They no longer construct a raw collateral resolution option independently.
- Ordinary change-address behavior and transaction semantics stay unchanged.

### MOD-232-PROOF — lasting funds-safety proof

- Observes final built bodies and the pre-sign rejection boundary across the
  shared kernel and every Plutus operation family.
- States the absolute 5,000,000-lovelace maximum as an asserted value.
- Includes negative controls for absent, oversized, non-returning, misdirected,
  and inconsistent collateral plus a cap-removal mutation.
- Retains #240 no-provider and #262 sole-route boundary checks.

## Dependency direction

- **EDGE-232-01:** Plutus operation builders → shared transaction runtime.
- **EDGE-232-02:** shared transaction runtime → ledger protocol parameters,
  final transaction body, resolved collateral input, and pinned tx-build API.
- **EDGE-232-03:** no operation-specific module owns collateral arithmetic or
  a permissive fallback.
- **EDGE-232-04:** chain query/provider components remain upstream input
  suppliers and do not depend on collateral policy.

## Promotion decision

- **PROMOTE-232-01:** enforce the policy in `TransactionRuntime`, the nearest
  stable owner shared by all in-process write builders.
- **PROMOTE-232-02:** do not move the product ceiling upstream into
  `cardano-tx-tools`; exact ledger field construction remains upstream, while
  ckeri independently constrains what it is willing to sign and submit.
- **PROMOTE-232-03:** retain the shared #181 selector and do not recreate the
  four pre-#181 funding/collateral implementations.
