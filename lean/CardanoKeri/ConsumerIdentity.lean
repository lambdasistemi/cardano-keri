import CardanoKeri.Checkpoint
import SingularApplicationHeld.Core

/-! Consumer identity and a bounded joint registration bridge.
The two upstream identity domains are deliberately not equated. The hash,
codec, AID-key mapping, datum decoder and externally validated environment
are interpretation inputs, not supplied by the candidate output.
No concrete bytes, cryptographic implementation, discovery or expiry law. -/
namespace CardanoKeri.ConsumerIdentity
open CardanoKeri.Checkpoint
namespace AH
export SingularApplicationHeld (PublishedRelease Preimage Codec Hash ObservedOutput
  stateAsset activeAsset quantity FiniteEncoding FiniteCollisionFree)
end AH

structure DecodedDatum where
  aid : AID
  state : State
  deriving Repr, DecidableEq

/-- The facts a checkpoint datum carries about a state. The premium pool is an
amount held in the output's value, not a datum fact, so it is set to zero; the
amounts are the separately named value obligation of `realizesState`. -/
def _root_.CardanoKeri.Checkpoint.State.datumFacts : State → State
  | .present l => .present { l with pool := 0 }
  | s => s

/-- A decoded datum with only its datum facts. -/
def DecodedDatum.facts (d : DecodedDatum) : DecodedDatum := { d with state := d.state.datumFacts }

structure Interpretation where
  hash : AH.Hash
  code : AH.Codec
  keyOf : AID → Singular.Key
  decode : AH.PublishedRelease → Nat → Option DecodedDatum

/-- Established by the relying contract, independently of the output. -/
structure Context where
  network : Nat
  release : AH.PublishedRelease
  seed : Singular.OutRef
  aid : AID
  deriving Repr, DecidableEq

/-- The actual network and the release resolved by the trusted integration.
Neither is a field read from an unauthenticated candidate datum. `none`
means unresolved release and fails closed. This type is an observation
boundary, not a proof that a provider or release resolver is correct. -/
structure Environment where
  network : Nat
  release : Option AH.PublishedRelease
  deriving Repr, DecidableEq

def registryAsset (i : Interpretation) (c : Context) : Singular.TokenId :=
  AH.stateAsset i.hash i.code c.release c.seed

def representativeAsset (i : Interpretation) (c : Context) : Singular.TokenId :=
  AH.activeAsset i.hash i.code (registryAsset i c) (i.keyOf c.aid)

def decoded (i : Interpretation) (c : Context) (o : AH.ObservedOutput) : Option DecodedDatum :=
  match o.datum with
  | .application raw => i.decode c.release raw
  | _ => none

def authenticatedContext (c : Context) (e : Environment) : Prop :=
  e.network = c.network ∧ e.release = some c.release

def authenticatedContextB (c : Context) (e : Environment) : Bool :=
  e.network == c.network && e.release == some c.release

/-- All previous lifecycle clauses survive in the unchanged predicate. -/
def consumableHolding (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) : Prop :=
  authenticatedContext c e ∧
  o.credential = c.release.applicationCredential ∧
  AH.quantity o (representativeAsset i c) = 1 ∧
  match decoded i c o with
  | none => False
  | some d => d.aid = c.aid ∧ consumableState p now d.state

def consumableHoldingB (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) : Bool :=
  authenticatedContextB c e &&
  o.credential == c.release.applicationCredential &&
  AH.quantity o (representativeAsset i c) == 1 &&
  match decoded i c o with
  | none => false
  | some d => d.aid == c.aid && consumableStateB p now d.state

/-- Logical asset custody observation only: it does not manufacture a ledger
UTxO or turn an Origin's registration reference into a current reference. -/
def heldRepresentative (i : Interpretation) (c : Context) (s : State) :
    Option Singular.TokenId :=
  if s.hasOutput then some (representativeAsset i c) else none

