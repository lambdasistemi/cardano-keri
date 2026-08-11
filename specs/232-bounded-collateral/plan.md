# Implementation plan — #232 bounded phase-2 collateral loss

Artifact ceiling: 6,000 bytes and 150 lines.

## Durable design decision

ckeri owns a post-balance collateral-safety boundary in the shared transaction
runtime. It validates the final Conway body against the same protocol-parameter
snapshot and resolved collateral input used by the build. Callers cannot rely
only on `cardano-tx-tools` having populated the fields correctly.

The accepted amount is the exact ledger requirement, not a padded estimate:
`ceiling(final fee * protocol collateral percentage / 100)`. An independent
product ceiling of **5,000,000 lovelace** bounds catastrophic loss even if fees
or protocol parameters move unexpectedly. The 2026-08-03 preprod lifecycle's
largest observed fee was 1,479,370 lovelace; at 150% its requirement is
2,219,055 lovelace, below the chosen ceiling without redefining the ledger
amount.

Unused collateral returns to the funding address. This is deliberately not
the ordinary change address: `close` and endpoint-board operations may route
ordinary change elsewhere, but that product choice must not redirect the
collateral safety remainder.

The existing shared selector already reserves the smallest eligible plain UTxO
after #181. Retain it. If that selected input cannot fund the exact total plus
a min-UTxO-valid return, the build fails closed; it never converts the whole
input into collateral. Broader selection ergonomics remain #229.

## Strategy

One OWNER slice keeps the shared safety policy, all Plutus call-site migration,
per-verb proof, and falsification receipt in one auditable behavior change.

1. Add a typed collateral-safety contract and named rejection family to the
   shared transaction runtime.
2. Give the Plutus build kernel the resolved collateral input and explicit
   funding-address return destination, while retaining the script-free kernel
   for Publisher.
3. Validate exact protocol amount, absolute ceiling, return presence/address/
   value, min-UTxO viability, and conservation after convergence and before
   signing.
4. Route every Plutus write family through that kernel and remove caller-owned
   raw collateral `BuildOptions` construction.
5. Add focused permanent proofs for exact arithmetic, the 5,000,000-lovelace
   bound, named failures, all write families, and script-free Publisher.
6. Demonstrate cap removal RED and restored GREEN; retain receipts and rerun
   #240/#262 boundary gates plus full local CI.

## Constraints

- Base is `3dc9403ed058d689e97b527ff0e34d17e82488c8`.
- Build budget is 10, plus a reserve of 4 used only for audit findings.
- Before every allocated compiled gate, `/` must have at least 34 GiB free and
  the complete free readiness barrier must be clean.
- No live-chain action, validator-test submission, dependency-pin change, or
  docs edit.
- No ticket-owner edit to production, tests, fixtures, dependency manifests,
  generated output, or shipped configuration.

## Verification

- focused shared runtime and per-verb deployment suites;
- explicit final-body assertions for exact total, 5,000,000-lovelace ceiling,
  return destination/value, and pre-sign failure order;
- removed-cap mutation RED and restored GREEN receipts;
- unchanged `query-algebra-check` and `local-write-path-check`;
- full `ci-offchain`, final root `just ci`, format, hlint, diff, path-fence,
  commit, task, and finalization audits.
