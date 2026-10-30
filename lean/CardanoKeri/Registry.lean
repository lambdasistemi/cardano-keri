import Singular.Statements.FoldAccounting
import Singular.Statements.FoldTermination

/-! Registry adapter: a checkpoint is live until convicted; there is no owner exit. Generic booking and fold economics execute the pinned Singular model. Local evidence remains the named coarse Registry abstraction. -/
namespace CardanoKeri.Registry
structure Params where
  D : Nat
  tip : Nat
  Mc : Nat
  Mr : Nat
  hD : 0 < D
  hFund : Mr + tip ≤ Mc
-- Named opaque premises; no claim of equivalence with Checkpoint's concrete
-- evidence or signature checks.
structure Env where
  inception : Nat → Bool
  duplicity : Nat → Nat → Bool

inductive CkState where
  | live
  | terminationPending
  deriving DecidableEq, BEq

structure Carrier where
  aid : Nat
  token : Nat
  original : Singular.Holding
  k : Nat
  st : CkState
  minAda : Nat
  deriving DecidableEq

structure TerminationPayload where
  aid : Nat
  token : Nat
  keyState : Nat
  original : Singular.Holding
  booker : Nat
  bookingFee : Nat
  deriving DecidableEq

structure TerminationEntry where
  booking : Singular.TerminationBooking
  payload : TerminationPayload
  deriving DecidableEq

structure Sys where
  gen : Nat
  config : Singular.Config
  trie : Singular.Trie
  carriers : List Carrier
  registrations : List Singular.RegistrationBooking
  terminations : List TerminationEntry
  treasury : Nat
  bindings : List (Nat × Nat)
  nextToken : Nat
  deriving DecidableEq

def Sys.toWorld (s : Sys) : Singular.World :=
  { registry := { config := s.config, trie := s.trie,
                  held := s.carriers.map (·.original) },
    pending := s.registrations,
    terminations := s.terminations.map (·.booking), treasury := s.treasury }

def Sys.init (c : Singular.Config) : Sys :=
  { gen := 0, config := { c with root := Singular.rootOf [] }, trie := [],
    carriers := [], registrations := [], terminations := [], treasury := 0,
    bindings := [], nextToken := 0 }

def carrierAt (s : Sys) (aid : Nat) : Option Carrier :=
  s.carriers.find? (fun c => c.aid == aid)

def pendingAt (s : Sys) (ref : Singular.OutRef) : Option TerminationEntry :=
  s.terminations.find? (fun e => e.booking.request.reference == ref)

def bindingAt (s : Sys) (aid : Nat) : Option Nat :=
  (s.bindings.find? (fun e => e.1 == aid)).map Prod.snd

def minAdaAt (s : Sys) (aid : Nat) : Nat :=
  ((carrierAt s aid).map (·.minAda)).getD 0

-- Bond movement inside a checkpoint conviction remains the Checkpoint
-- abstraction's addressed flow. This Registry flow is not a claim of total
-- application ADA conservation across that internal event.
structure Flow where
  deposited : Nat := 0
  locked : List (Nat × Nat) := []
  bondReturn : Option (Nat × Nat) := none
  premium : Option (Nat × Nat) := none
  intoRequest : Nat := 0
  bookingFee : Nat := 0
  deriving DecidableEq

abbrev Result := Flow × Sys

def registrationShape (p : Params) (b : Singular.RegistrationBooking) : Prop :=
  b.request.carrierAda = p.Mc + p.D ∧ b.request.declaredTip = p.tip

instance (p : Params) (b : Singular.RegistrationBooking) :
    Decidable (registrationShape p b) :=
  inferInstanceAs (Decidable (_ ∧ _))

def bookRegistration (p : Params) (s : Sys)
    (b : Singular.RegistrationBooking) : Except String Result := do
  if ¬ registrationShape p b then throw "keri-registration-value-mismatch"
  let world ← Singular.book s.toWorld b
  let after := { s with registrations := b :: s.registrations }
  if after.toWorld ≠ world then throw "keri-registration-reconstruction-mismatch"
  pure ({ deposited := b.request.contents.lovelace }, after)

