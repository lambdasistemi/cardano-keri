# Data model

## DM-291-DECODED-EVENT — decoded establishment event

A variant-tagged, non-wire result produced only from complete event bytes:

- common exact raw spellings: version, type, SAID, AID, sequence, current
  threshold/keys, next threshold/keys, witness threshold, and anchors;
- `icp`: witness set and config traits;
- `dip`: the `icp` projection plus delegator prefix;
- `rot`: prior event, witness cuts, and witness adds;
- `drt`: the `rot` projection under the delegated-rotation variant;
- a structure-derived SAID preimage with only the canonical `d`/`i` spans
  blanked where the selected variant requires it.

Fields remain byte spellings at this boundary. Existing datum/evidence owners
retain semantic types and compare their canonical spelling with this result.

Invariants: INV-BIND-291, INV-TOTAL-291, INV-TYPE-291.

## DM-291-DECODE-ERROR — total-parse rejection

Closed reasons distinguish length bound, version prefix/size mismatch,
framing, field order/name/count, duplicate/missing/unknown field, value shape,
unsupported event type, and trailing bytes. No error carries a caller offset.

## DM-291-REGISTRATION-EVIDENCE — offset-free Register evidence

Wire fields, in order: exact event bytes, indexed controller signatures, and
indexed witness receipts.

Removed authority: all scalar/list event-field offsets.

## DM-291-ADVANCE-EVIDENCE — offset-free Advance evidence

Wire fields, in order: exact event bytes, typed witness-cut list, typed
witness-add list, indexed controller signatures, and indexed witness receipts.
The typed deltas must equal the decoded `br`/`ba` spellings.

Removed authority: all scalar/list event-field offsets.

## DM-291-ENFORCEMENT-EVIDENCE — offset-free enforcement evidence

Wire fields, in order: exact event bytes; native sequence; SAID; revealed and
next keys; current and next thresholds; witness threshold; controller
signatures; witness signatures. Every duplicated semantic value remains bound
to the decoded `rot` value.

Removed authority: all scalar/list event-field offsets. The changed canonical
encoding also changes its entitlement digest and all dependent wire goldens.

## DM-291-HASH-PROOF-REDEEMER — offset-free hash proof

Wire fields, in order: exact event bytes and raw 32-byte CESR AID. The decoded
`icp` supplies the `d`/`i` values and blanking boundary.

Removed authority: `off_i` and `off_d`.

## DM-291-ORACLE-ROW — non-wire reference evidence

Test-only keripy metadata may retain expected event variant, protected values,
and field spans. A row records fixture ID, raw bytes, keripy version, source
seed, and expected projection. It has no encoder to Plutus `Data`.

## Output ceiling

This artifact is limited to 80 lines and 7 KiB.
