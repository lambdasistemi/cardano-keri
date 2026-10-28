import CardanoKeri.Duplicity
import CardanoKeri.Registry

/-! Checkpoint lifecycle with retained parking and explicit pending termination. -/

namespace CardanoKeri.Checkpoint

abbrev Slot := Nat

abbrev Seq := Nat

abbrev Epoch := Nat

abbrev Addr := Nat

abbrev Value := Nat

abbrev AID := Nat

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

inductive Intent where
  | keep
  | deposit
  | close (payee : Addr)
  deriving DecidableEq, Repr

def BondOp.intent : BondOp → Intent
  | .keep => .keep
  | .deposit => .deposit

structure Env where

  rotationTo : Epoch → Seq → Seq → Bool

  intentAuthorized : Epoch → Intent → Option Addr → Bool

  quorum : Epoch → Bool

  convictionContext : Epoch → Seq → Option CardanoKeri.Duplicity.Context

  convictionRival : Epoch → Seq → Option CardanoKeri.Duplicity.SignedEvent

def Env.duplicityAt (env : Env) (epoch : Epoch) (sn : Seq) : Bool :=
  match env.convictionContext epoch sn, env.convictionRival epoch sn with
  | some context, some rival => CardanoKeri.Duplicity.duplicityAt epoch sn context rival
  | _, _ => false

def Env.intentOk (env : Env) (e : Epoch) (i : Intent) (r : Option Addr) : Bool :=
  match i, r with
  | .keep, none => true
  | i, r => env.intentAuthorized e i r

inductive Actor where
  | nextKeys
  | currentQuorum
  | proof
  | anyone
  deriving DecidableEq, Repr

