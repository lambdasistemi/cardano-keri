/-!
# The M1 return: the checkpoint machine

Abstract model of what the on-chain validator family admits under the design
ruled on 2026-09-02 (project decisions D-022 … D-034; plan
`AUDIT-M1-RETURN`, Phase 0.2). It replaces the freeze/bond/convict/reap
machine of `Lifecycle.lean`, which is retired with the enforcement economy in
Phase 1; both coexist on this branch so the retirement is a reviewed
deletion.

Second cut, after the independent statement audit of 2026-09-02
(`handoffs/lean-audit/FINDINGS-codex-statement-audit.md`):

* the evidence a transition needs is a **guard on the constructor**, not a
  label — an `Env` of decidable predicates stands for the cryptographic
  checks the validator performs over the data the transaction presents;
* transitions are **actions** carrying their parameters (the bond option,
  the payee, the refund address), and the authorizing actor is derived from
  the action;
* value moves as **addressed, component-wise flows**, so "three components
  never mix" and "paid to the refund address, not to the closer" are
  theorems;
* a **functional step** `stepFn` mirrors the relation, so the fold theorem
  (T7) and the simulator's transcription have one executable source;
* the parameters carry `0 < D` and `0 < B`, closing the zero-bond defect.

No cryptography. Keys are abstracted to an epoch counter: a rotation opens
the next epoch. Two open details of D-034 are fixed here as modelling
assumptions, documented on the constructor: a freeze is not enabled from a
poisoned state, and conviction sends the freeze bond and the pool to the
refund address while the conviction bond goes to the convictor. Validity
(D-027, A11) is reserved in the datum and not modelled; threshold
satisfaction by a consumer's own signature is the consumer's check, outside
this machine — `consumableState` names exactly the state-side conjuncts.
-/

namespace CardanoKeri.Checkpoint

/-- Chain time; a transition's `now` abstracts the transaction validity range. -/
abbrev Slot := Nat

/-- KERI sequence numbers of establishment events. -/
abbrev Seq := Nat

/-- Abstract key epochs: incremented by every rotation. -/
abbrev Epoch := Nat

/-- Abstract addresses. -/
abbrev Addr := Nat

/-- Lovelace. -/
abbrev Value := Nat

/-- AIDs, at the system level. -/
abbrev AID := Nat

/-- Deployment parameters. Both bonds are positive: a zero bond would make
"bond missing" indistinguishable from "bond full". -/
structure Params where
  /-- `D_reg`, the conviction bond: seized by a duplicity proof, never a fee source. -/
  D : Value
  /-- `B`, the freeze bond: taken by the hunter who freezes a stale AID. -/
  B : Value
  /-- `P`, the premium paid from the pool per landed rotation. -/
  P : Value
  /-- `W`, the juvenility window in slots. Consumer policy only (T9). -/
  W : Nat
  hD : 0 < D
  hB : 0 < B

/-- The evidence the validator verifies, abstracted at the KEL boundary. Each
predicate stands for a cryptographic check over data the transaction
presents; the model does not care how it is decided, only that the
transition is enabled exactly when it holds. -/
structure Env where
  /-- `rotationTo e sn sn'`: a valid witnessed rotation from the state at
  epoch `e`, sequence `sn`, to sequence `sn'` was presented — signatures at
  the current threshold over the rotation bytes, revealed keys matching the
  pre-committed digests at the next threshold, receipts at `toad` from the
  new witness set. The advance predicate; also the freeze evidence (D-034). -/
  rotationTo : Epoch → Seq → Seq → Bool
  /-- `refundAuthorized e a`: the keys of epoch `e` signed refund address `a`
  at their threshold (D-032). -/
  refundAuthorized : Epoch → Addr → Bool
  /-- `quorum e`: the current keys of epoch `e` signed the Cardano-side
  preimage at their threshold (poison, close; D-023). -/
  quorum : Epoch → Bool
  /-- `duplicityAt e sn`: a second rotation at sequence `sn`, revealing the
  keys of epoch `e`, signed at the current threshold and receipted at `toad`
  by the tip's witnesses, differing from the accepted one (D-030). -/
  duplicityAt : Epoch → Seq → Bool

/-- Who authorizes a transition; derived from the action. -/
inductive Actor where
  | nextKeys
  | currentQuorum
  | proof
  | anyone
  deriving DecidableEq, Repr

/-- The bond option a rotation carries (D-033). -/
inductive BondOp where
  | keep
  | withdraw
  | deposit
  deriving DecidableEq, Repr

