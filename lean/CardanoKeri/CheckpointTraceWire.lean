import CardanoKeri.AttestationFixtures
import Lean
import CardanoKeri.Checkpoint
import CardanoKeri.DuplicityExamples

/-! Shared Checkpoint JSON instances and finite cryptographic-evidence fixtures.
A duplicity selector chooses the concrete model fixture; it is not a Boolean
substitute for the duplicity decision. -/

open Lean (ToJson toJson Json FromJson fromJson?)
open CardanoKeri.Checkpoint

namespace CardanoKeri.Checkpoint.TraceWire

deriving instance Lean.ToJson for BondOp
deriving instance Lean.ToJson for Live
deriving instance Lean.ToJson for Commitment
deriving instance Lean.ToJson for Action
deriving instance Lean.ToJson for State
deriving instance Lean.ToJson for Payment
deriving instance Lean.ToJson for Flow
deriving instance Lean.FromJson for BondOp
deriving instance Lean.FromJson for Live
deriving instance Lean.FromJson for Commitment
deriving instance Lean.FromJson for Action
deriving instance Lean.FromJson for State

/-- `Params` carries two proofs, so its instance is written by hand. -/
instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("B", toJson p.B), ("P", toJson p.P), ("W", toJson p.W)]

/-- `Params` from JSON, with the two positivity proofs decided at parse time:
a deployment with a zero bond has no `Params` and therefore no Lean cell. -/
def paramsOfJson (j : Json) : Except String Params := do
  let D ← j.getObjValAs? Nat "D"
  let B ← j.getObjValAs? Nat "B"
  let P ← j.getObjValAs? Nat "P"
  let W ← j.getObjValAs? Nat "W"
  if hD : 0 < D then
    if hB : 0 < B then pure { D, B, P, W, hD, hB }
    else throw "B must be positive"
  else throw "D must be positive"

structure InceptionRow where
  aid : Nat
  datum : Nat
  signed : CardanoKeri.Duplicity.SignedEvent
  witnesses : List Nat
  deriving Lean.ToJson, Lean.FromJson

structure RotationRow where
  aid : Nat
  epoch : Nat
  sn : Nat
  signed : CardanoKeri.Duplicity.SignedEvent
  deriving Lean.ToJson, Lean.FromJson

structure WriterTable where
  inceptions : List InceptionRow := []
  rotations : List RotationRow := []
  deriving Lean.ToJson, Lean.FromJson

/-- A synthetic event table for connected lifecycle fixtures. Every encoded
row contains the signed event checked by the interpreter. -/
def WriterTable.fixture (aid datum : Nat) (positions : List (Nat × Nat × Nat)) : WriterTable :=
  { inceptions := [⟨aid, datum, CardanoKeri.Duplicity.writerFixture aid 0 .inception, []⟩]
    rotations := positions.map fun (epoch, sn, target) =>
      ⟨aid, epoch, sn, CardanoKeri.Duplicity.writerFixture aid target .rotation⟩ }

/-- Three primitive decision tables and selectors for concrete duplicity
fixtures. A selector is a model scenario, not proof of real cryptography. -/
structure EnvTable where
  rotationTo : List (Nat × Nat × Nat)
  /-- The epochs whose keys signed the deposit of the rotation that opens them (D-038). -/
  depositAuthorized : List Nat
  quorum : List Nat
  duplicityAt : List (Nat × Nat)
  writers : WriterTable := {}

structure AdvanceObservation where
  kind : Attestation.Change
  epoch : Nat
  sn : Nat
  next : Nat
  observation : Attestation.Spend
  deriving ToJson, FromJson

structure MintTable where
  advances : List AdvanceObservation
  convictions : List Attestation.Production
  deriving ToJson, FromJson

/-- Expand the scenario's finite evidence positions into explicit sample
transactions. The interpreter can run against any supplied mint table. -/
def EnvTable.sampleTransactions (t : EnvTable) (aid : Nat := 0) : MintTable :=
  let advances := t.rotationTo.flatMap fun (epoch, sn, next) =>
    [Attestation.Change.advance, .freeze].map fun kind =>
      let ref : Singular.OutRef := if epoch == 0 then ⟨102, 1⟩ else ⟨102 + epoch, 0⟩
      (⟨kind, epoch, sn, next, Attestation.Fixtures.advanceSpend kind ref⟩ : AdvanceObservation)
  let convictions : List Attestation.Production := if t.duplicityAt.isEmpty then [] else
    [⟨⟨105 + (aid - 11), 0⟩, Attestation.Fixtures.convictionSpend ⟨103 + (aid - 11), 0⟩⟩]
  ⟨advances, convictions⟩

