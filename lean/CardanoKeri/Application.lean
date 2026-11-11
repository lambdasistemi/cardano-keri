import SingularApplicationHeld.RequestShapes
import CardanoKeri.Registry
import CardanoKeri.ConsumerIdentity

/-! KERI's application on Singular's public application-held model.

The public registry `singular_state(A)` checks, at a fold, that each request
carries the registration approval its holding commits to and that the holding
holds at least the committed deposit. Everything else is the application's:
the configuration record, booking, how a request is spent, and the money a
fold or a return moves. This module states KERI's application `A_keri` against
`models/singular-application-held` at the public pin.

* The configuration record of a registry is minted once, in the registry's
  genesis transaction, at the application address, with `retractTime = 0`.
  A registry whose state policy is not `state(A_keri)` gets none. Besides the
  request parameters it records the credential of the checkpoint validator,
  where the registry's checkpoints live.
* Booking reads the configuration record by reference and mints one
  registration approval. The approval commits the checkpoint validator's
  credential as the holding address, which is not the application's, and the
  deposit, which is the whole carrier the holding will hold; the request holds
  exactly the deposit, the registration cost and the registry's minimum tip.
* Until its deadline a request is spent only by a fold that delivers the
  committed holding, at the checkpoint validator's credential, with exactly
  the deposit, whose datum is exactly the initial state the checkpoint model's
  registration step writes for the request's key. From the deadline anyone may
  return it, paying its refund address everything but the tip.
* A fold's treasury donation is at least the registration costs of the
  requests it folds.
* A conviction leaves the checkpoint's pending output at the checkpoint
  validator's address: a pending-termination datum, exactly the registry's
  minimum ADA and the registry's active token. A termination booking, open to
  anyone, spends that output and mints exactly one termination approval of the
  registry and of the key of the datum's AID; it places the termination
  request at the application address with an empty datum, exactly the active
  token and the approval, holding the economic termination carrier `Mr` plus
  the registry's minimum tip. The booker keeps the rest of the minimum ADA.
  The checkpoint validator releases a pending output only into such a booking
  (`pendingReleased`).
* A termination request has no deadline and is spent only by a fold that
  reads the configuration record by reference and burns its approval and its
  active token; the fold's treasury donation also covers the request's
  lovelace less the minimum tip.
* The whole mint under the application policy is what the actions justify:
  one configuration token per created record, one registration approval per
  distinct booked output, one termination approval per termination booking,
  one approval burned per fold or return, one termination approval burned per
  terminating fold. Each booked output is booked once. `A_keri` mints
  nothing else. A key's termination is booked at most once per transaction:
  each booking requires exactly one approval of its key minted, and a
  terminating fold of the key requires one burned.

The application address holds configuration records and requests only. A
delivered checkpoint lives at the checkpoint validator's address, whose own
spends (advance, conviction, freeze, top-up) the checkpoint and economic models
state, and whose pending output only a termination booking releases; the
application never spends a checkpoint.

The network is not a field of any approval preimage: a Plutus address carries
no network identifier. It is fixed by the chain the transaction runs on, where
the ledger refuses outputs naming another network and the registry seed exists
on one chain only. This is a declared technical boundary of the model. -/
namespace CardanoKeri.Application
open Singular SingularApplicationHeld

/-- KERI's configuration record of a registry: the upstream request
parameters and the credential of the checkpoint validator, where a fold
delivers the registry's checkpoints. -/
structure Configuration where
  parameters : ApplicationParameters
  checkpointCredential : Nat
  deriving Repr, DecidableEq

