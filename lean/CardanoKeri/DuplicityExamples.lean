import CardanoKeri.Duplicity

namespace CardanoKeri.Duplicity

/-- Fixture signatures model verified cryptography, not possession of real keys. -/
def sign (event : Content) (keys : List Nat) : List Signature :=
  keys.map fun key => ⟨key, event, true⟩

def signed (event : Content) (keys witnesses : List Nat) : SignedEvent :=
  ⟨event, true, sign event keys, sign event witnesses⟩

/-- A concrete partial/augmented sibling pair; row (epoch,sn) selects this
fixture in the lifecycle simulator. Zero sequence deliberately fails validation. -/
def fixture (epoch sn : Nat) : Context × SignedEvent :=
  let prior : Predecessor := ⟨1, sn - 1, false, [1, 2], .count 1, [10]⟩
  let accepted : Content :=
    ⟨1, sn, .rotation, 50, [1], .count 1, [4], .count 1, [], [], 1, []⟩
  let rival := { accepted with
    keys := [2, 3]
    threshold := .count 2
    cuts := [10]
    adds := [11]
    extension := [99] }
  (⟨epoch, prior, signed accepted [1] [10]⟩, signed rival [2, 3] [11])

def baseContext : Context := (fixture 1 1).1
def baseRival : SignedEvent := (fixture 1 1).2

def thresholdRival (threshold : Threshold) : SignedEvent :=
  let event := { baseContext.accepted.event with threshold, extension := [1] }
  signed event [1] [10]

def exactKeyRival := thresholdRival (.count 2)
def weightedRival := thresholdRival (.weighted [[.key ⟨1, 2⟩]])
def tipReceiptRival := { baseRival with receipts := sign baseRival.event [10] }
def missingReceiptRival := { baseRival with receipts := [] }

/-- A test-only stale grader: equality with the tip's keys and its threshold
replaces checking the rival's current threshold. Prior authority still checked. -/
def exactKeyGrader (context : Context) (rival : SignedEvent) : Bool :=
  let event := rival.event
  let altered := { event with threshold := context.accepted.event.threshold }
  let signers := verifiedSigners event rival.signatures
  let receipts := verifiedSigners event rival.receipts
  event.keys == context.accepted.event.keys &&
    duplicity context (signed altered signers receipts)

/-- Test-only tip-set receipt grader. -/
def tipWitnessGrader (context : Context) (rival : SignedEvent) : Bool :=
  let receipts := verifiedSigners rival.event rival.receipts
  let tip := context.accepted.event
  rotationValid context.prior context.accepted &&
  rival.event.kind == .rotation && rival.structureVerified &&
  rival.event.aid == context.prior.aid && context.prior.sn < rival.event.sn &&
  signingValid context.prior rival &&
  tip.witnessThreshold <= ((derivedWitnesses context.prior tip).filter receipts.contains).length &&
  tip.sn == rival.event.sn && decide (tip ≠ rival.event)

/-- Test-only omission of the rival's receipt check. -/
def missingReceiptGrader (context : Context) (rival : SignedEvent) : Bool :=
  rotationValid context.prior context.accepted &&
  rival.event.kind == .rotation && rival.structureVerified &&
  rival.event.aid == context.prior.aid && context.prior.sn < rival.event.sn &&
  signingValid context.prior rival && context.accepted.event.sn == rival.event.sn &&
  decide (context.accepted.event ≠ rival.event)

/-- Test-only collapse of a weighted threshold to one signature. -/
def unweightedGrader (context : Context) (rival : SignedEvent) : Bool :=
  let event := { rival.event with threshold := .count 1 }
  duplicity context (signed event (verifiedSigners rival.event rival.signatures)
    (verifiedSigners rival.event rival.receipts))

def identicalContentGrader (context : Context) (rival : SignedEvent) : Bool :=
  rotationValid context.prior context.accepted && rotationValid context.prior rival &&
  context.accepted.event.sn == rival.event.sn

