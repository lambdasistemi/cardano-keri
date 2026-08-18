# S0 family size report

Architectural measurement of seven separately compiled skeletons.
Every row and verdict is size-only; transaction-fit unproven.

## Toolchain

- path: `/nix/store/zk3s76mjwcb5fz099d6dq02c684bg8wn-aiken-1.1.23/bin/aiken`
- version: `aiken v1.1.23+unknown`
- sha256: `c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689`

## Source and blueprint identity

- owned-source sha256: `d3ffc749a9c0f949b983addb0a78c10cc38885afae60ada878c30657b0d35e1d`
- blueprint sha256: `f5de8b9f52c38cbe7ff71735abf726a7816ef77af7694e61fc6274050eb0ae9c`
- reproduction command:

```
scripts/s0/measure-family.sh verify \
  --repo <repo> \
  --aiken /nix/store/zk3s76mjwcb5fz099d6dq02c684bg8wn-aiken-1.1.23/bin/aiken \
  --report specs/m11-s0-size-failfast/SIZE-REPORT.md \
  --evidence-dir <fresh-directory>
```

Runtime evidence directories are not the committed identity.

## Title mapping

| member | blueprint title |
| --- | --- |
| append | `s0_append.s0_append.spend` |
| cursor | `s0_cursor.s0_cursor.spend` |
| lineage | `s0_lineage.s0_lineage.spend` |
| maintenance_escrow | `s0_maintenance_escrow.s0_maintenance_escrow.spend` |
| staging_proof_token | `s0_staging_proof_token.s0_staging_proof_token.mint` |
| consumer_predicates | `s0_consumer_predicates.s0_consumer_predicates.spend` |
| reference_cursor_consumer | `s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend` |

## Rows

| member | title | bytes | ref % | ref headroom | tx % | tx headroom | threshold | caveat |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| append | `s0_append.s0_append.spend` | 5037 | 31.22 | 11096 | 30.74 | 11347 | PASS | size-only; transaction-fit unproven |
| cursor | `s0_cursor.s0_cursor.spend` | 5028 | 31.16 | 11105 | 30.68 | 11356 | PASS | size-only; transaction-fit unproven |
| lineage | `s0_lineage.s0_lineage.spend` | 1715 | 10.63 | 14418 | 10.46 | 14669 | PASS | size-only; transaction-fit unproven |
| maintenance_escrow | `s0_maintenance_escrow.s0_maintenance_escrow.spend` | 999 | 6.19 | 15134 | 6.09 | 15385 | PASS | size-only; transaction-fit unproven |
| staging_proof_token | `s0_staging_proof_token.s0_staging_proof_token.mint` | 1609 | 9.97 | 14524 | 9.82 | 14775 | PASS | size-only; transaction-fit unproven |
| consumer_predicates | `s0_consumer_predicates.s0_consumer_predicates.spend` | 1037 | 6.42 | 15096 | 6.32 | 15347 | PASS | size-only; transaction-fit unproven |
| reference_cursor_consumer | `s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend` | 1517 | 9.40 | 14616 | 9.25 | 14867 | PASS | size-only; transaction-fit unproven |

Percentages are truncated display values from integer arithmetic
`bytes * 10000 / ceiling`. Threshold uses integer bytes:
`>= 12907` is `REDESIGN`. Headroom is signed and not clamped.

## Machine rows

```
S0-ROW member=append title=s0_append.s0_append.spend bytes=5037 reference_pct=31.22 reference_headroom=11096 tx_pct=30.74 tx_headroom=11347 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=cursor title=s0_cursor.s0_cursor.spend bytes=5028 reference_pct=31.16 reference_headroom=11105 tx_pct=30.68 tx_headroom=11356 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=lineage title=s0_lineage.s0_lineage.spend bytes=1715 reference_pct=10.63 reference_headroom=14418 tx_pct=10.46 tx_headroom=14669 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=maintenance_escrow title=s0_maintenance_escrow.s0_maintenance_escrow.spend bytes=999 reference_pct=6.19 reference_headroom=15134 tx_pct=6.09 tx_headroom=15385 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=staging_proof_token title=s0_staging_proof_token.s0_staging_proof_token.mint bytes=1609 reference_pct=9.97 reference_headroom=14524 tx_pct=9.82 tx_headroom=14775 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=consumer_predicates title=s0_consumer_predicates.s0_consumer_predicates.spend bytes=1037 reference_pct=6.42 reference_headroom=15096 tx_pct=6.32 tx_headroom=15347 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=reference_cursor_consumer title=s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend bytes=1517 reference_pct=9.40 reference_headroom=14616 tx_pct=9.25 tx_headroom=14867 threshold=PASS caveat="size-only; transaction-fit unproven"

```
