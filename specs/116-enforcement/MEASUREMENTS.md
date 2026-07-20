# Final sovereign-path measurements (#116)

Measured on 2026-07-20 with pinned Aiken `v1.1.23+unknown`, from accepted S7
Git basis `0c1be59bd49c81685fe2e1cd3e015ebc1b4d4efd` plus the T116-S8
measurement/report/recipe working-tree diff. The measured
`checkpoint_measurements.ak` has SHA-256
`e98ce4a511b0bf4fc866976e13198b3d966951626479b38e20f3f962fede4cd0`.

The exact command was:

```console
just measure-checkpoint
```

That recipe uses Aiken and `jq` from the same pinned Nixpkgs revision. It
requires the exact nine test titles below and fails mechanically if a selected
test does not pass, lacks execution units, exceeds 10,500,000 memory, or
exceeds 7,500,000,000 CPU. The run passed 9/9 tests.

## Budgets and decision rule

The memory budget is 14,000,000 and the CPU budget is 10,000,000,000. For
either axis:

```text
used %     = raw / budget * 100
headroom % = 100 - used %
```

Percentages are computed from the raw integers and rounded to two decimals
only for display. The decision is made before rounding: a row is PASS exactly
when raw memory is at most 10,500,000 and raw CPU is at most 7,500,000,000.
Those unrounded limits are exactly 25.00% headroom on each axis.

## Required full-handler measurements

Every row invokes the real applied checkpoint typed handler over a prebuilt
full `Transaction` fixture on its ACCEPT path. Every handler application uses
the reference `d_reg = 1_000_000_000` lovelace; each state fixture holds
`checkpoint_min_ada + d_reg = 1_002_000_000` lovelace where applicable.

| Required row | Raw memory | Memory used | Memory headroom | Raw CPU | CPU used | CPU headroom | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Register — honest 2-key | 1,525,490 | 10.90% | 89.10% | 700,095,047 | 7.00% | 93.00% | PASS |
| Register — witnessed 2-of-3 | 2,094,544 | 14.96% | 85.04% | 929,299,233 | 9.29% | 90.71% | PASS |
| Register — honest GLEIF 7-key | 4,966,605 | 35.48% | 64.52% | 2,235,791,054 | 22.36% | 77.64% | PASS |
| Freeze — lag signed wire evidence | 2,259,730 | 16.14% | 83.86% | 1,066,248,253 | 10.66% | 89.34% | PASS |
| Freeze — honest 2-key signed wire evidence | 3,443,137 | 24.59% | 75.41% | 1,643,394,985 | 16.43% | 83.57% | PASS |
| Freeze — honest GLEIF 7-key signed wire evidence | 6,394,605 | 45.68% | 54.32% | 2,869,848,684 | 28.70% | 71.30% | PASS |
| Witnessed fork Convict — ACTIVE input | 1,500,843 | 10.72% | 89.28% | 654,278,897 | 6.54% | 93.46% | PASS |
| Witnessed fork Convict — FROZEN input | 1,529,920 | 10.93% | 89.07% | 667,575,670 | 6.68% | 93.32% | PASS |
| Ordinary full-proof Advance — FROZEN input to ACTIVE output | 3,997,867 | 28.56% | 71.44% | 1,943,343,633 | 19.43% | 80.57% | PASS |

Register executes the full mint handler, including proof-token lookup and
burn, datum reconstruction and binding, signature checks, and fixed-deposit
validation. Freeze and Convict execute the full spend handler including role,
datum, token, transaction-shape, EE0–EE9 binding, and enforcement predicates;
Convict uses the exact tombstone/direct-release shape. Advance executes the
ordinary full proof from a FROZEN input to an ACTIVE successor, including
controller signatures, AE1–AE10 binding, and witness receipt quorum.

The smallest required headroom is 54.32% for memory (GLEIF 7-key Freeze) and
71.30% for CPU (GLEIF 7-key Freeze). All raw rows pass both hard limits.

## SAID non-recomputation comparison

Freeze and Convict verify controller and witness signatures over the complete
signed `event_bytes`, apply EE0–EE9 field binding, and deliberately do not
recompute `blake3(said_blank)`. With the same pinned toolchain, the separately
measured 1024-byte hash-proof reference cell used 10,241,066 memory (73.15%
used, 26.85% headroom) and 5,510,621,625 CPU (55.11% used, 44.89% headroom).
That reference invokes the hash-proof mint handler and its surrounding checks;
it is not an enforcement handler measurement and is not added to any row.

This comparison supports the ratified V1 choice without claiming an
authorization boundary beyond the specification: the signed `d` remains an
audit locator, while acceptance binds predicate inputs to the signed event
bytes.

## Scope

As of 2026-07-20, the prior registry-era S6 rows are superseded by A-010 and
are not final acceptance evidence.

Aiken reports typed-handler execution costs over prebuilt `Transaction`
constants. These measurements do not include ledger `Data` deserialization
and make no live-node, devnet, or end-to-end transaction claim.
