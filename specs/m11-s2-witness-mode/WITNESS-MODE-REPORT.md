# M1.2 TxB witness-mode determination

## Determination

TxB selects **REFERENCE** carriage in production. The independent **INLINE**
control remains a live rendering of the same semantic plan and executed in the
focused `M11.S2.TxB.witness.mode` suite as `witness-mode/INLINE`.

The INLINE transaction serializes to **25,969 bytes**, exceeding the pinned
`maxTxSize` of **16,384 bytes**. REFERENCE carries no family script witnesses;
it supplies the three family script UTxOs through reference inputs instead.

## Program measurements and aggregate limit

The candidate's own `scripts/s0/measure-family.sh verify` control compiled the
real programs with the content-pinned Aiken binary and regenerated these sizes:

| role | program bytes |
| --- | ---: |
| append | 8,471 |
| cursor | 8,389 |
| staging proof token | 8,757 |

Their derived aggregate is **25,617 bytes**. It fits the distinct ledger
aggregate limit `maxRefScriptSizePerTx` of **204,800 bytes**. The aggregate is
the sum of those rows, not an independently asserted number.

Measurement evidence sha256:
`df228f2f4c6f341106857e66b40dd70fbc0630c8afd98937b4fca42378fcceb0`.

## Signed creation-transaction envelope

Each reference-script UTxO must first be created by a signed transaction. Those
transactions were constructed and signed independently per program, then
measured against `maxTxSize`:

| role | program bytes | signed creation transaction bytes | verdict |
| --- | ---: | ---: | --- |
| append | 8,471 | 8,680 | FIT |
| cursor | 8,389 | 8,598 | FIT |
| staging proof token | 8,757 | 8,966 | FIT |

The envelope limit is the Conway genesis `maxTxSize` from the pinned
`cardano-node-clients` snapshot
`a10cdb73317a2b6d5375b216f72f40b71736e648`. It is not the aggregate
`maxRefScriptSizePerTx` limit, and the two values are not interchangeable.

These are signed construction measurements, not live-ledger acceptance
evidence.

## Reference-script fee boundary

Provenance: `cardano-ledger-conway-1.21.0.0`, package tarball sha256
`c31a38424d578a7a6a2c51769e81296e731c84c5e69e1879645b044e2e6cf1e6`,
snapshot `cardano-node-clients-a10cdb73317a2b6d5375b216f72f40b71736e648`.
The pinned parameters are a 25,600-byte stride, 1.2 tier multiplier, and 44
lovelace per byte base price.

| reference bytes | fee (lovelace) |
| ---: | ---: |
| 25,599 | 1,126,356 |
| 25,600 | 1,126,400 |
| 25,601 | 1,126,452 |
| 25,617 | 1,127,297 |
| 26,448 | 1,171,174 |

The marginal cost increases after byte 25,600, revealing the tier boundary.

## Provenance and residuals

- Surface B: `status=ARCHIVED_RED`, evidence sha256
  `bd569a319a9c3bcee73012854759f67acb4f68c6be191b6421b912f63dd44da1`.
- S0 Aiken binary-content digest:
  `c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689`.
- Integrated `origin/main`:
  `c2cd6d6e23da4677ba2d3b13dca0558122dd429f`.
- Measured source-set digest:
  `bad9e495d447a5d706509fe8d8f4487e27a857d809597e0ee9ae9ad521579c42`.
- `A3-F1` — **ADVISORY**: the shipped harness does not observe the
  `AIKEN_EXPECTED_VERSION` seam; the binary-content digest is the control.
- `F1-ERROR-CLASSIFICATION` — **OPEN**: fail-closed safety held; error
  classification diverged.

All byte counts and fees above were regenerated on this candidate ancestry.
The honest remaining limit is: **size-only; transaction-fit unproven** except
for the explicitly measured signed creation-transaction envelopes, which still
do not prove acceptance by a live ledger.