/-- The interpretation KERI's application runs under: the upstream preimage
codec and hash, the AID key encoding, the request datum decoder, the hash an
approval commits for an initial datum, the configuration record's datum
decoder, the checkpoint datum decoder (the AID and the state facts a version 2
checkpoint datum carries), and the refund address a checkpoint datum records
for a request's refund address (its ledger bytes on the chain the transaction
runs on; `none` when no payable refund can carry it). All are inputs here;
the concrete choices live with the vectors. -/
structure Interpretation where
  hash : Hash
  code : Codec
  keyOf : CardanoKeri.Checkpoint.AID → Key
  decode : DecodeApplication
  datumHash : Nat → Nat
  decodeConfiguration : Nat → Option Configuration
  decodeCheckpoint : Nat → Option CardanoKeri.ConsumerIdentity.DecodedDatum
  refundTo : Nat → Option CardanoKeri.Checkpoint.Addr

/-- The opaque KERI processing premise the economic model already uses: the
key has its inception evidence. A fold delivers a checkpoint only for such a key. -/
structure Env where
  inception : Key → Bool

/-- One KERI registry deployment: the published release of `A_keri` and the
seed its registry state was created from. -/
structure Deployment where
  release : PublishedRelease
  seed : OutRef
  deriving Repr, DecidableEq

/-- The registry this deployment names: the state asset of its seed. -/
def Deployment.registry (i : Interpretation) (d : Deployment) : TokenId :=
  stateAsset i.hash i.code d.release d.seed

/-- The token of a registry's configuration record, under the application policy. -/
def configurationAsset (i : Interpretation) (release : PublishedRelease) (registry : TokenId) :
    TokenId :=
  ⟨release.applicationPolicy, i.hash (i.code (.applicationConfiguration registry))⟩

/-- The registration approval KERI mints for an AID of a deployment. The
network is not an argument: see the module note. -/
def approval (i : Interpretation) (d : Deployment) (aid : CardanoKeri.Checkpoint.AID)
    (address datumHash deposit : Nat) : TokenId :=
  registrationApproval i.hash i.code d.release (d.registry i) (i.keyOf aid) address datumHash deposit

/-- The application's operations, each naming the output it creates or the
input it spends. -/
inductive Action where
  | createConfiguration (registry : TokenId) (seed : OutRef) (index : Nat)
  | bookRegistration (index : Nat)
  | foldRegistration (input : OutRef) (holding : Nat)
  | returnRegistration (input : OutRef)
  | foldTermination (input : OutRef) (registry : TokenId) (key : Key)
  | bookTermination (pending : OutRef) (index : Nat) (registry : TokenId) (key : Key)
  deriving Repr, DecidableEq

def Action.input? : Action → Option OutRef
  | .foldRegistration ref _ | .returnRegistration ref | .foldTermination ref _ _ => some ref
  | _ => none

/-- What the application validator observes of one transaction. -/
structure Observation where
  assets : SingularApplicationHeld.Assets.TxView
  inputs : List ObservedOutput
  outputs : List ObservedOutput
  referenceInputs : List OutRef
  referenceOutputs : List ObservedOutput
  interval : Interval
  donation : Nat
  actions : List Action

/-! ## The configuration record -/

/-- The configuration an output's datum decodes to. -/
def configurationDatum (i : Interpretation) (output : ObservedOutput) : Option Configuration :=
  match output.datum with | .application raw => i.decodeConfiguration raw | _ => none

/-- A configuration record of `registry`: at the application address, with a
configuration datum and exactly its own token. -/
def configurationShape (i : Interpretation) (release : PublishedRelease) (registry : TokenId)
    (output : ObservedOutput) : Bool :=
  output.credential == release.applicationCredential &&
  (configurationDatum i output).isSome &&
  exactAssets output [(configurationAsset i release registry, 1)]

/-- The configuration of `registry`, read by reference from its record. -/
def configurationOf (i : Interpretation) (release : PublishedRelease) (registry : TokenId)
    (o : Observation) : Option Configuration :=
  match o.referenceOutputs.find? (fun c =>
      configurationShape i release registry c && o.referenceInputs.contains c.reference) with
  | some c => configurationDatum i c
  | none => none

