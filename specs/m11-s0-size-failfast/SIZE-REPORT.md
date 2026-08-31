# S0 family size report

Architectural measurement of seven separately compiled skeletons.
Every row and verdict is size-only; transaction-fit unproven.

## Toolchain

- path: `/nix/store/zk3s76mjwcb5fz099d6dq02c684bg8wn-aiken-1.1.23/bin/aiken`
- version: `aiken v1.1.23+unknown`
- sha256: `c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689`
Trace level: `silent`

## Source and blueprint identity

Measured source commit: `4bc8dad9b3fa39f98ba6d21987c9046623b8895f`
- owned-source sha256: `fd34bf5cc4af2748953c4651e4c8b7435eb430d635d979777cc75bfca2c0ac53`
- blueprint sha256: `83aa0525c30e8713dff6c67ca54c657193e0eb59b2f396a2449288f711526beb`
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
| append | `s0_append.s0_append.spend` | 9498 | 58.87 | 6635 | 57.97 | 6886 | PASS | size-only; transaction-fit unproven |
| cursor | `s0_cursor.s0_cursor.spend` | 7212 | 44.70 | 8921 | 44.01 | 9172 | PASS | size-only; transaction-fit unproven |
| lineage | `s0_lineage.s0_lineage.spend` | 2078 | 12.88 | 14055 | 12.68 | 14306 | PASS | size-only; transaction-fit unproven |
| maintenance_escrow | `s0_maintenance_escrow.s0_maintenance_escrow.spend` | 831 | 5.15 | 15302 | 5.07 | 15553 | PASS | size-only; transaction-fit unproven |
| staging_proof_token | `s0_staging_proof_token.s0_staging_proof_token.mint` | 9248 | 57.32 | 6885 | 56.44 | 7136 | PASS | size-only; transaction-fit unproven |
| consumer_predicates | `s0_consumer_predicates.s0_consumer_predicates.spend` | 699 | 4.33 | 15434 | 4.26 | 15685 | PASS | size-only; transaction-fit unproven |
| reference_cursor_consumer | `s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend` | 1389 | 8.60 | 14744 | 8.47 | 14995 | PASS | size-only; transaction-fit unproven |

Percentages are truncated display values from integer arithmetic
`bytes * 10000 / ceiling`. Threshold uses integer bytes:
`>= 12907` is `REDESIGN`. Headroom is signed and not clamped.

## Residuals

- Tx-A inherits the released 1024-byte premint cap. A 1,049-byte 8-key
  inception is refused at premint and never reaches append.
- G1 coupling 15,155,350 mem / 7,631,646,035 CPU is a two-transaction sum
  of the heaviest measured role instances: not a per-transaction limit,
  not headroom, not one AID's coupling. Per-role budgets remain S2.
- `g1_c4_input_393` and `g1_c4_input_966` are excluded (known broken
  SAID/offset fixtures). The 1024-byte boundary fact may be cited.
- Two transactions make `size-only; transaction-fit unproven` more load-bearing, not less.

## Machine rows

```
S0-ROW member=append title=s0_append.s0_append.spend bytes=9498 reference_pct=58.87 reference_headroom=6635 tx_pct=57.97 tx_headroom=6886 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=cursor title=s0_cursor.s0_cursor.spend bytes=7212 reference_pct=44.70 reference_headroom=8921 tx_pct=44.01 tx_headroom=9172 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=lineage title=s0_lineage.s0_lineage.spend bytes=2078 reference_pct=12.88 reference_headroom=14055 tx_pct=12.68 tx_headroom=14306 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=maintenance_escrow title=s0_maintenance_escrow.s0_maintenance_escrow.spend bytes=831 reference_pct=5.15 reference_headroom=15302 tx_pct=5.07 tx_headroom=15553 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=staging_proof_token title=s0_staging_proof_token.s0_staging_proof_token.mint bytes=9248 reference_pct=57.32 reference_headroom=6885 tx_pct=56.44 tx_headroom=7136 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=consumer_predicates title=s0_consumer_predicates.s0_consumer_predicates.spend bytes=699 reference_pct=4.33 reference_headroom=15434 tx_pct=4.26 tx_headroom=15685 threshold=PASS caveat="size-only; transaction-fit unproven"
S0-ROW member=reference_cursor_consumer title=s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend bytes=1389 reference_pct=8.60 reference_headroom=14744 tx_pct=8.47 tx_headroom=14995 threshold=PASS caveat="size-only; transaction-fit unproven"

```
