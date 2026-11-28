import CardanoKeri.ApplicationGoals

/-! The controller's booking runs the application and the inception evidence
policy in one transaction. The latter opens the signed inception and the
initial checkpoint at the exact output named by each booking action. -/
namespace CardanoKeri.Application.InceptionPrefix
open Checkpoint Duplicity SingularApplicationHeld

structure Reads extends OpeningReads where
  bytesAt : Observation → Nat → Option (List UInt8)
  openTip : Nat → List UInt8 → Option CheckpointConviction.Tip
  keys : KeyReads

abbrev binding (reads : Reads) := reads.toOpeningReads.binding

/-- Given a basic non-transferable prefix, when booking checks its signed
fields, then it requires the matching sole key, threshold one and empty
next commitments, initial witnesses and seals. -/
theorem nontransferable_iff (reads bytes aid e) :
    binding reads bytes aid e (.basic false) = true ↔
      e.signed.event.keys = [aid] ∧ e.signed.event.threshold = .count 1 ∧
      e.signed.event.nextKeys = [] ∧ e.witnesses = [] ∧ e.seals = [] := by
  simp [binding, OpeningReads.binding, and_assoc]

/-- A later chain reader gets the kind from the qualified AID in the public
checkpoint datum. Booking uses exactly this decoder. -/
def datumKind (i : Interpretation) (prefixCode : AID → Option String) (raw : Nat) : Option Kind := do
  let datum ← i.decodeCheckpoint raw
  kindOf prefixCode datum.aid

def holdingKind (i : Interpretation) (prefixCode : AID → Option String)
    (holding : ObservedOutput) : Option Kind :=
  match holding.datum with
  | .application raw => datumKind i prefixCode raw
  | _ => none

/-- Check the signed evidence against the identifier and writer carried by the
initial datum that the claim commits. Every failed primitive read refuses. -/
def verify (i : Interpretation) (reads : Reads) (o : Observation) (index raw : Nat) : Bool :=
  (do
    let d ← i.decodeCheckpoint raw
    let kind ← kindOf reads.prefixCode d.aid
    let bytes ← reads.bytesAt o index
    let e ← reads.decodeEvidence bytes
    let tip ← reads.openTip raw bytes
    return reads.toOpeningReads.accepts bytes d.aid e kind &&
      reads.keys.matchesDatum d.aid 0 (.inception e.signed.event e.witnesses) tip).getD false

def claimAt (i : Interpretation) (release : PublishedRelease) (o : Observation) :
    Application.Action → Option Attestation.Claim
  | .bookRegistration index => do
    let output ← o.outputs[index]?
    let .registration data ← decoded i.decode output | none
    return .book release.applicationPolicy index data.initialDatum data.deposit
  | _ => none

/-- The fixed inception policy's issue check instantiates the general mint
policy with signed inception verification for every indexed booking. -/
def issue (i : Interpretation) (env : Env) (release : PublishedRelease) (reads : Reads)
    (emptyName : Nat) (o : Observation) : Bool :=
  env.bookingPolicy.authorizes o.assets emptyName (fun _ claim => match claim with
    | .book _ index raw _ => verify i reads o index raw
    | .spend .. => false) (o.actions.filterMap (claimAt i release o))

/-- Joint booking verdict for the relying application and its evidence issuer. -/
def admitted (i : Interpretation) (env : Env) (rp : Registry.Params) (cp : Checkpoint.Params)
    (release : PublishedRelease) (reads : Reads) (emptyName : Nat) (o : Observation) : Bool :=
  Application.accepted i env rp cp release o && issue i env release reads emptyName o

/-- Given an admitted booking, when its indexed registration is opened, then
the existing application gate required +1 and the issuer verified this datum. -/
theorem admitted_evidence {i env rp cp release reads emptyName o index output data}
    (ok : admitted i env rp cp release reads emptyName o = true)
    (booked : Application.Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output)
    (registered : decoded i.decode output = some (.registration data)) :
    Assets.mintQty o.assets (env.bookingAsset release index data) = 1 ∧
      verify i reads o index data.initialDatum = true := by
  simp only [admitted, issue, Attestation.Policy.authorizes, Bool.and_eq_true, List.all_eq_true] at ok
  obtain ⟨app, checks, _⟩ := ok
  refine ⟨accepted_booking_has_inception i env rp cp release o app booked found registered, ?_⟩
  have member : Attestation.Claim.book release.applicationPolicy index data.initialDatum data.deposit ∈
      o.actions.filterMap (claimAt i release o) :=
    List.mem_filterMap.mpr ⟨_, booked, by simp [claimAt, found, registered]⟩
  exact (checks _ member).1