/-- Given partial and augmented siblings with their own sufficient receipts,
when compared, then duplicity holds despite different keys and witnesses. -/
theorem partial_augmented_siblings_accepted :
    duplicity baseContext baseRival = true ∧
    exactKeyGrader baseContext baseRival = false ∧
    tipWitnessGrader baseContext baseRival = false := by decide

/-- Given the tip's exact keys but insufficient signatures for the rival's
own threshold, when graded, then the real predicate refuses and the stale one accepts. -/
theorem exact_key_mutant_refused :
    duplicity baseContext exactKeyRival = false ∧
    exactKeyGrader baseContext exactKeyRival = true := by decide

/-- Given receipts only from the tip's removed witness, when the rival is
graded, then its own derived set refuses and the tip-set mutant accepts. -/
theorem tip_witness_mutant_refused :
    duplicity baseContext tipReceiptRival = false ∧
    tipWitnessGrader baseContext tipReceiptRival = true := by decide

/-- Given no required rival receipts, when graded, then the real predicate
refuses and omitting the receipt guard accepts. -/
theorem missing_receipts_mutant_refused :
    duplicity baseContext missingReceiptRival = false ∧
    missingReceiptGrader baseContext missingReceiptRival = true := by decide

/-- Given a one-key threshold of weight one half, when graded, then the
unsatisfiable rival is refused; treating its threshold as one signature accepts. -/
theorem weighted_threshold_mutant_refused :
    duplicity baseContext weightedRival = false ∧
    unweightedGrader baseContext weightedRival = true := by decide

/-- Given identical event content, when compared, then no duplicity exists;
omitting content inequality accepts the same event twice. -/
theorem identical_content_mutant_refused :
    duplicity baseContext baseContext.accepted = false ∧
    identicalContentGrader baseContext baseContext.accepted = true := by decide

/-- Given a delegated identifier, when otherwise valid siblings are presented,
then this ordinary profile refuses them. -/
theorem delegated_identity_refused :
    duplicity { baseContext with prior.delegated := true } baseRival = false := by decide

/-- Given a signed interaction conflict, when offered for financial conviction,
then the rotation-only profile refuses it. -/
theorem interaction_conflict_refused :
    duplicity baseContext
      (signed { baseRival.event with kind := .interaction } [2, 3] [11]) = false := by decide

/-- Given sufficient signatures in only one weighted clause, when the threshold
is evaluated, then it refuses until every clause has its own sufficient weight. -/
theorem weighted_clauses_are_conjunctive :
    Threshold.satisfied (.weighted [[.key ⟨1,1⟩], [.key ⟨1,1⟩]]) [1,2] [1] = false ∧
    Threshold.satisfied (.weighted [[.key ⟨1,1⟩], [.key ⟨1,1⟩]]) [1,2] [1,2] = true := by decide

/-- Given a nested two-of-three group contributing half and a fourth key
contributing half, when signed, then two inner keys plus the fourth suffice;
one inner key plus the fourth does not. -/
theorem nested_weight_requires_inner_threshold :
    Threshold.satisfied (.weighted [[.group ⟨1,2⟩ [⟨1,2⟩,⟨1,2⟩,⟨1,2⟩], .key ⟨1,2⟩]])
      [1,2,3,4] [1,2,4] = true ∧
    Threshold.satisfied (.weighted [[.group ⟨1,2⟩ [⟨1,2⟩,⟨1,2⟩,⟨1,2⟩], .key ⟨1,2⟩]])
      [1,2,3,4] [1,4] = false := by decide

structure Scenario where
  name : String
  epoch : Nat
  sn : Nat
  context : Context
  rival : SignedEvent
  deriving Lean.ToJson, Lean.FromJson

