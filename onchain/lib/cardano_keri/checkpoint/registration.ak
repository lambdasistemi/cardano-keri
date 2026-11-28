//// The registration predicate and the binding of an inception event to the datum it books.
////
//// The heavy evidence of a registration is the signed `icp` itself, its controller signatures and its witness
//// receipts. Nothing in it is positioned by the prover: the canonical inception is rebuilt from the datum's qualified
//// spellings and compared with the signed bytes whole. The datum keeps the qualified text of the identifier and of each
//// current key; the raw payloads are derived for the signature checks.
////
//// Transaction-shape checks (R1/R2/R5 token presence) are the validator layer; R5 appears here only as the proof-token
//// name derivation `proof_token_name`. The one-chunk length tier is the hash-proof policy's scope.

use aiken/builtin
use aiken/collection/list
use aiken/crypto.{blake2b_256, verify_ed25519_signature}
use aiken/primitive/bytearray
use cardano_keri/base64url
use cardano_keri/checkpoint/datum.{
  DatumError, DatumInvalid, DatumValid, KeyStateView,
  key_state_inception_well_formed,
}
use cardano_keri/checkpoint/event_decoder.{AnchorItem, anchor_after}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/qualified.{code_b, code_d, code_e, digest_payload}
use cardano_keri/checkpoint/threshold.{
  Threshold, Unweighted, Weight, Weighted, evaluate,
}

// ---------------------------------------------------------
// Deployment context (mirrors the S2 `DeploymentContext`)
// ---------------------------------------------------------

/// The deployment values registration validation enforces: the
/// deployment-fixed `d_reg` plus the ledger `min_ada` floor the R8
/// arithmetic runs over.
pub type DeploymentContext {
  min_ada: Int,
  d_reg: Int,
}

/// Mechanical lower bound for the deployment-fixed registration bond.
pub const registration_deposit_floor: Int = 5_000_000

/// Whether an applied registration-bond parameter is deployable.
pub fn valid_registration_deposit(d_reg: Int) -> Bool {
  d_reg >= registration_deposit_floor
}

// ---------------------------------------------------------
// Registration evidence (mirrors the S2 `RegistrationEvidence`)
// ---------------------------------------------------------

/// The `Register` redeemer evidence: the signed `icp` as keripy serialized it, the controller signatures and the witness
/// receipts. Both signature families authenticate the exact `event_bytes`.
pub type RegistrationEvidence {
  event_bytes: ByteArray,
  ctrl_sigs: List<(Int, ByteArray)>,
  wit_receipts: List<(Int, ByteArray)>,
}

/// The qualified spellings the datum keeps: the identifier and each current key, exactly as the event signed them.
pub type QualifiedSpelling {
  aid: ByteArray,
  cur_keys: List<ByteArray>,
}

// ---------------------------------------------------------
// B-code qb64 and canonical keripy re-spelling
// ---------------------------------------------------------

/// The fully qualified Base64url form of a raw 32-byte NON-TRANSFERABLE
/// Ed25519 verkey: code `'B'` (`0x42`) followed by `b64url(0x00 ‖ key)`
/// with the first (always `'A'`) character replaced by the code — 44
/// ASCII characters. The witness (`b` entry) spelling; same body as
/// `qb64_verkey` under the `B` code.
pub fn qb64_witness_verkey(key: ByteArray) -> ByteArray {
  bytearray.push(
    bytearray.drop(base64url.encode(bytearray.push(key, 0)), 1),
    66,
  )
}

/// The keripy `{:x}` integer spelling: lowercase hex, no leading zeros
/// (`0 -> "0"`, `26 -> "1a"`) — the `kt`/`nt` unweighted and `bt` value
/// bytes. Total: a negative input spells with a `-` prefix, which no
/// keripy serialization contains, so its slice check fails.
pub fn respell_hex(n: Int) -> ByteArray {
  if n < 0 {
    bytearray.concat("-", respell_hex(-n))
  } else if n < 16 {
    hex_digit(n)
  } else {
    bytearray.concat(respell_hex(n / 16), hex_digit(n % 16))
  }
}

