import CardanoKeri.Duplicity
import CardanoKeri.CheckpointConviction

namespace CardanoKeri.Checkpoint
open Duplicity

/-- The authenticated establishment events of one checkpoint in ledger order.
An inception records the witness list decoded from the event. Every rotation
extends the already stored history. Signature, digest opening and event
decoding results have the technical interpretation declared in Duplicity. -/
inductive EventHistory where
  | inception (event : SignedEvent) (witnesses : List Nat)
  | rotation (previous : EventHistory) (event : SignedEvent)
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

def EventHistory.writer : EventHistory → SignedEvent
  | .inception event _ | .rotation _ event => event

def EventHistory.epoch : EventHistory → Nat
  | .inception .. => 0
  | .rotation previous _ => previous.epoch + 1

/-- The next rotation reads the commitments and witnesses established by the
actual previous event. The advance observer reads these from the spent datum
(observer.ak 121–158 and 214–231). Its successor witnesses are derived from
the previous set and the signed cuts and additions (message.ak 199–236). -/
def EventHistory.predecessor : EventHistory → Predecessor
  | .inception signed witnesses =>
    ⟨signed.event.aid, signed.event.sn, false, signed.event.nextKeys,
      signed.event.nextThreshold, witnesses⟩
  | .rotation previous signed =>
    ⟨signed.event.aid, signed.event.sn, false, signed.event.nextKeys,
      signed.event.nextThreshold, derivedWitnesses previous.predecessor signed.event⟩

/-- At registration the controller supplies the inception. The observer binds
its fields to the initial datum, verifies its controller signatures and checks
its receipts (checkpoint/observer.ak 65–111, registration.ak 310–352 and
363–410). This check is on decoded evidence under the signature and structure
interpretation, for an inception of the selected identifier. -/
def inceptionWrites (aid : Nat) (event : SignedEvent) (witnesses : List Nat) : Bool :=
  let e := event.event
  let receipts := verifiedSigners e event.receipts
  e.aid == aid && e.sn == 0 && e.kind == .inception && event.structureVerified &&
    distinct e.keys && !e.keys.isEmpty && distinct witnesses &&
    e.threshold.satisfied e.keys (verifiedSigners e event.signatures) &&
    (if e.witnessThreshold == 0 then event.receipts.isEmpty
     else decide (e.witnessThreshold ≤ (witnesses.filter receipts.contains).length))

/-- The controller's registration starts the history. A relay of a rotation
supplies the successor event over the stored predecessor. The advance checks
the two thresholds, increasing sequence and witness continuity
(message.ak 199–248, advance.ak 225–261). Freeze checks proposed evidence
but keeps the existing writer. -/
def EventHistory.authenticated (aid : Nat) : EventHistory → Bool
  | .inception event witnesses => inceptionWrites aid event witnesses
  | .rotation previous event =>
    previous.authenticated aid && rotationValid previous.predecessor event

/-- Given a checkpoint written by an authenticated rotation, when its KERI
context is reconstructed, then the accepted event is valid against the
predecessor computed from the actual preceding writer. -/
theorem stored_rotation_valid {aid : Nat} {previous : EventHistory} {event : SignedEvent}
    (accepted : (EventHistory.rotation previous event).authenticated aid = true) :
    previous.authenticated aid = true ∧ rotationValid previous.predecessor event = true :=
  by simpa only [EventHistory.authenticated, Bool.and_eq_true] using accepted

/-- Given an authenticated rotation and different rival content at the same
native sequence, when the two-event definition is evaluated for that stored
writer, then duplicity is equivalent to the rival's validity against the
same predecessor. -/
theorem rotated_duplicity_iff_rival_valid {aid : Nat} {previous : EventHistory}
    {writer rival : SignedEvent}
    (accepted : (EventHistory.rotation previous writer).authenticated aid = true)
    (samePosition : writer.event.sn = rival.event.sn)
    (conflict : writer.event ≠ rival.event) :
    duplicityAt (previous.epoch + 1) writer.event.sn
      ⟨previous.epoch + 1, previous.predecessor, writer⟩ rival = true ↔
      rotationValid previous.predecessor rival = true := by
  rw [duplicityAt_iff]
  exact ⟨fun h => h.2.2.2.1,
    fun h => ⟨rfl, rfl, (stored_rotation_valid accepted).2, h, samePosition, conflict⟩⟩

