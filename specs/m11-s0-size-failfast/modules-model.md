# S0 modules model

Artifact ceiling: 7,000 bytes / 150 lines.

## Dependency direction

`validators` depend on `family types` and narrowly scoped libraries. The
predicate library depends only on cursor policy data. No new S0 module depends
on the legacy monolithic checkpoint validator, measurement output, or runtime
evidence.

## Components

| ID | Component | Responsibility | Required honest surface |
|---|---|---|---|
| S0-M01 | family types | Minimal record, parsed-event, cursor, lineage, escrow, and predicate inputs | Typed fields sufficient to make each required operation reachable |
| S0-M02 | append validator | Tx-B append mutation | Total-parse event bytes, bind decoded SAID/AID to the premint digest, consume/burn the pair-named proof token, verify an authenticated-map proof/update, derive changed roots/count |
| S0-M03 | cursor validator | Tx-B cursor movement | Same parse+token-burn as append, plus historical proof and derived keys/state/grade/slot fields |
| S0-M04 | lineage validator | Represent genesis, juvenility, successor stamp, and close marker costs | Inspect transaction purpose/time, bind genesis identity or predecessor presence, derive inherited/final roots and flags |
| S0-M05 | maintenance escrow validator | Represent pay-per-fully-witnessed append and notice close | Decode grade and value/time context, compute premium/residue conditions, distinguish service and close transitions |
| S0-M06 | staging/proof-token validator | Tx-A premint policy | Inherited 1024-byte cap, KERI Blake3 SAID over dummy-spliced spans, pair-bound mint; burn always permitted. Payloads above 1024 B are refused here and never reach Tx-B |
| S0-M07 | consumer predicate library | Express adopted record-relative policy | Evaluate keys, KERI state, evidence grade, and freshness together; expose no always-true default |
| S0-M08 | consumer predicate measurement validator | Give S0-M07 an independent compiled program | Reach the complete S0-M07 predicate from a validator handler |
| S0-M09 | reference cursor consumer | Represent an adopted consumer | Select/decode cursor-like reference data and call S0-M07 before authorizing |
| S0-M10 | measurement harness | Produce one size row per unique blueprint program | Enforce title cardinality, toolchain pin, byte arithmetic, threshold verdict, caveat, hashes, and deterministic ordering |
| S0-M11 | anti-stub control | Refuse misleadingly small skeletons | Bind every measured handler to its role obligations and reject the deliberately hollow fixture |

## Non-responsibilities

S0 does not settle full KERI transition correctness, adversarial fixtures,
economic safety, lineage activation, preprod behavior, or worst-case ExUnits.
Those remain S2/S3 work. S0 also does not modify, wrap, or remeasure the M1
monolith as a candidate architecture.

