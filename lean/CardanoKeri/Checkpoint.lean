/-!
# The M1 return: the checkpoint machine

Abstract model of what the on-chain validator family admits under the design
ruled on 2026-09-02 (project decisions D-022 … D-034; plan
`AUDIT-M1-RETURN`, Phase 0.2). It replaces the freeze/bond/convict/reap
machine of `Lifecycle.lean`, which is retired with the enforcement economy in
Phase 1; both coexist on this branch so the retirement is a reviewed
deletion.

No cryptography. Signatures, witness receipts and duplicity proofs are
abstracted into the **actor** that authorizes a transition:

* `nextKeys` — a rotation: signed at the current threshold by the current
  keys, revealing the keys pre-committed for this epoch, carrying receipts at
  `toad` from the new witness set. The advance predicate of `advance.ak`.
* `currentQuorum` — signatures at the current threshold by the current keys
  over a Cardano-side preimage: poison and close.
* `proof` — evidence anyone may present: a later witnessed rotation
  (freeze), or two receipted rotations at the tip's sequence (convict).
* `anyone` — no authorization: registration of a public inception, top-up.

Keys are abstracted to an epoch counter: a rotation opens the next epoch.
Which concrete keys are current is irrelevant to every property below;
what matters is *who* can act, and that is the actor.

Value is modelled as three components that never mix (D-034): `dreg`, the
conviction bond; `b`, the freeze bond; `pool`, the advance funds. Every
transition carries a `Flow` recording what left the UTxO and to whom, so
conservation is a theorem rather than a comment.

Two open details of D-034 are fixed here as modelling assumptions, both
documented on the constructor: a freeze is not enabled from a poisoned
state, and conviction sends the freeze bond and the pool to the refund
address while the conviction bond goes to the convictor.
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

/-- Deployment parameters. -/
structure Params where
  /-- `D_reg`, the conviction bond: seized by a duplicity proof, never a fee source. -/
  D : Value
  /-- `B`, the freeze bond: taken by the hunter who freezes a stale AID. -/
  B : Value
  /-- `P`, the premium paid from the pool per landed rotation. -/
  P : Value
  /-- `W`, the juvenility window in slots. -/
  W : Nat

/-- Who authorizes a transition. See the module docstring. -/
inductive Actor where
  | nextKeys
  | currentQuorum
  | proof
  | anyone
  deriving DecidableEq, Repr

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
  /-- Where the bonds go at close; set by the registrant, moved only by a
  rotation authorized by the new keys (D-032). -/
  refundTo : Addr
  /-- Conviction bond currently held: `p.D` or `0`. -/
  dreg : Value
  /-- Freeze bond currently held: `p.B` or `0`. -/
  b : Value
  /-- Advance funds. -/
  pool : Value
  deriving Repr

/-- The lifecycle states. -/
inductive State where
  /-- Never registered (or, at the system level, registered under no token). -/
  | absent
  /-- Live on chain, consumable or not according to `consumable`. -/
  | present (l : Live)
  /-- Terminal: a duplicity proof landed (D-030). The tombstone keeps the AID,
  epoch and sequence; no transition leaves it. -/
  | convicted (epoch : Epoch) (sn : Seq)
  /-- Terminal: closed; the token is burned and the registry row stays (D-028). -/
  | gone
  deriving Repr

/-- The bond option a rotation carries (D-033). -/
inductive BondOp where
  | keep
  | withdraw
  | deposit
  deriving DecidableEq, Repr

/-- Value carried by a state. -/
def State.value : State → Value
  | .present l => l.dreg + l.b + l.pool
  | _ => 0

/-- What a consumer reading the checkpoint as a reference input accepts:
both bonds full, unpoisoned, past juvenility. Validity (A11) is reserved in
the datum and not modelled here. -/
def consumable (p : Params) (now : Slot) : State → Prop
  | .present l => l.dreg = p.D ∧ l.b = p.B ∧ l.poisoned = false ∧ l.bornAt + p.W ≤ now
  | _ => False

/-- Value movements of one transition. -/
structure Flow where
  /-- Paid to `refundTo`. -/
  toRefund : Value := 0
  /-- Paid to the hunter or payee named by the transaction. -/
  toHunter : Value := 0
  /-- Paid to the convictor. -/
  toConvictor : Value := 0
  /-- Brought in by the transaction (registrant, owner, or anyone topping up). -/
  deposited : Value := 0
  deriving Repr

