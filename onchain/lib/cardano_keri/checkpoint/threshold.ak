//// Frozen KERI `kt`/`nt` threshold wire codec (F18), #68 Slice 5.
////
//// Mirrors the Slice-2 Haskell `Cardano.KERI.AID.Checkpoint.Threshold`
//// byte-for-byte: the `Threshold` sum (constructor 0 = `Unweighted`,
//// constructor 1 = `Weighted`) and the `Weight` record (constructor 0,
//// fields `num`/`den`) encode to the exact canonical Plutus-Data CBOR the
//// Haskell encoder emits (see `vectors.ak`). Constructor indices and field
//// order are protocol surface: they change only by minting a new version tag.
////
//// This is a validator-free schema-support layer: the frozen types, the F18
//// well-formedness predicate (rules 1-13), and a deterministic `evaluate`
//// using exact rational (cross-multiplied) arithmetic — no floats, no rounding.

use aiken/collection/list
use aiken/math
use aiken/primitive/bytearray

// ---------------------------------------------------------
// Types (constructor order frozen — confirmed against vectors.ak)
// ---------------------------------------------------------

/// An exact rational weight `num/den` in reduced canonical form
/// (`den > 0`, `num > 0`, `num <= den`, `gcd(num, den) == 1`).
/// Encodes as `Constr 0 [I num, I den]`.
pub type Weight {
  num: Int,
  den: Int,
}

/// A KERI signing threshold (`kt`/`nt`): either an integer `m`-of-`n` or a
/// fractionally weighted multi-clause threshold. Clauses partition the key
/// list positionally and are logically ANDed.
pub type Threshold {
  /// Integer `m`-of-`n` (Constr 0). All keys carry implicit weight 1.
  Unweighted(Int)
  /// Fractionally weighted; clauses partition `cur_keys` positionally (Constr 1).
  Weighted(List<List<Weight>>)
}

/// A specific F18 well-formedness rejection reason (mirrors the Slice-2
/// `ThresholdError`).
pub type ThresholdError {
  /// Rule 1: empty key set.
  EmptyKeys
  /// Rule 2: duplicate `KeyDigest`.
  DuplicateKey
  /// Rule 3: a key digest is not exactly 32 bytes.
  KeyWidth
  /// Rule 4: `Unweighted(m)` with `m < 1` or `m > n`.
  UnweightedRange
  /// Rule 5: empty clause set or an empty clause.
  EmptyClause
  /// Rule 6: clause lengths do not partition the key list.
  PartitionMismatch
  /// Rule 7: a weight has `den <= 0`.
  NonPositiveDen
  /// Rule 8: a weight has `num <= 0` (dead key).
  NonPositiveNum
  /// Rule 9: a weight has `num > den` (over unity).
  OverUnityWeight
  /// Rule 10: a weight is unreduced (`gcd(num, den) != 1`).
  UnreducedWeight
  /// Rule 11: a weight's denominator exceeds `max_weight_denom`.
  WeightOutOfBound
  /// Rule 12: a clause's weights sum to `< 1` (unsatisfiable).
  UnsatisfiableClause
}

/// The result of the F18 well-formedness check. Aiken's prelude has no
/// `Result`, so this custom sum mirrors the Slice-2 Haskell
/// `Either ThresholdError ()`: `Valid` ≙ `Right ()`, `Invalid(e)` ≙ `Left e`.
pub type Verdict {
  Valid
  Invalid(ThresholdError)
}

/// Frozen V1 upper bound on a `Weight` denominator: `2^32 = 4294967296`
/// (F18 rule 11). Changing it requires a new version tag.
pub const max_weight_denom: Int = 4294967296

// ---------------------------------------------------------
// F18 well-formedness (rules 1-13)
// ---------------------------------------------------------

/// The F18 well-formedness predicate over a positional `(keys, threshold)`
/// pair. Total and deterministic; each rejection maps to a specific
/// `ThresholdError`. Rule 13 (no nested weighted list) is enforced
/// structurally by the typed `Weight` and at the decode boundary (a nested
/// weighted-list `Data` shape fails the soft-cast to `Threshold`).
pub fn well_formed(keys: List<ByteArray>, threshold: Threshold) -> Verdict {
  if list.is_empty(keys) {
    // Rule 1.
    Invalid(EmptyKeys)
  } else if !list.all(keys, fn(k) { bytearray.length(k) == 32 }) {
    // Rule 3.
    Invalid(KeyWidth)
  } else if list.length(list.unique(keys)) != list.length(keys) {
    // Rule 2.
    Invalid(DuplicateKey)
  } else {
    when threshold is {
      Unweighted(m) ->
        // Rule 4: 1 <= m <= n.
        if 1 <= m && m <= list.length(keys) {
          Valid
        } else {
          Invalid(UnweightedRange)
        }
      Weighted(clauses) -> well_formed_weighted(keys, clauses)
    }
  }
}

