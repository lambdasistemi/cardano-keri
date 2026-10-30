import CardanoKeri.ConsumerFixtures
import CardanoKeri.ConsumerWire

/-! Connected model journey, beginning with actual genesis and both registration
folds. Local holding observations use an explicit finite datum interpretation;
this is not a physical ledger observer or a proof of datum/value correspondence.
The accepted certificate interpreter supplies every system transition. -/
namespace CardanoKeri.ConsumerIdentity.Witness
open Lean (Json toJson)
open CardanoKeri.Checkpoint SystemWire

/-- Every naming lookup needed by the fixed consumer is recorded explicitly. -/
def tables (st : State) (raw : Nat := 711) : Wire.Tables :=
  let domain : List AH.Preimage := [.state context.seed,
    .active (registryAsset interpretation context) (interpretation.keyOf context.aid)]
  { keys := [(context.aid, interpretation.keyOf context.aid)]
    codes := domain.map fun p => (p, interpretation.code p)
    hashes := domain.map fun p => (interpretation.code p, interpretation.hash (interpretation.code p))
    datums := [(context.release, raw, ⟨context.aid, st⟩)] }

/-- Chosen observation interpretation for current model states. References and
raw datum numbers are fresh fixture labels, not derived ledger artifacts.
No holding is created for absent or terminal states. -/
def observe (initial : AH.ObservedOutput) (st : State) (serial : Nat) : Option AH.ObservedOutput :=
  if serial == 0 then some initial
  else if st.hasOutput then some { initial with
    reference := ⟨1000 + serial, 0⟩, datum := .application (711 + serial) }
  else none

def query (initial : AH.ObservedOutput) (st : State) (serial now : Nat) : Wire.Query :=
  { tables := tables st (711 + serial), context,
    environment := ⟨context.network, some context.release⟩, params := cp, now,
    holding := (observe initial st serial).getD { initial with assets := [], datum := .empty } }

def snapshot (name : String) (initial : AH.ObservedOutput) (machine : Machine)
    (serial now : Nat) : Json :=
  let st := machine.certified.state.states context.aid
  Json.mkObj [("name", toJson name), ("now", toJson now),
    ("system", stateJson machine), ("holding", toJson (observe initial st serial)),
    ("logicalAsset", toJson (heldRepresentative interpretation context st)),
    ("consumer", Wire.cell name (query initial st serial now))]

def registrationCommand (q : RegistrationInput) : Command :=
  .register context.aid q.now q.refund q.pool
    ⟨q.registryParams, registryEnvironment, q.configuration⟩
    ⟨[.bookRegistration q.booking], q.unspent, q.economicTx⟩ q.booking q.holdingIndex

def advance (machine : Machine) (command : Command) : Except String Machine := do
  let (next, _, _) ← execute machine cp ce command
  pure next

def localSteps : List (String × Nat × Action) := [
  ("rotate-keep-paid", 8, .rotate 1 .keep 7 none),
  ("rotate-deposit-paid", 9, .rotate 2 .deposit 7 none),
  ("rotate-keep-paid-3", 10, .rotate 3 .keep 7 none),
  ("rotate-keep-paid-4", 11, .rotate 4 .keep 7 none),
  ("rotate-keep-paid-5", 12, .rotate 5 .keep 7 none),
  ("frozen", 13, .freeze 6 7),
  ("rotate-keep-unpaid-frozen", 14, .rotate 6 .keep 7 none),
  ("rotate-deposit-unpaid", 15, .rotate 7 .deposit 7 none),
  ("poisoned", 16, .poison),
  ("rotate-clears-poison-unpaid", 17, .rotate 8 .keep 7 none),
  ("refill", 18, .topUp 3)]

structure Journey where
  input : RegistrationInput
  registration : Registered
  registered : Machine
  live : Machine
  pending : Machine
  booked : Machine
  terminal : Machine
  booking : Singular.TerminationBooking
  completion : FoldCertificate
  frames : List Json
  events : List Json