/-- Given an admitted request and a fold delivering it, when a reader opens
the holding, then its public identifier yields the same kind that passed the
booking check. The reader needs only the datum and prefix decoders. -/
theorem delivered_kind {i env rp cp release reads emptyName o index output data holding fold}
    (ok : admitted i env rp cp release reads emptyName o = true)
    (booked : Application.Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output)
    (registered : decoded i.decode output = some (.registration data))
    (delivery : delivered i data holding fold = true) :
    ∃ k, datumKind i reads.prefixCode data.initialDatum = some k ∧
      holdingKind i reads.prefixCode holding = some k := by
  have verified := (admitted_evidence ok booked found registered).2
  simp only [delivered, Bool.and_eq_true, decide_eq_true_eq] at delivery
  have raw := delivery.1.1.1.2
  cases hd : i.decodeCheckpoint data.initialDatum with
  | none => simp [verify, hd] at verified
  | some d =>
    cases hk : kindOf reads.prefixCode d.aid with
    | none => simp [verify, hd, hk] at verified
    | some k => exact ⟨k, by simp [datumKind, hd, hk], by simp [holdingKind, raw, datumKind, hd, hk]⟩

/-- Given an admitted booking whose public datum reads as a basic prefix, when
the controller's signed inception is opened, then its only inception key is
the datum's qualified identifier and its numeric signing threshold is one. -/
theorem admitted_basic_sole_key {i env rp cp release reads emptyName o index output data d transferable}
    (ok : admitted i env rp cp release reads emptyName o = true)
    (booked : Application.Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output)
    (registered : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some d)
    (basic : datumKind i reads.prefixCode data.initialDatum = some (.basic transferable)) :
    ∃ bytes e, reads.bytesAt o index = some bytes ∧ reads.decodeEvidence bytes = some e ∧
      inceptionWrites d.aid e.signed e.witnesses = true ∧
      e.signed.event.keys = [d.aid] ∧ e.signed.event.threshold = .count 1 := by
  have verified := (admitted_evidence ok booked found registered).2
  have kind : kindOf reads.prefixCode d.aid = some (.basic transferable) := by
    simpa [datumKind, opened] using basic
  cases hb : reads.bytesAt o index <;> simp [verify, opened, kind, hb] at verified
  rename_i bytes
  cases he : reads.decodeEvidence bytes <;> simp [he] at verified
  rename_i e
  cases ht : reads.openTip data.initialDatum bytes <;> simp [ht, OpeningReads.accepts, OpeningReads.binding] at verified
  exact ⟨bytes, e, rfl, he, verified.1.1, verified.1.2.1.1, verified.1.2.1.2⟩

/-- Given the public datum and the decoded evidence at an admitted booking,
the identifier binds that same body, its next threshold fits its commitments,
and the controller signature threshold is satisfied. -/
theorem admitted_opening_fields {i env rp cp release reads emptyName o index output data d bytes e k}
    (ok : admitted i env rp cp release reads emptyName o = true)
    (booked : Application.Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output)
    (registered : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some d)
    (kind : kindOf reads.prefixCode d.aid = some k)
    (source : reads.bytesAt o index = some bytes) (decodedBody : reads.decodeEvidence bytes = some e) :
    binding reads bytes d.aid e k = true ∧ e.signed.event.nextThreshold.width ≤ e.signed.event.nextKeys.length ∧
      e.signed.event.threshold.satisfied e.signed.event.keys (verifiedSigners e.signed.event e.signed.signatures) = true := by
  have verified := (admitted_evidence ok booked found registered).2
  cases ht : reads.openTip data.initialDatum bytes <;>
    simp [verify, opened, kind, source, decodedBody, ht, OpeningReads.accepts] at verified
  obtain ⟨⟨written, bound⟩, _⟩ := verified
  simp [inceptionWrites, Threshold.fitsNextKeys] at written
  exact ⟨bound, by grind, by grind⟩

