# Functions model

## FN-291-DECODE-AIKEN — `decode_establishment_event`

- Arguments: `event_bytes: ByteArray`.
- Result: `EventDecodeVerdict` containing DM-291-DECODED-EVENT or
  DM-291-DECODE-ERROR.
- Constraint: total, bounded to 1–1024 bytes, complete consumption, no caller
  position argument or ambient evidence.

## FN-291-DECODE-HS — `decodeEstablishmentEvent`

- Arguments: `eventBytes :: ByteString`.
- Result: `Either EventDecodeError DecodedEstablishmentEvent`.
- Constraint: verdict and protected-value parity with FN-291-DECODE-AIKEN.

## FN-291-SAID-PREIMAGE-AIKEN — `decode_said_preimage`

- Arguments: `event_bytes: ByteArray`.
- Result: event-decode verdict carrying canonical SAID-blanked bytes.
- Constraint: blanking boundaries derive only from the successful total parse.

## FN-291-SAID-PREIMAGE-HS — `decodeSaidPreimage`

- Arguments: `eventBytes :: ByteString`.
- Result: `Either EventDecodeError ByteString`.
- Constraint: byte parity with FN-291-SAID-PREIMAGE-AIKEN.

## Changed binders

- Aiken `event_binding(d: CheckpointDatumV1, e: RegistrationEvidence) ->
  RegistrationVerdict` and Haskell `eventBinding` retain their external
  signatures over the new offset-free evidence type.
- Aiken `event_binding(new: CheckpointDatumV1, e: AdvanceEvidence) ->
  AdvanceEventVerdict` and its Haskell mirror retain their external signatures
  over the new offset-free evidence type.
- Aiken `bind_enforcement_evidence(aid: ByteArray, evidence:
  EnforcementEvidence) -> EnforcementBindingVerdict` and Haskell
  `bindEnforcementEvidence` retain their external signatures over the new
  offset-free evidence type.
- `registration_predicate`, `advance_predicate`, `convict_predicate`, and
  `freeze_predicate` retain signature-authentication inputs and results.

All three binders reject a decode error or wrong structural variant before
field comparisons. None accepts or constructs a field position.

## Changed hash-proof boundary

- `HashProofRedeemer` carries DM-291-HASH-PROOF-REDEEMER.
- The mint branch consumes `decode_said_preimage(input_bytes)` and the decoded
  `icp` projection; no public helper accepts `off_i` or `off_d`.
- The burn branch remains content-independent.

## Changed wire functions

Existing `registrationEvidenceData`, `advanceEvidenceData`,
`enforcementEvidenceData`, observer/spend redeemer encoders, and the live
hash-proof encoder retain their names while encoding the DM-291 offset-free
field orders exactly once.

## Output ceiling

This artifact is limited to 75 lines and 7 KiB.
