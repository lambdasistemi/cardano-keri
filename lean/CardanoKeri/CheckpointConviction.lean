import CardanoKeri.Duplicity

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


/-- The decoded input of a conviction. The current writer's content is bound
to its event opening. Only one previous establishment is carried forward. -/
structure Tip where
  aid : Nat
  epoch : Nat
  sn : Nat
  keys : KeyMaterial
  previous : Option Duplicity.Predecessor
  writer : Duplicity.Content
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- One decoded event with its own event-bound signature and receipt reads. -/
abbrev Rival := Duplicity.SignedEvent

/-- At a rotated checkpoint the mint judges one rival using the previous
commitments and the rival's own rules. Difference is over the complete event. -/
def accepts (tip : Tip) (rival : Rival) : Bool :=
  match tip.previous with
  | none => false
  | some previous =>
    tip.epoch != 0 && tip.aid == rival.event.aid && tip.sn == rival.event.sn &&
      Duplicity.rotationValid previous rival && decide (tip.writer ≠ rival.event)

/-- Given one decoded spend, it accepts exactly a conflicting, valid rotation
at this identifier and sequence with a carried predecessor. -/
theorem accepts_iff (tip : Tip) (rival : Rival) :
    accepts tip rival = true ↔ ∃ previous, tip.previous = some previous ∧
      tip.epoch ≠ 0 ∧ tip.aid = rival.event.aid ∧ tip.sn = rival.event.sn ∧
      Duplicity.rotationValid previous rival = true ∧ tip.writer ≠ rival.event := by
  cases h : tip.previous <;> simp [accepts, h, and_assoc]

structure Comparison where
  tip : Tip
  rival : Rival
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

def Comparison.acceptsAt (comparison : Comparison) (epoch sn : Nat) : Bool :=
  comparison.tip.epoch == epoch && comparison.tip.sn == sn && accepts comparison.tip comparison.rival

end CardanoKeri.CheckpointConviction
