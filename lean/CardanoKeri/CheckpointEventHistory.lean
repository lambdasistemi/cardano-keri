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
interpretation, for an inception of the selected identifier. KERI 1.1
`spec/spec-body.md` at fbdd4a61, line 556, excludes the rotation fields
`p`, `br` and `ba` from an inception. In this decoded content their absence
is represented by zero for the prior digest and empty lists for both deltas.
The wire reader must check field absence in the signed body. -/
def inceptionWrites (aid : Nat) (event : SignedEvent) (witnesses : List Nat) : Bool :=
  let e := event.event
  let receipts := verifiedSigners e event.receipts
  let inceptionFields := e.priorDigest == 0 && e.cuts.isEmpty && e.adds.isEmpty &&
    e.nextThreshold.fitsNextKeys e.nextKeys.length
  e.aid == aid && e.sn == 0 && e.kind == .inception &&
    (event.structureVerified && inceptionFields && e.weightsAtMostOne && e.nextThreshold.positiveDenominators) &&
    distinct e.keys && !e.keys.isEmpty && distinct witnesses &&
    e.threshold.satisfied e.keys (verifiedSigners e event.signatures) &&
    (if e.witnessThreshold == 0 then event.receipts.isEmpty
     else decide (e.witnessThreshold ≤ (witnesses.filter receipts.contains).length))

/-- Given a signed event and initial witnesses, when registration accepts its
inception opening, the decoded writer has no prior digest or witness deltas. -/
theorem inception_has_no_rotation_fields {aid : Nat} {event : SignedEvent} {witnesses : List Nat}
    (accepted : inceptionWrites aid event witnesses = true) :
    event.event.priorDigest = 0 ∧ event.event.cuts = [] ∧ event.event.adds = [] := by
  simp [inceptionWrites, Bool.and_eq_true] at accepted
  grind

/-- Given a signed inception, when registration opens its writer, each
denominator in the next threshold it stores is positive. -/
theorem inception_next_denominators_positive {aid : Nat} {event : SignedEvent} {witnesses : List Nat}
    (accepted : inceptionWrites aid event witnesses = true) :
    event.event.nextThreshold.positiveDenominators = true := by
  simp only [inceptionWrites, Bool.and_eq_true] at accepted
  exact accepted.1.1.1.1.1.2.2

/-- Given a signed rotation, when it passes against its predecessor, each
denominator in the next threshold it declares is positive. -/
theorem rotation_next_denominators_positive {prior : Predecessor} {signed : SignedEvent}
    (accepted : rotationValid prior signed = true) :
    signed.event.nextThreshold.positiveDenominators = true := by
  simp only [rotationValid, Bool.and_eq_true] at accepted
  exact accepted.1.1.1.1.2.2

/-- Given a signed inception, when its registration opening passes, each
individual signing weight in its current and next rules is at most one,
including the outer and member weights of groups (keripy admission profile). -/
theorem inception_weights_at_most_one {aid : Nat} {event : SignedEvent} {witnesses : List Nat}
    (accepted : inceptionWrites aid event witnesses = true) :
    event.event.threshold.weightsAtMostOne = true ∧ event.event.nextThreshold.weightsAtMostOne = true := by
  simp only [inceptionWrites, Content.weightsAtMostOne, Bool.and_eq_true] at accepted
  exact accepted.1.1.1.1.1.2.1.2

/-- Given a writer or rival rotation, when it validates against its predecessor,
the prior signing rule and both rules in the event satisfy keripy’s ceiling. -/
theorem rotation_weights_at_most_one {prior : Predecessor} {signed : SignedEvent}
    (accepted : rotationValid prior signed = true) :
    prior.nextThreshold.weightsAtMostOne = true ∧ signed.event.threshold.weightsAtMostOne = true ∧
    signed.event.nextThreshold.weightsAtMostOne = true := by
  simp only [rotationValid, Content.weightsAtMostOne, Bool.and_eq_true] at accepted
  exact ⟨accepted.1.1.1.1.2.1.1.2, accepted.1.1.1.1.2.1.2⟩

/-- Given an admitted rotation, when the next rule is read from its signed
body, its width fits its declared digests and its weighted clauses and groups
meet the minimum for a declaration. -/
theorem rotation_next_rule_fits {prior : Predecessor} {signed : SignedEvent}
    (accepted : rotationValid prior signed = true) :
    signed.event.nextThreshold.fitsNextKeys signed.event.nextKeys.length = true := by
  simp only [rotationValid, Bool.and_eq_true] at accepted
  grind

/-- Given an admitted rotation, its cuts are prior witnesses, its additions
are new, and any nonempty resulting set has a positive receipt threshold. -/
theorem rotation_witness_changes_valid {prior : Predecessor} {signed : SignedEvent}
    (accepted : rotationValid prior signed = true) :
    (∀ w ∈ signed.event.cuts, w ∈ prior.witnesses) ∧
    (∀ w ∈ signed.event.adds, w ∉ prior.witnesses) ∧
    (derivedWitnesses prior signed.event ≠ [] → 0 < signed.event.witnessThreshold) := by
  simp [rotationValid, receiptsValid] at accepted
  grind

