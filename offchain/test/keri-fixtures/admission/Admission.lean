import CardanoKeri.Duplicity

/-! Ordinary admission driver: evaluates the model's executable admission predicates on the rows the keripy
runner translated (`lean-input.json`), and prints one JSON object per row.

Run (see README.md): `lean --run Admission.lean lean-input.json`, with the compiled
`CardanoKeri.Duplicity` on LEAN_PATH. The driver parses the rows itself; the model is used
as it is, no predicate is re-implemented here. -/
open Lean CardanoKeri.Duplicity

abbrev P := Except String

def nat (j : Json) (k : String) : P Nat := do (← j.getObjVal? k).getNat?
def flag (j : Json) (k : String) : P Bool := do (← j.getObjVal? k).getBool?
def arr (j : Json) (k : String) : P (Array Json) := do (← j.getObjVal? k).getArr?
def nats (j : Json) (k : String) : P (List Nat) := do
  let a ← arr j k
  a.toList.mapM Json.getNat?

def fraction (j : Json) : P Fraction := do
  let a ← j.getArr?
  match a.toList with
  | [n, d] => pure ⟨← n.getNat?, ← d.getNat?⟩
  | _ => throw "fraction"

def weight (j : Json) : P Weight := do
  match j.getObjVal? "key" with
  | .ok f => pure (.key (← fraction f))
  | .error _ =>
    let g ← (← j.getObjVal? "group").getArr?
    match g.toList with
    | [w, ms] => pure (.group (← fraction w) (← (← ms.getArr?).toList.mapM fraction))
    | _ => throw "group"

def threshold (j : Json) : P Threshold :=
  match j.getObjVal? "count" with
  | .ok n => do pure (.count (← n.getNat?))
  | .error _ =>
    match j.getObjVal? "weighted" with
    | .ok w => do
      let clauses ← (← w.getArr?).toList.mapM fun c => do (← c.getArr?).toList.mapM weight
      pure (.weighted clauses)
    | .error _ => throw "threshold form not representable"

def kind (s : String) : P EventKind :=
  match s with
  | "inception" => pure .inception | "rotation" => pure .rotation | "interaction" => pure .interaction
  | "delegatedInception" => pure .delegatedInception | "delegatedRotation" => pure .delegatedRotation
  | _ => throw "kind"

def content (j : Json) : P Content := do
  pure { aid := ← nat j "aid", sn := ← nat j "sn", kind := ← kind (← (← j.getObjVal? "kind").getStr?),
         priorDigest := ← nat j "priorDigest", keys := ← nats j "keys", threshold := ← threshold (← j.getObjVal? "threshold"),
         nextKeys := ← nats j "nextKeys", nextThreshold := ← threshold (← j.getObjVal? "nextThreshold"),
         cuts := ← nats j "cuts", adds := ← nats j "adds", witnessThreshold := ← nat j "witnessThreshold",
         extension := ← nats j "extension" }

def signature (e : Content) (j : Json) : P Signature := do
  pure ⟨← nat j "signer", e, ← flag j "verified"⟩

def signedEvent (j : Json) : P SignedEvent := do
  let e ← content (← j.getObjVal? "event")
  pure ⟨e, ← flag j "structureVerified",
        ← (← arr j "signatures").toList.mapM (signature e), ← (← arr j "receipts").toList.mapM (signature e)⟩

def predecessor (j : Json) : P Predecessor := do
  pure ⟨← nat j "aid", ← nat j "sn", ← flag j "delegated", ← nats j "nextKeys",
        ← threshold (← j.getObjVal? "nextThreshold"), ← nats j "witnesses"⟩

def row (j : Json) : P Json := do
  let prior ← predecessor (← j.getObjVal? "prior")
  let signed ← signedEvent (← j.getObjVal? "signed")
  let base : List (String × Json) := [
    ("case", (← j.getObjVal? "case")), ("role", (← j.getObjVal? "role")),
    ("rotationValid", toJson (rotationValid prior signed)),
    ("signingValid", toJson (signingValid prior signed)),
    ("receiptsValid", toJson (receiptsValid prior signed))]
  pure (Json.mkObj base)

def rows (args : List String) : IO UInt32 := do
  let text ← IO.FS.readFile (args.headD "lean-input.json")
  let json ← IO.ofExcept (Json.parse text)
  let rows ← IO.ofExcept (← IO.ofExcept (json.getObjVal? "rows")).getArr?
  for r in rows do
    let comparable ← IO.ofExcept ((← IO.ofExcept (r.getObjVal? "comparable")).getBool?)
    if comparable then
      match row r with
      | .ok out => IO.println out.compress
      | .error e => IO.println (Json.mkObj [("case", r.getObjValD "case"), ("role", r.getObjValD "role"), ("untranslatable", toJson e)]).compress
    else
      IO.println (Json.mkObj [("case", r.getObjValD "case"), ("role", r.getObjValD "role"), ("notComparable", r.getObjValD "reason")]).compress
  return 0

/-- `Admission.lean thresholds <thresholds.json>`: `Threshold.satisfied` on every signer subset of every case. -/
def thresholds (path : String) : IO UInt32 := do
  let json ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  for c in ← IO.ofExcept (← IO.ofExcept (json.getObjVal? "cases")).getArr? do
    let id := c.getObjValD "id"
    let n ← IO.ofExcept ((← IO.ofExcept (c.getObjVal? "n")).getNat?)
    match threshold (c.getObjValD "threshold") with
    | .error e => IO.println (Json.mkObj [("id", id), ("untranslatable", toJson e)]).compress
    | .ok th =>
      let keys := List.range n
      let mut out : List (String × Json) := []
      let mut mask := 0
      while mask < 2 ^ n do
        let signers := keys.filter fun i => (mask >>> i) % 2 == 1
        let label := String.join (signers.map toString)
        out := out ++ [(label, toJson (th.satisfied keys signers))]
        mask := mask + 1
      IO.println (Json.mkObj [("id", id), ("satisfied", Json.mkObj out)]).compress
  return 0

def main (args : List String) : IO UInt32 :=
  match args with
  | "thresholds" :: path :: _ => thresholds path
  | _ => rows args