/-- A KERI registry has no retraction window. -/
def parametersValid (p : ApplicationParameters) : Bool := p.retractTime == 0

/-- The configuration record is created in the genesis transaction of a
registry whose state policy is `state(A_keri)`: the seed is spent once, the
state policy runs and mints the registry's state token once, and the record
holds valid parameters. -/
def createConfiguration (i : Interpretation) (release : PublishedRelease) (registry : TokenId)
    (seed : OutRef) (output : ObservedOutput) (o : Observation) : Bool :=
  configurationShape i release registry output &&
  (match configurationDatum i output with | some c => parametersValid c.parameters | none => false) &&
  registry.policy == release.statePolicy &&
  registry.name == i.hash (i.code (.state seed)) &&
  o.assets.spent.count seed == 1 &&
  o.assets.invoked.contains release.statePolicy &&
  SingularApplicationHeld.Assets.mintQty o.assets registry == 1 &&
  SingularApplicationHeld.Assets.mintQty o.assets (configurationAsset i release registry) == 1

/-! ## Booking -/

/-- The exact lovelace a booked request holds: the committed deposit, the
registration cost and the registry's minimum tip. -/
def requestLovelace (p : ApplicationParameters) (data : RegistrationData) : Nat :=
  data.deposit + p.registrationCost + p.minimumTip

/-- The booking clock: the request records its booking transaction's
validity upper bound, the interval is no wider than the booking width, and
the deadline is that bound plus the processing time. -/
def bookingClock (p : ApplicationParameters) (data : RegistrationData) (interval : Interval) : Bool :=
  nonemptyInterval interval && data.bookedAt == interval.upper &&
  interval.upper - interval.lower ≤ p.bookingWidth &&
  data.processDeadline == data.bookedAt + p.processTime &&
  data.reclaimEnd == data.processDeadline + p.retractTime

/-- A KERI booking. The request names a registry whose state policy is
`state(A_keri)` and whose configuration record is read by reference; it
commits as the holding address the checkpoint validator's credential that the
record names, which is not the application credential, and a deposit of at
least the registry's minimum ADA plus its deposit; it holds exactly
`requestLovelace`; exactly one approval of its payload is minted. -/
def bookRegistration (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) (o : Observation) (output : ObservedOutput) : Bool :=
  match decoded i.decode output with
  | some (.registration data) =>
    match configurationOf i release data.registry o with
    | some c =>
      registrationShape .none i.hash i.code release output data &&
      data.registry.policy == release.statePolicy &&
      data.holdingAddress == c.checkpointCredential &&
      c.checkpointCredential != release.applicationCredential &&
      rp.Mc + rp.D ≤ data.deposit &&
      output.lovelace == requestLovelace c.parameters data &&
      bookingClock c.parameters data o.interval &&
      SingularApplicationHeld.Assets.mintQty o.assets (registrationAsset i.hash i.code release data) == 1
    | none => false
  | _ => false

/-! ## Spending a request -/

/-- The initial datum hash of a holding, when it carries an application datum. -/
def holdingDatumHash (i : Interpretation) (holding : ObservedOutput) : Option Nat :=
  match holding.datum with | .application raw => some (i.datumHash raw) | _ => none

/-! ## The initial checkpoint state -/

