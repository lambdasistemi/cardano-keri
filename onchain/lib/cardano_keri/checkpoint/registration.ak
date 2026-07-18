//// #114 registration predicate + E1-E9 event binding (S3 mirror).
////
//// Mirrors the S2 Haskell `Cardano.KERI.AID.Checkpoint.Registration`
//// verdict-for-verdict: the pure R3/R4/R6/R7/R8 subset of the `Register`
//// mint branch over `RegistrationEvidence` (the full keripy `icp`
//// serialization plus prover-supplied per-field offsets) and the genesis
//// datum, returning a `RegistrationVerdict` sum (`RegistrationValid` ≙
//// `Right ()`, `RegistrationInvalid(e)` ≙ `Left e`) with one constructor
//// per check, evaluated in the same order.
////
//// Offsets LOCATE content, they never define it: every expected slice is
//// computed from the datum (derivation-code-prefixed qb64 or an exact
//// keripy re-spelling), so pointing an offset at a different field of the
//// genuine event compares differently-coded bytes and fails (the A-001
//// offset-misdirection argument; spec "Why offset misdirection fails").
////
//// Transaction-shape checks (R1/R2/R5 token presence) are the S5
//// validator layer; R5 appears here only as the proof-token name
//// derivation `proof_token_name`. The H1 `<= 1024` byte length tier is
//// the S4 hash-proof policy's scope — this predicate carries no length
//// guard. `registration_tests.ak` asserts these verdicts match the
//// Haskell over the shared generated vectors (`registration_vectors.ak`).

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{blake2b_256, verify_ed25519_signature}
use aiken/primitive/bytearray
use cardano_keri/base64url
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/message.{
  Icp, InceptionError, InceptionInvalid, InceptionMessage, InceptionValid,
  deriveAidAssetName, inception_datum, inception_domain, qb64_aid, qb64_verkey,
  validate_inception,
}
use cardano_keri/checkpoint/threshold.{
  Threshold, Unweighted, Weight, Weighted, evaluate,
}

// ---------------------------------------------------------
// Deployment context (mirrors the S2 `DeploymentContext`)
// ---------------------------------------------------------

/// The deployment the registration validates against: the frozen
/// validator parameters (`network_id`, the checkpoint policy = own script
/// hash, `d_reg`) plus the ledger `min_ada` floor the R8 arithmetic runs
/// over.
pub type DeploymentContext {
  network_id: Int,
  checkpoint_policy_id: ByteArray,
  min_ada: Int,
  d_reg: Int,
}

// ---------------------------------------------------------
// Registration evidence (mirrors the S2 `RegistrationEvidence`)
// ---------------------------------------------------------