-- Rename the old tomb stage to explicit pending: it is an extant convicted
-- carrier awaiting booking, not a retired registry key. This retains the
-- two-stage transport boundary and does not invent atomic CP equivalence.
def convictCkpt (env : Env) (s : Sys) (aid : Nat) : Except String Result := do
  let some c := carrierAt s aid | throw "keri-carrier-missing"
  if c.st == .terminationPending || env.duplicity aid c.k != true then
    throw "keri-conviction-refused"
  let carriers := s.carriers.map (fun old =>
    if old.aid == aid then { old with st := .terminationPending } else old)
  pure ({}, { s with carriers := carriers })

def bookTermination (p : Params) (s : Sys)
    (aid booker fee : Nat) (b : Singular.TerminationBooking) : Except String Result := do
  let some c := carrierAt s aid | throw "keri-carrier-missing"
  if c.st != .terminationPending then throw "keri-conviction-required"
  if ¬ (b.request.key = aid ∧ b.request.destination = c.original.output ∧
      b.custodyInputs = [c.original] ∧ c.minAda = p.Mc ∧
      b.request.carrierAda = p.Mr ∧ b.request.declaredTip = p.tip ∧
      b.request.contents.lovelace = p.Mr + p.tip) then
    throw "keri-termination-binding-mismatch"
  let world ← Singular.bookTermination s.toWorld b
  let e : TerminationEntry := { booking := b, payload := {
    aid := aid, token := c.token, keyState := c.k, original := c.original,
    booker := booker, bookingFee := fee } }
  let after := { s with
    carriers := s.carriers.filter (fun old => old.aid != aid),
    terminations := e :: s.terminations }
  if after.toWorld ≠ world then throw "keri-termination-reconstruction-mismatch"
  pure ({
    premium := some (booker, p.Mc - p.Mr - p.tip),
    bookingFee := fee, intoRequest := p.Mr + p.tip }, after)

-- Inception stays a KERI processing guard, as in the existing coarse model.
-- A generic application approval does not stand in for that premise.
def registrationsAuthorized (env : Env) (members : List Singular.FoldMember) : Bool :=
  members.all (fun m => match m with
    | .registration b => env.inception b.request.key
    | .termination _ => true)

def installMember (p : Params) (before : Sys) (acc : Sys)
    (member : Singular.FoldMember) : Except String Sys := do
  letI : BEq Singular.RegistrationBooking := instBEqOfDecidableEq
  match member with
  | .termination b => do
    let some e := pendingAt before b.request.reference
      | throw "keri-termination-metadata-missing"
    if e.booking ≠ b then throw "keri-termination-metadata-mismatch"
    pure acc
  | .registration b => do
    if b ∉ before.registrations then throw "keri-registration-metadata-missing"
    let c : Carrier := {
      aid := b.request.key, token := acc.nextToken,
      original := { key := b.request.key, kind := .active,
                    output := b.request.destination, datum := b.request.datum },
      k := 0, st := .live, minAda := p.Mc }
    pure { acc with
      carriers := c :: acc.carriers,
      bindings := (c.aid, c.token) :: acc.bindings, nextToken := acc.nextToken + 1 }

def foldResult (p : Params) (s : Sys) (tx : Singular.EconomicTransaction)
    (world : Singular.World) : Except String Result := do
  let members := Singular.foldMembers s.toWorld tx
  let acc ← members.foldlM (installMember p s) s
  let after := { acc with
    gen := s.gen + 1,
    config := world.registry.config, trie := world.registry.trie, treasury := world.treasury,
    registrations := s.registrations.filter (fun b =>
      !Singular.inputsContainReference tx.transaction.inputs b.request.reference),
    terminations := s.terminations.filter (fun e =>
      !Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference) }
  if after.toWorld ≠ world then throw "keri-fold-reconstruction-mismatch"
  let locked := members.filterMap (fun m => match m with
    | .registration b => some (b.request.key, p.D)
    | .termination _ => none)
  pure ({ locked := locked }, after)

