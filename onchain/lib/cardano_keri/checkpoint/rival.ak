//// The conviction predicate of the checkpoint spend: a rival rotation is
//// judged against the commitments of the event before the one that wrote the
//// checkpoint, under the rival's own thresholds and derived witnesses (Lean
//// `Duplicity.rotationValid`, `CheckpointConviction.accepts`).

use aiken/collection/list
use cardano_keri/checkpoint/message.{next_key_digest}
use cardano_keri/checkpoint/threshold.{
  Threshold, Unweighted, Weight, Weighted, evaluate,
}

/// What the previous establishment committed to (Lean `Predecessor`). The
/// profile is non-delegated, so the delegated flag is not carried.
pub type Previous {
  aid: ByteArray,
  sn: Int,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  witnesses: List<ByteArray>,
}

/// A rival rotation as decoded, with the signatures and receipts that
/// verified over its own signed bytes (Lean `SignedEvent` after the primitive
/// verifications). `event_digest` is the event's own digest.
pub type Rotation {
  aid: ByteArray,
  sn: Int,
  is_rotation: Bool,
  structure_ok: Bool,
  keys: List<ByteArray>,
  /// How many next-key commitments the rotation declares (its `n`).
  next_key_count: Int,
  threshold: Threshold,
  next_threshold: Threshold,
  cuts: List<ByteArray>,
  adds: List<ByteArray>,
  toad: Int,
  signers: List<ByteArray>,
  receipts: List<ByteArray>,
  event_digest: ByteArray,
}

/// The spent checkpoint's side of a conviction (Lean `Tip`, without the key
/// material whose agreement with the datum is a separate check).
pub type Tip {
  aid: ByteArray,
  epoch: Int,
  sn: Int,
  previous: Option<Previous>,
  writer_digest: ByteArray,
}

// ---------------------------------------------------------
// Thresholds
// ---------------------------------------------------------

/// Every individual weight at most one (the keripy ceiling, Lean
/// `Threshold.weightsAtMostOne`). A count has no weights.
fn weights_at_most_one(threshold: Threshold) -> Bool {
  when threshold is {
    Unweighted(_) -> True
    Weighted(clauses) ->
      list.all(
        clauses,
        fn(clause) { list.all(clause, fn(w) { w.num <= w.den }) },
      )
  }
}

/// Every denominator of a declared rule positive (Lean
/// `Threshold.positiveDenominators`).
fn positive_denominators(threshold: Threshold) -> Bool {
  when threshold is {
    Unweighted(_) -> True
    Weighted(clauses) ->
      list.all(clauses, fn(clause) { list.all(clause, fn(w) { w.den > 0 }) })
  }
}

/// Lean `Threshold.satisfied`: a count of at least one is met by that many
/// signers (a count of zero is never satisfied, #596); a weighted
/// rule needs a nonempty list of nonempty clauses with positive denominators
/// that partition the keys, each clause summing to at least one.
pub fn satisfied(
  threshold: Threshold,
  key_count: Int,
  signed: List<Int>,
) -> Bool {
  when threshold is {
    Unweighted(m) ->
      m >= 1 && m <= key_count && evaluate(threshold, key_count, signed)
    Weighted(clauses) ->
      !list.is_empty(clauses) && list.all(
        clauses,
        fn(clause) {
          !list.is_empty(clause) && list.all(clause, fn(w) { w.den > 0 })
        },
      ) && list.foldl(
        clauses,
        0,
        fn(clause, width) { width + list.length(clause) },
      ) == key_count && evaluate(threshold, key_count, signed)
  }
}

/// Whether the weights of one clause total at least one, exactly (Lean
/// `sumAtLeastOne` over `Fraction.add` from zero).
fn clause_total_at_least_one(clause: List<Weight>) -> Bool {
  let (num, den) = list.foldl(
    clause,
    (0, 1),
    fn(w, total) {
      let (n, d) = total
      (n * w.den + w.num * d, d * w.den)
    },
  )
  den > 0 && num >= den
}

/// A declared next rule fits the next keys it declares (Lean
/// `Threshold.fitsNextKeys`, #595): its width is at most the key count and a
/// weighted rule is a nonempty list of clauses each totalling at least one. A
/// count of zero over no keys (abandonment) fits.
fn fits_next_keys(threshold: Threshold, key_count: Int) -> Bool {
  when threshold is {
    Unweighted(m) -> m >= 0 && m <= key_count
    Weighted(clauses) ->
      list.foldl(clauses, 0, fn(clause, width) { width + list.length(clause) }) <= key_count && !list.is_empty(
        clauses,
      ) && list.all(clauses, clause_total_at_least_one)
  }
}

