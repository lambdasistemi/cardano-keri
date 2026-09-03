/-!
# The M1 return: the checkpoint machine

Abstract model of what the on-chain validator family admits under the design
ruled on 2026-09-02 and 2026-09-03 (project decisions D-022 … D-038; plan
`AUDIT-M1-RETURN`, Phase 0.2 and 0.4). It replaces the freeze/bond/convict/reap
machine of `Lifecycle.lean`, which is retired with the enforcement economy in
Phase 1; both coexist on this branch so the retirement is a reviewed
deletion.

Third cut, the second Lean slice (D-036, D-037, D-038), after the simulator's
escalation Q-001:

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
* the parameters carry `0 < D` and `0 < B`, closing the zero-bond defect;
* **D-038**: every bond option other than `keep`, and every new refund
  address, is authorized by the keys of the epoch the rotation opens — one
  signed message carrying the intent and the address; absent means keep and
  unchanged. A relayer on public data can land a rotation, never park, age
  or close the owner;
* **D-036**: close is a witnessed rotation that withdraws everything and
  burns the UTxO, poisoned or not, authorized like any other intent by the
  new keys; the result is `closed (epoch, sn)`, a tombstone that is **not
  terminal**: a later witnessed rotation reopens it with fresh bonds and a
  fresh juvenility window. Conviction is the only terminal state;
* **D-037**: the registry is a map from AID to a leaf — absent, live,
  closed (epoch, sn), convicted. `live` means the checkpoint UTxO exists.
  Register, reopen, close and convict change the leaf; rotate, poison,
  freeze and top-up never touch it. Only the leaf map the machine sees is
  modelled here; the MPFS request mechanics that land leaf changes (batches,
  appliers, tips, windows) are the registry's own work and are outside this
  machine — the leaf map is the interface the registry will provide.

No cryptography. Keys are abstracted to an epoch counter: a rotation opens
the next epoch. Two details of D-034 stay fixed here as modelling
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

/-- The bond option a rotation carries (D-033). -/
inductive BondOp where
  | keep
  | withdraw
  | deposit
  deriving DecidableEq, Repr

/-- What the new keys sign along with the refund address (D-038): the bond
option of a rotation, or the close. `keep` with no new address is the empty
message and needs no signature. -/
inductive Intent where
  | keep
  | withdraw
  | deposit
  | close
  deriving DecidableEq, Repr

/-- The intent of a bond option. -/
def BondOp.intent : BondOp → Intent
  | .keep => .keep
  | .withdraw => .withdraw
  | .deposit => .deposit

/-- The evidence the validator verifies, abstracted at the KEL boundary. Each
predicate stands for a cryptographic check over data the transaction
presents; the model does not care how it is decided, only that the
transition is enabled exactly when it holds. -/
structure Env where
  /-- `rotationTo e sn sn'`: a valid witnessed rotation from the state at
  epoch `e`, sequence `sn`, to sequence `sn'` was presented — signatures at
  the current threshold over the rotation bytes, revealed keys matching the
  pre-committed digests at the next threshold, receipts at `toad` from the
  new witness set. The advance predicate; also the freeze evidence (D-034),
  the close evidence (D-036) and, from a closed tombstone, the reopen
  evidence: a witnessed rotation path from the closed sequence to `sn'`
  (several off-chain rotations collapse into one predicate). -/
  rotationTo : Epoch → Seq → Seq → Bool
  /-- `intentAuthorized e i r`: the keys of epoch `e` signed, at their
  threshold, one message carrying the intent `i` and the refund address `r`
  (`none`: unchanged) (D-032, D-038). -/
  intentAuthorized : Epoch → Intent → Option Addr → Bool
  /-- `quorum e`: the current keys of epoch `e` signed the Cardano-side
  preimage at their threshold (poison; D-023). -/
  quorum : Epoch → Bool
  /-- `duplicityAt e sn`: a second rotation at sequence `sn`, revealing the
  keys of epoch `e`, signed at the current threshold and receipted at `toad`
  by the tip's witnesses, differing from the accepted one (D-030). -/
  duplicityAt : Epoch → Seq → Bool

/-- The intent guard: `keep` with no new address needs nothing; every other
intent, and every new address, needs the signed message (D-038). -/
def Env.intentOk (env : Env) (e : Epoch) (i : Intent) (r : Option Addr) : Bool :=
  match i, r with
  | .keep, none => true
  | i, r => env.intentAuthorized e i r

/-- Who authorizes a transition; derived from the action. -/
inductive Actor where
  | nextKeys
  | currentQuorum
  | proof
  | anyone
  deriving DecidableEq, Repr

