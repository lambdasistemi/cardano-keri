import Lean

namespace CardanoKeri.CheckpointDatum

/-- A threshold weight `num/den`. -/
abbrev Weight := Int × Int

/-- A KERI signing threshold, as `threshold.ak`'s `Threshold`. -/
inductive Threshold where
  | unweighted (m : Int)
  | weighted (clauses : List (List Weight))
  deriving Repr, DecidableEq, Inhabited, Lean.ToJson, Lean.FromJson

/-- The key material carried by the live checkpoint datum. -/
structure KeyMaterial where
  curKeys : List (List Nat)
  curThreshold : Threshold
  nextKeys : List (List Nat)
  nextThreshold : Threshold
  witnesses : List (List Nat)
  toad : Int
  deriving Repr, DecidableEq, Inhabited, Lean.ToJson, Lean.FromJson

end CardanoKeri.CheckpointDatum

namespace CardanoKeri.CheckpointConviction

open CardanoKeri.CheckpointDatum

/-- The enforcement observer reads these fields from the spent active input.
The epoch and native sequence together identify the checkpoint's key state. -/
structure Tip where
  aid : Nat
  epoch : Nat
  sn : Nat
  keys : KeyMaterial
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- A rival decoded by the enforcement observer. The byte parser and its field
bindings are a technical premise. The convictor supplies exactly these event
bytes and the indexed signatures and receipts over them. -/
structure Rival where
  bytes : List Nat
  rotation : Bool
  aid : Nat
  sn : Nat
  revealedKeys : List (List Nat)
  threshold : Threshold
  nextKeys : List (List Nat)
  nextThreshold : Threshold
  toad : Int
  signatures : List (Nat × List Nat)
  receipts : List (Nat × List Nat)
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The checkpoint enforcement observer verifies each indexed signature under
the key at that position over the bytes of the one decoded rival. -/
abbrev Verify := List Nat → List Nat → List Nat → Bool

def verifiedPositions (verify : Verify) (keys : List (List Nat)) (bytes : List Nat)
    (signatures : List (Nat × List Nat)) : List Nat :=
  (signatures.filterMap fun (i, signature) => do
    let key ← keys[i]?
    if verify key bytes signature then some i else none).eraseDups

private def clauseSatisfied (positions : List Nat) (offset : Nat) (clause : List Weight) : Bool :=
  let (num, den) := clause.zipIdx.foldl (fun (n, d) (weight, i) =>
    if positions.contains (offset + i) then (n * weight.2 + weight.1 * d, d * weight.2)
    else (n, d)) ((0, 1) : Int × Int)
  decide (den ≤ num)

private def clausesSatisfied (positions : List Nat) (offset : Nat) : List (List Weight) → Bool
  | [] => true
  | clause :: tail => clauseSatisfied positions offset clause &&
    clausesSatisfied positions (offset + clause.length) tail

def thresholdMet (threshold : Threshold) (positions : List Nat) : Bool :=
  match threshold with
  | .unweighted required => decide (required ≤ (positions.length : Int))
  | .weighted clauses => clausesSatisfied positions 0 clauses

/-- The spent tip supplies the first record and the keys for both checks.
The four forward fields are the current signing threshold, next keys, next
threshold and witness threshold. An independent history reader can evaluate
the two-event KERI definition in `Duplicity`. -/
def accepts (verify : Verify) (tip : Tip) (rival : Rival) : Bool :=
  rival.rotation && tip.aid == rival.aid && tip.sn == rival.sn &&
  decide (tip.keys.curKeys = rival.revealedKeys) &&
  thresholdMet tip.keys.curThreshold
    (verifiedPositions verify tip.keys.curKeys rival.bytes rival.signatures) &&
  decide (tip.keys.toad ≤ ((verifiedPositions verify tip.keys.witnesses rival.bytes rival.receipts).length : Int)) &&
  decide ((tip.keys.curThreshold, tip.keys.nextKeys, tip.keys.nextThreshold, tip.keys.toad) ≠
    (rival.threshold, rival.nextKeys, rival.nextThreshold, rival.toad))

/-- Given a spent tip and a rival, when the enforcement comparison succeeds,
then the rival is a rotation for the same identifier and native sequence,
reveals exactly the spent keys, meets both thresholds under the spent tip,
and disagrees with at least one of its four forward fields. -/
theorem accepted_rival (verify : Verify) (tip : Tip) (rival : Rival)
    (accepted : accepts verify tip rival = true) :
    rival.rotation = true ∧ tip.aid = rival.aid ∧ tip.sn = rival.sn ∧
    tip.keys.curKeys = rival.revealedKeys ∧
    thresholdMet tip.keys.curThreshold
      (verifiedPositions verify tip.keys.curKeys rival.bytes rival.signatures) = true ∧
    tip.keys.toad ≤ ((verifiedPositions verify tip.keys.witnesses rival.bytes rival.receipts).length : Int) ∧
    (tip.keys.curThreshold, tip.keys.nextKeys, tip.keys.nextThreshold, tip.keys.toad) ≠
      (rival.threshold, rival.nextKeys, rival.nextThreshold, rival.toad) := by
  simpa only [accepts, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, and_assoc] using accepted

end CardanoKeri.CheckpointConviction
