import CardanoKeri.CheckpointEventHistory
import CardanoKeri.DuplicityExamples

/-! Public decoded inputs for checking the conviction predicate against an
independent rotation implementation. Cryptographic and byte-structure reads
are premises. No external implementation is invoked here. -/
open CardanoKeri Duplicity

namespace RivalValidityVectors

private def context := baseContext

/-- The actual inception for the previously committed two-key set. -/
private def inception : Checkpoint.EventHistory :=
  let event : Content := { context.accepted.event with sn := 0, kind := .inception, nextKeys := [1, 2], nextThreshold := .count 1 }
  .inception (signed event [1] [10]) [10]

private def history : Checkpoint.EventHistory := .rotation inception context.accepted

private def tip : CheckpointConviction.Tip :=
  ⟨1, 1, 1, ⟨[[1]], .count 1, [[4]], .count 1, [[10]], 1⟩,
    history.datum.previous, history.datum.writer⟩

#guard history.authenticated 1
#guard Checkpoint.KeyReads.symbolic.matches 1 history tip
#guard tip.previous == some context.prior

structure Row where
  name : String
  input : CheckpointConviction.Comparison
  expectedRotationValid : Option Bool
  expectedConvictionAccepted : Bool
  deriving Lean.ToJson

private def row (name : String) (rival : SignedEvent) (rotation conviction : Bool) : Row :=
  ⟨name, ⟨tip, rival⟩, some rotation, conviction⟩

def rows : List Row :=
  let writer := context.accepted.event
  let variant := { writer with extension := [99] }
  let alternate := { variant with keys := [2] }
  let augmented := { variant with keys := [1, 3], threshold := .count 2 }
  let changed := { variant with cuts := [10], adds := [11] }
  let weighted := { augmented with threshold := .weighted [[.key ⟨1,2⟩, .key ⟨1,2⟩]] }
  [row "partial-other-committed-key" (signed alternate [2] [10]) true true,
   row "augmented-key-list" (signed augmented [1,3] [10]) true true,
   row "rival-witness-change" (signed changed [1] [11]) true true,
   row "prior-witness-only" (signed changed [1] [10]) false false,
   row "missing-rival-receipts" (signed changed [1] []) false false,
   row "below-rival-signing-threshold" (signed augmented [1] [10]) false false,
   row "tip-keys-insufficient-own-threshold" exactKeyRival false false,
   row "prior-next-threshold-not-met" (signed { variant with keys := [3] } [3] [10]) false false,
   row "weighted-sufficient" (signed weighted [1,3] [10]) true true,
   row "weighted-insufficient" (signed weighted [1] [10]) false false,
   row "only-seal-differs" (signed variant [1] [10]) true true,
   row "identical-event" context.accepted true false,
   row "wrong-identifier" (signed {variant with aid := 2} [1] [10]) false false,
   row "wrong-position" (signed {variant with sn := 2} [1] [10]) true false,
   row "not-a-rotation" (signed {variant with kind := .interaction} [1] [10]) false false,
   ⟨"never-rotated", ⟨{tip with previous := none, epoch := 0, sn := 0, writer := inception.writer.event}, signed variant [1] [10]⟩, none, false⟩]

def rotationValid (r : Row) : Option Bool :=
  r.input.tip.previous.map fun prior => Duplicity.rotationValid prior r.input.rival

def convictionAccepted (r : Row) : Bool := r.input.acceptsAt r.input.tip.epoch r.input.tip.sn

#guard rows.length == 16
#guard rows.all fun r => rotationValid r == r.expectedRotationValid
#guard rows.all fun r => convictionAccepted r == r.expectedConvictionAccepted

end RivalValidityVectors

def main : IO Unit :=
  open RivalValidityVectors in
  IO.println (Lean.Json.arr (rows.toArray.map fun r =>
    ((Lean.toJson r).setObjVal! "rotationValid" (Lean.toJson (RivalValidityVectors.rotationValid r))).setObjVal!
      "convictionAccepted" (Lean.toJson (convictionAccepted r)))).compress