/-- The actions: exactly the redeemers of the validator family, with the
data each carries. -/
inductive Action where
  /-- Register a public inception; the registrant names the refund address
  and brings the initial pool. -/
  | register (refund : Addr) (pool0 : Value)
  /-- Land a rotation to `sn'` with a bond option, naming a payee for the
  premium and optionally a new refund address; the option and the address
  are one message the new keys sign (D-038). -/
  | rotate (sn' : Seq) (op : BondOp) (payee : Addr) (refund' : Option Addr)
  /-- The current quorum's poison declaration. -/
  | poison
  /-- Freeze on the old keys, presenting the later rotation to `sn'`. -/
  | freeze (sn' : Seq) (payee : Addr)
  /-- Add to the pool. -/
  | topUp (x : Value)
  /-- Present a duplicity proof; the convictor names a payee. -/
  | convict (payee : Addr)
  /-- Close: a witnessed rotation to `sn'` that withdraws everything to the
  refund address (optionally a new one the new keys authorized) and burns
  the UTxO (D-036). -/
  | close (sn' : Seq) (refund' : Option Addr)
  /-- Reopen a closed tombstone with a witnessed rotation later than it,
  fresh bonds, a first pool and a refund address chosen by whoever pays
  (D-036). -/
  | reopen (sn' : Seq) (refund : Addr) (pool0 : Value)
  deriving Repr

/-- The actor an action needs: the party whose signature or evidence the
validator checks. `proof` is a permissionless party presenting witnessed
evidence — a freeze, a conviction, and a reopen (its rotation path from
the tombstone, D-036); `anyone` presents nothing but money and a public
inception. -/
def Action.actor : Action → Actor
  | .register .. => .anyone
  | .rotate .. => .nextKeys
  | .poison => .currentQuorum
  | .freeze .. => .proof
  | .topUp .. => .anyone
  | .convict .. => .proof
  | .close .. => .nextKeys
  | .reopen .. => .proof

/-- The datum plus the value of a present checkpoint. -/
structure Live where
  /-- `native_sn` of the establishment event reflected. -/
  sn : Seq
  /-- The key epoch: which pre-rotation commitment is current. -/
  epoch : Epoch
  /-- The declared poison bit, local to the current keys (D-022). -/
  poisoned : Bool
  /-- Slot of the last bonding: register, reopen or a depositing rotation (juvenility, A9). -/
  bornAt : Slot
  /-- Where the bonds go at withdraw and close (D-032). -/
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
  /-- Closed (D-036): the UTxO is burned; the registry leaf keeps the epoch
  the closing rotation opened and its sequence. Not terminal: a witnessed
  rotation later than `sn` reopens it. -/
  | closed (epoch : Epoch) (sn : Seq)
  deriving Repr, DecidableEq

/-- The sequence a state records, when it records one. -/
def State.sn? : State → Option Seq
  | .present l => some l.sn
  | .convicted _ sn _ => some sn
  | .closed _ sn => some sn
  | .absent => none

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

/-- The decidable mirror of `consumableState`: what a consumer, the trace
driver and the simulator actually run. `consumableStateB_iff` ties the two. -/
def consumableStateB (p : Params) (now : Slot) : State → Bool
  | .present l => l.dreg == p.D && l.b == p.B && l.poisoned == false && decide (l.bornAt + p.W ≤ now)
  | _ => false

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
  authorized it, `P` to the payee (D-033, D-034, D-032, D-038). -/
  | rotateKeepPaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .keep refund' = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.rotate sn' .keep payee refund') now (.present l)
        { hunter := some { addr := payee, pool := p.P } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo, pool := l.pool - p.P })
  /-- The same rotation when the pool does not cover the premium: nothing is
  paid; payment is never a gate (T14). -/
  | rotateKeepUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .keep refund' = true)
      (hnopay : l.pool < p.P) :
      Step p env (.rotate sn' .keep payee refund') now (.present l)
        {}
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo })
  /-- A rotation that withdraws everything to the refund address it results
  in: the pause (D-033). Available from either poisoned state; the new keys
  sign the intent (D-038). -/
  | rotateWithdraw {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .withdraw refund' = true) :
      Step p env (.rotate sn' .withdraw payee refund') now (.present l)
        { refund := some { addr := refund'.getD l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo, dreg := 0, b := 0, pool := 0 })
  /-- A rotation that restores both bonds to full: resurrection from a pause,
  unfreeze after a freeze (D-026, D-034). Resets juvenility. The new keys
  sign the intent (D-038). -/
  | rotateDeposit {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .deposit refund' = true)
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
  /-- Close (D-036, D-032, D-038): a witnessed rotation to `sn'`, poisoned or
  not, whose new keys signed the close intent (and the new refund address,
  if any); everything goes to the refund address it results in — the closer
  chooses when, never where — and the UTxO is burned. The tombstone keeps the
  epoch the rotation opened and its sequence. -/
  | close {l : Live} (now : Slot) (sn' : Seq) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .close refund' = true) :
      Step p env (.close sn' refund') now (.present l)
        { refund := some { addr := refund'.getD l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } }
        (.closed (l.epoch + 1) sn')
  /-- Reopen (D-036): from a closed tombstone, a witnessed rotation path later
  than the closed sequence, fresh bonds and a first pool bring the checkpoint
  back at the next epoch, juvenile, with the refund address whoever pays
  chose (as at registration: the owner moves it at her next rotation). A
  rotation at the closed sequence or earlier cannot reopen: no stale
  resurrection. -/
  | reopen {e : Epoch} {sn : Seq} (now : Slot) (sn' : Seq) (refund : Addr) (pool0 : Value)
      (hev : env.rotationTo e sn sn' = true) (hsn : sn < sn') :
      Step p env (.reopen sn' refund pool0) now (.closed e sn)
        { dregIn := p.D, bIn := p.B, poolIn := pool0 }
        (.present ⟨sn', e + 1, false, now, refund, p.D, p.B, pool0⟩)

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
  | .close sn' refund', .present l =>
      if env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
         env.intentOk (l.epoch + 1) .close refund' = true then
        some ({ refund := some { addr := refund'.getD l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } },
              .closed (l.epoch + 1) sn')
      else none
  | .reopen sn' refund pool0, .closed e sn =>
      if env.rotationTo e sn sn' = true ∧ sn < sn' then
        some ({ dregIn := p.D, bIn := p.B, poolIn := pool0 },
              .present ⟨sn', e + 1, false, now, refund, p.D, p.B, pool0⟩)
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

/-- The poison bit after a list of actions, starting from `b`: register,
rotate and reopen open an epoch (clear), poison marks it, everything else
keeps it. -/
def poisonAfter : Bool → List (Slot × Action) → Bool
  | b, [] => b
  | _, (_, .poison) :: rest => poisonAfter true rest
  | _, (_, .rotate ..) :: rest => poisonAfter false rest
  | _, (_, .register ..) :: rest => poisonAfter false rest
  | _, (_, .reopen ..) :: rest => poisonAfter false rest
  | b, _ :: rest => poisonAfter b rest

/-- Was the last epoch-relevant action a poison? -/
def poisonSinceLastRotation (es : List (Slot × Action)) : Bool :=
  poisonAfter false es

/-! ## The system level: the registry leaf, one per AID (D-036, D-037) -/

/-- The registry leaf of an AID: what the registry records about the
identity. `live` means the checkpoint UTxO exists; every key-state fact
lives in the UTxO. Only `convicted` is terminal. -/
inductive Leaf where
  | absent
  | live
  | closed (epoch : Epoch) (sn : Seq)
  | convicted
  deriving DecidableEq, Repr

/-- The leaf a state projects to. -/
def State.leaf : State → Leaf
  | .absent => .absent
  | .present _ => .live
  | .closed e sn => .closed e sn
  | .convicted .. => .convicted

/-- The system: the registry as a map from AID to leaf, and each AID's
state. The registry's concrete form (an MPFS trie, its requests, batches,
appliers and windows) is outside this machine; the leaf map is the interface
it provides. -/
structure Sys where
  leaves : AID → Leaf
  states : AID → State

/-- Initial system: no leaf, everything absent. -/
def Sys.init : Sys := ⟨fun _ => .absent, fun _ => .absent⟩

/-- Update one AID's state; its leaf follows the state. -/
def Sys.set (s : Sys) (aid : AID) (st : State) : Sys :=
  { leaves := fun a => if a = aid then st.leaf else s.leaves a,
    states := fun a => if a = aid then st else s.states a }

/-- Does the action change the leaf? Register, reopen, close and convict do;
rotate, poison, freeze and top-up never touch the registry. -/
def Action.touchesLeaf : Action → Bool
  | .register .. => true
  | .reopen .. => true
  | .close .. => true
  | .convict .. => true
  | _ => false

/-- System transitions: a registration needs the absence proof (no leaf), a
reopen the presence proof of the closed leaf; every other action is a step
on the AID's state, and the leaf follows. -/
inductive SysStep (p : Params) (env : Env) : Sys → Sys → Prop
  | register {s : Sys} {aid : AID} {now : Slot} {refund : Addr} {pool0 : Value} {f : Flow} {st' : State}
      (habs : s.leaves aid = .absent)
      (hstep : Step p env (.register refund pool0) now (s.states aid) f st') :
      SysStep p env s (s.set aid st')
  | reopen {s : Sys} {aid : AID} {now : Slot} {sn' : Seq} {refund : Addr} {pool0 : Value} {f : Flow} {st' : State}
      {e : Epoch} {sn : Seq}
      (hclosed : s.leaves aid = .closed e sn)
      (hstep : Step p env (.reopen sn' refund pool0) now (s.states aid) f st') :
      SysStep p env s (s.set aid st')
  | other {s : Sys} {aid : AID} {a : Action} {now : Slot} {f : Flow} {st' : State}
      (hnotreg : ∀ refund pool0, a ≠ .register refund pool0)
      (hnotreopen : ∀ sn' refund pool0, a ≠ .reopen sn' refund pool0)
      (hstep : Step p env a now (s.states aid) f st') :
      SysStep p env s (s.set aid st')

/-- System reachability. -/
inductive SysReach (p : Params) (env : Env) : Sys → Prop
  | init : SysReach p env Sys.init
  | step {s s' : Sys} (h : SysReach p env s) (hs : SysStep p env s s') : SysReach p env s'

end CardanoKeri.Checkpoint
