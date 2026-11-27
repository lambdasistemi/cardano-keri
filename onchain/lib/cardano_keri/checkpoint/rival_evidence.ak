//// The signed-byte side of the conviction predicate: a rival rotation opened
//// from its exact signed bytes (Lean `Duplicity.SignedEvent` after the
//// primitive verifications), and the event's own SAID opened from the same
//// bytes (#582 `Content.eventDigest`).
////
//// The prover claims what the bytes say. No position is supplied: the claimed
//// values are written out in keripy's canonical rotation order (the version
//// string with the size of the bytes, then `d`, `i`, `s`, `p`, `kt`, `k`, `nt`,
//// `n`, `bt`, `br`, `ba`, then the list of anchors `a`) and the signed bytes
//// must be exactly that text followed by the anchors. So every value the
//// opener consumes, each whole list included, sits in its named top-level field
//// of the signed event, and nothing can be smuggled between the fields.
//// What it does not establish: that the anchors, which the model keeps opaque,
//// are well-formed JSON seals; the structure check requires only that they
//// are a list that closes the event.
////
//// The controller signatures and the witness receipts are verified over the
//// exact bytes, the receipts against the witnesses the rival derives from the
//// previous establishment and its own cuts and additions.
////
//// The event's own digest is the BLAKE3 of the canonical bytes with the 44
//// characters of its `d` value replaced by `#` (keripy's SAID derivation),
//// accepted only when the `d` value the bytes carry is that digest: a declared
//// digest that is not the digest of the bytes is refused.
////
//// The thresholds are written in the canonical respelling (`respell_threshold`):
//// an event that spells a fraction otherwise (`1/1`, `2/4`) is not matched here.
//// That is the grouped and spelled wire domain of the January codec (#576),
//// not claimed by this module.
////
//// The rival's own prior digest (`p`) is a value of the claim and is not
//// compared with any on-chain value, by decision; that is an open limit, not a
//// property.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/blake3
use cardano_keri/checkpoint/advance.{verified_indices}
use cardano_keri/checkpoint/message.{aid_digest, qb64_aid, qb64_verkey}
use cardano_keri/checkpoint/registration.{
  qb64_witness_verkey, respell_hex, respell_threshold, slice_matches,
}
use cardano_keri/checkpoint/rival.{Previous, Rotation, derived_witnesses}
use cardano_keri/checkpoint/threshold.{Threshold, Unweighted}

/// What the prover claims the rival's bytes say. Each value is written into the
/// canonical text the bytes must equal.
pub type RivalClaim {
  aid: ByteArray,
  sn: Int,
  /// The 44 characters of `p`.
  prior: ByteArray,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  toad: Int,
  cuts: List<ByteArray>,
  adds: List<ByteArray>,
}

/// keripy's SAID dressing for one 44-character qualified value.
const dummy_span: ByteArray = "############################################"

const hash_limit: Int = 1024

fn zeros(n: Int) -> ByteArray {
  if n <= 0 {
    ""
  } else {
    bytearray.push(zeros(n - 1), 48)
  }
}

/// The version string size: the length of the whole event in six hexadecimal
/// digits.
fn size_text(size: Int) -> ByteArray {
  let digits = respell_hex(size)
  bytearray.concat(zeros(6 - bytearray.length(digits)), digits)
}

/// Everything before the `d` value.
fn head(size: Int) -> ByteArray {
  bytearray.concat(
    bytearray.concat("{\"v\":\"KERI10JSON", size_text(size)),
    "_\",\"t\":\"rot\",\"d\":\"",
  )
}

/// A threshold as keripy writes the value: a string for a count, a list of
/// fraction strings for weights.
fn threshold_text(threshold: Threshold) -> ByteArray {
  when threshold is {
    Unweighted(_) ->
      bytearray.concat(
        bytearray.concat("\"", respell_threshold(threshold)),
        "\"",
      )
    _ -> respell_threshold(threshold)
  }
}

fn quoted(texts: List<ByteArray>) -> ByteArray {
  when texts is {
    [] -> ""
    [last] -> bytearray.concat(bytearray.concat("\"", last), "\"")
    [first, ..rest] ->
      bytearray.concat(
        bytearray.concat(bytearray.concat("\"", first), "\","),
        quoted(rest),
      )
  }
}

/// The JSON text keripy writes for a list of qualified values.
fn list_text(texts: List<ByteArray>) -> ByteArray {
  bytearray.concat(bytearray.concat("[", quoted(texts)), "]")
}

fn join(parts: List<ByteArray>) -> ByteArray {
  list.foldr(parts, "", fn(part, rest) { bytearray.concat(part, rest) })
}

