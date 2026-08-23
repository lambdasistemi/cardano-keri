# Modules model — R1 event-derived MPF key

Only new or changed responsibilities are listed. Data and signatures are
defined in the sibling model files.

| ID | Component | Responsibility | Dependency direction |
|---|---|---|---|
| R1-M01 | `m12/event_key` | Own V1 canonical event-key derivation and fail-closed adaptation from verified decoder output | consumes decoder event shape; depends on no validator or record module |
| R1-M02 | `m12/event_key_vectors` | Own independent accepted vectors, code-set coverage, constructor coverage, rejection properties, and coexistence proof | consumes the public event-key boundary and MPF proof surface |
| R1-M03 | `m12/record` | Bind successful verified decode to a derived key and use that key for record insertion | depends on `event_key`; never the reverse |
| R1-M04 | `m12/types` | Expose derived event-key data to record flow and narrow `HistoricalProof` to sibling proof only | remains a shared leaf type owner |
| R1-M05 | `m12/cursor` | Stop consuming removed historical-proof authority while preserving R1-compatible compilation and existing non-R1 behavior | depends on narrowed types and record parsing; owns no R2/R3 redesign |
| R1-M06 | `validators/s0_skeleton_tests` | Preserve existing S0 reachability and prove submitter-key rejection after the proof shape narrows | consumes public M12 validator surfaces |
| R1-M07 | R1 evidence bundle | Reproduce the exact measured-source manifest and classify all changed non-onchain flake inputs | reads only the gate-owned source horizon; owns no product semantics |

## Promotion decision

Event-key derivation is promoted to `m12/event_key` because both record
insertion and independent proof vectors need one stable source of truth. It is
not placed in the decoder: successful decoding and key-protocol derivation are
distinct responsibilities, and the decoder remains unchanged in this slice.
