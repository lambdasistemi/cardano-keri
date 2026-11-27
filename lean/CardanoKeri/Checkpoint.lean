import CardanoKeri.CheckpointEventHistory
import CardanoKeri.Registry

/-! Checkpoint lifecycle: alive until convicted, then explicit pending termination.
There is no owner exit: no close, no parking and no revival. -/

namespace CardanoKeri.Checkpoint

abbrev Slot := Nat

abbrev Seq := Nat

abbrev Epoch := Nat

abbrev Addr := Nat

abbrev Value := Nat

abbrev AID := Nat

/-- The deployer fixes the two positive bonds, relay premium and waiting time
when publishing the checkpoint validator. Booking checks the locked bonds and
pool, checkpoint spends account for them, and the consuming party checks age
with the validity time of its consuming transaction. -/
structure Params where

  D : Value

  B : Value

  P : Value

  W : Nat
  hD : 0 < D
  hB : 0 < B

inductive BondOp where
  | keep
  | deposit
  deriving DecidableEq, Repr

/-- Evidence at one checkpoint spend. For keep, deposit and freeze, the party
relaying the later rotation supplies its public event, signatures and receipts
to the advance minting policy. For deposit, the controller additionally signs the
spend-bound intent with the successor keys. For poison, the controller presents
the current-key quorum in the modeled poison spend. For conviction, the
convictor presents one rival. The conviction mint checks it against the
previous commitments carried in the spent tip. The separate two-event read serves the KERI conformance question. -/
structure Env where

  advanceReads : Attestation.AdvanceReads

  -- The keys of epoch `e` signed the deposit of the rotation that opens `e`.
  depositAuthorized : Epoch → Bool

  quorum : Epoch → Bool

  -- The conviction mint decodes the spent active datum and the rival in
  -- the same checkpoint transaction. Signature verification is a primitive.
  presentedSpend : Epoch → Seq → Option Registry.Conviction := fun _ _ => none
  convictionReads : Attestation.ConvictionReads
  keyReads : KeyReads := ⟨fun _ => none, fun _ => none⟩

  -- A history reader can independently evaluate the KERI two-event definition.
  convictionContext : Epoch → Seq → Option CardanoKeri.Duplicity.Context

  convictionRival : Epoch → Seq → Option CardanoKeri.Duplicity.SignedEvent

  -- The booking policy reads the identified inception from the event
  -- and datum admitted at booking. The advance policy reads the signed
  -- rotation presented for the spent identifier and the proposed successor.
  inceptionWriter : AID → Nat → Option (Duplicity.SignedEvent × List Nat) := fun _ _ => none
  rotationWriter : AID → Epoch → Seq → Seq → Option Duplicity.SignedEvent := fun _ _ _ _ => none

def Env.rotationTo (env : Env) := env.advanceReads.attested .advance
def Env.freezeTo (env : Env) := env.advanceReads.attested .freeze

def Env.attestationMinted (env : Env) (observed : Registry.Conviction) : Bool :=
  env.convictionReads.attested observed.output

/-- The convictor mints the attestation in this transaction for this
specific output and claim. A held or previously burned token supplies no mint. -/
def Env.convictionSpend (env : Env) (epoch : Epoch) (sn : Seq) : Option Registry.Conviction :=
  (env.presentedSpend epoch sn).filter env.attestationMinted

/-- An observed conviction spend has a matching mint at use. -/
theorem Env.convictionSpend_attested {env : Env} {epoch sn observation}
    (found : env.convictionSpend epoch sn = some observation) :
    env.presentedSpend epoch sn = some observation ∧ env.attestationMinted observation = true := by
  simpa [convictionSpend, Option.filter_eq_some_iff] using found

/-- The comparison and the indexed output are reads of one conviction transaction. -/
def Env.comparison (env : Env) (epoch : Epoch) (sn : Seq) :=
  (env.convictionSpend epoch sn).map Registry.Conviction.comparison

def Env.initialHistory (env : Env) (aid : AID) (datum : Option Nat) : Option EventHistory :=
  match datum with
  | none => none
  | some raw => match env.inceptionWriter aid raw with
    | none => none
    | some (event, witnesses) =>
      let history := EventHistory.inception event witnesses
      if history.authenticated aid then some history else none

/-- The checkpoint spend selects its identifier before consulting any evidence.
A rotation relayer or a hunter supplies the witnessed event for that identifier.
A deposit additionally carries its successor-key intent. For a poison spend
the controller supplies that identifier’s current-key threshold authorization. -/
abbrev SystemEnv := AID → Env

def Env.duplicityAt (env : Env) (epoch : Epoch) (sn : Seq) : Bool :=
  match env.convictionContext epoch sn, env.convictionRival epoch sn with
  | some context, some rival => CardanoKeri.Duplicity.duplicityAt epoch sn context rival
  | _, _ => false

