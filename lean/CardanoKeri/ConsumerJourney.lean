import CardanoKeri.ConsumerFixtures
import CardanoKeri.ConsumerWire
import CardanoKeri.ReaderStatus

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

/-- The termination request a booking places: at the application's
credential, with an empty datum, holding the representative asset and the
termination approval of the registry and key, at the reference the booking
records. -/
def requestHolding (reference : Singular.OutRef) (lovelace : Nat) : AH.ObservedOutput :=
  { reference, credential := context.release.applicationCredential, lovelace, datum := .empty,
    assets := [(representativeAsset interpretation context, 1),
      (SingularApplicationHeld.terminationApproval interpretation.hash interpretation.code
        context.release (registryAsset interpretation context)
        (interpretation.keyOf context.aid), 1)] }

/-- Chosen observation interpretation for current model states. References and
raw datum numbers are fresh fixture labels, not derived ledger artifacts.
Once the termination is booked the holding is the termination request, at the
reference the system records for the booking: the booking spends the
checkpoint. No holding is created for absent or terminal states. -/
def observe (initial : AH.ObservedOutput) (st : State) (pending : Option PendingAssociation)
    (serial : Nat) : Option AH.ObservedOutput :=
  if serial == 0 then some initial
  else match pending with
    | some association => some (requestHolding association.reference initial.lovelace)
    | none =>
      if st.hasOutput then some { initial with
        reference := ⟨1000 + serial, 0⟩, datum := .application (711 + serial) }
      else none

def query (initial : AH.ObservedOutput) (st : State) (pending : Option PendingAssociation)
    (serial now : Nat) : Wire.Query :=
  { tables := tables st (711 + serial), context,
    environment := ⟨context.network, some context.release, some context.checkpointCredential⟩, params := cp, now,
    holding := (observe initial st pending serial).getD { initial with assets := [], datum := .empty } }

def snapshot (name : String) (initial : AH.ObservedOutput) (machine : Machine)
    (serial now : Nat) : Json :=
  let st := machine.certified.state.states context.aid
  let pending := machine.certified.state.pending context.aid
  Json.mkObj [("name", toJson name), ("now", toJson now),
    ("system", stateJson machine), ("holding", toJson (observe initial st pending serial)),
    ("logicalAsset", toJson (heldRepresentative interpretation context st)),
    ("consumer", Wire.cell name (query initial st pending serial now))]

/-- What a reader answers from the holders alone at one frame. -/
def readerAnswer (holders : List AH.ObservedOutput) : ReaderStatus.Status :=
  ReaderStatus.classify interpretation context
    { point := 0,
      environment := ⟨context.network, some context.release, some context.checkpointCredential⟩,
      holding := some { point := 0, asset := representativeAsset interpretation context, holders },
      history := none }

def registrationCommand (q : RegistrationInput) : Command :=
  .register context.aid q.now q.refund q.pool
    ⟨q.registryParams, registryEnvironment, q.configuration⟩
    ⟨[.bookRegistration q.booking], q.unspent, q.economicTx⟩ q.booking q.holdingIndex

def advance (machine : Machine) (command : Command) : Except String Machine := do
  let (next, _, _) ← execute machine cp (evidenceFor [(context.aid, evidence)]) command
  pure next

def localSteps : List (String × Nat × Action) := [
  ("rotate-keep-paid", 8, .rotate 1 .keep 7),
  ("rotate-deposit-paid", 9, .rotate 2 .deposit 7),
  ("rotate-keep-paid-3", 10, .rotate 3 .keep 7),
  ("rotate-keep-paid-4", 11, .rotate 4 .keep 7),
  ("rotate-keep-paid-5", 12, .rotate 5 .keep 7),
  ("frozen", 13, .freeze 6 7),
  ("rotate-keep-unpaid-frozen", 14, .rotate 6 .keep 7),
  ("rotate-deposit-unpaid", 15, .rotate 7 .deposit 7),
  ("poisoned", 16, .poison),
  ("rotate-clears-poison-unpaid", 17, .rotate 8 .keep 7),
  ("refill", 18, .topUp 3)]

structure Journey where
  input : RegistrationInput
  registration : Registered
  registered : Machine
  live : Machine
  pending : Machine
  booked : Machine
  terminal : Machine
  booking : CardanoKeri.Registry.TerminationBooking
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

/-- The checkpoint deployment the journey runs in. -/
def deployment : CardanoKeri.Checkpoint.Deployment := 21

