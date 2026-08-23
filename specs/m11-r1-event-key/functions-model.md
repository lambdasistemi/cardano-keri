# Functions model — R1 event-derived MPF key

New or changed signatures only. Names and argument/result types are contract;
implementation details are not specified here.

| ID | Function | Signature | Constraint / effect |
|---|---|---|---|
| R1-F01 | `event_key` | `(i: ByteArray, s: Int, prior: Option<ByteArray>, d: ByteArray) -> ByteArray` | sole V1 key producer over canonical qualified inputs |
| R1-F02 | `event_key_of` | `(ev: DecodedEstablishmentEvent) -> Option<ByteArray>` | accepts only canonical identity and event-type-consistent prior shape; no sentinel/default |
| R1-F03 | `event_sequence_of` | `(ev: DecodedEstablishmentEvent) -> Option<Int>` | exposes canonical hexadecimal sequence as integer or fails closed |
| R1-F04 | `bind_parsed_event` | existing arguments and `Option<ParsedEvent>` result | successful result carries R1-D04 derived from the same verified event |
| R1-F05 | `apply_record_append` | existing arguments and `Option<RecordState>` result | key argument to MPF insertion is the derived event key; redeemer contributes only sibling proof |
| R1-F06 | `derive_cursor` | existing arguments and `Option<CursorState>` result | consumes no removed `HistoricalProof` authority; R2/R3 behavior is unchanged and out of scope |
| R1-F07 | `s0_append.spend` | `(staging_proof_policy: PolicyId)` applied to the validator, plus existing datum, redeemer, self reference, and transaction | passes only the applied policy to record proof consumption; redeemer has no policy field |
| R1-F08 | `validate_staging_token` | existing arguments and `Bool` result | authenticates recomputed `d`, admits distinct canonical qualified `i`, and preserves pair-bound mint/burn behavior |

No public function in this slice accepts a submitter-selected event key,
location, prior-snapshot digest, event identity field, or settlement order.