def EnvTable.read (t : EnvTable) (mints : MintTable) (aid : Nat := 0) : Env where
  keyReads := ⟨(fun | [key] => some key | _ => none), (fun | [key] => some key | _ => none)⟩
  convictionReads := ⟨Attestation.Fixtures.policies, fun out =>
    (mints.convictions.find? (·.output == out)).map (·.observation)⟩
  presentedSpend := fun e sn => if t.duplicityAt.contains (e, sn) then
    some ⟨⟨105 + (aid - 11), 0⟩, CardanoKeri.CheckpointConviction.Fixtures.comparison aid e sn⟩ else none
  advanceReads := ⟨111, Attestation.Fixtures.advancePolicy, fun kind e sn next =>
    (mints.advances.find? (fun row => decide (row.kind = kind) &&
      row.epoch == e && row.sn == sn && row.next == next)).map (·.observation)⟩
  depositAuthorized := fun e => t.depositAuthorized.contains e
  quorum := fun e => t.quorum.contains e
  inceptionWriter := fun aid datum => do
    let row ← t.writers.inceptions.find? fun row => row.aid == aid && row.datum == datum
    return (row.signed, row.witnesses)
  rotationWriter := fun aid epoch sn target => do
    let row ← t.writers.rotations.find? fun row =>
      row.aid == aid && row.epoch == epoch && row.sn == sn && row.signed.event.sn == target
    return row.signed
  convictionContext := fun e sn =>
    if t.duplicityAt.contains (e, sn) then some (CardanoKeri.Duplicity.fixture e sn).1 else none
  convictionRival := fun e sn =>
    if t.duplicityAt.contains (e, sn) then some (CardanoKeri.Duplicity.fixture e sn).2 else none

/-- Evaluate the explicit transactions constructed for a fixture. -/
def EnvTable.toEnv (t : EnvTable) (aid : Nat := 0) : Env := t.read (t.sampleTransactions aid) aid

def EnvTable.toWire (t : EnvTable) (aid : Nat := 0) : Json := Json.mkObj [
    ("mintTransactions", toJson (t.sampleTransactions aid)),
    ("rotationTo", toJson (t.rotationTo.map fun (e, sn, sn') => [e, sn, sn'])),
    ("depositAuthorized", toJson (t.depositAuthorized.map fun e => [e])),
    ("quorum", toJson (t.quorum.map fun e => [e])),
    ("duplicityAt", toJson (t.duplicityAt.map fun (e, sn) => [e, sn]))]

instance : ToJson EnvTable := ⟨fun t => t.toWire⟩

/-- An evidence row `{kind: [args]}` of a scenario file, added to or removed from a table. -/
def EnvTable.applyRow (t : EnvTable) (add : Bool) (row : Json) : Except String EnvTable := do
  let upd {α} [BEq α] (l : List α) (x : α) : List α := if add then (if l.contains x then l else l ++ [x]) else l.filter (· != x)
  let nats (v : Json) : Except String (List Nat) := fromJson? v
  match row.getObjVal? "rotationTo" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e, sn, sn'] => pure { t with rotationTo := upd t.rotationTo (e, sn, sn') }
    | _ => throw "rotationTo row needs three numbers"
  | .error _ =>
  match row.getObjVal? "depositAuthorized" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e] => pure { t with depositAuthorized := upd t.depositAuthorized e }
    | _ => throw "depositAuthorized row needs one number"
  | .error _ =>
  match row.getObjVal? "quorum" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e] => pure { t with quorum := upd t.quorum e }
    | _ => throw "quorum row needs one number"
  | .error _ =>
  match row.getObjVal? "duplicityAt" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e, sn] => pure { t with duplicityAt := upd t.duplicityAt (e, sn) }
    | _ => throw "duplicityAt row needs two numbers"
  | .error _ => throw "unknown evidence row"

end CardanoKeri.Checkpoint.TraceWire