inductive Action where

  | register (refund : Addr) (pool0 : Value)

  | rotate (sn' : Seq) (op : BondOp) (payee : Addr) (refund' : Option Addr)

  | poison

  | freeze (sn' : Seq) (payee : Addr)

  | topUp (x : Value)

  | convict (payee : Addr)

  | close (sn' : Seq) (payee : Addr) (refund' : Option Addr)

  | reopen (sn' : Seq) (refund : Addr) (pool0 : Value)
  deriving Repr

def Action.actor : Action → Actor
  | .register .. => .anyone
  | .rotate .. => .nextKeys
  | .poison => .currentQuorum
  | .freeze .. => .proof
  | .topUp .. => .anyone
  | .convict .. => .proof
  | .close .. => .nextKeys
  | .reopen .. => .proof

structure KeyState where
  epoch : Epoch
  sn : Seq
  deriving Repr, DecidableEq

abbrev Hash := KeyState

structure Live where

  sn : Seq

  epoch : Epoch

  poisoned : Bool

  frozen : Bool

  bornAt : Slot

  refundTo : Addr

  pool : Value
  deriving Repr, DecidableEq

def Live.hash (l : Live) : Hash := ⟨l.epoch, l.sn⟩

def Live.bHeld (p : Params) (l : Live) : Value := if l.frozen then 0 else p.B

def Live.rotated (p : Params) (l : Live) (sn' : Seq) (refund' : Option Addr) : Live :=
  { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
           refundTo := refund'.getD l.refundTo,
           pool := if p.P ≤ l.pool then l.pool - p.P else l.pool }

inductive State where

  | absent

  | present (l : Live)

  | parked (h : Hash)
  | terminationPending (h : Hash)

  | convicted
  deriving Repr, DecidableEq

def State.sn? : State → Option Seq
  | .present l => some l.sn
  | .parked h | .terminationPending h => some h.sn
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
  | .parked _ | .terminationPending _ => False
  | .absent | .convicted => False

def consumableStateB (p : Params) (now : Slot) : State → Bool
  | .present l => l.frozen == false && l.poisoned == false && decide (l.bornAt + p.W ≤ now)
  | .parked _ | .terminationPending _ => false
  | .absent | .convicted => false

inductive Step (p : Params) (env : Env) : Action → Slot → State → Flow → State → Prop

  | register (now : Slot) (refund : Addr) (pool0 : Value) :
      Step p env (.register refund pool0) now .absent
        { dregIn := p.D, bIn := p.B, poolIn := pool0 }
        (.present ⟨0, 0, false, false, now, refund, pool0⟩)

  | rotateKeepPaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .keep refund' = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.rotate sn' .keep payee refund') now (.present l)
        { hunter := some { addr := payee, pool := p.P } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo, pool := l.pool - p.P })

  | rotateKeepUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .keep refund' = true)
      (hnopay : l.pool < p.P) :
      Step p env (.rotate sn' .keep payee refund') now (.present l)
        {}
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo })

  | rotateDepositPaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .deposit refund' = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.rotate sn' .deposit payee refund') now (.present l)
        { bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                           refundTo := refund'.getD l.refundTo, pool := l.pool - p.P })

  | rotateDepositUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .deposit refund' = true)
      (hnopay : l.pool < p.P) :
      Step p env (.rotate sn' .deposit payee refund') now (.present l)
        { bIn := p.B - l.bHeld p }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                           refundTo := refund'.getD l.refundTo })

  | poison {l : Live} (now : Slot)
      (hq : env.quorum l.epoch = true) (hclean : l.poisoned = false) :
      Step p env .poison now (.present l) {} (.present { l with poisoned := true })

  | freeze {l : Live} (now : Slot) (sn' : Seq) (payee : Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hpool : l.pool < p.P) (hb : l.frozen = false) (hclean : l.poisoned = false) :
      Step p env (.freeze sn' payee) now (.present l)
        { hunter := some { addr := payee, b := p.B } }
        (.present { l with frozen := true })

  | topUp {l : Live} (now : Slot) (x : Value) :
      Step p env (.topUp x) now (.present l) { poolIn := x } (.present { l with pool := l.pool + x })

  | convict {l : Live} (now : Slot) (payee : Addr)
      (hdup : env.duplicityAt l.epoch l.sn = true) :
      Step p env (.convict payee) now (.present l)
        { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
          convictor := some { addr := payee, dreg := p.D } }
        (.terminationPending l.hash)

  | convictParked {h : Hash} (now : Slot) (payee : Addr)
      (hdup : env.duplicityAt h.epoch h.sn = true) :
      Step p env (.convict payee) now (.parked h) {} (.terminationPending h)

  | closePaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) (.close payee) refund' = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.close sn' payee refund') now (.present l)
        { refund := some { addr := refund'.getD l.refundTo, dreg := p.D, b := l.bHeld p, pool := l.pool - p.P },
          hunter := some { addr := payee, pool := p.P } }
        (.parked ⟨l.epoch + 1, sn'⟩)

  | closeUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) (.close payee) refund' = true)
      (hnopay : l.pool < p.P) :
      Step p env (.close sn' payee refund') now (.present l)
        { refund := some { addr := refund'.getD l.refundTo, dreg := p.D, b := l.bHeld p, pool := l.pool } }
        (.parked ⟨l.epoch + 1, sn'⟩)

  | reopen {h : Hash} (now : Slot) (sn' : Seq) (refund : Addr) (pool0 : Value)
      (hev : env.rotationTo h.epoch h.sn sn' = true) (hsn : h.sn < sn') :
      Step p env (.reopen sn' refund pool0) now (.parked h)
        { dregIn := p.D, bIn := p.B, poolIn := pool0 }
        (.present ⟨sn', h.epoch + 1, false, false, now, refund, pool0⟩)

def stepFn (p : Params) (env : Env) (a : Action) (now : Slot) (s : State) : Option (Flow × State) :=
  match a, s with
  | .register refund pool0, .absent =>
      some ({ dregIn := p.D, bIn := p.B, poolIn := pool0 },
            .present ⟨0, 0, false, false, now, refund, pool0⟩)
  | .rotate sn' op payee refund', .present l =>
      if env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
         env.intentOk (l.epoch + 1) op.intent refund' = true then
        let r' := refund'.getD l.refundTo
        match op with
        | .keep =>
            if p.P ≤ l.pool then
              some ({ hunter := some { addr := payee, pool := p.P } },
                    .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                                      refundTo := r', pool := l.pool - p.P })
            else
              some ({}, .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                                          refundTo := r' })
        | .deposit =>
            if p.P ≤ l.pool then
              some ({ bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } },
                    .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                                      refundTo := r', pool := l.pool - p.P })
            else
              some ({ bIn := p.B - l.bHeld p },
                    .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                                      refundTo := r' })
      else none
  | .poison, .present l =>
      if env.quorum l.epoch = true ∧ l.poisoned = false then
        some ({}, .present { l with poisoned := true })
      else none
  | .freeze sn' payee, .present l =>
      if env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ l.pool < p.P ∧ l.frozen = false ∧
         l.poisoned = false then
        some ({ hunter := some { addr := payee, b := p.B } }, .present { l with frozen := true })
      else none
  | .topUp x, .present l =>
      some ({ poolIn := x }, .present { l with pool := l.pool + x })
  | .convict payee, .present l =>
      if env.duplicityAt l.epoch l.sn = true then
        some ({ refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
                convictor := some { addr := payee, dreg := p.D } },
              .terminationPending l.hash)
      else none
  | .convict _, .parked h =>
      if env.duplicityAt h.epoch h.sn = true then
        some ({}, .terminationPending h)
      else none
  | .close sn' payee refund', .present l =>
      if env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
         env.intentOk (l.epoch + 1) (.close payee) refund' = true then
        if p.P ≤ l.pool then
          some ({ refund := some { addr := refund'.getD l.refundTo, dreg := p.D, b := l.bHeld p, pool := l.pool - p.P },
                  hunter := some { addr := payee, pool := p.P } },
                .parked ⟨l.epoch + 1, sn'⟩)
        else
          some ({ refund := some { addr := refund'.getD l.refundTo, dreg := p.D, b := l.bHeld p, pool := l.pool } },
                .parked ⟨l.epoch + 1, sn'⟩)
      else none
  | .reopen sn' refund pool0, .parked h =>
      if env.rotationTo h.epoch h.sn sn' = true ∧ h.sn < sn' then
        some ({ dregIn := p.D, bIn := p.B, poolIn := pool0 },
              .present ⟨sn', h.epoch + 1, false, false, now, refund, pool0⟩)
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
  | _, (_, .reopen ..) :: rest => poisonAfter false rest
  | b, _ :: rest => poisonAfter b rest

def poisonSinceLastRotation (es : List (Slot × Action)) : Bool :=
  poisonAfter false es

inductive Leaf where
  | absent
  | active
  | retired
  deriving DecidableEq, Repr

def State.leaf : State → Leaf
  | .absent => .absent
  | .present _ | .parked _ | .terminationPending _ => .active
  | .convicted => .retired

def State.hasOutput : State → Bool
  | .present _ | .parked _ | .terminationPending _ => true
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

structure PendingAssociation where
  origin : Origin
  keyState : Hash
  reference : Singular.OutRef
  entry : CardanoKeri.Registry.TerminationEntry
  booked : CardanoKeri.Registry.Sys

-- These associations are model state, not data chosen at completion.
structure Sys where
  leaves : AID → Leaf
  states : AID → State
  origins : AID → Option Origin
  pending : AID → Option PendingAssociation

def Sys.init : Sys :=
  { leaves := fun _ => .absent, states := fun _ => .absent,
    origins := fun _ => none, pending := fun _ => none }

def Sys.set (s : Sys) (aid : AID) (st : State) : Sys :=
  { s with
    leaves := fun a => if a = aid then st.leaf else s.leaves a,
    states := fun a => if a = aid then st else s.states a }

def Sys.installOrigin (s : Sys) (aid : AID) (st : State) (origin : Origin) : Sys :=
  { s.set aid st with
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

-- Registration is the only event that creates an origin. Existing ordinary
-- local operations preserve the already stored origin/pending map.
def RegistrationEvent (p : Params) (env : Env) (s s' : Sys) : Prop :=
  ∃ (aid : AID) (now : Slot) (refund : Addr) (pool0 : Value) (f : Flow) (st : State)
    (rp : CardanoKeri.Registry.Params) (re : CardanoKeri.Registry.Env) (cfg : Singular.Config)
    (receipt : CardanoKeri.Registry.FoldReceipt rp re cfg) (b : Singular.RegistrationBooking) (origin : Origin),
    s.leaves aid = .absent ∧ s.origins aid = none ∧
    Step p env (.register refund pool0) now (s.states aid) f st ∧
    DeliveredOrigin receipt b aid origin ∧
    s' = s.installOrigin aid st origin

def LocalEvent (p : Params) (env : Env) (s s' : Sys) : Prop :=
  ∃ (aid : AID) (a : Action) (now : Slot) (f : Flow) (st : State),
    (∀ refund pool0, a ≠ .register refund pool0) ∧
    Step p env a now (s.states aid) f st ∧
    ((∃ sn' refund pool0, a = .reopen sn' refund pool0) → s.leaves aid = .active) ∧
    s' = s.set aid st

-- The request association is fixed by an actual booking in this origin's
-- extending Registry history, while this checkpoint is already pending.
def BookingEvent (s s' : Sys) : Prop :=
  ∃ (aid : AID) (h : Hash) (origin : Origin)
    (before booked : CardanoKeri.Registry.Sys)
    (booker fee : Nat) (b : Singular.TerminationBooking) (f : CardanoKeri.Registry.Flow)
    (entry : CardanoKeri.Registry.TerminationEntry),
    s.states aid = .terminationPending h ∧ s.origins aid = some origin ∧
    s.pending aid = none ∧
    CardanoKeri.Registry.History origin.parameters origin.environment origin.registered before ∧
    CardanoKeri.Registry.bookTermination origin.parameters before aid booker fee b = .ok (f, booked) ∧
    CardanoKeri.Registry.pendingAt booked b.request.reference = some entry ∧
    entry.booking = b ∧ entry.payload.aid = aid ∧ entry.payload.token = origin.token ∧
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

inductive SysStep (p : Params) (env : Env) : Sys → Sys → Prop where
  | register {s s' : Sys} : RegistrationEvent p env s s' → SysStep p env s s'
  | local {s s' : Sys} : LocalEvent p env s s' → SysStep p env s s'
  | book {s s' : Sys} : BookingEvent s s' → SysStep p env s s'
  | complete {s s' : Sys} : CompletionEvent s s' → SysStep p env s s'

inductive SysReach (p : Params) (env : Env) : Sys → Prop where
  | init : SysReach p env Sys.init
  | step {s s' : Sys} : SysReach p env s → SysStep p env s s' → SysReach p env s'

end CardanoKeri.Checkpoint
