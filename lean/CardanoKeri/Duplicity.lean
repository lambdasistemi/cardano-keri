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
The decoded extension carries additional content such as seals. Event identity
uses the own digest of the authenticated signed body, including its original
spelling. The raw-to-decoded correspondence remains a technical obligation.
In the modeled checkpoint conviction spend the convictor supplies the
rival event and its signatures and receipts. The conviction mint binds the
writer and preceding commitments to the spent input and checks the event bytes,
digest openings, signatures and receipts represented by the primitive results. Neither a rival nor its receipts may choose that context.
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

def Weight.positiveDenominators : Weight → Bool
  | .key w => w.denominator > 0
  | .group w ws => w.denominator > 0 && ws.all (·.denominator > 0)

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

/-- The declared next rule is stored before its keys sign. A rational in
either threshold still requires a nonzero denominator (KERI 1.1, line 1419). -/
def Threshold.positiveDenominators : Threshold → Bool
  | .count _ => true
  | .weighted cs => cs.all fun clause => clause.all Weight.positiveDenominators

/-- The decoded model checks keripy 1.3.5’s individual weight ceiling.
This necessary admission condition is stricter than the pinned KERI 1.1 fractional threshold
clause (line 1419), which imposes a minimum on the signed sum and gives no
individual maximum. Keep the original fraction pair for the signed opening. -/
def Threshold.weightsAtMostOne : Threshold → Bool
  | .count _ => true
  | .weighted clauses => clauses.all fun clause => clause.all fun
    | .key w => decide (w.numerator ≤ w.denominator)
    | .group outer members => decide (outer.numerator ≤ outer.denominator) &&
        members.all fun w => decide (w.numerator ≤ w.denominator)

/-- Minimum number of committed keys described by this threshold. -/
def Threshold.width : Threshold → Nat
  | .count n => n
  | .weighted clauses => (clauses.map clauseWidth).sum

private def sumAtLeastOne (weights : List Fraction) : Bool :=
  (weights.foldl Fraction.add ⟨0, 1⟩).atLeastOne

/-- A declared weighted rule can be constructed only if every clause and
every nested member list totals at least one. The width counts the members
of a nested group. Numeric zero remains a valid declaration for the future. -/
def Threshold.fitsNextKeys (threshold : Threshold) (keyCount : Nat) : Bool :=
  decide (threshold.width ≤ keyCount) && match threshold with
    | .count _ => true
    | .weighted clauses => !clauses.isEmpty && clauses.all fun clause =>
      sumAtLeastOne (clause.map fun | .key w | .group w _ => w) &&
      clause.all fun | .key _ => true | .group _ members => sumAtLeastOne members

/-- Each key contributes once, in that list's order; clauses are conjunctive. -/
def Threshold.satisfied (threshold : Threshold) (keys signers : List Nat) : Bool :=
  let signed := keys.map signers.contains
  match threshold with
  | .count n => 0 < n && n <= keys.length && n <= (signed.filter id).length
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
  /-- The event’s own SAID, authenticated by the signed-byte opening. -/
  eventDigest : String
  deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

/-- Both the current and the declared next rule belong to the signed event. -/
def Content.weightsAtMostOne (e : Content) : Bool :=
  e.threshold.weightsAtMostOne && e.nextThreshold.weightsAtMostOne

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
  signed.event.cuts.all prior.witnesses.contains &&
  signed.event.adds.all (fun w => !prior.witnesses.contains w) &&
  (witnesses.isEmpty || 0 < signed.event.witnessThreshold) &&
  signed.event.witnessThreshold <= witnesses.length &&
  signed.event.witnessThreshold <= (witnesses.filter receipts.contains).length

def rotationValid (prior : Predecessor) (signed : SignedEvent) : Bool :=
  !prior.delegated && decide (signed.event.kind = .rotation) &&
  ((signed.structureVerified && signed.event.nextThreshold.fitsNextKeys signed.event.nextKeys.length) &&
    prior.nextThreshold.weightsAtMostOne &&
    signed.event.weightsAtMostOne && signed.event.nextThreshold.positiveDenominators) &&
  signed.event.aid == prior.aid && prior.sn < signed.event.sn &&
  signingValid prior signed && receiptsValid prior signed

/-- Both branches use the same authenticated prior-next commitment, their own
thresholds and derived witnesses. The two authenticated event digests identify the signed bodies. -/
def duplicity (context : Context) (rival : SignedEvent) : Bool :=
  rotationValid context.prior context.accepted && rotationValid context.prior rival &&
  context.accepted.event.sn == rival.event.sn &&
  decide (context.accepted.event.eventDigest ≠ rival.event.eventDigest)

/-- The checkpoint target is checked in addition to the event comparison. -/
def duplicityAt (epoch sn : Nat) (context : Context) (rival : SignedEvent) : Bool :=
  context.epoch == epoch && context.accepted.event.sn == sn && duplicity context rival

/-- Given an accepted context and a rival, when duplicity holds, then both
rotations validate, share native sequence, and have different event digests. -/
theorem duplicity_iff (context : Context) (rival : SignedEvent) :
    duplicity context rival = true ↔
      rotationValid context.prior context.accepted = true ∧
      rotationValid context.prior rival = true ∧
      context.accepted.event.sn = rival.event.sn ∧
      context.accepted.event.eventDigest ≠ rival.event.eventDigest := by
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
      context.accepted.event.eventDigest ≠ rival.event.eventDigest := by
  simp [duplicityAt, duplicity_iff, Bool.and_eq_true, and_assoc]

end CardanoKeri.Duplicity
