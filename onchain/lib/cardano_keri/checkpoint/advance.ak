//// The advance evidence, the binding of a signed rotation to the successor datum, and the receipt gate.
////
//// The heavy evidence of an advance is the signed `rot` itself, the witness-delta lists, the controller signatures and
//// the incoming-set witness receipts. Nothing in it is positioned by the prover: the canonical rotation is rebuilt from the
//// successor datum's qualified spellings and the evidence's witness deltas and compared with the signed bytes whole.
////
//// `advance_predicate` runs, in order: the message equalities (with the controller-signature evidence, verified
//// against `event_bytes` directly, folded in as the revealed-signer positions), the event binding (AE1-AE10), and the
//// incoming-set witness receipt quorum. No digest proof is taken over the rot bytes: `d` and `p` are not checked.

use aiken/builtin
use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{KeyStateView}
use cardano_keri/checkpoint/event_decoder.{anchor_after}
use cardano_keri/checkpoint/message.{
  AdvanceError, AdvanceInvalid, AdvanceValid, RevealedSuccessorSigners,
  SpentCheckpoint, advance_equalities, qb64_aid,
}
use cardano_keri/checkpoint/qualified.{digest_payload}
use cardano_keri/checkpoint/registration.{
  QualifiedSpelling, hex6, list_json, qb64_witness_verkey, respell_hex,
  respell_threshold, threshold_json,
}

// ---------------------------------------------------------
// Advance evidence
// ---------------------------------------------------------

/// The `Advance` redeemer evidence: the signed `rot`, the ordered witness-delta lists, the controller signatures and the
/// incoming-set witness receipts.
///
/// `ctrl_sigs` index into `NEW.cur_keys` and sign `event_bytes` directly. `wit_receipts` index into the DERIVED incoming
/// witness set (the created datum's own `witnesses`, already derived and pinned) and sign `event_bytes` exactly.
pub type AdvanceEvidence {
  event_bytes: ByteArray,
  wit_cut: List<ByteArray>,
  wit_add: List<ByteArray>,
  ctrl_sigs: List<(Int, ByteArray)>,
  wit_receipts: List<(Int, ByteArray)>,
}

// ---------------------------------------------------------
// Event binding (V6, AE1-AE10)
// ---------------------------------------------------------

/// Why the event binding rejected.
pub type AdvanceEventError {
  /// The signed bytes are not the canonical rotation of the successor datum and the witness deltas: rebuilt from them
  /// they differ anywhere before the anchor, `d` or `p` is not an `E` digest, or the anchor is not one complete array
  /// that the closing brace follows.
  AEEventNotCanonical
}

/// The event-binding verdict. `AdvanceEventValid` ≙ `Right ()`,
/// `AdvanceEventInvalid(e)` ≙ `Left e`.
pub type AdvanceEventVerdict {
  AdvanceEventValid
  AdvanceEventInvalid(AdvanceEventError)
}

/// V6 — the binding of the event to the successor datum, by reconstruction: the canonical rotation is rebuilt from the successor datum's
/// spellings and the evidence's witness deltas, the digests `d` and `p` read at their places, and the whole event
/// compared once up to the anchor, which the one anchor scanner then reads and ends at the closing brace.
fn event_binding_holds(
  new: KeyStateView,
  q: QualifiedSpelling,
  e: AdvanceEvidence,
) -> Bool {
  let raw = e.event_bytes
  let size = bytearray.length(raw)
  if size < 1 || size > 1024 {
    False
  } else {
    let said = builtin.slice_bytearray(40, 44, raw)
    let lead = "{\"v\":\"KERI10JSON"
      |> bytearray.concat(hex6(size))
      |> bytearray.concat("_\",\"t\":\"rot\",\"d\":\"")
      |> bytearray.concat(said)
      |> bytearray.concat("\",\"i\":\"")
      |> bytearray.concat(q.aid)
      |> bytearray.concat("\",\"s\":\"")
      |> bytearray.concat(respell_hex(new.native_sn))
      |> bytearray.concat("\",\"p\":\"")
    let at = bytearray.length(lead)
    if at + 44 >= size {
      False
    } else {
      let prior = builtin.slice_bytearray(at, 44, raw)
      when (digest_payload(said), digest_payload(prior)) is {
        (Some(_), Some(_)) -> {
          let prefix = lead
            |> bytearray.concat(prior)
            |> bytearray.concat("\",\"kt\":")
            |> bytearray.concat(threshold_json(new.cur_threshold))
            |> bytearray.concat(",\"k\":")
            |> bytearray.concat(list_json(q.cur_keys))
            |> bytearray.concat(",\"nt\":")
            |> bytearray.concat(threshold_json(new.next_threshold))
            |> bytearray.concat(",\"n\":")
            |> bytearray.concat(list_json(list.map(new.next_keys, qb64_aid)))
            |> bytearray.concat(",\"bt\":\"")
            |> bytearray.concat(respell_hex(new.toad))
            |> bytearray.concat("\",\"br\":")
            |> bytearray.concat(
                list_json(list.map(e.wit_cut, qb64_witness_verkey)),
              )
            |> bytearray.concat(",\"ba\":")
            |> bytearray.concat(
                list_json(list.map(e.wit_add, qb64_witness_verkey)),
              )
            |> bytearray.concat(",\"a\":")
          let n = bytearray.length(prefix)
          if n >= size || builtin.slice_bytearray(0, n, raw) != prefix {
            False
          } else {
            when anchor_after(raw, n) is {
              None -> False
              Some((_, end)) ->
                end + 1 == size && builtin.index_bytearray(raw, end) == 125
            }
          }
        }
        _ -> False
      }
    }
  }
}