/-- Explicit interpretation of the reduced economic model's registry id.
Neither the allocated alias origin.token nor Config.stateToken.name is used
as the full Active asset name. This relation establishes no full machine
correspondence between the imported economic and application-held models. -/
def originBinding (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (origin : Origin) : Prop :=
  origin.configuration.registryId = abstractRegistry (registryAsset i c) ∧
  origin.configuration.applicationPolicy = c.release.applicationPolicy ∧
  origin.configuration.activePolicy = c.release.statePolicy

/-- Finitely scoped premises for separating two registries' active names.
The domain is in the type, including both State and both Active preimages. -/
def identityDomain (i : Interpretation) (c d : Context) : List AH.Preimage :=
  [.state c.seed, .state d.seed,
   .active (registryAsset i c) (i.keyOf c.aid),
   .active (registryAsset i d) (i.keyOf d.aid)]

/-- Refinement boundary for a current ledger holding. Caller must establish it
from a complete actual observation and the selected decoder, not old Origin
metadata. The datum carries the state's facts only (`State.datumFacts`): the
premium pool and the bond amounts are held in the output's value, and reading
them from the value is a separate named obligation. -/
def realizesState (i : Interpretation) (c : Context) (s : State)
    (o : AH.ObservedOutput) : Prop :=
  o.credential = c.release.applicationCredential ∧
  AH.quantity o (representativeAsset i c) = s.representativeHeld ∧
  (decoded i c o).map DecodedDatum.facts = some ⟨c.aid, s.datumFacts⟩

/-- Faithfulness is a separate finite premise; originBinding alone does not
prove that a consumer-allocated abstract registry id distinguishes registries. -/
def faithfulRegistryMap (abstractRegistry : Singular.TokenId → Nat)
    (domain : List Singular.TokenId) : Prop :=
  ∀ r ∈ domain, ∀ s ∈ domain, abstractRegistry r = abstractRegistry s → r = s

/-- Creation bridge preserves the two models' different root representations.
The economic parameters are a trusted input, not read from a candidate holding. -/
def configBinding (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (cfg : Singular.Config) : Bool :=
  cfg.registryId == abstractRegistry (registryAsset i c) &&
  cfg.applicationPolicy == c.release.applicationPolicy &&
  cfg.activePolicy == c.release.statePolicy

structure CreatedRegistry where
  full : SingularApplicationHeld.PublicRegistry
  economic : CardanoKeri.Registry.Sys
  deriving DecidableEq

/-- Execute actual imported genesis, select its actual state output, then
initialize the unchanged economic model. This bounded representation bridge
is not a general equivalence of ledger machines or request economics. -/
def createRegistry (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (cfg : Singular.Config)
    (commit : SingularApplicationHeld.TrieCommit)
    (tx : SingularApplicationHeld.Assets.TxView) (outputs : List AH.ObservedOutput) :
    Except String CreatedRegistry := do
  if !configBinding i c abstractRegistry cfg then throw "configuration-identity-mismatch"
  if !SingularApplicationHeld.genesis .none i.hash i.code commit c.release c.seed tx outputs then
    throw "genesis-refused"
  let some state := outputs.find? (fun o => AH.quantity o (registryAsset i c) > 0)
    | throw "genesis-state-missing"
  pure {
    full := { identity := registryAsset i c, seed := c.seed, state := state, trie := [] }
    economic := CardanoKeri.Registry.Sys.init cfg }

/-- Bounded one-registration witness input. All fields are actual observations
or the already selected model contexts; no consumer acceptance field exists. -/
structure RegistrationInput where
  registryParams : CardanoKeri.Registry.Params
  registryEnv : CardanoKeri.Registry.Env
  configuration : Singular.Config
  checkpointParams : Params
  checkpointEnv : Env
  now : Slot
  refund : Addr
  pool : Value
  genesisTx : SingularApplicationHeld.Assets.TxView
  genesisOutputs : List AH.ObservedOutput
  booking : Singular.RegistrationBooking
  unspent : Singular.EconomicUtxo
  economicTx : Singular.EconomicTransaction
  fullFold : SingularApplicationHeld.FoldObservation
  holdingIndex : Nat

/-- Exact shared value observations. Neither fold can hide a changed request
input amount, output amount, donation, fee, or validity interval behind a
successful identity comparison. Additional tokens use different abstractions. -/
def moneyAgreementB (q : RegistrationInput) : Bool :=
  q.fullFold.assets.spent == q.economicTx.transaction.inputs.filterMap (·.ref) &&
  q.economicTx.transaction.inputs.length ==
    (q.economicTx.transaction.inputs.filterMap (·.ref)).length &&
  q.fullFold.spentOutputs.map (fun o => (o.reference, o.lovelace)) ==
    (q.unspent.filter fun item => Singular.inputsContainReference
      q.economicTx.transaction.inputs item.1).map (fun item => (item.1, item.2.output.lovelace)) &&
  q.fullFold.outputs.map (·.lovelace) == q.economicTx.outputs.map (fun o => o.output.lovelace) &&
  q.fullFold.fee == q.economicTx.transaction.fee &&
  q.fullFold.donation == q.economicTx.transaction.donation &&
  some q.fullFold.interval == q.economicTx.transaction.validity

/-- A single selected registration, with all identity/data/value links checked
against the actual two transaction observations. This does not compare opaque
root bytes or claim equivalence for arbitrary batches. -/
def registrationAgreementB (i : Interpretation) (c : Context) (q : RegistrationInput)
    (created : CreatedRegistry) (booked after : CardanoKeri.Registry.Sys)
    (st : State) (o : AH.ObservedOutput) (eo : Singular.EconomicOutput) : Bool :=
  q.fullFold.before == created.full &&
  q.fullFold.before.trie == booked.trie.map (fun entry => (i.keyOf entry.1, entry.2)) &&
  q.fullFold.after.trie == after.trie.map (fun entry => (i.keyOf entry.1, entry.2)) &&
  q.booking.request.key == c.aid &&
  q.fullFold.changes == [.register q.booking.request.reference (i.keyOf c.aid)
    q.holdingIndex q.booking.request.carrierAda] &&
  (Singular.foldMembers booked.toWorld q.economicTx).contains (.registration q.booking) &&
  q.fullFold.outputs[q.holdingIndex]? == some o &&
  q.economicTx.outputs[q.holdingIndex]? == some eo &&
  o.reference == Singular.OutRef.mk q.economicTx.identity q.holdingIndex &&
  o.credential == q.booking.request.destination &&
  o.credential == c.release.applicationCredential &&
  eo.output.address == some q.booking.request.destination &&
  eo.output.datumValue == q.booking.request.datum &&
  eo.output.lovelace == q.booking.request.carrierAda &&
  eo.singularTags == [booked.config.singularTag c.aid] &&
  o.lovelace == q.booking.request.carrierAda &&
  (match o.datum, q.booking.request.datum with
    | .application raw, some expected => raw == expected
    | _, _ => false) &&
  AH.quantity o (representativeAsset i c) == 1 &&
  decide ((decoded i c o).map DecodedDatum.facts = some ⟨c.aid, st.datumFacts⟩) &&
  moneyAgreementB q

structure Registered where
  created : CreatedRegistry
  booked : CardanoKeri.Registry.Sys
  after : CardanoKeri.Registry.Sys
  registrationFlow : CardanoKeri.Registry.Flow
  foldFlow : CardanoKeri.Registry.Flow
  checkpointFlow : Flow
  checkpoint : State
  holding : AH.ObservedOutput
  economicHolding : Singular.EconomicOutput
  origin : Origin

/-- The actual imported genesis, old book/fold and new identity fold all run.
A relation failure is an error, never a passing technical-gap row. -/
def registerJoint (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (commit : SingularApplicationHeld.TrieCommit)
    (q : RegistrationInput) : Except String Registered := do
  let created ← createRegistry i c abstractRegistry q.configuration commit q.genesisTx q.genesisOutputs
  let (registrationFlow, booked) ← CardanoKeri.Registry.bookRegistration
    q.registryParams created.economic q.booking
  let (foldFlow, after) ← CardanoKeri.Registry.fold q.registryParams q.registryEnv
    booked booked.gen booked.config.applicationPolicy q.unspent q.economicTx
  if !SingularApplicationHeld.fold .none i.hash i.code commit c.release q.fullFold then
    throw "full-identity-fold-refused"
  let some (checkpointFlow, st) := stepFn q.checkpointParams q.checkpointEnv
    (.register q.refund q.pool) q.now .absent | throw "checkpoint-registration-refused"
  let some o := q.fullFold.outputs[q.holdingIndex]? | throw "full-holding-missing"
  let some eo := q.economicTx.outputs[q.holdingIndex]? | throw "economic-holding-missing"
  if !registrationAgreementB i c q created booked after st o eo then
    throw "registration-correspondence-mismatch"
  let some token := CardanoKeri.Registry.bindingAt after c.aid | throw "origin-binding-missing"
  let origin : Origin := {
    parameters := q.registryParams, environment := q.registryEnv,
    configuration := q.configuration, registered := after,
    token := token, registrationRef := q.booking.request.reference,
    carrierRef := ⟨q.economicTx.identity, q.holdingIndex⟩ }
  pure {
    created := created, booked := booked, after := after,
    registrationFlow := registrationFlow, foldFlow := foldFlow,
    checkpointFlow := checkpointFlow, checkpoint := st, holding := o,
    economicHolding := eo, origin := origin }

end CardanoKeri.ConsumerIdentity