/-- The actions: exactly the redeemers of the validator family, with the
data each carries. -/
inductive Action where
  /-- Register a public inception; the registrant names the refund address
  and brings the initial pool. -/
  | register (refund : Addr) (pool0 : Value)
  /-- Land a rotation to `sn'` with a bond option, naming a payee for the
  premium and optionally a new refund address for the new keys to authorize. -/
  | rotate (sn' : Seq) (op : BondOp) (payee : Addr) (refund' : Option Addr)
  /-- The current quorum's poison declaration. -/
  | poison
  /-- Freeze on the old keys, presenting the later rotation to `sn'`. -/
  | freeze (sn' : Seq) (payee : Addr)
  /-- Add to the pool. -/
  | topUp (x : Value)
  /-- Present a duplicity proof; the convictor names a payee. -/
  | convict (payee : Addr)
  /-- The current quorum's close. -/
  | close
  deriving Repr

/-- The actor an action needs. -/
def Action.actor : Action → Actor
  | .register .. => .anyone
  | .rotate .. => .nextKeys
  | .poison => .currentQuorum
  | .freeze .. => .proof
  | .topUp .. => .anyone
  | .convict .. => .proof
  | .close => .currentQuorum

/-- The datum plus the value of a present checkpoint. -/
structure Live where
  /-- `native_sn` of the establishment event reflected. -/
  sn : Seq
  /-- The key epoch: which pre-rotation commitment is current. -/
  epoch : Epoch
  /-- The declared poison bit, local to the current keys (D-022). -/
  poisoned : Bool
  /-- Slot of the last bonding: register or a depositing rotation (juvenility, A9). -/
  bornAt : Slot
  /-- Where the bonds go at close (D-032). -/
  refundTo : Addr
  /-- Conviction bond currently held: `p.D` or `0`. -/
  dreg : Value
  /-- Freeze bond currently held: `p.B` or `0`. -/
  b : Value
  /-- Advance funds. -/
  pool : Value
  deriving Repr, DecidableEq

/-- The lifecycle states. -/
inductive State where
  /-- Never registered. -/
  | absent
  /-- Live on chain, consumable or not according to `consumableState`. -/
  | present (l : Live)
  /-- Terminal (D-030): the tombstone keeps epoch, sequence and the slot of
  the conviction; no transition leaves it. -/
  | convicted (epoch : Epoch) (sn : Seq) (convictedAt : Slot)
  /-- Terminal (D-028): closed; the token is burned, the registry row stays. -/
  | gone
  deriving Repr, DecidableEq

/-- One payment line: an address and how much of each component it receives. -/
structure Payment where
  addr : Addr
  dreg : Value := 0
  b : Value := 0
  pool : Value := 0
  deriving Repr, DecidableEq

/-- Value movements of one transition, by component and by destination. -/
structure Flow where
  /-- Brought in, by component. -/
  dregIn : Value := 0
  bIn : Value := 0
  poolIn : Value := 0
  /-- Paid to the refund address recorded in the datum (or the one the
  rotation installs). -/
  refund : Option Payment := none
  /-- Paid to the hunter or payee the transaction names. -/
  hunter : Option Payment := none
  /-- Paid to the convictor. -/
  convictor : Option Payment := none
  deriving Repr, DecidableEq

/-- Component held by a state. -/
def State.dregHeld : State → Value
  | .present l => l.dreg
  | _ => 0

def State.bHeld : State → Value
  | .present l => l.b
  | _ => 0

def State.poolHeld : State → Value
  | .present l => l.pool
  | _ => 0

/-- Component paid out by a flow. -/
def Payment?.dreg : Option Payment → Value
  | some q => q.dreg
  | none => 0

def Payment?.b : Option Payment → Value
  | some q => q.b
  | none => 0

def Payment?.pool : Option Payment → Value
  | some q => q.pool
  | none => 0

/-- The state-side conjuncts of what a consumer accepts: both bonds full,
unpoisoned, past juvenility. The consumer's own threshold check on its
transaction, and validity once A11 ships, are outside this machine. -/
def consumableState (p : Params) (now : Slot) : State → Prop
  | .present l => l.dreg = p.D ∧ l.b = p.B ∧ l.poisoned = false ∧ l.bornAt + p.W ≤ now
  | _ => False

/-- The transition relation: exactly the spends the validator family admits. -/
inductive Step (p : Params) (env : Env) : Action → Slot → State → Flow → State → Prop
  /-- Absent → Present. The inception is public, so registration is
  permissionless; mint-once is the registry's job (`Sys`). -/
  | register (now : Slot) (refund : Addr) (pool0 : Value) :
      Step p env (.register refund pool0) now .absent
        { dregIn := p.D, bIn := p.B, poolIn := pool0 }
        (.present ⟨0, 0, false, now, refund, p.D, p.B, pool0⟩)
  /-- A rotation that keeps the bonds, when the pool covers the premium:
  next epoch, poison cleared, refund address moved only if the new keys
  authorized it, `P` to the payee (D-033, D-034, D-032). -/
  | rotateKeepPaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : refund'.all (fun r => env.refundAuthorized (l.epoch + 1) r) = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.rotate sn' .keep payee refund') now (.present l)
        { hunter := some { addr := payee, pool := p.P } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo, pool := l.pool - p.P })
  /-- The same rotation when the pool does not cover the premium: nothing is
  paid; payment is never a gate (T14). -/
  | rotateKeepUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : refund'.all (fun r => env.refundAuthorized (l.epoch + 1) r) = true)
      (hnopay : l.pool < p.P) :
      Step p env (.rotate sn' .keep payee refund') now (.present l)
        {}
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo })
  /-- A rotation that withdraws everything to the refund address it results
  in: the pause (D-033). Available from either poisoned state; the rotation
  is the authorization. -/
  | rotateWithdraw {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : refund'.all (fun r => env.refundAuthorized (l.epoch + 1) r) = true) :
      Step p env (.rotate sn' .withdraw payee refund') now (.present l)
        { refund := some { addr := refund'.getD l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo, dreg := 0, b := 0, pool := 0 })
  /-- A rotation that restores both bonds to full: resurrection from a pause,
  unfreeze after a freeze (D-026, D-034). Resets juvenility. -/
  | rotateDeposit {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : refund'.all (fun r => env.refundAuthorized (l.epoch + 1) r) = true)
      (hd : l.dreg ≤ p.D) (hb : l.b ≤ p.B) :
      Step p env (.rotate sn' .deposit payee refund') now (.present l)
        { dregIn := p.D - l.dreg, bIn := p.B - l.b }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           bornAt := now, refundTo := refund'.getD l.refundTo,
                           dreg := p.D, b := p.B })
  /-- The poison: the current quorum's declaration against the current epoch
  (D-022, D-023). Enabled only once per epoch; touches no value. -/
  | poison {l : Live} (now : Slot)
      (hq : env.quorum l.epoch = true) (hclean : l.poisoned = false) :
      Step p env .poison now (.present l) {} (.present { l with poisoned := true })
  /-- The freeze (D-034): anyone presenting a later witnessed rotation while
  the pool does not cover the premium takes the freeze bond and leaves the
  datum as it is — the old keys stay. Modelling assumption: not enabled from
  a poisoned state. -/
  | freeze {l : Live} (now : Slot) (sn' : Seq) (payee : Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hpool : l.pool < p.P) (hb : l.b = p.B) (hclean : l.poisoned = false) :
      Step p env (.freeze sn' payee) now (.present l)
        { hunter := some { addr := payee, b := p.B } }
        (.present { l with b := 0 })
  /-- Anyone may add to the pool; the datum is untouched. -/
  | topUp {l : Live} (now : Slot) (x : Value) :
      Step p env (.topUp x) now (.present l) { poolIn := x } (.present { l with pool := l.pool + x })
  /-- Conviction (D-030, D-031): a verified duplicity proof seizes the
  conviction bond to the convictor and ends the machine. Modelling
  assumption: the freeze bond and the pool return to the refund address. -/
  | convict {l : Live} (now : Slot) (payee : Addr)
      (hdup : env.duplicityAt l.epoch l.sn = true) :
      Step p env (.convict payee) now (.present l)
        { refund := some { addr := l.refundTo, b := l.b, pool := l.pool },
          convictor := some { addr := payee, dreg := l.dreg } }
        (.convicted l.epoch l.sn now)
  /-- Close (D-028, D-032): the current quorum, unpoisoned only; everything
  goes to the refund address in the datum — the closer chooses when, never
  where. -/
  | close {l : Live} (now : Slot)
      (hq : env.quorum l.epoch = true) (hclean : l.poisoned = false) :
      Step p env .close now (.present l)
        { refund := some { addr := l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } }
        .gone

/-! ## The functional step: one executable source for the relation, the
fold theorem and the simulator's transcription -/

/-- The functional mirror of `Step`. `T7_step_iff_stepFn` states that the two
agree exactly. -/
def stepFn (p : Params) (env : Env) (a : Action) (now : Slot) (s : State) : Option (Flow × State) :=
  match a, s with
  | .register refund pool0, .absent =>
      some ({ dregIn := p.D, bIn := p.B, poolIn := pool0 },
            .present ⟨0, 0, false, now, refund, p.D, p.B, pool0⟩)
  | .rotate sn' op payee refund', .present l =>
      if env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
         refund'.all (fun r => env.refundAuthorized (l.epoch + 1) r) = true then
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
        | .withdraw =>
            some ({ refund := some { addr := r', dreg := l.dreg, b := l.b, pool := l.pool } },
                  .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                                    refundTo := r', dreg := 0, b := 0, pool := 0 })
        | .deposit =>
            if l.dreg ≤ p.D ∧ l.b ≤ p.B then
              some ({ dregIn := p.D - l.dreg, bIn := p.B - l.b },
                    .present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                                      bornAt := now, refundTo := r', dreg := p.D, b := p.B })
            else none
      else none
  | .poison, .present l =>
      if env.quorum l.epoch = true ∧ l.poisoned = false then
        some ({}, .present { l with poisoned := true })
      else none
  | .freeze sn' payee, .present l =>
      if env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ l.pool < p.P ∧ l.b = p.B ∧
         l.poisoned = false then
        some ({ hunter := some { addr := payee, b := p.B } }, .present { l with b := 0 })
      else none
  | .topUp x, .present l =>
      some ({ poolIn := x }, .present { l with pool := l.pool + x })
  | .convict payee, .present l =>
      if env.duplicityAt l.epoch l.sn = true then
        some ({ refund := some { addr := l.refundTo, b := l.b, pool := l.pool },
                convictor := some { addr := payee, dreg := l.dreg } },
              .convicted l.epoch l.sn now)
      else none
  | .close, .present l =>
      if env.quorum l.epoch = true ∧ l.poisoned = false then
        some ({ refund := some { addr := l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } },
              .gone)
      else none
  | _, _ => none

/-! ## Traces -/

/-- A trace: timestamped actions at non-decreasing slots. -/
inductive Trace (p : Params) (env : Env) : Slot → State → List (Slot × Action) → State → Prop
  | nil (t : Slot) (s : State) : Trace p env t s [] s
  | cons {t t' : Slot} {s s' s'' : State} {a : Action} {f : Flow} {rest : List (Slot × Action)}
      (hle : t ≤ t') (hs : Step p env a t' s f s') (htail : Trace p env t' s' rest s'') :
      Trace p env t s ((t', a) :: rest) s''

/-- Replay of a timestamped action list through `stepFn`. -/
def replay (p : Params) (env : Env) : Slot → State → List (Slot × Action) → Option State
  | _, s, [] => some s
  | t, s, (t', a) :: rest =>
      if t ≤ t' then
        match stepFn p env a t' s with
        | some (_, s') => replay p env t' s' rest
        | none => none
      else none

/-- Reachable from `absent` at any slot by some trace. -/
def Reachable (p : Params) (env : Env) (s : State) : Prop :=
  ∃ t es, Trace p env t .absent es s

/-- Was the last epoch-relevant action a poison? Register and rotate open an
epoch; poison marks it. Scanned from the end of the list. -/
/-- The poison bit after a list of actions, starting from `b`: register and
rotate open an epoch (clear), poison marks it, everything else keeps it. -/
def poisonAfter : Bool → List (Slot × Action) → Bool
  | b, [] => b
  | _, (_, .poison) :: rest => poisonAfter true rest
  | _, (_, .rotate ..) :: rest => poisonAfter false rest
  | _, (_, .register ..) :: rest => poisonAfter false rest
  | b, _ :: rest => poisonAfter b rest

/-- Was the last epoch-relevant action a poison? -/
def poisonSinceLastRotation (es : List (Slot × Action)) : Bool :=
  poisonAfter false es

/-! ## The system level: one incarnation per AID, ever (D-024) -/

/-- The registry of every AID ever registered, and each AID's state. -/
structure Sys where
  registered : List AID
  states : AID → State

/-- Initial system: nothing registered, everything absent. -/
def Sys.init : Sys := ⟨[], fun _ => .absent⟩

/-- Update one AID's state. -/
def Sys.set (s : Sys) (aid : AID) (st : State) : Sys :=
  { s with states := fun a => if a = aid then st else s.states a }

/-- System transitions: registration inserts into the registry with an
absence proof (mint-once); every other action leaves the registry alone. -/
inductive SysStep (p : Params) (env : Env) : Sys → Sys → Prop
  | register {s : Sys} {aid : AID} {now : Slot} {refund : Addr} {pool0 : Value} {f : Flow} {st' : State}
      (habs : aid ∉ s.registered)
      (hstep : Step p env (.register refund pool0) now (s.states aid) f st') :
      SysStep p env s { registered := aid :: s.registered, states := (s.set aid st').states }
  | other {s : Sys} {aid : AID} {a : Action} {now : Slot} {f : Flow} {st' : State}
      (hnotreg : ∀ refund pool0, a ≠ .register refund pool0)
      (hstep : Step p env a now (s.states aid) f st') :
      SysStep p env s (s.set aid st')

/-- System reachability. -/
inductive SysReach (p : Params) (env : Env) : Sys → Prop
  | init : SysReach p env Sys.init
  | step {s s' : Sys} (h : SysReach p env s) (hs : SysStep p env s s') : SysReach p env s'

end CardanoKeri.Checkpoint