/-- Given any keys and signer subset, checking numeric signing threshold zero
returns false, including when every key signed. -/
theorem zero_signing_threshold_unsatisfied (keys signers : List Nat) :
    (Threshold.count 0).satisfied keys signers = false := by rfl

/-- Given a decoded rotation with numeric signing threshold zero, neither
the signatures it carries nor the predecessor can make it a valid rotation. -/
theorem rotation_zero_signing_threshold_refused (prior : Predecessor) (signed : SignedEvent)
    (zero : signed.event.threshold = .count 0) : rotationValid prior signed = false := by
  simp [rotationValid, signingValid, zero, zero_signing_threshold_unsatisfied]

/-- Given authenticated openings for the installed writer and the presented
rival, when the KERI digest has no collision on these two signed byte bodies,
digest inequality holds exactly when their bytes differ. -/
theorem opened_digest_conflict_iff_signed_bytes_differ
    (digestOf : ByteArray → String) (writer rival : Content) (writerBytes rivalBytes : ByteArray)
    (writerOpening : writer.eventDigest = digestOf writerBytes)
    (rivalOpening : rival.eventDigest = digestOf rivalBytes)
    (collisionResistance : digestOf writerBytes = digestOf rivalBytes → writerBytes = rivalBytes) :
    writer.eventDigest ≠ rival.eventDigest ↔ writerBytes ≠ rivalBytes := by
  rw [writerOpening, rivalOpening]
  exact ⟨fun different equal => different (congrArg digestOf equal),
    fun different equal => different (collisionResistance equal)⟩

/-- Equality after erasing the new field is exactly equality of the twelve
decoded fields used by the published comparison, including the extension. -/
def priorComparisonContent (e : Content) : Content := { e with eventDigest := "" }

