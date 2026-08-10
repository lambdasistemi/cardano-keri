# Implementation plan — #262 ChainQuery-only write acquisition

Artifact ceiling: 6,000 bytes and 150 lines.

## Durable design decision

The provider-neutral shape of a spendable output is the existing
**DAT-257-ASSET-OUTPUT** `ChainAssetUtxo`, not a new ledger-specific `TxOut`
wrapper and not a sixth output DTO.

Rationale:

- it already contains output identity, address, lovelace, every native asset,
  inline datum JSON, and optional reference-script identity/type/bytes;
- #240's final audit repaired the local decoder so inline datums are preserved
  rather than forced to `Nothing`;
- `Cardano.KERI.ChainQuery.LedgerOutput` already converts this neutral value
  into the exact Conway builder input and rejects malformed address, value,
  datum, script bytes, hash, transaction id, or index;
- local storage and Koios can both produce the same shape without leaking a
  store handle, HTTP response, or provider setting into the algebra;
- retaining `ActiveCheckpoint` and `BoardEntry` as deliberate authenticated
  summaries avoids duplicating domain fields. An exact checkpoint lookup
  returns `ChainAssetUtxo`; a board operation pairs each `BoardEntry` with its
  corresponding `ChainAssetUtxo`.

This deliberately revises #257's operation set while preserving its promoted
output contract. `TxOut ConwayEra` remains a downstream reconstructed builder
input rather than the cross-provider interchange type.

## Strategy

One OWNER slice keeps the algebra extension, both interpreter translations,
write-program migration, direct-route withdrawal, and falsifiable sole-route
proof in one auditable behavior change. Splitting after adding only the new
operations would leave two acquisition routes live without closing an
observable ticket outcome.

1. Extend the neutral locator/output relationships and both algebra operation
   families, interpreter factory, and dispatch.
2. Implement both concrete interpreter fields and repair every factory call.
3. Express the board, publication, checkpoint-signing, advance, and close
   acquisition bundles as `ChainQuery` programs; run each program once through
   the local interpreter.
4. Withdraw direct build-acquisition exports only after the final caller moves.
5. Replace the #240 deferred-disposition property with a met-disposition and
   sole-route property, retain RED/restored-GREEN receipts, and rerun #240's
   snapshot/parity gate.

## Constraints

- Base is merged #240 on `main`, commit
  `465415b87ace1ab3fa60fc05617fe80fc8649b4d`.
- Build budget is 12 plus a reserve of 4 used only for audit findings.
- The free readiness barrier precedes every allocated gate run.
- No `CKERI_BLUEPRINT` wiring change is planned; if implementation changes
  that wiring, `ci-onchain` joins every submission gate.
- Settlement observers and post-submit temporal probes remain outside the
  algebra.
- No ticket-owner edits to production, tests, fixtures, dependency manifests,
  generated output, or shipped configuration.

## Verification

- focused algebra and local-write-path suites;
- sole-route and disposition controls demonstrated RED then restored GREEN;
- unchanged #240 local-write-path acquisition/snapshot/parity proofs;
- full `ci-offchain`, and final root `just ci` before push;
- format, hlint, diff, path-fence, commit, task, and finalization audits.