/-- The local enforcement decision checks the spent native position. -/
def Env.acceptsRival (env : Env) (epoch : Epoch) (sn : Seq) : Bool :=
  ((env.comparison epoch sn).map (fun c => c.acceptsAt epoch sn)).getD false

/-- The commitment binds the decoded conviction evidence for one rival. The
wire offsets and canonical encoding of the complete evidence digest are
technical representation obligations of the enforcement policy. -/
abbrev Evidence := CheckpointConviction.Rival

def Env.evidenceAt (env : Env) (aid : AID) (epoch : Epoch) (sn : Seq) : Option Evidence := do
  let comparison ← env.comparison epoch sn
  if comparison.rival.event.aid = aid then some comparison.rival else none

def Env.bondOpOk (env : Env) (e : Epoch) : BondOp → Bool
  | .keep => true
  | .deposit => env.depositAuthorized e

inductive Actor where
  | nextKeys
  | currentQuorum
  | proof
  | anyone
  deriving DecidableEq, Repr

abbrev Hash := KeyState

structure Live where

  sn : Seq

  epoch : Epoch

  poisoned : Bool

  frozen : Bool

  bornAt : Slot

  refundTo : Addr

  pool : Value

  -- Set by the one top-up this key state allows; every rotation clears it.
  toppedUp : Bool
  deriving Repr, DecidableEq

def Live.hash (l : Live) : Hash := ⟨l.epoch, l.sn⟩

/-- The marker that names one commitment of the release's commitment program. -/
abbrev Marker := Nat

/-- The deployment a checkpoint belongs to: on chain, the checkpoint program
that holds it. -/
abbrev Deployment := Nat

/-- A bounty commitment of the release's commitment program, as a conviction
reads it. It names the identifier and the key state it accuses (`aid` and
`keyState`), the deployment it belongs to, the evidence the conviction will show,
the payee, the raw upper end of the opening transaction's validity range
(`openedAt`), the first slot it can be revealed in (`eligibleAfter`), the last
(`expiresAt`) and its marker. It names no checkpoint output: a conviction is
accepted at whichever live output carries that identifier and key state. On
chain the evidence and payee are hidden behind a hash until the reveal; the model
states them in the clear. -/
structure Commitment where
  aid : AID
  deployment : Deployment
  keyState : Hash
  evidence : Evidence
  payee : Addr
  openedAt : Slot
  eligibleAfter : Slot
  expiresAt : Slot
  marker : Marker
  deriving Repr, DecidableEq

/-- The commitment program opens a commitment only with an age of one slot and a
lifetime: it is first eligible in the slot after the opening and no later than
it expires. -/
def Commitment.wellFormed (c : Commitment) : Prop :=
  c.eligibleAfter = c.openedAt + 1 ∧ c.eligibleAfter ≤ c.expiresAt

instance (c : Commitment) : Decidable c.wellFormed := by
  unfold Commitment.wellFormed; infer_instance

/-- The commitment `c` entitles `payee` to convict the live output `l` at `now`:
it names `l`'s key state, the evidence the conviction shows there, this payee,
and `now` is inside its window. The identifier and the deployment are checked by
the system, which knows them (`Sys.revealOpen`). -/
def Commitment.entitles (env : Env) (c : Commitment) (l : Live) (payee : Addr) (now : Slot) : Prop :=
  c.keyState = l.hash ∧ env.evidenceAt c.aid l.epoch l.sn = some c.evidence ∧ c.payee = payee ∧
    c.eligibleAfter ≤ now ∧ now ≤ c.expiresAt

instance (env : Env) (c : Commitment) (l : Live) (payee : Addr) (now : Slot) :
    Decidable (c.entitles env l payee now) := by
  unfold Commitment.entitles; infer_instance