// ---------------------------------------------------------
// The rival's own rules
// ---------------------------------------------------------

fn distinct(xs: List<ByteArray>) -> Bool {
  list.length(list.unique(xs)) == list.length(xs)
}

/// The positions of `keys` that satisfy `signed`.
fn positions_where(
  keys: List<ByteArray>,
  signed: fn(ByteArray) -> Bool,
) -> List<Int> {
  list.indexed_foldr(
    keys,
    [],
    fn(i, key, positions) {
      if signed(key) {
        [i, ..positions]
      } else {
        positions
      }
    },
  )
}

/// The witnesses the rival establishes: the previous ones without its cuts,
/// then its additions not already present, in order (Lean `derivedWitnesses`).
pub fn derived_witnesses(previous: Previous, rival: Rotation) -> List<ByteArray> {
  let kept = list.filter(previous.witnesses, fn(w) { !list.has(rival.cuts, w) })
  list.foldl(
    rival.adds,
    kept,
    fn(add, witnesses) {
      if list.has(witnesses, add) {
        witnesses
      } else {
        list.concat(witnesses, [add])
      }
    },
  )
}

/// The previous next threshold is met by the rival's signed keys it committed
/// to, and the rival's own threshold by its own keys (Lean `signingValid`).
fn signing_valid(previous: Previous, rival: Rotation) -> Bool {
  and {
    !list.is_empty(previous.next_keys),
    distinct(previous.next_keys),
    distinct(rival.keys),
    !list.is_empty(rival.keys),
    satisfied(
      rival.threshold,
      list.length(rival.keys),
      positions_where(rival.keys, fn(key) { list.has(rival.signers, key) }),
    ),
    {
      let committed = list.map(
        list.filter(rival.keys, fn(key) { list.has(rival.signers, key) }),
        next_key_digest,
      )
      satisfied(
        previous.next_threshold,
        list.length(previous.next_keys),
        positions_where(
          previous.next_keys,
          fn(commitment) { list.has(committed, commitment) },
        ),
      )
    },
  }
}

/// The rival's receipts come from the witnesses it derives, and reach its own
/// receipt threshold (Lean `receiptsValid`).
fn receipts_valid(previous: Previous, rival: Rotation) -> Bool {
  let witnesses = derived_witnesses(previous, rival)
  let receipted = list.filter(witnesses, fn(w) { list.has(rival.receipts, w) })
  and {
    distinct(previous.witnesses),
    distinct(rival.cuts),
    distinct(rival.adds),
    // witness changes (#598): a cut is a member of the previous set, an addition
    // is not, and a nonempty resulting set needs a positive receipt threshold
    list.all(rival.cuts, fn(w) { list.has(previous.witnesses, w) }),
    list.all(rival.adds, fn(w) { !list.has(previous.witnesses, w) }),
    list.is_empty(witnesses) || rival.toad > 0,
    rival.toad >= 0,
    rival.toad <= list.length(witnesses),
    rival.toad <= list.length(receipted),
  }
}

/// A rival is a valid rotation against the previous commitments (Lean
/// `Duplicity.rotationValid`): a structurally verified rotation of the same
/// identifier at a later sequence, admitted as keripy admits it, signed and
/// receipted under its own rules.
pub fn rotation_valid(previous: Previous, rival: Rotation) -> Bool {
  and {
    rival.is_rotation,
    rival.structure_ok,
    fits_next_keys(rival.next_threshold, rival.next_key_count),
    weights_at_most_one(previous.next_threshold),
    weights_at_most_one(rival.threshold),
    weights_at_most_one(rival.next_threshold),
    positive_denominators(rival.next_threshold),
    rival.aid == previous.aid,
    previous.sn < rival.sn,
    receipts_valid(previous, rival),
    signing_valid(previous, rival),
  }
}

/// The conviction predicate of the checkpoint spend (Lean
/// `CheckpointConviction.accepts`): the checkpoint has rotated and carries its
/// previous commitments, the rival is for the same identifier and position,
/// is a valid rotation against those commitments, and has an event digest
/// other than the writer's.
pub fn conviction_accepts(tip: Tip, rival: Rotation) -> Bool {
  when tip.previous is {
    None -> False
    Some(previous) -> and {
        tip.epoch != 0,
        tip.aid == rival.aid,
        tip.sn == rival.sn,
        tip.writer_digest != rival.event_digest,
        rotation_valid(previous, rival),
      }
  }
}