/-- The pool a request's deposit leaves above the registry's minimum ADA, the
checkpoint deposit and the freeze bond; `none` when the deposit does not
cover them. -/
def initialPool (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (data : RegistrationData) : Option CardanoKeri.Checkpoint.Value :=
  if rp.Mc + cp.D + cp.B ≤ data.deposit then some (data.deposit - (rp.Mc + cp.D + cp.B)) else none

/-- The state the checkpoint model's registration step writes for a request
(`Checkpoint.Step.register`, `initialState_is_registration`): live at
sequence number and epoch 0, neither poisoned, frozen nor topped up, born at
the request's booking bound, refunding to `refund`, holding the deposit's
pool, which covers at least one premium. `none` when the pool does not. -/
def initialState (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (refund : CardanoKeri.Checkpoint.Addr) (data : RegistrationData) :
    Option CardanoKeri.Checkpoint.State :=
  match initialPool rp cp data with
  | some pool =>
    if cp.P ≤ pool then some (.present ⟨0, 0, false, false, data.bookedAt, refund, pool, false⟩)
    else none
  | none => none

/-- A holding's datum is exactly the initial state of the request's key: it
decodes as a checkpoint datum of the AID whose key the request names, carrying
the facts of the initial state for the refund address the request names. The
pool is not a datum fact; it is the holding's lovelace above the floor. -/
def writesInitialState (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (data : RegistrationData) (holding : ObservedOutput) : Bool :=
  match holding.datum, i.refundTo data.refundAddress with
  | .application raw, some refund =>
    match i.decodeCheckpoint raw, initialState rp cp refund data with
    | some d, some s => i.keyOf d.aid == data.key && d.state == s.datumFacts
    | _, _ => false
  | _, _ => false

/-- The holding a fold delivers: at the committed address, which is the
checkpoint validator's credential the configuration record names, carrying the
committed initial datum, which is exactly the initial state of the request's
key, holding exactly the committed deposit and the one newly minted active
token of the key. -/
def delivered (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (c : Configuration) (data : RegistrationData)
    (holding : ObservedOutput) (o : Observation) : Bool :=
  let active := activeAsset i.hash i.code data.registry data.key
  holding.credential == data.holdingAddress &&
  holding.credential == c.checkpointCredential &&
  holdingDatumHash i holding == some data.initialDatum &&
  writesInitialState i rp cp data holding &&
  holding.lovelace == data.deposit &&
  quantity holding active == 1 &&
  SingularApplicationHeld.Assets.mintQty o.assets active == 1

/-- A genuine checkpoint of a registration, in the terms the checkpoint
validator and a consumer recognise it by: at the checkpoint validator's
credential the configuration record names, which is not the application
credential; holding the one active token of the request's key under the
registry the request names, whose state policy is `state(A_keri)`; carrying
the committed initial datum; holding exactly the committed deposit. -/
def genuine (i : Interpretation) (release : PublishedRelease) (c : Configuration)
    (data : RegistrationData) (holding : ObservedOutput) : Prop :=
  holding.credential = c.checkpointCredential ∧
  holding.credential ≠ release.applicationCredential ∧
  data.registry.policy = release.statePolicy ∧
  quantity holding (activeAsset i.hash i.code data.registry data.key) = 1 ∧
  holdingDatumHash i holding = some data.initialDatum ∧
  holding.lovelace = data.deposit

/-- The approval the request carries is burned. -/
def approvalBurned (i : Interpretation) (release : PublishedRelease) (data : RegistrationData)
    (o : Observation) : Bool :=
  SingularApplicationHeld.Assets.mintQty o.assets (registrationAsset i.hash i.code release data) == -1

/-- A fold's whole validity interval ends by the request's deadline. -/
def foldWindow (data : RegistrationData) (interval : Interval) : Bool :=
  nonemptyInterval interval && interval.upper ≤ data.processDeadline

/-- A return's whole validity interval starts at the request's deadline or later. -/
def returnWindow (data : RegistrationData) (interval : Interval) : Bool :=
  nonemptyInterval interval && data.processDeadline ≤ interval.lower

/-- The spend of a booked registration request. The configuration record is
read by reference. A fold must end by the deadline, the key must have its
inception evidence, and the holding must be delivered to the checkpoint
validator in its initial state. A return must start at
the deadline or later. With `retractTime = 0` the two windows are the
upstream processing and cleanup phases (`windows_are_upstream_phases`). -/
def spendRegistration (i : Interpretation) (env : Env) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (release : PublishedRelease)
    (o : Observation) (action : Action) (input : ObservedOutput) (data : RegistrationData) : Bool :=
  match configurationOf i release data.registry o with
  | none => false
  | some c =>
    parametersValid c.parameters &&
    registrationShape .none i.hash i.code release input data &&
    approvalBurned i release data o &&
    match action with
    | .foldRegistration _ index =>
      foldWindow data o.interval &&
      env.inception data.key &&
      (match o.outputs[index]? with
        | some holding => delivered i rp cp c data holding o
        | none => false)
    | .returnRegistration _ => returnWindow data o.interval
    | _ => false

/-- The spend of a termination request: only a fold that reads the
configuration record by reference and burns its approval and its active token
with the state policy running. -/
def spendTermination (i : Interpretation) (release : PublishedRelease) (o : Observation)
    (input : ObservedOutput) (registry : TokenId) (key : Key) : Bool :=
  (configurationOf i release registry o).isSome &&
  terminationShape .none i.hash i.code release input registry key &&
  SingularApplicationHeld.Assets.mintQty o.assets (terminationApproval i.hash i.code release registry key) == -1 &&
  SingularApplicationHeld.Assets.mintQty o.assets (activeAsset i.hash i.code registry key) == -1 &&
  o.assets.invoked.contains registry.policy

/-! ## Booking a termination -/

/-- A checkpoint state that is a pending termination. -/
def pendingState : CardanoKeri.Checkpoint.State → Bool
  | .terminationPending _ => true
  | _ => false

/-- The checkpoint datum of an output: its AID and the state facts it carries. -/
def checkpointDatum (i : Interpretation) (output : ObservedOutput) :
    Option CardanoKeri.ConsumerIdentity.DecodedDatum :=
  match output.datum with | .application raw => i.decodeCheckpoint raw | _ => none

/-- The pending output a conviction leaves for `key` of `registry`
(`Checkpoint.Step.convict`, `pending_holds_minimum_ada`): at the checkpoint
validator's credential the configuration record names, carrying the
pending-termination datum of an AID whose key is `key`, holding exactly the
registry's minimum ADA and the one active token of the key. -/
def convictedPending (i : Interpretation) (rp : CardanoKeri.Registry.Params) (c : Configuration)
    (registry : TokenId) (key : Key) (input : ObservedOutput) : Bool :=
  input.credential == c.checkpointCredential &&
  (match checkpointDatum i input with
    | some d => i.keyOf d.aid == key && pendingState d.state
    | none => false) &&
  input.lovelace == rp.Mc &&
  exactAssets input [(activeAsset i.hash i.code registry key, 1)]

/-- The exact lovelace a termination request holds: the economic termination
carrier `Mr` and the registry's minimum tip (`Registry.bookTermination`). -/
def terminationLovelace (rp : CardanoKeri.Registry.Params) (p : ApplicationParameters) : Nat :=
  rp.Mr + p.minimumTip

/-- A termination booking, open to anyone. The configuration record of a
registry whose state policy is `state(A_keri)` is read by reference; the spent
input is the convicted checkpoint's pending output for the key; the placed
output is the termination request (`terminationShape`: the application
address, an empty datum, exactly the active token and the termination
approval) holding exactly `terminationLovelace`; exactly one termination
approval of the registry and key is minted. -/
def bookTermination (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) (o : Observation) (input output : ObservedOutput)
    (registry : TokenId) (key : Key) : Bool :=
  match configurationOf i release registry o with
  | some c =>
    registry.policy == release.statePolicy &&
    convictedPending i rp c registry key input &&
    terminationShape .none i.hash i.code release output registry key &&
    output.lovelace == terminationLovelace rp c.parameters &&
    SingularApplicationHeld.Assets.mintQty o.assets (terminationApproval i.hash i.code release registry key) == 1
  | none => false

/-- The checkpoint validator's one spend of a pending output: the transaction
mints exactly one termination approval of the registry and of the key of the
pending datum's AID. The application policy checks the rest of the booking. -/
def pendingReleased (i : Interpretation) (release : PublishedRelease) (registry : TokenId)
    (input : ObservedOutput) (o : Observation) : Bool :=
  match checkpointDatum i input with
  | some d => pendingState d.state &&
    SingularApplicationHeld.Assets.mintQty o.assets
      (terminationApproval i.hash i.code release registry (i.keyOf d.aid)) == 1
  | none => false

/-- The input an action names, spent exactly once in this transaction. -/
def namedInput (o : Observation) (ref : OutRef) : Option ObservedOutput :=
  if o.assets.spent.count ref == 1 && (o.inputs.filter fun x => decide (x.reference = ref)).length == 1
  then o.inputs.find? (fun x => decide (x.reference = ref)) else none

/-- One action. -/
def action (i : Interpretation) (env : Env) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (release : PublishedRelease) (o : Observation) : Action → Bool
  | .createConfiguration registry seed index => match o.outputs[index]? with
    | some output => createConfiguration i release registry seed output o
    | none => false
  | .bookRegistration index => match o.outputs[index]? with
    | some output => bookRegistration i rp release o output
    | none => false
  | .foldTermination ref registry key => match namedInput o ref with
    | some input => spendTermination i release o input registry key
    | none => false
  | .bookTermination ref index registry key => match namedInput o ref, o.outputs[index]? with
    | some input, some output => bookTermination i rp release o input output registry key
    | _, _ => false
  | a@(.foldRegistration ref _) | a@(.returnRegistration ref) => match namedInput o ref with
    | some input => match decoded i.decode input with
      | some (.registration data) => spendRegistration i env rp cp release o a input data
      | _ => false
    | none => false

/-! ## The money a transaction moves -/

/-- The parameters a spent registration request is paid under, with its data. -/
def spentRequest (i : Interpretation) (release : PublishedRelease) (o : Observation) (ref : OutRef) :
    Option (ObservedOutput × RegistrationData × ApplicationParameters) := do
  let input ← namedInput o ref
  let .registration data ← decoded i.decode input | none
  let c ← configurationOf i release data.registry o
  return (input, data, c.parameters)

/-- Every return pays its refund address everything but the tip. -/
def requiredRefunds (i : Interpretation) (release : PublishedRelease) (o : Observation) :
    List (Nat × Nat) :=
  o.actions.filterMap fun a => match a with
    | .returnRegistration ref => (spentRequest i release o ref).map fun (input, data, p) =>
        (data.refundAddress, input.lovelace - p.minimumTip)
    | _ => none

/-- What a terminating fold owes the treasury: the request's lovelace less the
registry's minimum tip (the economic termination donation). -/
def terminationDonation (i : Interpretation) (release : PublishedRelease) (o : Observation)
    (ref : OutRef) (registry : TokenId) : Option Nat := do
  let input ← namedInput o ref
  let c ← configurationOf i release registry o
  return input.lovelace - c.parameters.minimumTip

/-- What one action owes the treasury: a fold its request's registration cost,
a terminating fold its termination donation. -/
def Action.treasuryDue (i : Interpretation) (release : PublishedRelease) (o : Observation) :
    Action → Option Nat
  | .foldRegistration ref _ => (spentRequest i release o ref).map fun (_, _, p) => p.registrationCost
  | .foldTermination ref registry _ => terminationDonation i release o ref registry
  | _ => none

/-- The registration costs of the requests this transaction folds, and the
termination donations of the termination requests it folds. -/
def requiredTreasury (i : Interpretation) (release : PublishedRelease) (o : Observation) : Nat :=
  (o.actions.filterMap (Action.treasuryDue i release o)).sum

/-- The lovelace the transaction's outputs pay to `address`. -/
def paidTo (outputs : List ObservedOutput) (address : Nat) : Nat :=
  ((outputs.filter fun x => x.credential == address).map (·.lovelace)).sum

/-- Refunds are paid in full per address, and the treasury donation covers
the registration costs and the termination donations. -/
def moneyRouted (i : Interpretation) (release : PublishedRelease) (o : Observation) : Bool :=
  let refunds := requiredRefunds i release o
  refunds.all (fun entry =>
    ((refunds.filter fun other => other.1 == entry.1).map (·.2)).sum ≤ paidTo o.outputs entry.1) &&
  requiredTreasury i release o ≤ o.donation

/-! ## The application's mint -/

/-- The tokens under the application policy one action justifies, with their
quantities: its configuration token, the approval of the request it books, the
termination approval it books, the approval of the request it folds or
returns, or the termination approval it burns. -/
def Action.justifies (i : Interpretation) (release : PublishedRelease) (o : Observation) :
    Action → List (TokenId × Int)
  | .createConfiguration registry _ _ => [(configurationAsset i release registry, 1)]
  | .bookRegistration index => match o.outputs[index]? with
    | some output => match decoded i.decode output with
      | some (.registration data) => [(registrationAsset i.hash i.code release data, 1)]
      | _ => []
    | none => []
  | .foldRegistration ref _ | .returnRegistration ref => match namedInput o ref with
    | some input => match decoded i.decode input with
      | some (.registration data) => [(registrationAsset i.hash i.code release data, -1)]
      | _ => []
    | none => []
  | .foldTermination _ registry key => [(terminationApproval i.hash i.code release registry key, -1)]
  | .bookTermination _ _ registry key => [(terminationApproval i.hash i.code release registry key, 1)]

/-- The output a booking books, a registration's or a termination's. -/
def Action.booking? : Action → Option Nat
  | .bookRegistration index | .bookTermination _ index _ _ => some index
  | _ => none

/-- The outputs the transaction books, in action order. -/
def bookedOutputs (o : Observation) : List Nat := o.actions.filterMap Action.booking?

/-- Each booked output is booked once. -/
def bookedOnce (o : Observation) : Bool := decide (bookedOutputs o).Nodup

/-- The mint the actions justify. With each booked output booked once
(`bookedOnce`), the approvals it mints are one per distinct booked output. -/
def justifiedMint (i : Interpretation) (release : PublishedRelease) (o : Observation) :
    List (TokenId × Int) :=
  o.actions.flatMap (Action.justifies i release o)

/-- The quantity of `asset` the actions justify. -/
def justifiedQty (i : Interpretation) (release : PublishedRelease) (o : Observation)
    (asset : TokenId) : Int :=
  (((justifiedMint i release o).filter fun entry => entry.1 == asset).map (·.2)).sum

/-- The mint under the application policy is exactly the justified mint: every
token minted or justified under it has the justified quantity. -/
def mintClosed (i : Interpretation) (release : PublishedRelease) (o : Observation) : Bool :=
  ((o.assets.mint.map (·.1) ++ (justifiedMint i release o).map (·.1)).filter fun asset =>
      asset.policy == release.applicationPolicy).all fun asset =>
    SingularApplicationHeld.Assets.mintQty o.assets asset == justifiedQty i release o asset

/-- Every input at the application address is named by an action: the
application validator runs for each one it guards. No action names a
checkpoint: checkpoints live at the checkpoint validator's address. -/
def inputsCovered (release : PublishedRelease) (o : Observation) : Bool :=
  o.inputs.all fun input => input.credential != release.applicationCredential ||
    o.actions.any fun a => decide (a.input? = some input.reference)

/-- The application accepts a transaction. -/
def accepted (i : Interpretation) (env : Env) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (release : PublishedRelease) (o : Observation) : Bool :=
  inputsCovered release o && o.actions.all (action i env rp cp release o) && moneyRouted i release o &&
    mintClosed i release o && bookedOnce o

end CardanoKeri.Application
