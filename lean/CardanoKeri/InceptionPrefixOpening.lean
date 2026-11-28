import CardanoKeri.CheckpointEventHistory

namespace CardanoKeri.Application.InceptionPrefix
open Checkpoint Duplicity

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

/-- Both registration paths check these fields on the decoded signed body. -/
def OpeningReads.accepts (reads : OpeningReads) (bytes : List UInt8) (aid : Nat)
    (e : Evidence) (k : Kind) : Bool :=
  inceptionWrites aid e.signed e.witnesses && reads.binding bytes aid e k

end CardanoKeri.Application.InceptionPrefix
