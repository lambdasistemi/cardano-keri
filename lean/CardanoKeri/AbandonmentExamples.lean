import CardanoKeri.CheckpointEventHistory

namespace CardanoKeri.Checkpoint
open Duplicity

/-- Given a writer without next commitments, when any successor rotation is
checked against it, then the signing rule refuses the rotation. -/
theorem empty_commitments_refuse_rotation (p : Predecessor) (s : SignedEvent)
    (empty : p.nextKeys = []) : rotationValid p s = false := by
  simp [rotationValid, signingValid, empty]

namespace AbandonmentExamples

private def inception (next : List Nat) : Content :=
  ⟨11, 0, .inception, 0, [11], .count 1, next, .count next.length, [], [], 0, [], "inception"⟩

private def signed (e : Content) : SignedEvent := ⟨e, true, [⟨e.keys.head!, e, true⟩], []⟩

private def origin : EventHistory := .inception (signed (inception [22])) []

private def abandonment : Content :=
  { inception [] with sn := 1, kind := .rotation, keys := [22], priorDigest := 1, eventDigest := "stop" }

private def abandoned : EventHistory := .rotation origin (signed abandonment)

private def tip (history : EventHistory) := history.datum.tip KeyEncoding.symbolic history.epoch

private def sibling := signed
  { abandonment with nextKeys := [33], nextThreshold := .count 1, eventDigest := "sibling" }

#guard inceptionWrites 11 (signed (inception [])) []
#guard inceptionWrites 11 (signed (inception [22])) []
#guard !inceptionWrites 12 (signed (inception [])) []
#guard abandoned.authenticated 11
#guard !rotationValid abandoned.predecessor (signed {abandonment with sn := 2, eventDigest := "later"})

-- Both siblings answer to the commitments in the inception. Presenting the
-- abandoning writer itself supplies no conflicting event.
#guard CheckpointConviction.accepts (tip abandoned) sibling
#guard !CheckpointConviction.accepts (tip abandoned) (signed abandonment)
#guard !CheckpointConviction.accepts (tip origin) sibling

end AbandonmentExamples
end CardanoKeri.Checkpoint