inductive Action where

  | register (refund : Addr) (pool0 : Value)

  | rotate (sn' : Seq) (op : BondOp) (payee : Addr)

  | poison

  | freeze (sn' : Seq) (payee : Addr)

  | topUp (x : Value)

  | convict (payee : Addr) (commitment : Commitment)
  deriving Repr

def Action.actor : Action → Actor
  | .register .. => .anyone
  | .rotate .. => .nextKeys
  | .poison => .currentQuorum
  | .freeze .. => .proof
  | .topUp .. => .anyone
  | .convict .. => .proof

def Live.bHeld (p : Params) (l : Live) : Value := if l.frozen then 0 else p.B

def Live.rotated (p : Params) (l : Live) (sn' : Seq) : Live :=
  { l with sn := sn', epoch := l.epoch + 1, poisoned := false, toppedUp := false,
           pool := if p.P ≤ l.pool then l.pool - p.P else l.pool }

inductive State where

  | absent

  | present (l : Live)

  | terminationPending (h : Hash)

  | convicted
  deriving Repr, DecidableEq

def State.sn? : State → Option Seq
  | .present l => some l.sn
  | .terminationPending h => some h.sn
  | .absent => none
  | .convicted => none

structure Payment where
  addr : Addr
  dreg : Value := 0
  b : Value := 0
  pool : Value := 0
  deriving Repr, DecidableEq

def Params.premium (p : Params) (l : Live) (payee : Addr) : Option Payment :=
  if p.P ≤ l.pool then some { addr := payee, pool := p.P } else none

structure Flow where

  dregIn : Value := 0
  bIn : Value := 0
  poolIn : Value := 0

  refund : Option Payment := none

  hunter : Option Payment := none

  convictor : Option Payment := none
  deriving Repr, DecidableEq

def State.dregHeld (p : Params) : State → Value
  | .present _ => p.D
  | _ => 0

def State.bHeld (p : Params) : State → Value
  | .present l => l.bHeld p
  | _ => 0

def State.poolHeld : State → Value
  | .present l => l.pool
  | _ => 0

def Payment?.dreg : Option Payment → Value
  | some q => q.dreg
  | none => 0

def Payment?.b : Option Payment → Value
  | some q => q.b
  | none => 0

def Payment?.pool : Option Payment → Value
  | some q => q.pool
  | none => 0

def consumableState (p : Params) (now : Slot) : State → Prop
  | .present l => l.frozen = false ∧ l.poisoned = false ∧ l.bornAt + p.W ≤ now
  | .terminationPending _ => False
  | .absent | .convicted => False

def consumableStateB (p : Params) (now : Slot) : State → Bool
  | .present l => l.frozen == false && l.poisoned == false && decide (l.bornAt + p.W ≤ now)
  | .terminationPending _ => false
  | .absent | .convicted => false

inductive Step (p : Params) (env : Env) : Action → Slot → State → Flow → State → Prop

  | register (now : Slot) (refund : Addr) (pool0 : Value) (hpool : p.P ≤ pool0) :
      Step p env (.register refund pool0) now .absent
        { dregIn := p.D, bIn := p.B, poolIn := pool0 }
        (.present ⟨0, 0, false, false, now, refund, pool0, false⟩)

  | rotateKeepPaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hpay : p.P ≤ l.pool) :
      Step p env (.rotate sn' .keep payee) now (.present l)
        { hunter := some { addr := payee, pool := p.P } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, toppedUp := false,
                           pool := l.pool - p.P })

  | rotateKeepUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hnopay : l.pool < p.P) :
      Step p env (.rotate sn' .keep payee) now (.present l)
        {}
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, toppedUp := false })

  | rotateDepositPaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.depositAuthorized (l.epoch + 1) = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.rotate sn' .deposit payee) now (.present l)
        { bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                           toppedUp := false, pool := l.pool - p.P })

  | rotateDepositUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.depositAuthorized (l.epoch + 1) = true)
      (hnopay : l.pool < p.P) :
      Step p env (.rotate sn' .deposit payee) now (.present l)
        { bIn := p.B - l.bHeld p }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                           toppedUp := false })

  | poison {l : Live} (now : Slot)
      (hq : env.quorum l.epoch = true) (hclean : l.poisoned = false) :
      Step p env .poison now (.present l) {} (.present { l with poisoned := true })

  | freeze {l : Live} (now : Slot) (sn' : Seq) (payee : Addr)
      (hev : env.freezeTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hpool : l.pool < p.P) (hb : l.frozen = false) (hclean : l.poisoned = false) :
      Step p env (.freeze sn' payee) now (.present l)
        { hunter := some { addr := payee, b := p.B } }
        (.present { l with frozen := true })

  | topUp {l : Live} (now : Slot) (x : Value)
      (hfresh : l.toppedUp = false) (hx : p.P ≤ x) :
      Step p env (.topUp x) now (.present l) { poolIn := x }
        (.present { l with pool := l.pool + x, toppedUp := true })

  | convict {l : Live} (now : Slot) (payee : Addr) (c : Commitment)
      (hdup : env.acceptsRival l.epoch l.sn = true)
      (hent : c.entitles env l payee now) :
      Step p env (.convict payee c) now (.present l)
        { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
          convictor := some { addr := payee, dreg := p.D } }
        (.terminationPending l.hash)

def stepFn (p : Params) (env : Env) (a : Action) (now : Slot) (s : State) : Option (Flow × State) :=
  match a, s with
  | .register refund pool0, .absent =>
      if p.P ≤ pool0 then
        some ({ dregIn := p.D, bIn := p.B, poolIn := pool0 },
              .present ⟨0, 0, false, false, now, refund, pool0, false⟩)
      else none
  | .rotate sn' op payee, .present l =>
      if env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
         env.bondOpOk (l.epoch + 1) op = true then
        match op with
        | .keep =>
            if p.P ≤ l.pool then
              some ({ hunter := some { addr := payee, pool := p.P } },
                    .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                                      toppedUp := false, pool := l.pool - p.P })
            else
              some ({}, .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                                          toppedUp := false })
        | .deposit =>
            if p.P ≤ l.pool then
              some ({ bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } },
                    .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                                      toppedUp := false, pool := l.pool - p.P })
            else
              some ({ bIn := p.B - l.bHeld p },
                    .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                                      toppedUp := false })
      else none
  | .poison, .present l =>
      if env.quorum l.epoch = true ∧ l.poisoned = false then
        some ({}, .present { l with poisoned := true })
      else none
  | .freeze sn' payee, .present l =>
      if env.freezeTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ l.pool < p.P ∧ l.frozen = false ∧
         l.poisoned = false then
        some ({ hunter := some { addr := payee, b := p.B } }, .present { l with frozen := true })
      else none
  | .topUp x, .present l =>
      if l.toppedUp = false ∧ p.P ≤ x then
        some ({ poolIn := x }, .present { l with pool := l.pool + x, toppedUp := true })
      else none
  | .convict payee c, .present l =>
      if env.acceptsRival l.epoch l.sn = true ∧ c.entitles env l payee now then
        some ({ refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
                convictor := some { addr := payee, dreg := p.D } },
              .terminationPending l.hash)
      else none
  | _, _ => none