/-- Given a rotated tip and an otherwise valid same-position rival, when the
same deterministic old decoder opens each signed body and each own SAID opens
its body without a collision on this pair, the comparison retains every old
conflict. Its only additional conflicts are different signed bodies with the
same old decoded content. -/
theorem accepts_iff_old_conflict_or_collapsed_bodies
    (tip : CheckpointConviction.Tip) (rival : SignedEvent) (prior : Predecessor)
    (previous : tip.previous = some prior) (rotated : tip.epoch ≠ 0)
    (named : tip.aid = rival.event.aid) (position : tip.sn = rival.event.sn)
    (valid : rotationValid prior rival = true)
    (decode : ByteArray → Option Content) (digestOf : ByteArray → String)
    (wb rb : ByteArray)
    (decodedWriter : decode wb = some (priorComparisonContent tip.writer))
    (decodedRival : decode rb = some (priorComparisonContent rival.event))
    (writerOpening : tip.writer.eventDigest = digestOf wb)
    (rivalOpening : rival.event.eventDigest = digestOf rb)
    (collisionResistance : digestOf wb = digestOf rb → wb = rb) :
    CheckpointConviction.accepts tip rival = true ↔
      priorComparisonContent tip.writer ≠ priorComparisonContent rival.event ∨
      (priorComparisonContent tip.writer = priorComparisonContent rival.event ∧ wb ≠ rb) := by
  have identical (h : wb = rb) : priorComparisonContent tip.writer = priorComparisonContent rival.event :=
    Option.some.inj (decodedWriter.symm.trans ((congrArg decode h).trans decodedRival))
  rw [CheckpointConviction.accepts_iff]
  simp only [previous, Option.some.injEq, exists_eq_left', named, position, valid, true_and]
  rw [opened_digest_conflict_iff_signed_bytes_differ digestOf _ _ wb rb writerOpening rivalOpening collisionResistance]
  constructor
  · intro different
    by_cases eq : priorComparisonContent tip.writer = priorComparisonContent rival.event
    · exact Or.inr ⟨eq, different.2⟩
    · exact Or.inl eq
  · exact fun h => ⟨rotated, h.elim (fun ne same => ne (identical same)) And.right⟩

/-- For a faithful old opening of this pair, equal decoded content determines
equal bytes. In that case the old content test and the digest test agree. -/
theorem digest_conflict_iff_faithful_old_conflict
    (writer rival : Content) (wb rb : ByteArray)
    (decode : ByteArray → Option Content) (digestOf : ByteArray → String)
    (decodedWriter : decode wb = some (priorComparisonContent writer))
    (decodedRival : decode rb = some (priorComparisonContent rival))
    (faithful : decode wb = decode rb → wb = rb)
    (writerOpening : writer.eventDigest = digestOf wb) (rivalOpening : rival.eventDigest = digestOf rb)
    (collisionResistance : digestOf wb = digestOf rb → wb = rb) :
    writer.eventDigest ≠ rival.eventDigest ↔ priorComparisonContent writer ≠ priorComparisonContent rival := by
  rw [opened_digest_conflict_iff_signed_bytes_differ digestOf _ _ wb rb writerOpening rivalOpening collisionResistance]
  exact ⟨fun different same => different (faithful (decodedWriter.trans ((congrArg some same).trans decodedRival.symm))),
    fun different same => different (Option.some.inj (decodedWriter.symm.trans ((congrArg decode same).trans decodedRival)))⟩

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

/-- Given an authenticated rotation and a different rival event digest at the same
native sequence, when the two-event definition is evaluated for that stored
writer, then duplicity is equivalent to the rival's validity against the
same predecessor. -/
theorem rotated_duplicity_iff_rival_valid {aid : Nat} {previous : EventHistory}
    {writer rival : SignedEvent}
    (accepted : (EventHistory.rotation previous writer).authenticated aid = true)
    (samePosition : writer.event.sn = rival.event.sn)
    (conflict : writer.event.eventDigest ≠ rival.event.eventDigest) :
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
    decide (tip.keys.curThreshold = event.threshold) &&
    tip.keys.nextKeys.mapM reads.nextCommitment == some event.nextKeys &&
    decide (tip.keys.nextThreshold = event.nextThreshold) &&
    tip.keys.witnesses.mapM reads.verificationKey == some datum.witnesses &&
    tip.keys.toad == (event.witnessThreshold : Int)

def KeyReads.matches (reads : KeyReads) (aid : Nat) (history : EventHistory)
    (tip : CheckpointConviction.Tip) : Bool :=
  reads.matchesDatum aid history.epoch history.datum tip

/-- Encoders for a particular interpretation of verification keys and digests.
Only these primitive round trips are needed to present a decoded writer. -/
structure KeyEncoding (reads : KeyReads) where
  key : Nat → List Nat
  commitment : Nat → List Nat
  readKey : ∀ k, reads.verificationKey (key k) = some k
  readCommitment : ∀ k, reads.nextCommitment (commitment k) = some k

/-- Symbolic identities used by the executable decoded comparison. -/
def KeyReads.symbolic : KeyReads :=
  ⟨(fun | [k] => some k | _ => none), (fun | [k] => some k | _ => none)⟩

def KeyEncoding.symbolic : KeyEncoding KeyReads.symbolic :=
  ⟨List.singleton, List.singleton, fun _ => rfl, fun _ => rfl⟩

def WriterDatum.tip {reads : KeyReads} (datum : WriterDatum) (encoding : KeyEncoding reads)
    (epoch : Nat) : CheckpointConviction.Tip :=
  let e := datum.writer
  ⟨e.aid, epoch, e.sn,
    ⟨e.keys.map encoding.key, e.threshold, e.nextKeys.map encoding.commitment,
      e.nextThreshold, datum.witnesses.map encoding.key, e.witnessThreshold⟩,
    datum.previous, e⟩

private theorem read_encoded (read : List Nat → Option Nat) (encode : Nat → List Nat)
    (roundTrip : ∀ k, read (encode k) = some k) (keys : List Nat) :
    (keys.map encode).mapM read = some keys := by
  induction keys with
  | nil => rfl
  | cons k ks ih => simp [List.mapM_cons, roundTrip, ih]

/-- Given faithfully interpreted keys, presenting the stored writer preserves
every field checked by the conviction input, for all threshold constructors. -/
theorem WriterDatum.matches_tip {reads : KeyReads} (datum : WriterDatum)
    (encoding : KeyEncoding reads) (epoch : Nat) :
    reads.matchesDatum datum.writer.aid epoch datum (datum.tip encoding epoch) = true := by
  simp [KeyReads.matchesDatum, WriterDatum.tip, read_encoded _ _ encoding.readKey,
    read_encoded _ _ encoding.readCommitment]

/-- A history authenticated for an identifier ends in a writer for it. -/
theorem EventHistory.authenticated_aid {aid : Nat} {history : EventHistory}
    (h : history.authenticated aid = true) : history.writer.event.aid = aid := by
  induction history with
  | inception event witnesses =>
    simp only [authenticated, inceptionWrites, Bool.and_eq_true, beq_iff_eq] at h
    exact h.1.1.1.1.1.1.1.1
  | rotation previous event ih =>
    obtain ⟨auth, valid⟩ := stored_rotation_valid h
    simp only [rotationValid, Bool.and_eq_true, beq_iff_eq] at valid
    have idEq : previous.predecessor.aid = previous.writer.event.aid := by cases previous <;> rfl
    exact valid.1.1.1.2.trans (idEq.trans (ih auth))

/-- The spent datum binds the entire writer and the one carried predecessor. -/
theorem KeyReads.matches_history {reads : KeyReads} {aid history tip}
    (h : reads.matches aid history tip = true) :
    tip.previous = history.datum.previous ∧ tip.writer = history.writer.event ∧
    tip.aid = aid ∧ tip.aid = history.writer.event.aid ∧ tip.epoch = history.epoch ∧ tip.sn = history.writer.event.sn := by
  simp only [KeyReads.matches, KeyReads.matchesDatum, EventHistory.datum_writer, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  grind

end CardanoKeri.Checkpoint