/-- Reuse the actual previous registry state's reference in the next economic
fold observation. The generic assembler allocates isolated references; this
adapter connects them before either acceptance judgement runs. -/
def connectStateReference (reference : Singular.OutRef) (u : Singular.EconomicUtxo)
    (tx : Singular.EconomicTransaction) : Except String (Singular.EconomicUtxo × Singular.EconomicTransaction) := do
  let some old := u.find? (fun item => item.2.output.role == .state) | throw "state-input-missing"
  let mapped := u.map fun item => if item.1 == old.1 then (reference, item.2) else item
  let inputs := tx.transaction.inputs.map fun input =>
    if input.ref == some old.1 then { input with ref := some reference } else input
  pure (mapped, { tx with transaction.inputs := inputs })

def journey : Except String Journey := do
  let (q, r) ← run
  let registered ← advance Machine.init (registrationCommand q)
  unless decide (registered.certified.state.states context.aid = r.checkpoint) do throw "registration-state-disagreement"
  let some origin := registered.certified.state.origins context.aid | throw "registration-origin-missing"
  unless decide (origin.registered = r.after) && origin.token == r.origin.token &&
      origin.carrierRef == r.holding.reference && origin.registrationRef == r.origin.registrationRef do
    throw "registration-origin-disagreement"
  let start := [snapshot "registered-juvenile" r.holding registered 0 6,
    snapshot "registered-mature" r.holding registered 0 7]
  let firstEvent := (SystemWire.cell "register" cp evidence Machine.init (registrationCommand q)).1
  let (frames, live, serial, events) ← localSteps.foldlM (fun (frames, machine, serial, events) (name, now, action) => do
    let next ← advance machine (.local context.aid now action)
    unless heldRepresentative interpretation context (next.certified.state.states context.aid) ==
        some (representativeAsset interpretation context) do throw "local-asset-not-retained"
    pure (frames ++ [snapshot name r.holding next serial now], next, serial + 1,
      events ++ [(SystemWire.cell name cp evidence machine (.local context.aid now action)).1]))
      (start, registered, 1, [firstEvent])
  let frames := frames ++ [snapshot "mature" r.holding live serial 35]
  let pending ← advance live (.local context.aid 36 (.convict 7))
  let history : List CardanoKeri.Registry.Action := [.convictCkpt 11]
  let before ← CardanoKeri.Registry.replay q.registryParams q.registryEnv r.after history
  let booking ← CardanoKeri.Registry.Scenarios.termination before context.aid 200
  let booked ← advance pending (.book context.aid 7 1 history booking)
  let some association := booked.certified.state.pending context.aid | throw "association-missing"
  let (u, tx) ← S.foldTransaction association.booked [booking.request.reference] 40 1 1
  let (u, tx) ← connectStateReference q.fullFold.after.state.reference u tx
  let completion : FoldCertificate := ⟨[], u, tx⟩
  let terminal ← advance booked (.complete context.aid completion)
  unless decide (terminal.certified.state.states context.aid = .convicted) &&
      decide (terminal.certified.state.leaves context.aid = .retired) do throw "completion-not-terminal"
  let frames := frames ++ [snapshot "termination-pending" r.holding pending (serial + 1) 36,
    snapshot "termination-booked" r.holding booked (serial + 2) 37,
    snapshot "retired-after-matching-fold" r.holding terminal (serial + 3) 40]
  let events := events ++ [
    (SystemWire.cell "convict" cp evidence live (.local context.aid 36 (.convict 7))).1,
    (SystemWire.cell "book" cp evidence pending (.book context.aid 7 1 history booking)).1,
    (SystemWire.cell "pending-rotation-refused" cp evidence booked (.local context.aid 38 (.rotate 11 .keep 7 none))).1,
    (SystemWire.cell "complete" cp evidence booked (.complete context.aid completion)).1,
    (SystemWire.cell "retired-registration-refused" cp evidence terminal (registrationCommand q)).1,
    (SystemWire.cell "retired-rotation-refused" cp evidence terminal (.local context.aid 42 (.rotate 11 .keep 7 none))).1]
  pure ⟨q, r, registered, live, pending, booked, terminal, booking, completion, frames, events⟩

end CardanoKeri.ConsumerIdentity.Witness
