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

/-- The correspondence of decoded histories with the raw key representation
and indexed cryptographic observations. The enforcement observer reads the tip
from its named input and binds the rival's fields to the presented event bytes
(enforcement_observer.ak 68–94). A concrete interpretation must preserve the
writer, the signature messages and the event contents of those observations. -/
structure ComparisonReads where
  tipOf : EventHistory → CheckpointConviction.Tip
  rivalOf : CheckpointConviction.Tip → CheckpointConviction.Rival → SignedEvent
  verify : CheckpointConviction.Verify

/-- The decoded representation of the four fields compared for conflict. -/
abbrev ForwardFields :=
  CheckpointDatum.Threshold × List (List Nat) × CheckpointDatum.Threshold × Int

def tipFields (tip : CheckpointConviction.Tip) : ForwardFields :=
  (tip.keys.curThreshold, tip.keys.nextKeys, tip.keys.nextThreshold, tip.keys.toad)

def rivalFields (rival : CheckpointConviction.Rival) : ForwardFields :=
  (rival.threshold, rival.nextKeys, rival.nextThreshold, rival.toad)

/-- The spent tip and the presented rival must be decoded consistently with
the stored writer and signed message. The advance writes the accepted fields
and the enforcement observer reads those fields from its named input and
the rival bytes. This is a technical representation obligation. None of
these equalities asserts that the rival meets a signature threshold. -/
structure ComparisonReads.FieldsAgree (reads : ComparisonReads)
    (history : EventHistory) (rival : CheckpointConviction.Rival)
    (encode : Content → ForwardFields) : Prop where
  epoch : (reads.tipOf history).epoch = history.epoch
  writerPosition : (reads.tipOf history).sn = history.writer.event.sn
  rivalPosition : (reads.rivalOf (reads.tipOf history) rival).event.sn = rival.sn
  writerFields : tipFields (reads.tipOf history) = encode history.writer.event
  rivalFields : rivalFields rival = encode (reads.rivalOf (reads.tipOf history) rival).event

/-- Open conformance obligation at an authenticated inception. -/
def InceptionRefusal (reads : ComparisonReads) : Prop :=
  ∀ aid event witnesses rival, (EventHistory.inception event witnesses).authenticated aid = true →
    CheckpointConviction.accepts reads.verify (reads.tipOf (.inception event witnesses)) rival = false

/-- Open conformance obligation after a rotation. The earlier advance
authenticates the stored writer. The following assertion about the later
rival has no established discharge. -/
def RotatedRivalValidity (reads : ComparisonReads) : Prop :=
  ∀ aid previous writer rival, (EventHistory.rotation previous writer).authenticated aid = true →
    let tip := reads.tipOf (.rotation previous writer)
    CheckpointConviction.accepts reads.verify tip rival = true →
    rotationValid previous.predecessor (reads.rivalOf tip rival) = true

end CardanoKeri.Checkpoint