fn well_formed_weighted(
  keys: List<ByteArray>,
  clauses: List<List<Weight>>,
) -> Verdict {
  if list.is_empty(clauses) || list.any(clauses, list.is_empty) {
    // Rule 5.
    Invalid(EmptyClause)
  } else if sum_lengths(clauses) != list.length(keys) {
    // Rule 6.
    Invalid(PartitionMismatch)
  } else {
    // Rules 7-11 (each weight), then rule 12 (each clause sum).
    when check_weights(list.flat_map(clauses, fn(c) { c })) is {
      Invalid(e) -> Invalid(e)
      Valid -> check_clause_sums(clauses)
    }
  }
}

fn sum_lengths(clauses: List<List<Weight>>) -> Int {
  list.foldl(clauses, 0, fn(c, acc) { acc + list.length(c) })
}

fn check_weights(ws: List<Weight>) -> Verdict {
  when ws is {
    [] -> Valid
    [w, ..rest] ->
      when check_weight(w) is {
        Invalid(e) -> Invalid(e)
        Valid -> check_weights(rest)
      }
  }
}

fn check_weight(w: Weight) -> Verdict {
  let Weight { num, den } = w
  if den <= 0 {
    Invalid(NonPositiveDen)
  } else if num <= 0 {
    Invalid(NonPositiveNum)
  } else if num > den {
    Invalid(OverUnityWeight)
  } else if math.gcd(num, den) != 1 {
    Invalid(UnreducedWeight)
  } else if den > max_weight_denom {
    Invalid(WeightOutOfBound)
  } else {
    Valid
  }
}

fn check_clause_sums(clauses: List<List<Weight>>) -> Verdict {
  when clauses is {
    [] -> Valid
    [c, ..rest] ->
      if clause_sum_ge_one(c) {
        check_clause_sums(rest)
      } else {
        Invalid(UnsatisfiableClause)
      }
  }
}

// sum(all weights in clause) >= 1, exact rational via cross-multiplication.
fn clause_sum_ge_one(ws: List<Weight>) -> Bool {
  let (num_acc, den_acc) = sum_all(ws, 0, 1)
  num_acc >= den_acc
}

fn sum_all(ws: List<Weight>, num_acc: Int, den_acc: Int) -> (Int, Int) {
  when ws is {
    [] -> (num_acc, den_acc)
    [Weight { num, den }, ..rest] ->
      sum_all(rest, num_acc * den + num * den_acc, den_acc * den)
  }
}

// ---------------------------------------------------------
// Evaluation
// ---------------------------------------------------------

/// Evaluate a threshold against `n` (the key count) and the positions whose
/// signature verified. `Unweighted(m)` is satisfied when at least `m` distinct
/// in-range positions signed; `Weighted` is the AND over clauses, each clause
/// satisfied when the exact rational sum of its signed weights is `>= 1`.
/// Deterministic and order-independent within a clause.
pub fn evaluate(threshold: Threshold, n: Int, signers: List<Int>) -> Bool {
  let valid = list.filter(list.unique(signers), fn(p) { p >= 0 && p < n })
  when threshold is {
    Unweighted(m) -> list.length(valid) >= m
    Weighted(clauses) -> all_clauses_satisfied(clauses, 0, valid)
  }
}

fn all_clauses_satisfied(
  clauses: List<List<Weight>>,
  off: Int,
  signers: List<Int>,
) -> Bool {
  when clauses is {
    [] -> True
    [c, ..rest] ->
      clause_satisfied(c, off, signers) && all_clauses_satisfied(
        rest,
        off + list.length(c),
        signers,
      )
  }
}

fn clause_satisfied(ws: List<Weight>, pos: Int, signers: List<Int>) -> Bool {
  let (num_acc, den_acc) = sum_signed(ws, pos, signers, 0, 1)
  num_acc >= den_acc
}

fn sum_signed(
  ws: List<Weight>,
  pos: Int,
  signers: List<Int>,
  num_acc: Int,
  den_acc: Int,
) -> (Int, Int) {
  when ws is {
    [] -> (num_acc, den_acc)
    [Weight { num, den }, ..rest] -> {
      let (na, da) =
        if list.has(signers, pos) {
          (num_acc * den + num * den_acc, den_acc * den)
        } else {
          (num_acc, den_acc)
        }
      sum_signed(rest, pos + 1, signers, na, da)
    }
  }
}
