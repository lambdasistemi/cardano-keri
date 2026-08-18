# S0 family size report

Architectural measurement of seven separately compiled skeletons.
Every row and verdict is size-only; transaction-fit unproven.

## Toolchain

- path: `/nix/store/zk3s76mjwcb5fz099d6dq02c684bg8wn-aiken-1.1.23/bin/aiken`
- version: `aiken v1.1.23+unknown`
- sha256: `c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689`
Trace level: `silent`

## Source and blueprint identity

Measured source commit: `37c00f7b24e5d2a0d3a5f32c6bedb408eb77c78a`
- owned-source sha256: `b76a8144f75a9ea26d3e50c1356a8141ecb8cf69c04d1340450f7527104f56f5`
- blueprint sha256: `58ca022c2865fcc22d2463a14cda17041568cb921a0c9c2a85b1dc9ceed41cdb`
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
| append | `s0_append.s0_append.spend` | 3567 | 22.10 | 12566 | 21.77 | 12817 | PASS | size-only; transaction-fit unproven |
| cursor | `s0_cursor.s0_cursor.spend` | 3475 | 21.53 | 12658 | 21.20 | 12909 | PASS | size-only; transaction-fit unproven |
| lineage | `s0_lineage.s0_lineage.spend` | 2078 | 12.88 | 14055 | 12.68 | 14306 | PASS | size-only; transaction-fit unproven |
| maintenance_escrow | `s0_maintenance_escrow.s0_maintenance_escrow.spend` | 831 | 5.15 | 15302 | 5.07 | 15553 | PASS | size-only; transaction-fit unproven |
| staging_proof_token | `s0_staging_proof_token.s0_staging_proof_token.mint` | 13144 | 81.47 | 2989 | 80.22 | 3240 | REDESIGN | size-only; transaction-fit unproven |
| consumer_predicates | `s0_consumer_predicates.s0_consumer_predicates.spend` | 699 | 4.33 | 15434 | 4.26 | 15685 | PASS | size-only; transaction-fit unproven |
| reference_cursor_consumer | `s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend` | 1389 | 8.60 | 14744 | 8.47 | 14995 | PASS | size-only; transaction-fit unproven |

Percentages are truncated display values from integer arithmetic
`bytes * 10000 / ceiling`. Threshold uses integer bytes:
`>= 12907` is `REDESIGN`. Headroom is signed and not clamped.

## Machine rows

```
S0-ROW member=append title=s0_append.s0_append.spend bytes=3567 reference_pct=22.10 reference_headroom=12566 tx_pct=21.77 tx_headroom=12817 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=cursor title=s0_cursor.s0_cursor.spend bytes=3475 reference_pct=21.53 reference_headroom=12658 tx_pct=21.20 tx_headroom=12909 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=lineage title=s0_lineage.s0_lineage.spend bytes=2078 reference_pct=12.88 reference_headroom=14055 tx_pct=12.68 tx_headroom=14306 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=maintenance_escrow title=s0_maintenance_escrow.s0_maintenance_escrow.spend bytes=831 reference_pct=5.15 reference_headroom=15302 tx_pct=5.07 tx_headroom=15553 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=staging_proof_token title=s0_staging_proof_token.s0_staging_proof_token.mint bytes=13144 reference_pct=81.47 reference_headroom=2989 tx_pct=80.22 tx_headroom=3240 threshold=REDESIGN caveat="size-only; transaction-fit unproven"
S0-ROW member=consumer_predicates title=s0_consumer_predicates.s0_consumer_predicates.spend bytes=699 reference_pct=4.33 reference_headroom=15434 tx_pct=4.26 tx_headroom=15685 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=reference_cursor_consumer title=s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend bytes=1389 reference_pct=8.60 reference_headroom=14744 tx_pct=8.47 tx_headroom=14995 threshold=PASS caveat="size-only; transaction-fit unproven"

```
