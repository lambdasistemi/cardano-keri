import CardanoKeri.ApplicationGoals

namespace CardanoKeri.Application.InceptionPrefix
open SingularApplicationHeld Duplicity

/-- Given an accepted booking action, its indexed output and its committed
initial datum, the transaction supplies bytes whose signed event and key
material pass the inception opening for that datum's identifier. -/
theorem accepted_opening {i env rp cp release o index output data datum}
    (ok : accepted i env rp cp release o = true) (booked : Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output) (request : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some datum) :
    ∃ bytes kind e, o.signedInceptions[index]?.join = some bytes ∧
      kindOf env.opening.prefixCode datum.aid = some kind ∧ env.opening.decodeEvidence bytes = some e ∧
      env.opening.datumKeys data.initialDatum = some e.keyState ∧
      inceptionWrites datum.aid e.signed e.witnesses = true ∧
      env.opening.toOpeningReads.binding bytes datum.aid e kind = true := by
  simp only [accepted, Bool.and_eq_true] at ok
  have a := List.all_eq_true.mp ok.1.1.1.2 _ booked
  simp only [action, found, Bool.and_eq_true] at a
  have checked := a.2
  cases hb : o.signedInceptions[index]?.join <;> simp [bookingOpening, request, opened, hb] at checked
  rename_i bytes
  cases hk : kindOf env.opening.prefixCode datum.aid <;> simp [verify, hk] at checked
  rename_i kind
  cases he : env.opening.decodeEvidence bytes <;> simp [he] at checked
  rename_i e
  cases hm : env.opening.datumKeys data.initialDatum <;> simp [hm, OpeningReads.accepts] at checked
  exact ⟨bytes, kind, e, rfl, rfl, he, congrArg some checked.2, checked.1⟩

/-- Given a booking accepted for a key-derived identifier, its sole current
key is that identifier and its signing threshold is the numeric value one.
A non-transferable identifier has no next keys, witnesses or signed seals. -/
theorem accepted_basic {i env rp cp release o index output data datum transferable}
    (ok : accepted i env rp cp release o = true) (booked : Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output) (request : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some datum)
    (basic : kindOf env.opening.prefixCode datum.aid = some (.basic transferable)) :
    ∃ bytes e, o.signedInceptions[index]?.join = some bytes ∧ env.opening.decodeEvidence bytes = some e ∧
      e.signed.event.keys = [datum.aid] ∧ e.signed.event.threshold = .count 1 ∧
      (transferable = false → e.signed.event.nextKeys = [] ∧ e.witnesses = [] ∧ e.seals = []) := by
  obtain ⟨b, k, e, hb, hk, he, _, _, binding⟩ := accepted_opening ok booked found request opened
  rw [basic] at hk
  cases hk
  refine ⟨b, e, hb, he, ?_⟩
  cases transferable <;> simp_all [OpeningReads.binding, and_assoc]

/-- Given an accepted booking for a self-addressing identifier, deriving the
identifier from the signed bytes supplied at that very output returns the AID. -/
theorem accepted_self_addressing {i env rp cp release o index output data datum}
    (ok : accepted i env rp cp release o = true) (booked : Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output) (request : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some datum)
    (digest : kindOf env.opening.prefixCode datum.aid = some .selfAddressing) :
    ∃ bytes, o.signedInceptions[index]?.join = some bytes ∧ env.opening.deriveIdentifier bytes = some datum.aid := by
  obtain ⟨b, k, _, hb, hk, _, _, _, binding⟩ := accepted_opening ok booked found request opened
  rw [digest] at hk
  cases hk
  exact ⟨b, hb, by simpa [OpeningReads.binding] using binding⟩

/-- If an indexed signed opening has an oversized next rule, a zero numeric
signing threshold, or fails the identifier binding, its booking is refused. -/
theorem inconsistent_booking_refused {i env rp cp release o index output data datum bytes k e}
    (booked : Action.bookRegistration index ∈ o.actions) (found : o.outputs[index]? = some output)
    (request : decoded i.decode output = some (.registration data)) (opened : i.decodeCheckpoint data.initialDatum = some datum)
    (source : o.signedInceptions[index]?.join = some bytes) (kind : kindOf env.opening.prefixCode datum.aid = some k)
    (body : env.opening.decodeEvidence bytes = some e)
    (invalid : e.signed.event.nextKeys.length < e.signed.event.nextThreshold.width ∨
      e.signed.event.threshold = .count 0 ∨ env.opening.toOpeningReads.binding bytes datum.aid e k = false) :
    accepted i env rp cp release o = false := by
  cases ok : accepted i env rp cp release o with
  | false => rfl
  | true =>
    obtain ⟨_, _, _, hb, hk, he, _, writes, binding⟩ := accepted_opening ok booked found request opened
    rw [source] at hb
    cases hb
    rw [kind] at hk
    cases hk
    rw [body] at he
    cases he
    rcases invalid with wide | zero | wrong
    · simp [inceptionWrites, Threshold.fitsNextKeys] at writes
      omega
    · simp [inceptionWrites, zero, Threshold.satisfied] at writes
    · simp [wrong] at binding

/-- When the folder delivers an accepted request, its holding carries the
same initial datum. A reader applying the booking's public decoders to that
datum obtains the same identifier kind without the controller's signatures. -/
theorem delivered_kind {i env rp cp release o index output data datum holding fold}
    (ok : accepted i env rp cp release o = true) (booked : Action.bookRegistration index ∈ o.actions)
    (found : o.outputs[index]? = some output) (request : decoded i.decode output = some (.registration data))
    (opened : i.decodeCheckpoint data.initialDatum = some datum) (delivery : delivered i data holding fold = true) :
    ∃ k, kindOf env.opening.prefixCode datum.aid = some k ∧
      (match holding.datum with
       | .application raw => (i.decodeCheckpoint raw).bind fun d => kindOf env.opening.prefixCode d.aid
       | _ => none) = some k := by
  obtain ⟨_, k, _, _, hk, _⟩ := accepted_opening ok booked found request opened
  simp only [delivered, Bool.and_eq_true, decide_eq_true_eq] at delivery
  exact ⟨k, hk, by simp [delivery.1.1.1.2, opened, hk]⟩

end CardanoKeri.Application.InceptionPrefix