inductive Trace (p : Params) (env : Env) : Slot → State → List (Slot × Action) → State → Prop
  | nil (t : Slot) (s : State) : Trace p env t s [] s
  | cons {t t' : Slot} {s s' s'' : State} {a : Action} {f : Flow} {rest : List (Slot × Action)}
      (hle : t ≤ t') (hs : Step p env a t' s f s') (htail : Trace p env t' s' rest s'') :
      Trace p env t s ((t', a) :: rest) s''

def replay (p : Params) (env : Env) : Slot → State → List (Slot × Action) → Option State
  | _, s, [] => some s
  | t, s, (t', a) :: rest =>
      if t ≤ t' then
        match stepFn p env a t' s with
        | some (_, s') => replay p env t' s' rest
        | none => none
      else none

def Reachable (p : Params) (env : Env) (s : State) : Prop :=
  ∃ t es, Trace p env t .absent es s

def poisonAfter : Bool → List (Slot × Action) → Bool
  | b, [] => b
  | _, (_, .poison) :: rest => poisonAfter true rest
  | _, (_, .rotate ..) :: rest => poisonAfter false rest
  | _, (_, .register ..) :: rest => poisonAfter false rest
  | b, _ :: rest => poisonAfter b rest

def poisonSinceLastRotation (es : List (Slot × Action)) : Bool :=
  poisonAfter false es

def Action.isRotation : Action → Bool
  | .rotate .. => true
  | .register .. | .poison | .freeze .. | .topUp _ | .convict .. => false

/-- The number of top-ups among the actions. -/
def topUpCount : List (Slot × Action) → Nat
  | [] => 0
  | (_, .topUp _) :: rest => topUpCount rest + 1
  | _ :: rest => topUpCount rest

/-- One for a live checkpoint already topped up since its last rotation, zero otherwise. -/
def State.toppedUpCount : State → Nat
  | .present l => l.toppedUp.toNat
  | _ => 0

inductive Leaf where
  | absent
  | active
  | retired
  deriving DecidableEq, Repr

def State.leaf : State → Leaf
  | .absent => .absent
  | .present _ | .terminationPending _ => .active
  | .convicted => .retired

def State.hasOutput : State → Bool
  | .present _ | .terminationPending _ => true
  | .absent | .convicted => false

def State.representativeHeld (s : State) : Nat := if s.hasOutput then 1 else 0

def Action.touchesLeaf : Action → Bool
  | .register .. => true
  | _ => false

end CardanoKeri.Checkpoint

/-! Registration-origin and pending-request associations for actual fold completion. -/
namespace CardanoKeri.Checkpoint

structure Origin where
  parameters : CardanoKeri.Registry.Params
  environment : CardanoKeri.Registry.Env
  configuration : Singular.Config
  registered : CardanoKeri.Registry.Sys
  token : Nat
  registrationRef : Singular.OutRef
  carrierRef : Singular.OutRef
  inception : EventHistory

structure PendingAssociation where
  origin : Origin
  keyState : Hash
  reference : Singular.OutRef
  entry : CardanoKeri.Registry.TerminationEntry
  booked : CardanoKeri.Registry.Sys

-- These associations are model state, not data chosen at completion. A system
-- is one deployment, named by `deployment`.
structure Sys where
  deployment : Deployment
  leaves : AID → Leaf
  states : AID → State
  origins : AID → Option Origin
  pending : AID → Option PendingAssociation
  -- The open commitments of the release's commitment program, by marker.
  commitments : Marker → Option Commitment
  writerData : AID → Option WriterDatum := fun _ => none
  writers : AID → Option EventHistory
  -- Historical observation of the producing spend while the carrier is pending.
  convictions : AID → Option Registry.Conviction := fun _ => none

def Sys.init (d : Deployment) : Sys :=
  { deployment := d, leaves := fun _ => .absent, states := fun _ => .absent,
    origins := fun _ => none, pending := fun _ => none, commitments := fun _ => none, writers := fun _ => none }

/-- Only a live checkpoint exposes establishment data. The retained writer
history after a spend is separate from the pending output's datum. -/
def Sys.activeWriterDatum (s : Sys) (aid : AID) : Option WriterDatum :=
  match s.states aid with
  | .present _ => s.writerData aid
  | _ => none

/-- Registration initializes the live datum. A rotation advances the spent
datum by one writer, irrespective of the length of the ledger history. -/
def updateWriterDatum (old : Option WriterDatum) : Option EventHistory → Option WriterDatum
  | none => old
  | some (.inception event witnesses) => some (.inception event.event witnesses)
  | some (.rotation _ event) => old.map (·.advance event.event)

def Sys.set (s : Sys) (aid : AID) (st : State) (writer : Option EventHistory := none)
    (spend : Option Registry.Conviction := none) : Sys :=
  { s with
    leaves := fun a => if a = aid then st.leaf else s.leaves a,
    states := fun a => if a = aid then st else s.states a,
    convictions := fun a => if a = aid then spend else s.convictions a,
    writerData := fun a => if a = aid then updateWriterDatum (s.writerData a) writer else s.writerData a,
    writers := fun a => if a = aid then writer.orElse (fun _ => s.writers a) else s.writers a }

/-- Only the local transition producing a pending carrier records a conviction. -/
def State.producingSpend (state : State) (env : Env) : Option Registry.Conviction :=
  match state with
  | .terminationPending key => env.convictionSpend key.epoch key.sn
  | _ => none

def Sys.installOrigin (s : Sys) (aid : AID) (st : State) (origin : Origin) : Sys :=
  { s.set aid st (some origin.inception) with
    origins := fun a => if a = aid then some origin else s.origins a,
    pending := fun a => if a = aid then none else s.pending a }

def Sys.associate (s : Sys) (aid : AID) (association : PendingAssociation) : Sys :=
  { s with pending := fun a => if a = aid then some association else s.pending a }

def Sys.finish (s : Sys) (aid : AID) : Sys :=
  { s.set aid .convicted with pending := fun a => if a = aid then none else s.pending a }

-- A real registration's tagged output supplies the origin. The generic datum
-- observation is opaque; no encoding of Checkpoint fields is asserted here.
def DeliveredOrigin {rp : CardanoKeri.Registry.Params} {re : CardanoKeri.Registry.Env} {cfg : Singular.Config}
    (receipt : CardanoKeri.Registry.FoldReceipt rp re cfg) (b : Singular.RegistrationBooking)
    (aid : AID) (origin : Origin) : Prop :=
  Singular.FoldMember.registration b ∈
    Singular.foldMembers receipt.before.toWorld receipt.transaction ∧
  b.request.key = aid ∧ origin.parameters = rp ∧ origin.environment = re ∧
  origin.configuration = cfg ∧ origin.registered = receipt.after ∧
  origin.registrationRef = b.request.reference ∧
  CardanoKeri.Registry.bindingAt receipt.after aid = some origin.token ∧
  ∃ index output, receipt.transaction.outputs[index]? = some output ∧
    origin.carrierRef = ⟨receipt.transaction.identity, index⟩ ∧
    output.singularTags = [receipt.before.config.singularTag aid] ∧
    output.output.address = some b.request.destination ∧
    output.output.datumValue = b.request.datum ∧
    output.output.lovelace = b.request.carrierAda

/-- At the booking mint the controller commits the refund address, the upper
time bound and the entire carrier value. In the economic model addresses have
a common abstract identity. The carrier pays minimum ADA, both bonds and the
initial pool exactly. The Singular folder copies the admitted holding. -/
def BookedFacts (p : Params) (rp : CardanoKeri.Registry.Params)
    (b : Singular.RegistrationBooking) (now : Slot) (refund : Addr) (pool : Value) : Prop :=
  now = b.request.submittedAt ∧ refund = b.request.refundAddress ∧
  rp.D = p.D + p.B ∧ b.request.carrierAda = rp.Mc + rp.D + pool

instance (p : Params) (rp : CardanoKeri.Registry.Params) (b : Singular.RegistrationBooking)
    (now : Slot) (refund : Addr) (pool : Value) : Decidable (BookedFacts p rp b now refund pool) :=
  inferInstanceAs (Decidable (_ ∧ _ ∧ _ ∧ _))

-- Registration is the only event that creates an origin. Existing ordinary
-- local operations preserve the already stored origin/pending map.
def RegistrationEvent (p : Params) (env : SystemEnv) (s s' : Sys) : Prop :=
  ∃ (aid : AID) (now : Slot) (refund : Addr) (pool0 : Value) (f : Flow) (st : State)
    (rp : CardanoKeri.Registry.Params) (re : CardanoKeri.Registry.Env) (cfg : Singular.Config)
    (receipt : CardanoKeri.Registry.FoldReceipt rp re cfg) (b : Singular.RegistrationBooking) (origin : Origin),
    s.leaves aid = .absent ∧ s.origins aid = none ∧
    Step p (env aid) (.register refund pool0) now (s.states aid) f st ∧
    DeliveredOrigin receipt b aid origin ∧ (BookedFacts p rp b now refund pool0 ∧
      (env aid).initialHistory aid b.request.datum = some origin.inception) ∧
    s' = s.installOrigin aid st origin

/-- Given a system registration, when its delivered holding is installed, then
the same booking and receipt identify the stored origin and the new live state.
Its birth time and refund address are the booked ones. Its pool accounts for
all carrier value above minimum ADA and the two checkpoint bonds. -/
theorem registration_installs_booked_facts {p : Params} {env : SystemEnv} {s s' : Sys}
    (event : RegistrationEvent p env s s') :
    ∃ aid origin rp re cfg, ∃ (receipt : CardanoKeri.Registry.FoldReceipt rp re cfg)
      (booking : Singular.RegistrationBooking) (live : Live),
      DeliveredOrigin receipt booking aid origin ∧ s'.origins aid = some origin ∧
      s'.states aid = .present live ∧ live.bornAt = booking.request.submittedAt ∧
      live.refundTo = booking.request.refundAddress ∧ rp.D = p.D + p.B ∧
      booking.request.carrierAda = rp.Mc + rp.D + live.pool := by
  obtain ⟨aid, now, refund, pool, flow, st, rp, re, cfg, receipt, booking, origin,
    _, _, step, delivered, facts, rfl⟩ := event
  generalize h : s.states aid = before at step
  cases step
  exact ⟨aid, origin, rp, re, cfg, receipt, booking, ⟨0, 0, false, false, now, refund, pool, false⟩, delivered,
    by simp [Sys.installOrigin], by simp [Sys.installOrigin, Sys.set], facts.1⟩

/-- The commitment an action reveals: a conviction reveals the one it carries. -/
def Action.revealed : Action → Option Commitment
  | .convict _ c => some c
  | _ => none

/-- Burning a commitment's marker: the commitment is gone and entitles nothing more. -/
def Sys.retire (s : Sys) (m : Marker) : Sys :=
  { s with commitments := fun k => if k = m then none else s.commitments k }

/-- The commitment an action reveals, if any, is open in the release's commitment
program under its marker and names this AID and this system's deployment. -/
def Sys.revealOpenB (s : Sys) (aid : AID) (a : Action) : Bool :=
  match a.revealed with
  | none => true
  | some c => decide (s.commitments c.marker = some c ∧ c.aid = aid ∧ c.deployment = s.deployment)

def Sys.revealOpen (s : Sys) (aid : AID) (a : Action) : Prop := s.revealOpenB aid a = true

def Sys.retireRevealed (s : Sys) (a : Action) : Sys :=
  match a.revealed with
  | some c => s.retire c.marker
  | none => s

/-- Burning a revealed marker changes the commitments only: leaves, states,
origins and pending associations are those of the system before. -/
theorem Sys.retireRevealed_frame (s : Sys) (a : Action) :
    (s.retireRevealed a).leaves = s.leaves ∧ (s.retireRevealed a).states = s.states ∧
      (s.retireRevealed a).origins = s.origins ∧ (s.retireRevealed a).pending = s.pending := by
  unfold Sys.retireRevealed; cases a.revealed <;> exact ⟨rfl, rfl, rfl, rfl⟩

@[simp] theorem Sys.retireRevealed_convictions (s : Sys) (a : Action) :
    (s.retireRevealed a).convictions = s.convictions := by
  unfold Sys.retireRevealed
  cases a.revealed <;> rfl

@[simp] theorem Sys.retireRevealed_leaves (s : Sys) (a : Action) :
    (s.retireRevealed a).leaves = s.leaves := (s.retireRevealed_frame a).1
@[simp] theorem Sys.retireRevealed_states (s : Sys) (a : Action) :
    (s.retireRevealed a).states = s.states := (s.retireRevealed_frame a).2.1
@[simp] theorem Sys.retireRevealed_origins (s : Sys) (a : Action) :
    (s.retireRevealed a).origins = s.origins := (s.retireRevealed_frame a).2.2.1
@[simp] theorem Sys.retireRevealed_pending (s : Sys) (a : Action) :
    (s.retireRevealed a).pending = s.pending := (s.retireRevealed_frame a).2.2.2

/-- An advance reads the event for this spent writer. Freeze verifies the
same evidence but retains the old key state. A missing or mismatched event
refuses the local certificate before a new history can be installed. -/
def Sys.rotationHistory (s : Sys) (env : Env) (aid : AID) (sn : Seq) : Option EventHistory :=
  match s.writers aid, s.states aid with
  | some previous, .present live =>
    match env.rotationWriter aid live.epoch live.sn sn with
    | some event =>
      if previous.epoch == live.epoch && previous.writer.event.sn == live.sn &&
          event.event.sn == sn && Duplicity.rotationValid previous.datum.commitments event then
        some (.rotation previous event)
      else none
    | none => none
  | _, _ => none

/-- The conviction mint reads the carried commitments from the actual live
input. It never consults the historical writer log to grade the rival. -/
def Sys.comparisonMatchesWriter (s : Sys) (env : Env) (aid : AID) : Bool :=
  match s.writerData aid, s.states aid with
  | some datum, .present live =>
    ((env.comparison live.epoch live.sn).map (fun comparison =>
      env.keyReads.matchesDatum aid live.epoch datum comparison.tip)).getD false
  | _, _ => false

def Sys.localWriter (s : Sys) (env : Env) (aid : AID) : Action → Option (Option EventHistory)
  | .rotate sn _ _ => (s.rotationHistory env aid sn).map some
  | .freeze sn _ => (s.rotationHistory env aid sn).map (fun _ => none)
  | .convict .. => if s.comparisonMatchesWriter env aid then some none else none
  | _ => some none

@[simp] theorem Sys.conviction_keeps_writer (s : Sys) (env : Env) (aid payee : Nat) (c : Commitment) :
    (s.localWriter env aid (.convict payee c)).join = none := by
  simp [Sys.localWriter]; split <;> rfl

-- A local step of one checkpoint. A conviction also reveals its commitment in
-- the same transaction: the commitment must be open, and its marker is burnt.
def LocalEventAt (p : Params) (env : SystemEnv) (s s' : Sys) (aid : AID) (a : Action) (now : Slot) : Prop :=
  ∃ (f : Flow) (st : State),
    (∀ refund pool0, a ≠ .register refund pool0) ∧
    Step p (env aid) a now (s.states aid) f st ∧
    (s.revealOpen aid a ∧ (s.localWriter (env aid) aid a).isSome = true) ∧
    s' = (s.set aid st (s.localWriter (env aid) aid a).join (st.producingSpend (env aid))).retireRevealed a

def LocalEvent (p : Params) (env : SystemEnv) (s s' : Sys) : Prop :=
  ∃ aid a now, LocalEventAt p env s s' aid a now

/-- The identity and key-state evidence required by a local action. A deposit
uses the keys of the new epoch. Freeze, like keep, relays a witnessed rotation. -/
def Action.authorizedFor (a : Action) (env : SystemEnv) (aid : AID) (s : State) : Prop :=
  match a, s with
  | .freeze target _, .present l =>
    (env aid).freezeTo l.epoch l.sn target = true
  | .rotate target .keep _, .present l =>
    (env aid).rotationTo l.epoch l.sn target = true
  | .rotate target .deposit _, .present l =>
    (env aid).rotationTo l.epoch l.sn target = true ∧
    (env aid).depositAuthorized (l.epoch + 1) = true
  | .poison, .present l => (env aid).quorum l.epoch = true
  | .rotate .., _ | .freeze .., _ | .poison, _ => False
  | _, _ => True

/-- Given a local system event, when it updates a checkpoint, then the very
action and identifier producing the successor have that identifier's required
rotation, deposit or poison authorization for its prior live state. -/
theorem local_event_uses_own_authorization {p : Params} {env : SystemEnv} {s s' : Sys}
    (event : LocalEvent p env s s') :
    ∃ aid a now flow st, Step p (env aid) a now (s.states aid) flow st ∧
      a.authorizedFor env aid (s.states aid) ∧ s.revealOpen aid a ∧
      s' = (s.set aid st (s.localWriter (env aid) aid a).join (st.producingSpend (env aid))).retireRevealed a := by
  obtain ⟨aid, a, now, flow, st, _, step, opened, installed⟩ := event
  refine ⟨aid, a, now, flow, st, step, ?_, opened.1, installed⟩
  generalize h : s.states aid = before at step ⊢
  cases step <;> simp_all [Action.authorizedFor]

/-- Opening a commitment. The commitment program reads no checkpoint: it can be
opened over any identifier, key state and deployment, whether or not a checkpoint
carries them, and it is opened with an age of one slot and a lifetime. The
opening transaction lands at a slot no later than `openedAt`; the payee signs it
and locks the deposit. -/
def OpenEvent (s s' : Sys) : Prop :=
  ∃ c : Commitment, s.commitments c.marker = none ∧ c.wellFormed ∧
    s' = { s with commitments := fun k => if k = c.marker then some c else s.commitments k }

/-- Revealing a commitment without a conviction, inside its window: the payee
signs and takes the deposit back. -/
def RevealEventAt (s s' : Sys) (c : Commitment) (now : Slot) : Prop :=
  s.commitments c.marker = some c ∧
    c.eligibleAfter ≤ now ∧ now ≤ c.expiresAt ∧ s' = s.retire c.marker

def RevealEvent (s s' : Sys) : Prop :=
  ∃ c now, RevealEventAt s s' c now

/-- Sweeping an expired commitment: strictly after its window, whoever signs takes
the deposit, and no checkpoint is touched. -/
def SweepEventAt (s s' : Sys) (c : Commitment) (now : Slot) : Prop :=
  s.commitments c.marker = some c ∧
    c.expiresAt < now ∧ s' = s.retire c.marker

def SweepEvent (s s' : Sys) : Prop :=
  ∃ c now, SweepEventAt s s' c now

/-- A certificate presents two projections of the earlier spend. Compare their
ledger outpoint and full conviction evidence before associating the histories.
The termination mint itself only spends the named pending output. -/
def bookingSharesConviction (s : Sys) (aid : AID) (origin : Origin) (ref : Singular.OutRef) : Bool :=
  match s.convictions aid with
  | some observed => decide (observed.output = ref ∧ origin.environment.conviction aid = some observed)
  | none => false

-- The request association is fixed by an actual booking in this origin's
-- extending Registry history, while this checkpoint is already pending.
def BookingEvent (s s' : Sys) : Prop :=
  ∃ (aid : AID) (h : Hash) (origin : Origin)
    (before booked : CardanoKeri.Registry.Sys)
    (booker fee : Nat) (b : CardanoKeri.Registry.TerminationBooking) (f : CardanoKeri.Registry.Flow)
    (entry : CardanoKeri.Registry.TerminationEntry),
    s.states aid = .terminationPending h ∧ s.origins aid = some origin ∧
    s.pending aid = none ∧
    CardanoKeri.Registry.History origin.parameters origin.environment origin.registered before ∧
    CardanoKeri.Registry.bookTermination origin.parameters before aid booker fee b = .ok (f, booked) ∧
    CardanoKeri.Registry.pendingAt booked b.request.reference = some entry ∧
    entry.booking = b ∧ entry.payload.aid = aid ∧ (entry.payload.token = origin.token ∧
      entry.payload.spend = ⟨b.pendingReference, aid, h⟩ ∧
      bookingSharesConviction s aid origin b.pendingReference = true) ∧
    s' = s.associate aid {
      origin := origin, keyState := h, reference := b.request.reference,
      entry := entry, booked := booked }

-- Completion consumes the stored association; no ref/token/origin is freely
-- selected at completion. The intervening history may include mixed folds,
-- other AIDs and generic recovery, but this exact pending record must remain.
def ReceiptMatches (s : Sys) (aid : AID) (association : PendingAssociation)
    (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters
      association.origin.environment association.origin.configuration) : Prop :=
  s.pending aid = some association ∧
  s.origins aid = some association.origin ∧
  s.states aid = .terminationPending association.keyState ∧
  CardanoKeri.Registry.History association.origin.parameters association.origin.environment
    association.booked receipt.before ∧
  receipt.before.config = {
    association.origin.registered.config with root := receipt.before.config.root } ∧
  CardanoKeri.Registry.pendingAt receipt.before association.reference = some association.entry ∧
  CardanoKeri.Registry.Completes receipt association.reference aid association.origin.token

def CompletionEvent (s s' : Sys) : Prop :=
  ∃ (aid : AID) (association : PendingAssociation)
    (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters
      association.origin.environment association.origin.configuration),
    ReceiptMatches s aid association receipt ∧ s' = s.finish aid

inductive SysStep (p : Params) (env : SystemEnv) : Sys → Sys → Prop where
  | register {s s' : Sys} : RegistrationEvent p env s s' → SysStep p env s s'
  | local {s s' : Sys} : LocalEvent p env s s' → SysStep p env s s'
  | book {s s' : Sys} : BookingEvent s s' → SysStep p env s s'
  | complete {s s' : Sys} : CompletionEvent s s' → SysStep p env s s'
  | openCommitment {s s' : Sys} : OpenEvent s s' → SysStep p env s s'
  | reveal {s s' : Sys} : RevealEvent s s' → SysStep p env s s'
  | sweep {s s' : Sys} : SweepEvent s s' → SysStep p env s s'

inductive SysReach (p : Params) (env : SystemEnv) : Sys → Prop where
  | init (d : Deployment) : SysReach p env (Sys.init d)
  | step {s s' : Sys} : SysReach p env s → SysStep p env s s' → SysReach p env s'

end CardanoKeri.Checkpoint