/-- The advance and conviction mint interpret verification keys and
next-key commitments in the same identity domain used by the authenticated
history. A digest opening is a cryptographic assumption. Interpretation is
required only for bytes actually read from the checkpoint. -/
structure KeyReads where
  verificationKey : List Nat → Option Nat
  nextCommitment : List Nat → Option Nat

private def thresholdRead : CheckpointDatum.Threshold → Option Duplicity.Threshold
  | .unweighted n => Duplicity.Threshold.count <$> n.toNat?
  | .weighted clauses => do
    let weights ← clauses.mapM fun clause => clause.mapM fun (n, d) => do
      return Duplicity.Weight.key ⟨← n.toNat?, ← d.toNat?⟩
    return .weighted weights

/-- Decoded establishment data carried on a checkpoint. The current event
content can be identified by its authenticated digest opening. No previous
datum or log is a field of this structure. -/
structure WriterDatum where
  writer : Content
  witnesses : List Nat
  previous : Option Predecessor
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

def WriterDatum.inception (event : Content) (witnesses : List Nat) : WriterDatum :=
  ⟨event, witnesses, none⟩

def WriterDatum.commitments (datum : WriterDatum) : Predecessor :=
  ⟨datum.writer.aid, datum.writer.sn, false, datum.writer.nextKeys,
    datum.writer.nextThreshold, datum.witnesses⟩

/-- An accepted advance constructs its successor from the one spent datum. -/
def WriterDatum.advance (spent : WriterDatum) (event : Content) : WriterDatum :=
  ⟨event, derivedWitnesses spent.commitments event, some spent.commitments⟩

def EventHistory.datum : EventHistory → WriterDatum
  | .inception event witnesses => .inception event.event witnesses
  | .rotation previous event => previous.datum.advance event.event

/-- The one-step writer agrees with the complete authenticated history used
by a relying party. In particular the witness set includes earlier deltas. -/
theorem EventHistory.datum_commitments (h : EventHistory) :
    h.datum.commitments = h.predecessor := by
  induction h with
  | inception => rfl
  | rotation previous writer ih =>
    simp [datum, WriterDatum.advance, WriterDatum.commitments, predecessor] at ih ⊢
    rw [ih]

theorem inception_carries_no_previous (event witnesses) :
    (EventHistory.inception event witnesses).datum.previous = none := rfl

theorem rotation_replaces_previous (history event) :
    (EventHistory.rotation history event).datum.previous = some history.predecessor :=
  congrArg some history.datum_commitments

/-- Different older predecessors cannot affect the next output once the
current writer and its established witnesses agree. -/
theorem advance_forgets_older (datum : WriterDatum) (older : Option Predecessor) (event : Content) :
    ({datum with previous := older} : WriterDatum).advance event = datum.advance event := rfl

theorem EventHistory.datum_writer (history : EventHistory) :
    history.datum.writer = history.writer.event := by
  cases history <;> rfl

/-- The input datum is checked without traversing the historical event log. -/
def KeyReads.matchesDatum (reads : KeyReads) (aid epoch : Nat) (datum : WriterDatum)
    (tip : CheckpointConviction.Tip) : Bool :=
  let event := datum.writer
  decide (tip.previous = datum.previous) && decide (tip.writer = event) &&
    tip.aid == aid && tip.aid == event.aid && tip.epoch == epoch && tip.sn == event.sn &&
    tip.keys.curKeys.mapM reads.verificationKey == some event.keys &&
    thresholdRead tip.keys.curThreshold == some event.threshold &&
    tip.keys.nextKeys.mapM reads.nextCommitment == some event.nextKeys &&
    thresholdRead tip.keys.nextThreshold == some event.nextThreshold &&
    tip.keys.witnesses.mapM reads.verificationKey == some datum.witnesses &&
    tip.keys.toad == (event.witnessThreshold : Int)

def KeyReads.matches (reads : KeyReads) (aid : Nat) (history : EventHistory)
    (tip : CheckpointConviction.Tip) : Bool :=
  reads.matchesDatum aid history.epoch history.datum tip

/-- The spent datum binds the entire writer and the one carried predecessor. -/
theorem KeyReads.matches_history {reads : KeyReads} {aid history tip}
    (h : reads.matches aid history tip = true) :
    tip.previous = history.datum.previous ∧ tip.writer = history.writer.event ∧
    tip.aid = aid ∧ tip.aid = history.writer.event.aid ∧ tip.epoch = history.epoch ∧ tip.sn = history.writer.event.sn := by
  simp only [KeyReads.matches, KeyReads.matchesDatum, EventHistory.datum_writer, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  grind

end CardanoKeri.Checkpoint
