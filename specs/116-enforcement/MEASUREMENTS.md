# Final enforcement measurements (#116)

Measured on 2026-07-20 with Aiken `v1.1.23+unknown`. The Git basis was
`59165555d98330fabbf7a7624bff510a0c8fbbf1` plus the T116-S6
measurement/proof working-tree diff. The SHA-256 of that diff over
`GenUnicityVectors.hs`, `UnicitySpec.hs`, `unicity_vectors.ak`, and
`checkpoint_measurements.ak` is
`953891efa4b991d0dd3aa10da1d87393ec3f34eaa0e59d2377e057239872c736`.
The measured Aiken fixture module has SHA-256
`28c5b0cd71c7eb8b60433aecfbc6448cf8cc10fb855f50c83226a1131cff0798`;
the generated unicity vectors have SHA-256
`d9294f8bb5cc188668a5ce99e001a9e0d43f8f6427e7782a9f22aa5a9344001e`.

The exact checkpoint command was:

```console
cd onchain
nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken check --plain-numbers -m measure_checkpoint
```

The 1024-byte hash-proof reference was rerun with the same pinned toolchain,
replacing the final filter with `-m measure_hash_proof`. All checkpoint tests
reported below passed (15/15); all hash-proof tests passed (3/3).

## Budgets and decision rule

The memory budget is 14,000,000 and the CPU budget is 10,000,000,000. For
either axis:

```text
used %     = raw / budget * 100
headroom % = 100 - used %
```

Percentages are computed from the raw integers and rounded to two decimal
places only for display. The decision is made before rounding: a row is PASS
if raw memory is at most 10,500,000 and raw CPU is at most 7,500,000,000.
Those raw thresholds are exactly 25.00% headroom on each axis.

## Required handler measurements

Every row invokes a real applied checkpoint typed handler over a prebuilt
`Transaction` constant on its ACCEPT path. Registration rows are the explicit
arithmetic sum of the two separately executed script purposes from the same
transaction fixture.

| Required row | Raw memory | Memory used | Memory headroom | Raw CPU | CPU used | CPU headroom | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Freeze — lag signed wire evidence | 2,260,229 | 16.14% | 83.86% | 1,066,252,204 | 10.66% | 89.34% | PASS |
| Freeze — honest 2-key signed wire evidence | 3,443,636 | 24.60% | 75.40% | 1,643,398,936 | 16.43% | 83.57% | PASS |
| Freeze — honest GLEIF 7-key signed wire evidence | 6,395,104 | 45.68% | 54.32% | 2,869,852,635 | 28.70% | 71.30% | PASS |
| Witnessed fork Convict — ACTIVE input | 1,502,244 | 10.73% | 89.27% | 654,555,230 | 6.55% | 93.45% | PASS |
| Witnessed fork Convict — FROZEN input | 1,531,321 | 10.94% | 89.06% | 667,852,003 | 6.68% | 93.32% | PASS |
| Registry bootstrap — `BootstrapRegistry` mint | 123,160 | 0.88% | 99.12% | 41,375,284 | 0.41% | 99.59% | PASS |
| 2-key registration + MPFS absence depth 0 | 1,999,612 | 14.28% | 85.72% | 881,045,518 | 8.81% | 91.19% | PASS |
| Witnessed registration + MPFS absence depth 8 | 3,088,365 | 22.06% | 77.94% | 1,260,467,975 | 12.60% | 87.40% | PASS |
| GLEIF 7-key registration + MPFS absence depth 16 | 6,469,257 | 46.21% | 53.79% | 2,712,017,346 | 27.12% | 72.88% | PASS |

Bootstrap is a one-shot mint-handler measurement and is not included in any
registration sum.

## Registration components

Each pair below uses one transaction constant for both the `Register` mint
handler and the named registry input's `RecordRegistration` spend handler.
The proof key is the actual
`deriveAidAssetName(datum.cesr_aid)` for that registration fixture. The
Haskell generator derives the declared old and new roots from that key and
proof; focused Haskell transition tests and generated Aiken vector drift checks
cover all three pairs.

| Same-transaction fixture | Proof depth | Register mint memory | Registry spend memory | Summed memory | Register mint CPU | Registry spend CPU | Summed CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Honest 2-key registration | 0 | 1,723,106 | 276,506 | 1,999,612 | 779,630,285 | 101,415,233 | 881,045,518 |
| Witnessed registration | 8 | 2,811,859 | 276,506 | 3,088,365 | 1,159,052,742 | 101,415,233 | 1,260,467,975 |
| Honest GLEIF 7-key registration | 16 | 6,192,751 | 276,506 | 6,469,257 | 2,610,602,113 | 101,415,233 | 2,712,017,346 |

These sums are arithmetic aggregates of two separately measured typed-handler
executions. They are not a combined evaluator run and are not a live-node or
devnet measurement.

## SAID non-recomputation comparison

Freeze and Convict verify controller and witness signatures over the complete
signed `event_bytes`, apply the EE0–EE9 field binding, and deliberately do not
recompute `blake3(said_blank)`. The separately rerun 1024-byte hash-proof
reference cell measured 10,241,066 memory (73.15% used, 26.85% headroom) and
5,510,621,625 CPU (55.11% used, 44.89% headroom). That reference invokes the
hash-proof mint handler and its surrounding checks; it is not an enforcement
handler measurement and is not added to any row above.

This comparison supports the ratified V1 choice without claiming an
authorization boundary beyond the specification: the signed `d` remains an
audit locator, while the acceptance checks bind the predicate inputs to the
signed event bytes.

## Scope and conclusion

Aiken reports typed-handler execution costs over prebuilt `Transaction`
constants. The numbers do not include ledger `Data` deserialization and are
not live-node, devnet, or end-to-end transaction measurements.

On this freshly measured pinned basis, every required raw handler or aggregate
row stays below both STOP thresholds. The smallest required headroom is 53.79%
for memory (GLEIF 7-key registration at depth 16) and 71.30% for CPU (GLEIF
7-key Freeze), so the final T116-S6 measurement gate passes.
