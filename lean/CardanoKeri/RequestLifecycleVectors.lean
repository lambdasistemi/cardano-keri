import CardanoKeri.RegistryScenarioFixtures
import Lean

/-! Vectors of the registration request lifecycle for the on-chain validators. Each
row executes the actual `stepFn` on a reachable fixture state: a fold or a
return of one request, at a validity interval on either side of the request's
deadline, with the refund the transaction pays and the verdict. The deadline
is the booking's validity upper bound plus the deployment window; the fixture
registry is a KERI deployment (`retractTime = 0`). -/
namespace CardanoKeri.Registry.LifecycleVectors
open Lean CardanoKeri.Registry CardanoKeri.Registry.Scenarios

structure Case where
  id : String
  note : String
  state : Sys
  /-- The reference of the request the row spends. -/
  reference : Singular.OutRef
  action : Action

def verdict : Except String Result → String
  | .ok _ => "accepted"
  | .error why => why

def groundJson : Singular.RejectReason → Json
  | .expired => "expired"
  | .mismatch _ => "key-already-registered"

def intervalJson : Option Singular.Interval → Json
  | some i => Json.mkObj [("lower", toJson i.lower), ("upper", toJson i.upper)]
  | none => Json.null

def spendJson (c : Case) (refund : Nat) : Json :=
  match c.action with
  | .fold _ _ _ tx => Json.mkObj [("kind", "fold"),
      ("validity", intervalJson tx.transaction.validity)]
  | .returnRequests _ r => Json.mkObj [("kind", "return"),
      ("validity", intervalJson r.transaction.transaction.validity),
      ("ground", Json.arr (r.members.map (groundJson ·.2)).toArray),
      ("signers", toJson r.transaction.transaction.signers),
      ("fee", toJson r.transaction.transaction.fee),
      ("refundPaid", toJson (Singular.refundPaid r.transaction refund))]
  | _ => Json.null

def requestJson (s : Sys) (b : Singular.RegistrationBooking) : Json :=
  let r := b.request
  Json.mkObj [("reference", toJson r.reference.tx), ("key", toJson r.key),
    ("keyAlreadyRegistered", toJson (Singular.trieGet s.trie r.key != .unknown)),
    ("submittedAt", toJson r.submittedAt), ("processTime", toJson s.config.processTime),
    ("deadline", toJson (deadline s.config r)),
    ("registrationCost", toJson r.registrationCost), ("declaredTip", toJson r.declaredTip),
    ("carrierAda", toJson r.carrierAda), ("contents", toJson r.contents.lovelace),
    ("refundAddress", toJson r.refundAddress),
    ("refundOwed", toJson (r.contents.lovelace - r.declaredTip))]

def row (c : Case) : Json :=
  let result := verdict (stepFn p env c.action c.state)
  match c.state.registrations.find? (fun b => b.request.reference == c.reference) with
  | some b => Json.mkObj [("id", toJson c.id), ("note", toJson c.note),
      ("request", requestJson c.state b), ("spend", spendJson c b.request.refundAddress),
      ("verdict", toJson result)]
  | none => Json.mkObj [("id", toJson c.id), ("note", toJson c.note),
      ("pendingTermination", Json.mkObj [("reference", toJson c.reference.tx)]),
      ("spend", spendJson c 0), ("verdict", toJson result)]

def withValidity (r : Singular.Rejection) (lower upper : Nat) : Singular.Rejection :=
  { r with transaction.transaction.validity := some ⟨lower, upper⟩ }

def withRefund (r : Singular.Rejection) (amount fee : Nat) (address : Option Nat := none) :
    Singular.Rejection :=
  let outputs := r.transaction.outputs.map fun o =>
    let paid : Singular.EconomicOutput := { o with output.lovelace := amount }
    let paid : Singular.EconomicOutput := { paid with contents.lovelace := amount }
    match address with
    | some a => { paid with output.address := some a }
    | none => paid
  let r : Singular.Rejection := { r with transaction.outputs := outputs }
  let r : Singular.Rejection := { r with transaction.transaction.outputs := outputs.map (·.output) }
  { r with transaction.transaction.fee := fee }

