import CardanoKeri.CheckpointValueGoals
import CardanoKeri.CheckpointDatumVectors
import CardanoKeri.ConsumerFixtures

/-! Vectors of the checkpoint output's value (#502).

Held rows take the checkpoint states of the datum vectors and give the lovelace
an output in that state holds, the floor below which no pool makes up the
deposit and freeze bond, and what a holding with those datum facts reads as at
lovelace values around them: the state itself only at the held value.
Registration rows run the registry's booking on carriers with different initial
pools and one carrier short by one lovelace. The connected row is the joint
registration fixture. The Aiken work (#339, #343) reproduces them. Checks run the
actual Lean functions; they are evidence over the listed inputs, not a proof over
all inputs. -/
namespace CardanoKeri.CheckpointValue.Vectors
open Lean (Json toJson)
open CardanoKeri.Checkpoint
open CardanoKeri.ConsumerIdentity
open CardanoKeri.CheckpointDatum.Vectors (stateJson natJson rows mutateAt leaves)
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (field str)

/-- The connected fixture's checkpoint parameters: deposit 8, freeze bond 2. -/
def params : Params := CardanoKeri.ConsumerIdentity.Witness.cp

/-- The registry fixture's parameters: minimum ADA 4, deposit 10 = 8 + 2. -/
def registry : CardanoKeri.Registry.Params := CardanoKeri.Registry.Scenarios.p

def heldCases : List (String × State) :=
  CardanoKeri.CheckpointDatum.Vectors.acceptedCases.map fun a => (a.id, a.state)

/-- Lovelace values around the held value and the floor. -/
def probes (s : State) : List Value :=
  let held := s.heldValue params registry
  let floor := s.valueFloor params registry
  ([held, held + 1, held - 1, floor, floor - 1].eraseDups).filter (· ≠ 0)

def readJson : Option State → Json
  | none => Json.null
  | some s => stateJson s

def heldRow (id : String) (s : State) : Json :=
  Json.mkObj [
    ("id", toJson id), ("state", stateJson s),
    ("heldValue", natJson (s.heldValue params registry)),
    ("valueFloor", natJson (s.valueFloor params registry)),
    ("holdings", Json.arr ((probes s).map fun v =>
      let read := s.datumFacts.withValue params registry v
      Json.mkObj [("lovelace", natJson v), ("reads", readJson read),
        ("realizes", toJson (read == some s))]).toArray)]

structure Registration where
  id : String
  note : String
  pool0 : Nat
  short : Bool

def registrationCases : List Registration := [
  ⟨"carrier-empty-pool", "carrier of minimum ADA, deposit and freeze bond only: booked, initial pool 0", 0, false⟩,
  ⟨"carrier-pool-3", "the connected fixture's carrier, initial pool 3: booked", 3, false⟩,
  ⟨"carrier-large-pool", "a carrier with a large initial pool: booked", 5000000, false⟩,
  ⟨"carrier-short-by-one", "a carrier one lovelace short of minimum ADA, deposit and freeze bond: refused", 0, true⟩]

def booking (r : Registration) : Singular.RegistrationBooking :=
  let b := CardanoKeri.Registry.Scenarios.registration
    (CardanoKeri.Registry.Sys.init CardanoKeri.Registry.Scenarios.cfg) 11 100 r.pool0
  if r.short then { b with request.carrierAda := b.request.carrierAda - 1 } else b

def registrationRow (r : Registration) : Json :=
  let b := booking r
  let outcome := match CardanoKeri.Registry.bookRegistration registry
      (CardanoKeri.Registry.Sys.init CardanoKeri.Registry.Scenarios.cfg) b with
    | .ok _ => Json.mkObj [("booked", toJson true),
        ("pool", natJson (b.request.carrierAda - registry.Mc - params.D - params.B))]
    | .error e => Json.mkObj [("booked", toJson false), ("refusal", toJson e)]
  Json.mkObj [("id", toJson r.id), ("note", toJson r.note), ("pool0", natJson r.pool0),
    ("carrierAda", natJson b.request.carrierAda), ("outcome", outcome)]

def connectedRow : Except String Json := do
  let (q, r) ← CardanoKeri.ConsumerIdentity.Witness.run
  pure (Json.mkObj [
    ("carrierAda", natJson q.booking.request.carrierAda), ("pool0", natJson q.pool),
    ("checkpoint", stateJson r.checkpoint),
    ("heldValue", natJson (r.checkpoint.heldValue params registry)),
    ("holdingLovelace", natJson r.holding.lovelace)])

def table : Except String Json := do
  pure (Json.mkObj [
    ("description", toJson ("Vectors of the checkpoint output's value: for each checkpoint state, the " ++
      "lovelace its output holds and the floor of minimum ADA, deposit and freeze bond; what a holding " ++
      "with those datum facts reads as at lovelace values around them; registration carriers booked " ++
      "and refused; and the connected registration fixture.")),
    ("model", toJson "lean/CardanoKeri/CheckpointValue.lean"),
    ("datum", toJson "lean/checkpoint-datum-vectors.json: the same states by id"),
    ("params", Json.mkObj [
      ("checkpoint", Json.mkObj [("D", natJson params.D), ("B", natJson params.B)]),
      ("registry", Json.mkObj [("Mc", natJson registry.Mc), ("D", natJson registry.D)])]),
    ("rules", Json.mkObj [
      ("live", toJson "heldValue = Mc + D + (frozen ? 0 : B) + pool; valueFloor = Mc + D + (frozen ? 0 : B); the pool is lovelace - valueFloor"),
      ("terminationPending", toJson "heldValue = valueFloor = Mc"),
      ("registration", toJson "carrierAda >= Mc + registry D, registry D = D + B; pool0 = carrierAda - Mc - D - B")]),
    ("held", Json.arr (heldCases.map fun (id, s) => heldRow id s).toArray),
    ("registration", Json.arr (registrationCases.map registrationRow).toArray),
    ("connected", ← connectedRow)])

/-! ## Checking a committed table -/

/-- A committed held row equals the Lean's row for its id, and each of its
holdings realizes the state exactly when it reads as the committed state. -/
def verifyHeld (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some (_, s) := heldCases.find? (·.1 == id) | throw s!"{id}: no such held case"
  unless row == heldRow id s do throw s!"{id}: differs from the Lean's row"
  match ← field row ["holdings"] with
  | .arr hs => for h in hs do
      let realizes ← field h ["realizes"]
      unless realizes == toJson ((← field h ["reads"]) == (← field row ["state"])) do
        throw s!"{id}: a holding's verdict disagrees with its reading"
  | _ => throw s!"{id}: no holdings"

def verifyRegistration (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some r := registrationCases.find? (·.id == id) | throw s!"{id}: no such registration case"
  unless row == registrationRow r do throw s!"{id}: differs from the Lean's row"

def verifyConnected (row : Json) : Except String Unit := do
  unless row == (← connectedRow) do throw "connected: differs from the Lean's row"
  unless (← field row ["heldValue"]) == (← field row ["holdingLovelace"]) do
    throw "connected: the holding does not hold the registered state's value"

/-- Every leaf of every committed row except the free-text `id` and `note`,
changed in turn, must fail its row's verification. -/
def fieldControls (rs : Array Json) (verify : Json → Except String Unit) : Except String Nat := do
  let mut count := 0
  for row in rs do
    for path in leaves row [] do
      if path == ["id"] || path == ["note"] then continue
      match verify (mutateAt row path) with
      | .ok () => throw s!"changing {path} of a row still verifies"
      | .error _ => count := count + 1
  pure count

def checkTable (j : Json) : Except String (Nat × Nat × Nat × Nat) := do
  let held ← rows j "held"
  let registration ← rows j "registration"
  unless held.size == heldCases.length do throw "held count differs from the Lean cases"
  unless registration.size == registrationCases.length do
    throw "registration count differs from the Lean cases"
  for row in held do verifyHeld row
  for row in registration do verifyRegistration row
  let connected ← field j ["connected"]
  verifyConnected connected
  let holdings := held.foldl (fun n row => match row.getObjVal? "holdings" with
    | .ok (.arr hs) => n + hs.size | _ => n) 0
  let fields := (← fieldControls held verifyHeld) + (← fieldControls registration verifyRegistration) +
    (← fieldControls #[connected] verifyConnected)
  pure (held.size, holdings, registration.size, fields)

end CardanoKeri.CheckpointValue.Vectors
