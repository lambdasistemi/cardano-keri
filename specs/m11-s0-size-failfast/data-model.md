# S0 data model

Artifact ceiling: 6,000 bytes / 140 lines.

These are minimal measurement shapes, not frozen production schemas.

| ID | Shape | Required fields | Validation relevant to S0 |
|---|---|---|---|
| S0-D01 | Parsed event | raw bytes, event kind, sequence, SAID, key material, threshold, witness/receipt counts | Raw bytes and derived identity are both consumed by reachable parsing/binding work |
| S0-D02 | Record state | event root, occupancy root, event count | Append skeleton must derive changed roots/count rather than accept submitter-authored replacements |
| S0-D03 | Cursor state | keys digest, KERI state enum, grade enum, last-moved slot, registration slot | Cursor and predicates consume every field |
| S0-D04 | Historical proof input | key/location, proof path, prior snapshot digest | Append/cursor skeletons exercise authenticated proof work |
| S0-D05 | Lineage state | lineage id, registration slot, predecessor id option, event root, occupancy root, cursor, closed flag | Lineage skeleton exercises genesis/presence/age/marker-relevant fields |
| S0-D06 | Escrow state | funder, premium, remaining value, notice start option | Escrow skeleton exercises witnessed-service and notice-close branches |
| S0-D07 | Predicate policy | accepted keys digest, accepted states, minimum grade, maximum age | Predicate result depends on all four policy dimensions |
| S0-D08 | Measurement row | member, blueprint title, bytes, reference percentage/headroom, transaction percentage/headroom, threshold verdict, caveat | Arithmetic is derived from compiled hex and fixed ceilings |
| S0-D09 | Evidence identity | source commit, blueprint SHA-256, compiler path/version/SHA-256, command, exit, output SHA-256 | Every published row is reproducible and attributable |

## State invariants

- Measurement-only types must not be described as final on-chain schemas.
- A passing predicate cannot ignore any field in S0-D07.
- A measured program cannot borrow another member's compiled code/title.
- Headroom may be negative; it is never clamped to zero.
- Percentages are presentation values. Threshold classification uses integer
  bytes and the exact rational comparison, not rounded display text.
- Tx-A inherits the released 1024-byte premint cap. An 8-key 1,049-byte
  inception is refused there and never reaches append. Extending Blake3
  domain is out of S0.
- `g1_c4_input_393` and `g1_c4_input_966` are excluded: known broken SAID
  fixtures, not green controls.
- Cited G1 coupling 15,155,350 mem / 7,631,646,035 CPU is a two-transaction
  sum of heaviest role instances, not a per-tx limit or headroom.