/// The `Register` redeemer evidence: the full keripy `icp` serialization,
/// per-field value offsets into it (the generator's offset convention:
/// first byte of the value content between the quotes; a weighted
/// `kt`/`nt` offset points at the opening `[` of the full compact-JSON
/// array), and the controller signatures.
///
/// `ctrl_sigs` index into the datum's `cur_keys` and sign the
/// `InceptionMessage` canonical-CBOR preimage — NOT the KERI event bytes
/// (`event_bytes`); the KEL's own indexed KERI signatures stay off-chain
/// audit material (spec QF).
pub type RegistrationEvidence {
  event_bytes: ByteArray,
  off_t: Int,
  off_i: Int,
  off_s: Int,
  off_k: List<Int>,
  off_kt: Int,
  off_n: List<Int>,
  off_nt: Int,
  off_b: List<Int>,
  off_bt: Int,
  ctrl_sigs: List<(Int, ByteArray)>,
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
// Message reconstruction (R3)
// ---------------------------------------------------------

/// The RECONSTRUCTED `InceptionMessage`: deployment parameters from the
/// context, the asset name derived (never copied) from the datum's AID,
/// and the datum's own key-state fields. This is the only message shape
/// the predicate ever consults — nothing message-shaped is
/// caller-supplied (R3).
pub fn registration_message(
  ctx: DeploymentContext,
  d: CheckpointDatumV1,
) -> InceptionMessage {
  InceptionMessage {
    domain: inception_domain,
    network_id: ctx.network_id,
    checkpoint_policy_id: ctx.checkpoint_policy_id,
    aid_asset_name: deriveAidAssetName(d.cesr_aid),
    cesr_aid: d.cesr_aid,
    cur_keys: d.cur_keys,
    cur_threshold: d.cur_threshold,
    next_keys: d.next_keys,
    next_threshold: d.next_threshold,
    witnesses: d.witnesses,
    toad: d.toad,
    native_sn: d.native_sn,
  }
}

// ---------------------------------------------------------
// The registration predicate
// ---------------------------------------------------------

/// A registration rejection reason (one constructor per check; mirrors
/// the S2 `RegistrationError` constructor-for-constructor).
pub type RegistrationError {
  /// R3: `seq != 0` or the datum is not the genesis datum of the
  /// reconstructed message.
  R3GenesisDatumMismatch
  /// R4: the frozen #68 `validate_inception` rejected (domain, AID
  /// width, derived asset name, `native_sn`, F18 + rule 14).
  R4InceptionInvalid(InceptionError)
  /// E1: the `t` slice is not `"icp"` (`dip`/`drt`/`rot` all reject
  /// here; the verified slice feeds R4's event type).
  E1EventTypeMismatch
  /// E2: the `i` slice is not the datum AID's E-code qb64.
  E2AidMismatch
  /// E3: the `s` slice is not `"0"` (an `icp` has `s = 0`).
  E3SequenceMismatch
  /// E4: `k` offset count or a slice differs from the datum's
  /// `cur_keys` D-code qb64 — the keys-must-match gate.
  E4CurKeysMismatch
  /// E5: the `kt` slice is not the canonical re-spelling of
  /// `cur_threshold`.
  E5CurThresholdMismatch
  /// E6: `n` offset count or a slice differs from the datum's
  /// `next_keys` E-code qb64.
  E6NextKeysMismatch
  /// E7: the `nt` slice is not the canonical re-spelling of
  /// `next_threshold`.
  E7NextThresholdMismatch
  /// E8: `b` offset count or a slice differs from the datum's witness
  /// B-code qb64.
  E8WitnessesMismatch
  /// E9: the `bt` slice is not the hex re-spelling of `toad`.
  E9ToadMismatch
  /// R7: the distinct positions with a verifying signature over the
  /// message preimage do not satisfy `cur_threshold`.
  R7QuorumUnsatisfied
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

/// R6 — the E1-E9 event-binding slice set. Every expected value is
/// computed from the datum (derivation-code-prefixed qb64 or exact
/// re-spelling); the prover's offsets only locate it. A slice is checked
/// bounds-first, so a truncated (tail) or negative offset fails its
/// field's check like any mismatch.
pub fn event_binding(
  d: CheckpointDatumV1,
  e: RegistrationEvidence,
) -> RegistrationVerdict {
  if !slice_matches(e.event_bytes, e.off_t, "icp") {
    RegistrationInvalid(E1EventTypeMismatch)
  } else if !slice_matches(e.event_bytes, e.off_i, qb64_aid(d.cesr_aid)) {
    RegistrationInvalid(E2AidMismatch)
  } else if !slice_matches(e.event_bytes, e.off_s, "0") {
    RegistrationInvalid(E3SequenceMismatch)
  } else if !slices_match(
    e.event_bytes,
    e.off_k,
    list.map(d.cur_keys, qb64_verkey),
  ) {
    RegistrationInvalid(E4CurKeysMismatch)
  } else if !slice_matches(
    e.event_bytes,
    e.off_kt,
    respell_threshold(d.cur_threshold),
  ) {
    RegistrationInvalid(E5CurThresholdMismatch)
  } else if !slices_match(
    e.event_bytes,
    e.off_n,
    list.map(d.next_keys, qb64_aid),
  ) {
    RegistrationInvalid(E6NextKeysMismatch)
  } else if !slice_matches(
    e.event_bytes,
    e.off_nt,
    respell_threshold(d.next_threshold),
  ) {
    RegistrationInvalid(E7NextThresholdMismatch)
  } else if !slices_match(
    e.event_bytes,
    e.off_b,
    list.map(d.witnesses, qb64_witness_verkey),
  ) {
    RegistrationInvalid(E8WitnessesMismatch)
  } else if !slice_matches(e.event_bytes, e.off_bt, respell_hex(d.toad)) {
    RegistrationInvalid(E9ToadMismatch)
  } else {
    RegistrationValid
  }
}

/// The pure registration predicate: R3, R6 (E1-E9), R4, R7, R8, in
/// order (the same order as the S2 Haskell). R6 precedes R4 because E1's
/// verified `t` slice is what derives R4's event type (after E1 only
/// `Icp` can reach it); misdirected offsets that force a duplicate datum
/// key slip past E4 only to fail R4's F18 (rule 2). The `lovelace`
/// argument is the state output's value the R8 arithmetic runs over;
/// transaction shape itself (R1/R2/R5) is the S5 validator layer.
pub fn registration_predicate(
  ctx: DeploymentContext,
  d: CheckpointDatumV1,
  lovelace: Int,
  e: RegistrationEvidence,
) -> RegistrationVerdict {
  // R3: genesis datum — reconstructed message, nothing supplied.
  let m = registration_message(ctx, d)
  if !(d.seq == 0 && d == inception_datum(m)) {
    RegistrationInvalid(R3GenesisDatumMismatch)
  } else {
    // R6: the event-binding slice set (E1 derives R4's type).
    when event_binding(d, e) is {
      RegistrationInvalid(err) -> RegistrationInvalid(err)
      RegistrationValid ->
        // R4: the frozen #68 schema predicate, reused.
        when validate_inception(Icp, m) is {
          InceptionInvalid(err) -> RegistrationInvalid(R4InceptionInvalid(err))
          InceptionValid -> {
            // R7: distinct verified positions over the message preimage.
            let preimage = cbor.serialise(m)
            let signed = verified_positions(d.cur_keys, preimage, e.ctrl_sigs)
            if !evaluate(d.cur_threshold, list.length(d.cur_keys), signed) {
              RegistrationInvalid(R7QuorumUnsatisfied)
            } else if lovelace < ctx.min_ada + ctx.d_reg {
              // R8: deposit floor.
              RegistrationInvalid(R8DepositBelowMinimum)
            } else {
              RegistrationValid
            }
          }
        }
    }
  }
}

// ---------------------------------------------------------
// Helpers
// ---------------------------------------------------------

/// Does the slice of `raw` at `off` equal `expected`? Bounds-checked: an
/// out-of-range span never matches (mirrors the S2 `sliceMatches`).
pub fn slice_matches(raw: ByteArray, off: Int, expected: ByteArray) -> Bool {
  let n = bytearray.length(expected)
  off >= 0 && off + n <= bytearray.length(raw) && bytearray.take(
    bytearray.drop(raw, off),
    n,
  ) == expected
}

// Offset-count equality + slice equality at every offset (the E4/E6/E8
// list form; mirrors the S2 `slices`).
fn slices_match(
  raw: ByteArray,
  offs: List<Int>,
  expected: List<ByteArray>,
) -> Bool {
  when offs is {
    [] -> expected == []
    [o, ..os] ->
      when expected is {
        [] -> False
        [x, ..xs] -> slice_matches(raw, o, x) && slices_match(raw, os, xs)
      }
  }
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
      when list.at(keys, idx) is {
        Some(k) ->
          if verify_ed25519_signature(k, msg, sig) {
            Some(idx)
          } else {
            None
          }
        None -> None
      }
    },
  )
}