/-- Executable witnesses and refused cells shared with the simulator. -/
def scenarios : List Scenario :=
  let row (name : String) (rival : SignedEvent) : Scenario :=
    ⟨name, 1, 1, baseContext, rival⟩
  [row "partial-and-augmented" baseRival,
   row "exact-key-grading" exactKeyRival,
   row "tip-witness-grading" tipReceiptRival,
   row "missing-derived-receipts" missingReceiptRival,
   row "unsatisfiable-weighted-threshold" weightedRival,
   row "identical-content" baseContext.accepted,
   ⟨"sequence-zero", 0, 0, (fixture 0 0).1, (fixture 0 0).2⟩,
   ⟨"delegated-identity", 1, 1, { baseContext with prior.delegated := true }, baseRival⟩,
   row "interaction-conflict" (signed { baseRival.event with kind := .interaction } [2,3] [11]),
   ⟨"wrong-checkpoint-sequence", 1, 2, baseContext, baseRival⟩,
   ⟨"wrong-checkpoint-epoch", 2, 1, baseContext, baseRival⟩,
   row "signatures-bound-to-other-content" { baseRival with signatures := baseContext.accepted.signatures },
   row "receipts-bound-to-other-content" { baseRival with receipts := baseContext.accepted.receipts },
   row "duplicate-receipts" (let event := { baseRival.event with adds := [11,12], witnessThreshold := 2 }
     { (signed event [2,3] [11]) with receipts := sign event [11,11] }),
   row "current-without-prior-authority" (signed { baseRival.event with keys := [3], threshold := .count 1 } [3] [11]),
   row "same-projection-different-seals" (signed { baseContext.accepted.event with extension := [42] } [1] [10]),
   row "reordered-keys" (signed { baseRival.event with keys := [3,2] } [2,3] [11]),
   row "zero-denominator" (thresholdRival (.weighted [[.key ⟨1,0⟩]])),
   row "weighted-positive" (signed { baseRival.event with threshold := .weighted [[.key ⟨1,2⟩, .key ⟨1,2⟩]] } [2,3] [11]),
   row "unverified-wire-structure" { baseRival with structureVerified := false },
   row "weighted-conjunctive-positive" (signed { baseRival.event with
     threshold := .weighted [[.key ⟨1,1⟩], [.key ⟨1,1⟩]] } [2,3] [11]),
   row "weighted-conjunctive-missing-clause" (signed { baseRival.event with
     threshold := .weighted [[.key ⟨1,1⟩], [.key ⟨1,1⟩]] } [2] [11]),
   row "nested-weight-positive" (signed { baseRival.event with
     keys := [1,2,3,4]
     threshold := .weighted [[.group ⟨1,2⟩ [⟨1,2⟩,⟨1,2⟩,⟨1,2⟩], .key ⟨1,2⟩]] } [1,2,4] [11]),
   row "nested-weight-inner-insufficient" (signed { baseRival.event with
     keys := [1,2,3,4]
     threshold := .weighted [[.group ⟨1,2⟩ [⟨1,2⟩,⟨1,2⟩,⟨1,2⟩], .key ⟨1,2⟩]] } [1,4] [11]),
   ⟨"prior-weighted-positive", 1, 1,
     { baseContext with prior.nextThreshold := .weighted [[.key ⟨1,1⟩, .key ⟨1,1⟩]] }, baseRival⟩,
   ⟨"prior-weighted-insufficient", 1, 1,
     { baseContext with prior.nextThreshold := .weighted [[.key ⟨1,2⟩, .key ⟨1,2⟩]] }, baseRival⟩,
   row "different-prior-digest" (signed { baseRival.event with priorDigest := 51 } [2,3] [11]),
   row "existing-witness-add-is-not-duplicated" (signed { baseContext.accepted.event with adds := [10] } [1] [10]),
   row "duplicate-cuts" (signed { baseRival.event with cuts := [10,10] } [2,3] [11])]

def scenarioJson (scenario : Scenario) : Lean.Json :=
  Lean.Json.mkObj [("input", Lean.toJson scenario),
    ("accepted", Lean.toJson (duplicityAt scenario.epoch scenario.sn scenario.context scenario.rival))]

end CardanoKeri.Duplicity