def journey : Except String Journey := do
  let (q, r) ← run
  let registered ← advance (Machine.init deployment) (registrationCommand q)
  unless decide (registered.certified.state.states context.aid = r.checkpoint) do throw "registration-state-disagreement"
  let some origin := registered.certified.state.origins context.aid | throw "registration-origin-missing"
  unless decide (origin.registered = r.after) && origin.token == r.origin.token &&
      origin.carrierRef == r.holding.reference && origin.registrationRef == r.origin.registrationRef do
    throw "registration-origin-disagreement"
  let start := [snapshot "registered-juvenile" r.holding registered 0 5,
    snapshot "registered-mature" r.holding registered 0 6]
  let firstEvent := (SystemWire.cell "register" cp [(context.aid, evidence)] (Machine.init deployment) (registrationCommand q)).1
  let (frames, live, serial, events) ← localSteps.foldlM (fun (frames, machine, serial, events) (name, now, action) => do
    let next ← advance machine (.local context.aid now action)
    unless heldRepresentative interpretation context (next.certified.state.states context.aid) ==
        some (representativeAsset interpretation context) do throw "local-asset-not-retained"
    pure (frames ++ [snapshot name r.holding next serial now], next, serial + 1,
      events ++ [(SystemWire.cell name cp [(context.aid, evidence)] machine (.local context.aid now action)).1]))
      (start, registered, 1, [firstEvent])
  let frames := frames ++ [snapshot "mature" r.holding live serial 35]
  -- The convictor opens a commitment naming the AID, the deployment, the key state
  -- of the mature output and the evidence at
  -- it, then convicts once it is eligible.
  let .present output := live.certified.state.states context.aid | throw "mature-output-missing"
  let some shown := (evidence.toEnv context.aid).evidenceAt context.aid output.epoch output.sn | throw "conviction-evidence-missing"
  let commitment : CardanoKeri.Checkpoint.Commitment := {
    aid := context.aid, deployment, keyState := output.hash, evidence := shown, payee := 7,
    openedAt := 35, eligibleAfter := 36, expiresAt := 50, marker := 1 }
  let committed ← advance live (.openCommitment commitment)
  let pending ← advance committed (.local context.aid 36 (.convict 7 commitment))
  let history : List CardanoKeri.Registry.Action := [.convictCkpt 11]
  let before ← CardanoKeri.Registry.replay q.registryParams q.registryEnv r.after history
  let booking ← CardanoKeri.Registry.Scenarios.termination before context.aid 200 ⟨105, 0⟩ output.hash
  let booked ← advance pending (.book context.aid 7 1 history booking)
  let some association := booked.certified.state.pending context.aid | throw "association-missing"
  -- The booked frame shows the request the booking placed, and a reader answers
  -- pending termination from it and names it.
  let some shownBooked := observe r.holding (booked.certified.state.states context.aid)
    (some association) (serial + 2) | throw "booked-holding-missing"
  unless shownBooked.reference == association.reference do throw "booked-holding-is-not-the-booked-request"
  unless decide (ReaderStatus.custodyOf interpretation context shownBooked = .request) do
    throw "booked-holding-is-not-a-termination-request"
  unless decide (readerAnswer [shownBooked] = .pendingTermination) do
    throw "booked-holding-is-not-answered-pending-termination"
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
    (SystemWire.cell "open-commitment" cp [(context.aid, evidence)] live (.openCommitment commitment)).1,
    (SystemWire.cell "convict" cp [(context.aid, evidence)] committed (.local context.aid 36 (.convict 7 commitment))).1,
    (SystemWire.cell "book" cp [(context.aid, evidence)] pending (.book context.aid 7 1 history booking)).1,
    (SystemWire.cell "pending-rotation-refused" cp [(context.aid, evidence)] booked (.local context.aid 38 (.rotate 11 .keep 7))).1,
    (SystemWire.cell "complete" cp [(context.aid, evidence)] booked (.complete context.aid completion)).1,
    (SystemWire.cell "retired-registration-refused" cp [(context.aid, evidence)] terminal (registrationCommand q)).1,
    (SystemWire.cell "retired-rotation-refused" cp [(context.aid, evidence)] terminal (.local context.aid 42 (.rotate 11 .keep 7))).1]
  pure ⟨q, r, registered, live, pending, booked, terminal, booking, completion, frames, events⟩

end CardanoKeri.ConsumerIdentity.Witness
