import CardanoKeri.Duplicity

namespace CardanoKeri.Application.InceptionPrefix
open Duplicity

inductive Kind where
  | basic (transferable : Bool)
  | selfAddressing
  deriving Repr, DecidableEq, BEq

/-- Classify a decoded CESR derivation code in the ordinary basic-key and
self-addressing inception domain (keripy 1.3.5, coring.py, PreNonDigDex,
NonTransDex and DigDex). The serialized material must already parse. -/
def classify : String → Option Kind
  | "B" | "1AAA" | "1AAC" | "1AAI" => some (.basic false)
  | "D" | "1AAB" | "1AAD" | "1AAJ" => some (.basic true)
  | "E" | "F" | "G" | "H" | "I" | "0D" | "0E" | "0F" | "0G" => some .selfAddressing
  | _ => none

/-- Decoded from one signed inception body and its attachments. -/
structure Evidence where
  signed : SignedEvent
  witnesses : List Nat

/-- Anchors are part of the signed inception content. -/
def Evidence.seals (e : Evidence) := e.signed.event.extension

/-- The issuer decodes the signed evidence and derives a qualified identifier
from the same serialized bytes under the public identifier's derivation code. -/
structure OpeningReads where
  decodeEvidence : List UInt8 → Option Evidence := fun _ => none
  prefixCode : Nat → Option String := fun _ => none
  deriveIdentifier : List UInt8 → Option Nat := fun _ => none

def kindOf (prefixCode : Nat → Option String) (aid : Nat) : Option Kind :=
  (prefixCode aid).bind classify

def OpeningReads.binding (reads : OpeningReads) (bytes : List UInt8) (aid : Nat) (e : Evidence) : Kind → Bool
  | .basic transferable =>
    e.signed.event.keys == [aid] && decide (e.signed.event.threshold = .count 1) &&
      (transferable || (e.signed.event.nextKeys.isEmpty && e.witnesses.isEmpty && e.seals.isEmpty))
  | .selfAddressing => reads.deriveIdentifier bytes == some aid

def inceptionWrites (aid : Nat) (event : SignedEvent) (witnesses : List Nat) : Bool :=
  let e := event.event
  let receipts := verifiedSigners e event.receipts
  let inceptionFields := e.priorDigest == 0 && e.cuts.isEmpty && e.adds.isEmpty &&
    decide (e.nextThreshold.width ≤ e.nextKeys.length)
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

/-- Check ordinary inception admission and the prefix binding on the same decoded body. -/
def OpeningReads.accepts (reads : OpeningReads) (bytes : List UInt8) (aid : Nat)
    (e : Evidence) (k : Kind) : Bool :=
  inceptionWrites aid e.signed e.witnesses && reads.binding bytes aid e k

/-- The six key-state fields in main's initial checkpoint datum, after
decoding qualified keys and commitments into the signed event's domain. -/
structure KeyState where
  keys : List Nat
  threshold : Threshold
  nextKeys : List Nat
  nextThreshold : Threshold
  witnesses : List Nat
  toad : Nat
  deriving DecidableEq

def Evidence.keyState (e : Evidence) : KeyState :=
  ⟨e.signed.event.keys, e.signed.event.threshold, e.signed.event.nextKeys,
    e.signed.event.nextThreshold, e.witnesses, e.signed.event.witnessThreshold⟩

structure Reads extends OpeningReads where
  datumKeys : Nat → Option KeyState := fun _ => none

/-- The controller supplies the signed opening in the booking transaction.
The structural decoder and cryptographic reads are partial primitives. The
datum reader opens the request's committed initial datum independently. -/
def verify (reads : Reads) (raw aid : Nat) (bytes : List UInt8) : Bool :=
  (do
    let kind ← kindOf reads.prefixCode aid
    let e ← reads.decodeEvidence bytes
    let keys ← reads.datumKeys raw
    return reads.toOpeningReads.accepts bytes aid e kind && decide (keys = e.keyState)).getD false

end CardanoKeri.Application.InceptionPrefix
