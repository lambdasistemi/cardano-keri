import Lean

/-!
# Concrete evidence for ordinary rotation duplicity

KERI 1.1, specification source fbdd4a6155e48248873cccd5cf6f79b6b631a021:
sequence (323), thresholds (327–331, 1417–1466), witness deltas (348–362),
general rotation (1474–1498), validation/duplicity (1733–1744), first seen
and recovery (1784–1827). This is the non-delegated rotation profile.

Technical boundary: keys and key digests share an abstract identity after a
verified digest opening. Signature verification and wire structure/SAID/prior
link verification are primitive results, bound to the complete event below.
`extension` represents all remaining event content, including seals. A wire
decoder must preserve it injectively; no byte/crypto correspondence is proved.
The caller supplies authenticated predecessor context and the recorded first
accepted event. Neither a rival nor its receipts may choose that context.
-/
namespace CardanoKeri.Duplicity

structure Fraction where
  numerator : Nat
  denominator : Nat
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

def Fraction.add (a b : Fraction) : Fraction :=
  ⟨a.numerator * b.denominator + b.numerator * a.denominator,
    a.denominator * b.denominator⟩

def Fraction.atLeastOne (f : Fraction) : Bool :=
  f.denominator > 0 && f.numerator >= f.denominator

/-- A nested group contributes its outer weight only when its inner sum reaches one. -/
inductive Weight where
  | key (weight : Fraction)
  | group (weight : Fraction) (members : List Fraction)
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

def Weight.width : Weight → Nat
  | .key _ => 1
  | .group _ ws => ws.length

def Weight.wellFormed : Weight → Bool
  | .key w => w.denominator > 0
  | .group w ws => w.denominator > 0 && !ws.isEmpty && ws.all (·.denominator > 0)

def weightedSum (weights : List Fraction) (signed : List Bool) : Fraction :=
  (weights.zip signed).foldl (fun total (w, yes) =>
    if yes then total.add w else total) ⟨0, 1⟩

def clauseSum : List Weight → List Bool → Fraction
  | [], _ => ⟨0, 1⟩
  | .key w :: rest, signed =>
    (if signed.headD false then w else ⟨0, 1⟩).add (clauseSum rest (signed.drop 1))
  | .group w ws :: rest, signed =>
    (if (weightedSum ws (signed.take ws.length)).atLeastOne then w else ⟨0, 1⟩).add
      (clauseSum rest (signed.drop ws.length))

def clauseWidth (ws : List Weight) : Nat := (ws.map Weight.width).sum

def clausesSatisfied : List (List Weight) → List Bool → Bool
  | [], signed => signed.isEmpty
  | c :: cs, signed =>
    !c.isEmpty && c.all Weight.wellFormed &&
    (clauseSum c (signed.take (clauseWidth c))).atLeastOne &&
    clausesSatisfied cs (signed.drop (clauseWidth c))

inductive Threshold where
  | count (required : Nat)
  | weighted (clauses : List (List Weight))
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

/-- Each key contributes once, in that list's order; clauses are conjunctive. -/
def Threshold.satisfied (threshold : Threshold) (keys signers : List Nat) : Bool :=
  let signed := keys.map signers.contains
  match threshold with
  | .count n => n <= keys.length && n <= (signed.filter id).length
  | .weighted clauses =>
    !clauses.isEmpty && (clauses.map clauseWidth).sum == keys.length &&
    clausesSatisfied clauses signed

inductive EventKind where
  | inception | rotation | interaction | delegatedInception | delegatedRotation
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

structure Content where
  aid : Nat
  sn : Nat
  kind : EventKind
  priorDigest : Nat
  keys : List Nat
  threshold : Threshold
  nextKeys : List Nat
  nextThreshold : Threshold
  cuts : List Nat
  adds : List Nat
  witnessThreshold : Nat
  extension : List Nat
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

structure Signature where
  signer : Nat
  event : Content
  verified : Bool
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

structure SignedEvent where
  event : Content
  structureVerified : Bool
  signatures : List Signature
  receipts : List Signature
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

structure Predecessor where
  aid : Nat
  sn : Nat
  delegated : Bool
  nextKeys : List Nat
  nextThreshold : Threshold
  witnesses : List Nat
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