/// V6 — the verdict of the binding.
pub fn event_binding(
  new: KeyStateView,
  q: QualifiedSpelling,
  e: AdvanceEvidence,
) -> AdvanceEventVerdict {
  if event_binding_holds(new, q, e) {
    AdvanceEventValid
  } else {
    AdvanceEventInvalid(AEEventNotCanonical)
  }
}

// ---------------------------------------------------------
// The advance predicate
// ---------------------------------------------------------

/// Which advance validation rejected: message equalities, event binding,
/// or the receipt quorum.
pub type AdvancePredicateError {
  /// V4: `advance_equalities` rejected (eq1-eq5, W1/W2, eq6 dual-threshold
  /// — including the controller-evidence gate, amended eq7, eq8).
  AdvMessageInvalid(AdvanceError)
  /// V6: the event binding rejected.
  AdvEventBinding(AdvanceEventError)
  /// V7: the count of distinct valid incoming-set witness receipts is
  /// below `NEW.toad`.
  AdvReceiptQuorumUnsatisfied
}

/// The advance predicate verdict. `AdvancePredicateValid` ≙ `Right ()`,
/// `AdvancePredicateInvalid(e)` ≙ `Left e` (mirrors the S4 Haskell
/// `Either AdvancePredicateError ()`).
pub type AdvancePredicateVerdict {
  AdvancePredicateValid
  AdvancePredicateInvalid(AdvancePredicateError)
}

/// The pure advance predicate: V4 (message reconstruction + equalities,
/// with V5's controller-signature evidence folded in as the `signers`
/// argument), V6 (AE1-AE10 event binding), V7 (incoming-set witness
/// receipt gate), in order.
///
/// V5's controller evidence is the distinct positions of `ctrl_sigs` whose
/// signature verifies over `event_bytes` directly (#219: mirrors
/// registration's R7) against `NEW.cur_keys` at that position (bad index
/// or bad signature never counts, never aborts — the `verified_positions`
/// convention).
///
/// V7 counts distinct indices of `wit_receipts` whose signature verifies
/// over `event_bytes` against the created datum's own witness list at
/// that position. Because V4's eq7 (amended, W3) already pins that list to
/// be exactly the derived incoming set, no separate re-derivation is
/// needed here: a cut witness sits at no position of it, so its receipt
/// can never count — structurally, not by filter. When `NEW.toad == 0`,
/// the evidence must carry literally no receipt entries (the brief's
/// downgrade rule): a non-empty list is rejected outright, even one whose
/// entries could never verify, rather than silently ignored.
pub fn advance_predicate(
  spent: SpentCheckpoint,
  new: KeyStateView,
  q: QualifiedSpelling,
  e: AdvanceEvidence,
) -> AdvancePredicateVerdict {
  let revealed = RevealedSuccessorSigners(
    keys_at(
      new.cur_keys,
      verified_indices(new.cur_keys, e.event_bytes, e.ctrl_sigs),
    ),
  )
  when advance_equalities(spent, new, e.wit_cut, e.wit_add, revealed) is {
    AdvanceInvalid(err) -> AdvancePredicateInvalid(AdvMessageInvalid(err))
    AdvanceValid ->
      when event_binding(new, q, e) is {
        AdvanceEventInvalid(err) ->
          AdvancePredicateInvalid(AdvEventBinding(err))
        AdvanceEventValid ->
          if new.toad == 0 {
            if e.wit_receipts != [] {
              AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied)
            } else {
              AdvancePredicateValid
            }
          } else {
            let receipted = verified_indices(
              new.witnesses,
              e.event_bytes,
              e.wit_receipts,
            )
            if list.length(receipted) >= new.toad {
              AdvancePredicateValid
            } else {
              AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied)
            }
          }
      }
  }
}

// ---------------------------------------------------------
// Helpers
// ---------------------------------------------------------

// The distinct positions whose `(idx, sig)` verifies with `keys[idx]`
// over `msg` (mirrors the S4 Haskell `IntSet.fromList` dedup; reused for
// both V5's controller-signature gate and V7's receipt gate).
pub fn verified_indices(
  keys: List<ByteArray>,
  msg: ByteArray,
  sigs: List<(Int, ByteArray)>,
) -> List<Int> {
  list.unique(
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
    ),
  )
}

// The keys of `keys` at the given (already-distinct) `positions`,
// preserving `keys`' own ascending order (mirrors the S4 Haskell
// `zip [0..] (cdCurKeys new)` filter by IntSet membership).
fn keys_at(keys: List<ByteArray>, positions: List<Int>) -> List<ByteArray> {
  list.indexed_foldr(
    keys,
    [],
    fn(i, k, acc) {
      if list.has(positions, i) {
        [k, ..acc]
      } else {
        acc
      }
    },
  )
}