// One lowercase-hex digit byte ('0'..'9', 'a'..'f').
fn hex_digit(d: Int) -> ByteArray {
  if d < 10 {
    bytearray.push(#"", 48 + d)
  } else {
    bytearray.push(#"", 87 + d)
  }
}

/// The exact compact-JSON value bytes keripy emits for a threshold
/// (E5/E7 expected content — #106 O2's canonical re-spelling, owned here
/// for `icp`): an `Unweighted` threshold as its lowercase-hex string
/// content (`respell_hex`; the offset points between the quotes), a
/// single-clause `Weighted` threshold as the flat fraction-string array
/// (`["1/2","1/4","1/4"]` — the S1 fixture ground truth), and a
/// multi-clause one as the nested array of arrays (keripy's multi-clause
/// convention). A unity/zero weight (`den == 1`) spells without a
/// denominator, as keripy does.
pub fn respell_threshold(threshold: Threshold) -> ByteArray {
  when threshold is {
    Unweighted(m) -> respell_hex(m)
    Weighted([clause]) -> respell_clause(clause)
    Weighted(clauses) ->
      bytearray.concat(
        bytearray.concat(
          "[",
          intercalate(",", list.map(clauses, respell_clause)),
        ),
        "]",
      )
  }
}

// One clause as a compact-JSON array of quoted fraction strings.
fn respell_clause(ws: List<Weight>) -> ByteArray {
  bytearray.concat(
    bytearray.concat("[", intercalate(",", list.map(ws, quoted_weight))),
    "]",
  )
}

// A weight as a quoted fraction string.
fn quoted_weight(w: Weight) -> ByteArray {
  bytearray.concat(bytearray.concat("\"", respell_weight(w)), "\"")
}

// `num/den` fraction-string content; `den == 1` spells bare.
fn respell_weight(w: Weight) -> ByteArray {
  let Weight { num, den } = w
  if den == 1 {
    respell_dec(num)
  } else {
    bytearray.concat(bytearray.concat(respell_dec(num), "/"), respell_dec(den))
  }
}

// The decimal spelling of an integer (keripy fraction components).
fn respell_dec(n: Int) -> ByteArray {
  if n < 0 {
    bytearray.concat("-", respell_dec(-n))
  } else if n < 10 {
    bytearray.push(#"", 48 + n)
  } else {
    bytearray.concat(respell_dec(n / 10), bytearray.push(#"", 48 + n % 10))
  }
}

// Join byte strings with a separator (no stdlib intercalate for bytes).
fn intercalate(sep: ByteArray, xs: List<ByteArray>) -> ByteArray {
  when xs is {
    [] -> #""
    [x] -> x
    [x, ..rest] ->
      bytearray.concat(bytearray.concat(x, sep), intercalate(sep, rest))
  }
}

// ---------------------------------------------------------
// Proof-token name (R5 derivation)
// ---------------------------------------------------------

/// The hash-proof token name: `blake2b_256(event_bytes ‖ cesr_aid)`. The
/// name binds the PAIR (bytes, AID): a proof minted for one AID can never
/// satisfy a registration carrying different bytes or a different AID.
/// The outer hash is the cheap native blake2b — a Cardano-internal label,
/// never a KERI artifact (no blake3 on the registration path, R5).
pub fn proof_token_name(
  event_bytes: ByteArray,
  cesr_aid: ByteArray,
) -> ByteArray {
  blake2b_256(bytearray.concat(event_bytes, cesr_aid))
}

// ---------------------------------------------------------
// Inception schema validation (R4)
// ---------------------------------------------------------

/// The attested KERI inception event type. V1 accepts only `Icp`.
pub type EventType {
  Icp
  Dip
  Drt
}

/// An inception datum rejection reason, with no authorization message.
pub type InceptionError {
  DelegatedInceptionRejected
  InceptionAidWidth
  InceptionNativeSnNonZero
  InceptionIllFormed(DatumError)
}

/// Structural inception-datum validation verdict.
pub type InceptionVerdict {
  InceptionValid
  InceptionInvalid(InceptionError)
}

/// Validate the structural inception projection carried by a datum.
pub fn validate_inception_datum(
  event_type: EventType,
  d: KeyStateView,
) -> InceptionVerdict {
  if event_type != Icp {
    InceptionInvalid(DelegatedInceptionRejected)
  } else if bytearray.length(d.cesr_aid) != 32 {
    InceptionInvalid(InceptionAidWidth)
  } else if d.native_sn != 0 {
    InceptionInvalid(InceptionNativeSnNonZero)
  } else {
    when key_state_inception_well_formed(d) is {
      DatumInvalid(err) -> InceptionInvalid(InceptionIllFormed(err))
      DatumValid -> InceptionValid
    }
  }
}

// ---------------------------------------------------------
// The registration predicate
// ---------------------------------------------------------

/// A registration rejection reason (one constructor per check; mirrors
/// the S2 `RegistrationError` constructor-for-constructor).
pub type RegistrationError {
  /// Applied `d_reg` is below `registration_deposit_floor`.
  DRegBelowMinimum
  /// R3: `seq != 0`.
  R3GenesisDatumMismatch
  /// R4: inception datum validation rejected (AID width, `native_sn`,
  /// F18 + rule 14).
  R4InceptionInvalid(InceptionError)
  /// R6: the signed bytes are not the canonical inception of the datum: rebuilt from the datum's spellings they differ
  /// anywhere before the anchor, the digest `d` is not an `E` digest, or the anchor is not one complete array that
  /// the closing brace follows.
  R6EventNotCanonical
  /// R6: the identifier does not fit its derivation code: a key must be the sole current key under threshold one
  /// (a `B` key also with empty next keys, witnesses and anchor), a digest must be the event's own digest.
  R6PrefixMismatch
  /// R7: distinct valid controller positions over `event_bytes` do not
  /// satisfy `cur_threshold`.
  R7QuorumUnsatisfied
  /// R7: distinct valid witness receipts over `event_bytes` do not meet
  /// `toad`, or a zero-toad datum carried a non-empty receipt list.
  R7WitnessQuorumUnsatisfied
  /// R8: state-output lovelace below `min_ada + d_reg`.
  R8DepositBelowMinimum
}

/// The registration verdict. `RegistrationValid` ≙ `Right ()`,
/// `RegistrationInvalid(e)` ≙ `Left e` (mirrors the S2
/// `Either RegistrationError ()`).
pub type RegistrationVerdict {
  RegistrationValid
  RegistrationInvalid(RegistrationError)
}

/// R6 — the binding of the event to the datum, by reconstruction: the canonical inception is rebuilt from the datum's own validated
/// spellings, the digest `d` read at its fixed place, and the whole event compared once up to the anchor, which the one
/// anchor scanner then reads and ends at the closing brace. No other field is scanned.
pub fn event_binding(
  d: KeyStateView,
  q: QualifiedSpelling,
  e: RegistrationEvidence,
) -> RegistrationVerdict {
  let raw = e.event_bytes
  let size = bytearray.length(raw)
  if size < 1 || size > 1024 {
    RegistrationInvalid(R6EventNotCanonical)
  } else {
    let said = builtin.slice_bytearray(40, 44, raw)
    when digest_payload(said) is {
      None -> RegistrationInvalid(R6EventNotCanonical)
      Some(_) -> {
        let prefix = "{\"v\":\"KERI10JSON"
          |> bytearray.concat(hex6(size))
          |> bytearray.concat("_\",\"t\":\"icp\",\"d\":\"")
          |> bytearray.concat(said)
          |> bytearray.concat("\",\"i\":\"")
          |> bytearray.concat(q.aid)
          |> bytearray.concat("\",\"s\":\"0\",\"kt\":")
          |> bytearray.concat(threshold_json(d.cur_threshold))
          |> bytearray.concat(",\"k\":")
          |> bytearray.concat(list_json(q.cur_keys))
          |> bytearray.concat(",\"nt\":")
          |> bytearray.concat(threshold_json(d.next_threshold))
          |> bytearray.concat(",\"n\":")
          |> bytearray.concat(list_json(list.map(d.next_keys, qb64_aid)))
          |> bytearray.concat(",\"bt\":\"")
          |> bytearray.concat(respell_hex(d.toad))
          |> bytearray.concat("\",\"b\":")
          |> bytearray.concat(
              list_json(list.map(d.witnesses, qb64_witness_verkey)),
            )
          |> bytearray.concat(",\"c\":[],\"a\":")
        let n = bytearray.length(prefix)
        if n >= size || builtin.slice_bytearray(0, n, raw) != prefix {
          RegistrationInvalid(R6EventNotCanonical)
        } else {
          when anchor_after(raw, n) is {
            None -> RegistrationInvalid(R6EventNotCanonical)
            Some((anchor, end)) ->
              if end + 1 != size || builtin.index_bytearray(raw, end) != 125 {
                RegistrationInvalid(R6EventNotCanonical)
              } else if prefix_binding(d, q, said, anchor) {
                RegistrationValid
              } else {
                RegistrationInvalid(R6PrefixMismatch)
              }
          }
        }
      }
    }
  }
}

/// Six lowercase hexadecimal digits of a size.
pub fn hex6(n: Int) -> ByteArray {
  let h = respell_hex(n)
  bytearray.concat(bytearray.take("000000", 6 - bytearray.length(h)), h)
}

/// A threshold as its JSON value: the quoted hexadecimal string, or the array.
pub fn threshold_json(t: Threshold) -> ByteArray {
  let spelled = respell_threshold(t)
  if bytearray.at(spelled, 0) == 91 {
    spelled
  } else {
    bytearray.concat(bytearray.concat("\"", spelled), "\"")
  }
}

/// A list of qualified texts as a JSON array of strings.
pub fn list_json(items: List<ByteArray>) -> ByteArray {
  when items is {
    [] -> "[]"
    [first, ..rest] ->
      bytearray.concat(
        bytearray.concat(
          "[\"",
          list.foldl(
            rest,
            first,
            fn(item, acc) {
              bytearray.concat(bytearray.concat(acc, "\",\""), item)
            },
          ),
        ),
        "\"]",
      )
  }
}

/// The identifier fits its derivation code. A digest identifier is the event's own digest. A key identifier is the sole
/// current key, signing alone; a non-transferable one also leaves nothing to rotate to, witness or anchor.
fn prefix_binding(
  d: KeyStateView,
  q: QualifiedSpelling,
  said: ByteArray,
  anchor: List<AnchorItem>,
) -> Bool {
  let code = bytearray.at(q.aid, 0)
  if code == code_e {
    said == q.aid
  } else if code == code_d {
    q.cur_keys == [q.aid] && d.cur_threshold == Unweighted(1)
  } else if code == code_b {
    q.cur_keys == [q.aid] && d.cur_threshold == Unweighted(1) && d.next_keys == [] && d.witnesses == [] && anchor == []
  } else {
    False
  }
}

/// The pure registration predicate: R3, R6, R4, R7, R8, in order. The `lovelace` argument is the state
/// output's value the R8 arithmetic runs over; transaction shape itself (R1/R2/R5) is the validator layer.
pub fn registration_predicate(
  ctx: DeploymentContext,
  d: KeyStateView,
  q: QualifiedSpelling,
  lovelace: Int,
  e: RegistrationEvidence,
) -> RegistrationVerdict {
  if !valid_registration_deposit(ctx.d_reg) {
    RegistrationInvalid(DRegBelowMinimum)
  } else if d.seq != 0 {
    RegistrationInvalid(R3GenesisDatumMismatch)
  } else {
    when event_binding(d, q, e) is {
      RegistrationInvalid(err) -> RegistrationInvalid(err)
      RegistrationValid ->
        when validate_inception_datum(Icp, d) is {
          InceptionInvalid(err) -> RegistrationInvalid(R4InceptionInvalid(err))
          InceptionValid -> {
            let signed = verified_positions(
              d.cur_keys,
              e.event_bytes,
              e.ctrl_sigs,
            )
            if !evaluate(d.cur_threshold, list.length(d.cur_keys), signed) {
              RegistrationInvalid(R7QuorumUnsatisfied)
            } else {
              let witnessed = verified_positions(
                d.witnesses,
                e.event_bytes,
                e.wit_receipts,
              )
              let receipts_satisfied = if d.toad == 0 {
                e.wit_receipts == []
              } else {
                list.length(list.unique(witnessed)) >= d.toad
              }
              if !receipts_satisfied {
                RegistrationInvalid(R7WitnessQuorumUnsatisfied)
              } else if lovelace < ctx.min_ada + ctx.d_reg {
                RegistrationInvalid(R8DepositBelowMinimum)
              } else {
                RegistrationValid
              }
            }
          }
        }
    }
  }
}

// ---------------------------------------------------------
// Helpers
// ---------------------------------------------------------

/// Does the slice of `raw` at `off` equal `expected`? Bounds-checked: an out-of-range span never matches. The
/// conviction binding still locates its fields by position and uses it.
pub fn slice_matches(raw: ByteArray, off: Int, expected: ByteArray) -> Bool {
  let n = bytearray.length(expected)
  off >= 0 && off + n <= bytearray.length(raw) && bytearray.take(
    bytearray.drop(raw, off),
    n,
  ) == expected
}

// The positions whose `(idx, sig)` verifies with `keys[idx]` over `msg`
// (the enforcement-layer helper shape; `evaluate` dedups positions).
fn verified_positions(
  keys: List<ByteArray>,
  msg: ByteArray,
  sigs: List<(Int, ByteArray)>,
) -> List<Int> {
  list.filter_map(
    sigs,
    fn(pair) {
      let (idx, sig) = pair
      if idx < 0 {
        None
      } else {
        when list.at(keys, idx) is {
          Some(k) ->
            if verify_ed25519_signature(k, msg, sig) {
              Some(idx)
            } else {
              None
            }
          None -> None
        }
      }
    },
  )
}