def fold (p : Params) (env : Env) (s : Sys) (expectedGen expectedPlugin : Nat)
    (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) : Except String Result := do
  if expectedGen != s.gen then throw "keri-generation-mismatch"
  if expectedPlugin != s.config.applicationPolicy then throw "keri-plugin-mismatch"
  let members := Singular.foldMembers s.toWorld tx
  if !registrationsAuthorized env members then throw "keri-inception-refused"
  let world ← Singular.foldAccepted s.toWorld u tx
  foldResult p s tx world

-- These wrappers expose only the already imported generic recovery judgment.
-- They do not claim to discharge broader KERI application recovery in #468,
-- nor inherit legacy Registry recovery statements by sharing a name.
def recoverRegistrations (s : Sys) (world : Singular.World) : Except String Sys := do
  let after := { s with registrations := s.registrations.filter (fun b =>
    world.pending.contains b) }
  if after.toWorld ≠ world then throw "keri-recovery-reconstruction-mismatch"
  pure after

def genericRetraction (s : Sys) (u : Singular.EconomicUtxo)
    (tx : Singular.EconomicTransaction) : Except String Result := do
  let world ← Singular.retractionAccepted s.toWorld u tx
  let after ← recoverRegistrations s world
  pure ({}, after)

def genericRejection (s : Sys) (u : Singular.EconomicUtxo)
    (tx : Singular.Rejection) : Except String Result := do
  let world ← Singular.rejectionAccepted s.toWorld u tx
  let after ← recoverRegistrations s world
  pure ({}, after)

inductive Action where
  | bookRegistration (booking : Singular.RegistrationBooking)
  | convictCkpt (aid : Nat)
  | bookTermination (aid booker fee : Nat) (booking : Singular.TerminationBooking)
  | fold (expectedGen expectedPlugin : Nat)
      (unspent : Singular.EconomicUtxo) (transaction : Singular.EconomicTransaction)
  | genericRetraction (unspent : Singular.EconomicUtxo) (transaction : Singular.EconomicTransaction)
  | genericRejection (unspent : Singular.EconomicUtxo) (transaction : Singular.Rejection)

def stepFn (p : Params) (env : Env) (action : Action) (s : Sys) : Except String Result :=
  match action with
  | .bookRegistration b => bookRegistration p s b
  | .convictCkpt aid => convictCkpt env s aid
  | .bookTermination aid booker fee b => bookTermination p s aid booker fee b
  | .fold gen plugin u tx => fold p env s gen plugin u tx
  | .genericRetraction u tx => genericRetraction s u tx
  | .genericRejection u tx => genericRejection s u tx