/// The canonical rotation up to and including the label of the anchors, with
/// `d_text` as the `d` value.
fn through_anchor_label(
  claim: RivalClaim,
  d_text: ByteArray,
  size: Int,
) -> ByteArray {
  join(
    [
      head(size),
      d_text,
      "\",\"i\":\"",
      qb64_aid(claim.aid),
      "\",\"s\":\"",
      respell_hex(claim.sn),
      "\",\"p\":\"",
      claim.prior,
      "\",\"kt\":",
      threshold_text(claim.cur_threshold),
      ",\"k\":",
      list_text(list.map(claim.cur_keys, qb64_verkey)),
      ",\"nt\":",
      threshold_text(claim.next_threshold),
      ",\"n\":",
      list_text(list.map(claim.next_keys, qb64_aid)),
      ",\"bt\":\"",
      respell_hex(claim.toad),
      "\",\"br\":",
      list_text(list.map(claim.cuts, qb64_witness_verkey)),
      ",\"ba\":",
      list_text(list.map(claim.adds, qb64_witness_verkey)),
      ",\"a\":",
    ],
  )
}

fn thirty_two(xs: List<ByteArray>) -> Bool {
  list.all(xs, fn(x) { bytearray.length(x) == 32 })
}

/// The claim can be written as canonical text: raw values of the right width,
/// natural numbers, a qualified digest for `p`.
fn well_formed(claim: RivalClaim) -> Bool {
  and {
    bytearray.length(claim.aid) == 32,
    claim.sn >= 0,
    claim.toad >= 0,
    aid_digest(claim.prior) != None,
    thirty_two(claim.cur_keys),
    thirty_two(claim.next_keys),
    thirty_two(claim.cuts),
    thirty_two(claim.adds),
  }
}

/// The bytes are the canonical rotation of the claim, whatever the `d` value
/// and the anchors: the claimed values in their top-level fields, in order, and
/// a list of anchors that closes the event.
pub fn canonical_structure(claim: RivalClaim, event_bytes: ByteArray) -> Bool {
  let size = bytearray.length(event_bytes)
  if size > hash_limit || !well_formed(claim) {
    False
  } else {
    let d_off = bytearray.length(head(size))
    let expected = through_anchor_label(claim, dummy_span, size)
    let prefix = bytearray.length(expected)
    and {
      size >= prefix + 3,
      bytearray.take(dress(event_bytes, d_off), prefix) == expected,
      bytearray.at(event_bytes, prefix) == 91,
      bytearray.drop(event_bytes, size - 2) == "]}",
    }
  }
}

fn dress(event_bytes: ByteArray, d_off: Int) -> ByteArray {
  bytearray.take(event_bytes, d_off)
    |> bytearray.concat(dummy_span)
    |> bytearray.concat(bytearray.drop(event_bytes, d_off + 44))
}

/// The event's own digest, opened from its bytes: the BLAKE3 of the canonical
/// bytes with the `d` value dressed, accepted only when it is the `d` value the
/// bytes carry.
pub fn open_digest(
  claim: RivalClaim,
  event_bytes: ByteArray,
) -> Option<ByteArray> {
  if canonical_structure(claim, event_bytes) {
    let d_off = bytearray.length(head(bytearray.length(event_bytes)))
    let digest = blake3.hash(dress(event_bytes, d_off))
    if slice_matches(event_bytes, d_off, qb64_aid(digest)) {
      Some(digest)
    } else {
      None
    }
  } else {
    None
  }
}

/// The items of `items` at the given positions, in position order.
fn at_positions(items: List<ByteArray>, positions: List<Int>) -> List<ByteArray> {
  list.filter_map(positions, fn(position) { list.at(items, position) })
}

/// A rival opened from its exact signed bytes against the previous
/// establishment it follows: the claim bound to the canonical fields, the own
/// digest opened from the bytes, the controller signatures verified over them,
/// and the witness receipts verified over them against the derived witnesses.
/// None when any binding fails.
pub fn open_rival(
  previous: Previous,
  claim: RivalClaim,
  event_bytes: ByteArray,
  ctrl_sigs: List<(Int, ByteArray)>,
  wit_receipts: List<(Int, ByteArray)>,
) -> Option<Rotation> {
  when open_digest(claim, event_bytes) is {
    None -> None
    Some(digest) -> {
      let skeleton = Rotation {
        aid: claim.aid,
        sn: claim.sn,
        is_rotation: True,
        structure_ok: True,
        keys: claim.cur_keys,
        next_key_count: list.length(claim.next_keys),
        threshold: claim.cur_threshold,
        next_threshold: claim.next_threshold,
        cuts: claim.cuts,
        adds: claim.adds,
        toad: claim.toad,
        signers: [],
        receipts: [],
        event_digest: digest,
      }
      let witnesses = derived_witnesses(previous, skeleton)
      Some(
        Rotation {
          ..skeleton,
          signers: at_positions(
            claim.cur_keys,
            verified_indices(claim.cur_keys, event_bytes, ctrl_sigs),
          ),
          receipts: at_positions(
            witnesses,
            verified_indices(witnesses, event_bytes, wit_receipts),
          ),
        },
      )
    }
  }
}
