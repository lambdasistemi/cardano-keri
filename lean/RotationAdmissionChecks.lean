import CardanoKeri.DuplicityExamples

/-! Decoded rotation inputs from the pinned keripy comparison. Identifiers,
keys and prior digests use the comparison's integer identities. Event digest
labels distinguish bodies in the symbolic model. -/
open CardanoKeri Duplicity

namespace RotationAdmissionChecks

structure Case where
  name : String
  prior : Predecessor
  rotation : SignedEvent
  expected : Bool
  deriving Lean.ToJson

private def rotation (name : String) (aid priorDigest : Nat) (keys nextKeys : List Nat)
    (current next : Threshold) (expected : Bool) : Case :=
  let prior : Predecessor := ⟨aid, 0, false, keys, .count 2, []⟩
  let body : Content := ⟨aid, 1, .rotation, priorDigest, keys, current, nextKeys, next, [], [], 0, [], name⟩
  ⟨name, prior, signed body keys [], expected⟩

private def two := Threshold.count 2
private def overweight := Threshold.weighted [[.key ⟨3,2⟩, .key ⟨1,2⟩]]
private def ordinary := rotation "R01" 3 4 [1,2] [5,6] two two true
private def r09a := rotation "R09a" 63 64 [61,62] [65,66] two overweight false
private def r09b := rotation "R09b" 69 70 [67,68] [71,72] two (.count 3) false
private def first := rotation "D08 accepted" 258 259 [256,257] [260,261] two two true
private def rival := rotation "D08 rival" 258 259 [256,257] [262,263] two overweight false

private def agrees (c : Case) := rotationValid c.prior c.rotation == c.expected

#guard agrees ordinary
#guard agrees r09a
#guard agrees r09b
#guard agrees first && agrees rival
#guard !duplicityAt 1 1 ⟨1, first.prior, first.rotation⟩ rival.rotation

private def declaration (name : String) (nextKeys : List Nat) (next : Threshold) (expected : Bool) :=
  rotation name 3 4 [1,2] nextKeys two next expected

private def witnesses (name : String) (aid priorDigest : Nat) (keys nextKeys old cuts adds : List Nat)
    (threshold : Nat) (receipts : List Nat) (expected : Bool) : Case :=
  let prior : Predecessor := ⟨aid, 0, false, keys, two, old⟩
  let body : Content := ⟨aid, 1, .rotation, priorDigest, keys, two, nextKeys, two, cuts, adds, threshold, [], name⟩
  ⟨name, prior, signed body keys receipts, expected⟩

private def w04 := witnesses "W04" 151 152 [147,148] [153,154] [149,150] [155] [] 2 [149,150] false
private def w05 := witnesses "W05" 160 161 [156,157] [162,163] [158,159] [] [158] 2 [158,159] false
private def w06 := witnesses "W06" 168 169 [164,165] [170,171] [167,166] [167] [167] 2 [166,167] false
private def w11 := witnesses "W11" 278 279 [276,277] [280,281] [282,283] [] [] 0 [] false

#guard agrees w04
#guard agrees w05
#guard agrees w06
#guard agrees w11

def cases : List Case := [ordinary, r09a, r09b, first, rival, w04, w05, w06, w11,
  witnesses "genuine removal" 151 152 [147,148] [153,154] [149,150] [149] [] 1 [150] true,
  witnesses "genuine addition" 160 161 [156,157] [162,163] [158,159] [] [125] 2 [159,125] true,
  witnesses "W01 distinct replacement" 126 127 [122,123] [128,129] [130,124] [130] [125] 2 [124,125] true,
  witnesses "W13 all removed" 292 293 [290,291] [294,295] [296,297] [296,297] [] 0 [] true,
  declaration "zero next at abandonment" [] (.count 0) true,
  declaration "weighted width exceeds key count" [5] (.weighted [[.key ⟨1,2⟩, .key ⟨1,2⟩]]) false,
  declaration "weighted width below key count" [5,6] (.weighted [[.key ⟨1,1⟩]]) true,
  declaration "empty weighted declaration" [] (.weighted []) false,
  declaration "underweight next clause" [5,6] (.weighted [[.key ⟨1,4⟩, .key ⟨1,2⟩]]) false,
  declaration "underweight nested members" [5,6] (.weighted [[.key ⟨1,1⟩, .group ⟨1,1⟩ [⟨1,2⟩]]]) false,
  declaration "valid nested declaration" [5,6] (.weighted [[.group ⟨1,1⟩ [⟨1,2⟩, ⟨1,2⟩]]]) true]

#guard cases.all agrees

/-- A valid first-seen sibling under the same prior for the rival checks.
Its witnesses stay in place and sign their original quorum. -/
private def contextFor (c : Case) : Context :=
  let old := c.prior.witnesses
  let body := { c.rotation.event with
    eventDigest := "first-seen", threshold := two, nextKeys := c.prior.nextKeys,
    nextThreshold := two, cuts := [], adds := [], witnessThreshold := old.length }
  ⟨1, c.prior, signed body c.prior.nextKeys old⟩

#guard cases.all fun c => rotationValid c.prior (contextFor c).accepted
#guard cases.all fun c => duplicityAt 1 1 (contextFor c) c.rotation == c.expected

def exportCases := cases.map fun c => (Lean.toJson c).setObjVal! "context" (Lean.toJson (contextFor c))

end RotationAdmissionChecks

def main : IO Unit := IO.println (Lean.toJson RotationAdmissionChecks.exportCases).compress