def cases : Except String (List Case) := do
  let first := registration start.state 11 100
  let (_, booked) ← execute start (.bookRegistration first)
  let (u0, t0) ← foldTransaction booked.state [first.request.reference] 2 1 1
  let (_, live) ← execute booked (.fold 0 cfg.applicationPolicy u0 t0)
  let fresh := registration live.state 12 101
  let (_, withFresh) ← execute live (.bookRegistration fresh)
  let dup := registration withFresh.state 11 300
  let (_, both) ← execute withFresh (.bookRegistration dup)
  let s := both.state
  let f := fresh.request.reference
  let d := dup.request.reference
  let foldAt (lower upper : Nat) : Except String Action := do
    let (u, tx) ← foldTransaction s [f] lower 1 1
    pure (.fold s.gen cfg.applicationPolicy u { tx with transaction.validity := some ⟨lower, upper⟩ })
  let (ru, r) ← returnTransaction s [f] 6
  let (du, dr) ← returnTransaction s [d] 6 (.mismatch (.known .active))
  let (_, de) ← returnTransaction s [d] 6
  let (pu, ptx) ← foldTransaction { s with trie := [] } [d] 2 1 1
  -- Conviction custody: a pending termination next to a booked registration.
  let (_, convicted) ← execute withFresh (.convictCkpt 11)
  let tb ← termination convicted.state 11 200
  let (_, custody) ← execute convicted (.bookTermination 11 7 1 tb)
  let c := custody.state
  let (cu, cr) ← returnTransaction c [f] 6
  let custodyReturn : Singular.Rejection := { cr with members := [(tb.request.reference, .expired)] }
  let custodyReturn : Singular.Rejection := { custodyReturn with
    transaction.transaction.inputs := [Singular.foldWitnessInput tb.request.reference] }
  let (tu, ttx) ← foldTransaction c [tb.request.reference] 20 1 1
  let regs : List (String × String × Action) := [
    ("fold-before-booking", "a fold whose interval starts before the booking", ← foldAt 0 1),
    ("fold-at-booking", "a fold from the booking's upper bound", ← foldAt 1 2),
    ("fold-ending-at-deadline", "a fold whose interval ends exactly at the deadline", ← foldAt 5 6),
    ("fold-ending-after-deadline", "a fold whose interval ends after the deadline", ← foldAt 5 7),
    ("fold-after-deadline", "a fold after the deadline", ← foldAt 6 7),
    ("return-in-window", "a return inside the processing window", .returnRequests ru (withValidity r 3 4)),
    ("return-straddling-deadline", "a return whose interval starts before the deadline",
      .returnRequests ru (withValidity r 5 7)),
    ("return-at-deadline", "a return from the deadline, no signer, the tip as the fee",
      .returnRequests ru r),
    ("return-long-after-deadline", "a return long after the deadline", .returnRequests ru (withValidity r 20 21)),
    ("return-with-signer", "a return carrying a signer: a signature is neither needed nor harmful",
      .returnRequests ru { r with transaction.transaction.signers := [42] }),
    ("return-refund-reduced", "the refund one lovelace short, the spender keeping one more than the tip",
      .returnRequests ru (withRefund r 15 2)),
    ("return-refund-redirected", "the refund paid to the spender's address",
      .returnRequests ru (withRefund r 16 1 (some 7))),
    ("return-refund-above-floor", "the whole contents refunded, the spender keeping nothing",
      .returnRequests ru (withRefund r 17 0)),
    ("return-unbalanced", "a return that does not balance", .returnRequests ru (withRefund r 16 0)),
    ("duplicate-fold", "a fold of a request whose key is already registered",
      .fold s.gen cfg.applicationPolicy pu ptx),
    ("duplicate-return-in-window", "a duplicate's return before its deadline",
      .returnRequests du (withValidity dr 5 6)),
    ("duplicate-return-at-deadline", "a duplicate's return from its deadline, citing the registered key",
      .returnRequests du dr),
    ("duplicate-return-expired", "a duplicate's return from its deadline, citing expiry",
      .returnRequests du de) ]
  let duplicateIds := ["duplicate-fold", "duplicate-return-in-window", "duplicate-return-at-deadline",
    "duplicate-return-expired"]
  pure (regs.map (fun (id, note, action) =>
      { id, note, state := s, reference := if duplicateIds.contains id then d else f, action }) ++
    [{ id := "termination-return", note := "a return naming a pending termination",
       state := c, reference := tb.request.reference, action := .returnRequests cu custodyReturn },
     { id := "termination-fold", note := "the terminating fold of the same pending termination",
       state := c, reference := tb.request.reference, action := .fold c.gen cfg.applicationPolicy tu ttx }])

def table : Except String Json := do
  let rows := (← cases).map row
  pure (Json.mkObj [
    ("description", toJson ("Registration request lifecycle: until the deadline only a fold spends a request; " ++
      "from the deadline anyone returns it, paying the refund address at least the contents less the " ++
      "declared tip. A pending termination is never returned.")),
    ("model", toJson "lean/CardanoKeri/Registry.lean"),
    ("deadline", toJson "the booking's validity upper bound (submittedAt) plus processTime"),
    ("deployment", toJson "retractTime = 0"),
    ("intervals", toJson "lower bound included, upper bound excluded, as the ledger hands them to scripts"),
    ("rows", Json.arr rows.toArray)])

/-! ## Checking a committed table -/

def rowsOf (j : Json) : Except String (Array Json) := do
  match j.getObjVal? "rows" with
  | .ok (.arr rows) => pure rows
  | _ => throw "missing rows"

/-- A committed row equals the Lean's row of the same id. -/
def verifyRow (row : Json) : Except String Unit := do
  let id ← row.getObjValAs? String "id"
  let some c := (← cases).find? (·.id == id) | throw s!"{id}: no such case"
  unless row == CardanoKeri.Registry.LifecycleVectors.row c do throw s!"{id}: differs from the Lean's row"

/-- Every leaf of a row, changed, must fail verification. -/
partial def perturbations (j : Json) : List Json :=
  match j with
  | .num n => [.num { n with mantissa := n.mantissa + 1 }]
  | .str s => [.str (s ++ "-changed")]
  | .bool b => [.bool (!b)]
  | .null => [toJson (1 : Nat)]
  | .arr xs => (List.range xs.size).flatMap fun i =>
      (perturbations xs[i]!).map fun x => .arr (xs.set! i x)
  | .obj kvs => kvs.toList.flatMap fun (k, v) =>
      (perturbations v).map fun x => Json.mkObj ((kvs.toList.map fun (k', v') => (k', if k' == k then x else v')))

def checkTable (j : Json) : Except String (Nat × Nat × Nat) := do
  let committed ← rowsOf j
  let fresh ← table
  unless j == fresh do throw "committed table differs from the Lean's table"
  unless committed.size == (← cases).length do throw "row count differs from the Lean cases"
  let mut fields := 0
  for row in committed do
    verifyRow row
    for changed in perturbations row do
      if (verifyRow changed).toOption.isSome then throw s!"a changed field survived verification: {changed.compress}"
      fields := fields + 1
  let accepted := committed.filter (fun r => (r.getObjValAs? String "verdict").toOption == some "accepted")
  if accepted.size == 0 || accepted.size == committed.size then throw "rows need both verdicts"
  pure (committed.size, accepted.size, fields)

end CardanoKeri.Registry.LifecycleVectors