/-- The transition relation: exactly the spends the validator family admits,
tagged with the authorizing actor and the slot. -/
inductive Step (p : Params) : Actor → Slot → State → Flow → State → Prop
  /-- Absent → Present. The inception is public, so registration is
  permissionless; the registrant brings both bonds and an initial pool and
  names the refund address. Mint-once is enforced at the system level
  (`Sys`), not here. -/
  | register (now : Slot) (refund : Addr) (pool0 : Value) :
      Step p .anyone now .absent
        { deposited := p.D + p.B + pool0 }
        (.present ⟨0, 0, false, now, refund, p.D, p.B, pool0⟩)
  /-- A rotation that keeps the bonds. Opens the next epoch, clears the
  poison, may move `refundTo` when the new keys authorize it, and pays the
  premium from the pool when the pool covers it (D-034). -/
  | rotateKeep {l : Live} (now : Slot) (sn' : Seq) (hsn : l.sn < sn')
      (refund' : Option Addr) (hpay : p.P ≤ l.pool) :
      Step p .nextKeys now (.present l)
        { toHunter := p.P }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo, pool := l.pool - p.P })
  /-- The same rotation when the pool does not cover the premium: nothing is
  paid; payment is never a gate (T14). -/
  | rotateKeepUnpaid {l : Live} (now : Slot) (sn' : Seq) (hsn : l.sn < sn')
      (refund' : Option Addr) (hnopay : l.pool < p.P) :
      Step p .nextKeys now (.present l)
        {}
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo })
  /-- A rotation that withdraws everything to the refund address: the pause
  (D-033). The rotation itself is the authorization, so it is available from
  either poisoned state. -/
  | rotateWithdraw {l : Live} (now : Slot) (sn' : Seq) (hsn : l.sn < sn')
      (refund' : Option Addr) :
      Step p .nextKeys now (.present l)
        { toRefund := l.dreg + l.b + l.pool }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           refundTo := refund'.getD l.refundTo, dreg := 0, b := 0, pool := 0 })
  /-- A rotation that restores both bonds to full: resurrection from a pause,
  unfreeze after a freeze (D-026, D-034). Resets juvenility. -/
  | rotateDeposit {l : Live} (now : Slot) (sn' : Seq) (hsn : l.sn < sn')
      (refund' : Option Addr) (hd : l.dreg ≤ p.D) (hb : l.b ≤ p.B) :
      Step p .nextKeys now (.present l)
        { deposited := (p.D - l.dreg) + (p.B - l.b) }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                           bornAt := now, refundTo := refund'.getD l.refundTo,
                           dreg := p.D, b := p.B })
  /-- The poison: a declaration by the current quorum against the current
  epoch (D-022, D-023). Enabled only once per epoch; touches no value. -/
  | poison {l : Live} (now : Slot) (hclean : l.poisoned = false) :
      Step p .currentQuorum now (.present l) {} (.present { l with poisoned := true })
  /-- The freeze (D-034): anyone presenting a later witnessed rotation while
  the pool does not cover the premium takes the freeze bond and leaves the
  datum as it is — the old keys stay. Modelling assumption: not enabled from
  a poisoned state (already unconsumable). -/
  | freeze {l : Live} (now : Slot) (hpool : l.pool < p.P) (hb : l.b = p.B)
      (hclean : l.poisoned = false) :
      Step p .proof now (.present l) { toHunter := p.B } (.present { l with b := 0 })
  /-- Anyone may add to the pool; the datum is untouched. -/
  | topUp {l : Live} (now : Slot) (x : Value) :
      Step p .anyone now (.present l) { deposited := x } (.present { l with pool := l.pool + x })
  /-- Conviction (D-030, D-031): a verified duplicity proof — two rotations at
  the tip's sequence revealing the current keys, each receipted at `toad` by
  the tip's witnesses — seizes the conviction bond to the convictor and ends
  the machine. Modelling assumption: the freeze bond and the pool return to
  the refund address. -/
  | convict {l : Live} (now : Slot) :
      Step p .proof now (.present l)
        { toRefund := l.b + l.pool, toConvictor := l.dreg }
        (.convicted l.epoch l.sn)
  /-- Close (D-028, D-032): the current quorum, unpoisoned only; everything
  goes to the refund address, the closer chooses when and never where. -/
  | close {l : Live} (now : Slot) (hclean : l.poisoned = false) :
      Step p .currentQuorum now (.present l)
        { toRefund := l.dreg + l.b + l.pool }
        .gone

/-- A trace: steps at non-decreasing slots. -/
inductive Trace (p : Params) : Slot → State → State → Prop
  | nil (t : Slot) (s : State) : Trace p t s s
  | cons {t t' : Slot} {s s' s'' : State} {a : Actor} {f : Flow}
      (hle : t ≤ t') (hs : Step p a t' s f s') (rest : Trace p t' s' s'') :
      Trace p t s s''

/-- Reachable from `absent` at any slot. -/
def Reachable (p : Params) (s : State) : Prop :=
  ∃ t, Trace p t .absent s

/-! ## The system level: one incarnation per AID, ever (D-024) -/

/-- AIDs. -/
abbrev AID := Nat

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
absence proof (mint-once); every other step leaves the registry alone. -/
inductive SysStep (p : Params) : Sys → Sys → Prop
  | register {s : Sys} {aid : AID} {now : Slot} {f : Flow} {st' : State}
      (habs : aid ∉ s.registered)
      (hstep : Step p .anyone now (s.states aid) f st')
      (hfrom : s.states aid = .absent) :
      SysStep p s { registered := aid :: s.registered, states := (s.set aid st').states }
  | other {s : Sys} {aid : AID} {a : Actor} {now : Slot} {f : Flow} {st' : State}
      (hstep : Step p a now (s.states aid) f st')
      (hnotabs : s.states aid ≠ .absent) :
      SysStep p s (s.set aid st')

/-- System reachability. -/
inductive SysReach (p : Params) : Sys → Prop
  | init : SysReach p Sys.init
  | step {s s' : Sys} (h : SysReach p s) (hs : SysStep p s s') : SysReach p s'

end CardanoKeri.Checkpoint
