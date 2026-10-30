import CardanoKeri.ConsumerIdentity
import CardanoKeri.CheckpointTraceWire
import CardanoKeri.RegistryTraceWire

/-! Finite model interchange. Tables are explicit interpretations of the
frozen functions, not encodings of Cardano data. Missing naming entries are
errors before predicate evaluation; a missing datum decode is a refusal.
Context remains separate from the observed output and environment. -/
namespace CardanoKeri.ConsumerIdentity.Wire
open Lean
open CardanoKeri.Checkpoint

deriving instance ToJson, FromJson for DecodedDatum
deriving instance ToJson, FromJson for Context
deriving instance ToJson, FromJson for Environment

structure Tables where
  keys : List (AID × Singular.Key)
  codes : List (AH.Preimage × List Nat)
  hashes : List (List Nat × Nat)
  datums : List (AH.PublishedRelease × Nat × DecodedDatum)
  deriving ToJson, FromJson

def Tables.interpretation (t : Tables) : Interpretation := {
  keyOf := fun aid => ((t.keys.find? fun entry => entry.1 == aid).map (·.2)).getD 0
  code := fun p => ((t.codes.find? fun entry => entry.1 == p).map (·.2)).getD []
  hash := fun bytes => ((t.hashes.find? fun entry => entry.1 == bytes).map (·.2)).getD 0
  decode := fun release raw =>
    (t.datums.find? fun entry => entry.1 == release && entry.2.1 == raw).map (·.2.2) }

/-- A lookup failure is never an allocated identity. This checks coverage of
all naming lookups performed for the fixed consumer context, plus unambiguous
keys in each finite table. It deliberately does not assert hash injectivity. -/
def Tables.covers (t : Tables) (c : Context) : Bool :=
  let i := t.interpretation
  let domain : List AH.Preimage := [.state c.seed, .active (registryAsset i c) (i.keyOf c.aid)]
  !t.keys.isEmpty && !t.codes.isEmpty && !t.hashes.isEmpty &&
  decide (t.keys.map (·.1)).Nodup && decide (t.codes.map (·.1)).Nodup &&
  decide (t.hashes.map (·.1)).Nodup &&
  decide (t.datums.map (fun e => (e.1, e.2.1))).Nodup &&
  t.keys.any (fun e => e.1 == c.aid) &&
  domain.all (fun p => t.codes.any (fun e => e.1 == p) &&
    t.hashes.any (fun e => e.1 == i.code p))

structure Query where
  tables : Tables
  context : Context
  environment : Environment
  params : Params
  now : Slot
  holding : AH.ObservedOutput

instance : ToJson Query where
  toJson q := Json.mkObj [
    ("tables", toJson q.tables), ("context", toJson q.context),
    ("environment", toJson q.environment), ("params", toJson q.params),
    ("now", toJson q.now), ("holding", toJson q.holding)]

/-- Decode the exact-integer interchange emitted by Registry.TraceWire.
Decimal strings are reserved for naturals outside the safe JSON Number range. -/
partial def restoreExact (j : Json) : Except String Json := do
  match j with
  | .str text =>
    match text.toNat? with
    | some n =>
      if n > 9007199254740991 && toString n == text then pure (toJson n)
      else throw "noncanonical-exact-integer"
    | none => pure j
  | .arr entries => return .arr (← entries.mapM restoreExact)
  | .obj entries => return Json.mkObj (← entries.toList.mapM fun (key, value) => do
      pure (key, ← restoreExact value))
  | _ => pure j

instance : FromJson Query where
  fromJson? j := do
    let j ← restoreExact j
    pure ⟨← j.getObjValAs? Tables "tables", ← j.getObjValAs? Context "context",
      ← j.getObjValAs? Environment "environment",
      ← TraceWire.paramsOfJson (← j.getObjVal? "params"),
      ← j.getObjValAs? Nat "now", ← j.getObjValAs? AH.ObservedOutput "holding"⟩

def execute (q : Query) : Except String Bool := do
  unless q.tables.covers q.context do throw "incomplete-or-ambiguous-interpretation"
  pure (consumableHoldingB q.tables.interpretation q.context q.environment q.params q.now q.holding)

def cell (name : String) (q : Query) : Json :=
  CardanoKeri.Registry.TraceWire.exactJson (Json.mkObj [
    ("name", toJson name), ("query", toJson q),
    ("result", match execute q with
      | .ok accepted => Json.mkObj [("ok", toJson accepted)]
      | .error reason => Json.mkObj [("error", toJson reason)])])

end CardanoKeri.ConsumerIdentity.Wire