/-- Given an admitted booking, when the registration reader opens the same
indexed evidence and uses the same public decoders, it installs that booking's
signed writer and witnesses as the initial history. -/
theorem admitted_initial_history {i env rp cp release reads emptyName o index output data d}
    (ok : admitted i env rp cp release reads emptyName o = true)
    (booked : Application.Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output)
    (registered : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some d) (system : Checkpoint.Env)
    (decoders : system.inceptionOpening = reads.toOpeningReads)
    (indexed : system.inceptionBytes d.aid data.initialDatum = reads.bytesAt o index) :
    ∃ bytes e, reads.bytesAt o index = some bytes ∧ reads.decodeEvidence bytes = some e ∧
      system.initialHistory d.aid (some data.initialDatum) = some (.inception e.signed e.witnesses) := by
  have verified := (admitted_evidence ok booked found registered).2
  cases hk : kindOf reads.prefixCode d.aid <;> simp [verify, opened, hk] at verified
  rename_i k
  cases hb : reads.bytesAt o index <;> simp [hb] at verified
  rename_i bytes
  cases hd : reads.decodeEvidence bytes <;> simp [hd] at verified
  rename_i e
  cases ht : reads.openTip data.initialDatum bytes <;> simp [ht] at verified
  exact ⟨bytes, e, rfl, hd, by simp [Checkpoint.Env.initialHistory, decoders, indexed, hb, hd, hk, verified.1]⟩

/-- Given an admitted self-addressing booking, when its indexed evidence is
read, deriving the qualified digest from those very bytes returns the AID. -/
theorem admitted_self_addressing_digest {i env rp cp release reads emptyName o index output data d}
    (ok : admitted i env rp cp release reads emptyName o = true)
    (booked : Application.Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output)
    (registered : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some d)
    (kind : kindOf reads.prefixCode d.aid = some .selfAddressing) :
    ∃ bytes, reads.bytesAt o index = some bytes ∧ reads.deriveIdentifier bytes = some d.aid := by
  have verified := (admitted_evidence ok booked found registered).2
  cases hb : reads.bytesAt o index <;> simp [verify, opened, kind, hb] at verified
  rename_i bytes
  cases he : reads.decodeEvidence bytes <;> simp [he] at verified
  rename_i e
  have fields := admitted_opening_fields ok booked found registered opened kind hb he
  exact ⟨bytes, rfl, by simpa [binding, OpeningReads.binding] using fields.1⟩

/-- Given the signed body and the public identifier at the indexed request,
booking refuses an oversized next threshold, zero numeric signing threshold,
incorrect basic key list or threshold, non-transferable commitments, witnesses
or signed anchors, and a self-addressing digest mismatch. -/
theorem inconsistent_booking_refused {i env rp cp release reads emptyName o index output data d bytes e k}
    (booked : Application.Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output)
    (registered : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some d)
    (kind : kindOf reads.prefixCode d.aid = some k)
    (source : reads.bytesAt o index = some bytes) (decodedBody : reads.decodeEvidence bytes = some e)
    (invalid : e.signed.event.nextKeys.length < e.signed.event.nextThreshold.width ∨
      e.signed.event.threshold = .count 0 ∨
      (match k with
      | .basic transferable => e.signed.event.keys ≠ [d.aid] ∨ e.signed.event.threshold ≠ .count 1 ∨
        (transferable = false ∧ (e.signed.event.nextKeys ≠ [] ∨ e.witnesses ≠ [] ∨ e.signed.event.extension ≠ []))
      | .selfAddressing => reads.deriveIdentifier bytes ≠ some d.aid)) :
    admitted i env rp cp release reads emptyName o = false := by
  cases ok : admitted i env rp cp release reads emptyName o with
  | false => rfl
  | true =>
    obtain ⟨bound, fits, signed⟩ := admitted_opening_fields ok booked found registered opened kind source decodedBody
    rcases invalid with wide | zero | mismatch
    · omega
    · simp [zero, Threshold.satisfied] at signed
    · cases k with
      | selfAddressing => simp_all [binding, OpeningReads.binding]
      | basic t => cases t <;> simp_all [binding, OpeningReads.binding, Evidence.seals]

end CardanoKeri.Application.InceptionPrefix