inductive Reach (p : Params) (env : Env) (cfg : Singular.Config) : Sys → Prop where
  | init : Reach p env cfg (Sys.init cfg)
  | next {s s' : Sys} {action : Action} {flow : Flow} :
      Reach p env cfg s → stepFn p env action s = .ok (flow, s') → Reach p env cfg s'

end CardanoKeri.Registry

namespace CardanoKeri.Registry
/-- An actual sequence of the same canonical stepFn, from a supplied snapshot.
This is not generic WorldReachable and it does not erase application history. -/
inductive History (p : Params) (env : Env) : Sys → Sys → Prop where
  | refl (s : Sys) : History p env s s
  | step {start before after : Sys} {action : Action} {flow : Flow} :
      History p env start before → stepFn p env action before = .ok (flow, after) →
      History p env start after
end CardanoKeri.Registry

namespace CardanoKeri.Registry

def ConsumesPending (ref : Singular.OutRef) (action : Action) : Prop :=
  ∃ gen plugin u tx, action = .fold gen plugin u tx ∧
    Singular.inputsContainReference tx.transaction.inputs ref = true

end CardanoKeri.Registry


namespace CardanoKeri.Registry

structure WellFormed (p : Params) (s : Sys) : Prop where
  trieKeys : (s.trie.map Prod.fst).Nodup
  bindingDomain : ∀ aid,
    (∃ token, bindingAt s aid = some token) ↔
      (Singular.trieGet s.trie aid = .known .active ∨
       Singular.trieGet s.trie aid = .known .terminal)
  bindingKeys : (s.bindings.map Prod.fst).Nodup
  bindingAliases : (s.bindings.map Prod.snd).Nodup
  allocated : ∀ aid tok, (aid, tok) ∈ s.bindings → tok < s.nextToken
  carrierKeys : (s.carriers.map (·.aid)).Nodup
  terminationKeys : (s.terminations.map (·.payload.aid)).Nodup
  requestRefs : ((s.registrations.map (·.request.reference)) ++
    s.terminations.map (·.booking.request.reference)).Nodup
  carrierShape : ∀ c ∈ s.carriers,
    c.original.key = c.aid ∧ c.original.kind = .active ∧ c.minAda = p.Mc ∧
    bindingAt s c.aid = some c.token ∧
    Singular.trieGet s.trie c.aid = .known .active ∧
    ∀ e ∈ s.terminations, e.payload.aid ≠ c.aid
  registrationValues : ∀ b ∈ s.registrations, registrationShape p b
  terminationShape : ∀ e ∈ s.terminations,
    e.booking.request.key = e.payload.aid ∧
    e.booking.request.destination = e.payload.original.output ∧
    e.payload.original.key = e.payload.aid ∧ e.payload.original.kind = .active ∧
    e.booking.custodyInputs = [e.payload.original] ∧
    e.booking.request.carrierAda = p.Mr ∧ e.booking.request.declaredTip = p.tip ∧
    e.booking.request.contents.lovelace = p.Mr + p.tip ∧
    e.booking.request.singularTags = [s.config.singularTag e.payload.aid] ∧
    bindingAt s e.payload.aid = some e.payload.token ∧
    Singular.trieGet s.trie e.payload.aid = .known .active
  worldReachable : Singular.WorldReachable s.toWorld

-- Local KERI observations are erased from the stored generic descriptor.
-- Exact total generic coverage is by the definition of toWorld; uniqueness
-- and intrinsic field agreement are the clauses above, not assumed by a name.

structure FoldReceipt (p : Params) (env : Env) (cfg : Singular.Config) where
  before : Sys
  after : Sys
  unspent : Singular.EconomicUtxo
  transaction : Singular.EconomicTransaction
  flow : Flow
  reachable : Reach p env cfg before
  executed : fold p env before before.gen before.config.applicationPolicy
    unspent transaction = .ok (flow, after)

def Completes {p : Params} {env : Env} {cfg : Singular.Config}
    (r : FoldReceipt p env cfg) (ref : Singular.OutRef) (aid token : Nat) : Prop :=
  ∃ e, pendingAt r.before ref = some e ∧ e.payload.aid = aid ∧
    e.payload.token = token ∧
    Singular.inputsContainReference r.transaction.transaction.inputs ref = true

-- Completion uses the checked execution and the exact pending request.
-- It asserts no automatic Checkpoint/Registry key encoding.
end CardanoKeri.Registry

namespace CardanoKeri.Registry
def lookup {α : Type} : List (Nat × α) → Nat → Option α
  | [], _ => none
  | (i, r) :: rs, id => if i = id then some r else lookup rs id

def remove {α : Type} : List (Nat × α) → Nat → List (Nat × α)
  | [], _ => []
  | (i, r) :: rs, id => if i = id then remove rs id else (i, r) :: remove rs id


end CardanoKeri.Registry