/-- Authenticated first-seen context, selected by the checkpoint, never by the rival. -/
structure Context where
  epoch : Nat
  prior : Predecessor
  accepted : SignedEvent
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

def distinct (xs : List Nat) : Bool := xs.eraseDups.length == xs.length

/-- Remove before adding; additions already in the resulting list are not repeated. -/
def derivedWitnesses (prior : Predecessor) (event : Content) : List Nat :=
  event.adds.foldl (fun ws w => if ws.contains w then ws else ws ++ [w])
    (prior.witnesses.filter fun w => !event.cuts.contains w)

def verifiedSigners (event : Content) (signatures : List Signature) : List Nat :=
  ((signatures.filter fun s => s.verified && decide (s.event = event)).map (·.signer)).eraseDups

def signingValid (prior : Predecessor) (signed : SignedEvent) : Bool :=
  let signers := verifiedSigners signed.event signed.signatures
  let exposed := prior.nextKeys.filter signed.event.keys.contains
  !prior.nextKeys.isEmpty && distinct prior.nextKeys && distinct signed.event.keys &&
  !signed.event.keys.isEmpty &&
  prior.nextThreshold.satisfied prior.nextKeys (signers.filter exposed.contains) &&
  signed.event.threshold.satisfied signed.event.keys signers

def receiptsValid (prior : Predecessor) (signed : SignedEvent) : Bool :=
  let witnesses := derivedWitnesses prior signed.event
  let receipts := verifiedSigners signed.event signed.receipts
  distinct prior.witnesses && distinct signed.event.cuts && distinct signed.event.adds &&
  signed.event.witnessThreshold <= witnesses.length &&
  signed.event.witnessThreshold <= (witnesses.filter receipts.contains).length

def rotationValid (prior : Predecessor) (signed : SignedEvent) : Bool :=
  !prior.delegated && decide (signed.event.kind = .rotation) && signed.structureVerified &&
  signed.event.aid == prior.aid && prior.sn < signed.event.sn &&
  signingValid prior signed && receiptsValid prior signed

/-- Both branches use the same authenticated prior-next commitment, their own
thresholds and derived witnesses. Comparing content does not replace first seen. -/
def duplicity (context : Context) (rival : SignedEvent) : Bool :=
  rotationValid context.prior context.accepted && rotationValid context.prior rival &&
  context.accepted.event.sn == rival.event.sn &&
  decide (context.accepted.event ≠ rival.event)

/-- The checkpoint target is checked in addition to the event comparison. -/
def duplicityAt (epoch sn : Nat) (context : Context) (rival : SignedEvent) : Bool :=
  context.epoch == epoch && context.accepted.event.sn == sn && duplicity context rival

/-- Given an accepted context and a rival, when duplicity holds, then both
rotations validate, share native sequence, and differ in complete content. -/
theorem duplicity_iff (context : Context) (rival : SignedEvent) :
    duplicity context rival = true ↔
      rotationValid context.prior context.accepted = true ∧
      rotationValid context.prior rival = true ∧
      context.accepted.event.sn = rival.event.sn ∧
      context.accepted.event ≠ rival.event := by
  simp [duplicity, Bool.and_eq_true, and_assoc]

/-- Given any pair at sequence zero, when it is offered to the checkpoint,
then it is refused: a rotation must be later than its prior establishment. -/
theorem sequence_zero_refused (epoch : Nat) (context : Context) (rival : SignedEvent) :
    duplicityAt epoch 0 context rival = false := by
  simp [duplicityAt, duplicity, rotationValid]
  omega

/-- Given a checkpoint target, when duplicity holds, then the accepted and
rival rotations both concern that target and satisfy their own validation. -/
theorem duplicityAt_iff (epoch sn : Nat) (context : Context) (rival : SignedEvent) :
    duplicityAt epoch sn context rival = true ↔
      context.epoch = epoch ∧ context.accepted.event.sn = sn ∧
      rotationValid context.prior context.accepted = true ∧
      rotationValid context.prior rival = true ∧
      context.accepted.event.sn = rival.event.sn ∧
      context.accepted.event ≠ rival.event := by
  simp [duplicityAt, duplicity_iff, Bool.and_eq_true, and_assoc]

end CardanoKeri.Duplicity
