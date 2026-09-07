/-!
# The M1 return: the checkpoint machine

Abstract model of what the on-chain validator family admits under the design
ruled on 2026-09-02 and 2026-09-03 (project decisions D-022 … D-040; plan
`AUDIT-M1-RETURN`, Phase 0.2 and 0.4, 2.15–2.17 with the D-040 addendum). It
replaced the freeze/bond/convict/reap machine of `Lifecycle.lean`, retired
with the enforcement economy in Phase 1 and removed in #366; Checkpoint is
now the sole compiled lifecycle specification.

Fourth cut, the third Lean slice (D-039, D-040), after the registry's slice 3:

* **D-040, three registry states, one UTxO.** An identity is **active** (the
  checkpoint UTxO exists: live, poisoned or frozen), **parked** (no UTxO; the
  registry leaf holds the hash of the last checkpoint) or **convicted**
  (terminal; the leaf holds nothing but the mark). The withdraw option and
  the unbonded on-chain state are gone: a present checkpoint always holds
  the conviction bond, and the only bond that can be missing is the freeze
  bond, taken by a hunter's freeze. Leaving is the **reap** — the close of
  D-036: a witnessed rotation by the next keys with the D-038 signed intent
  naming the refund address, everything paid to that address, the UTxO
  burned, the leaf parked with the hash. The close message also names the
  **payee** of the rotation's premium (D-039): the closer chooses when,
  never where the bonds go and never who is paid, so the copied reap with
  the payee rewritten (the registry's Q-R6) is refused. **Deposit survives
  as the unfreeze**: it refills the freeze bond when it is missing and is a no-op on
  full bonds — a keep with a deposit's signature — still signed by the new
  keys (D-038).
* **The parked hash.** With no cryptography in the model, the hash the leaf
  holds is the key state it commits to: the epoch and the sequence the
  closing rotation reached. The only way back is a witnessed rotation from
  exactly that key state (a rotation *later* than the parked sequence; the
  close's own rotation cannot revive), with fresh bonds, a first pool, a
  refund address chosen by whoever pays, born now (D-036, D-040). What the
  hash does not commit: the refund address, the pool and the juvenility slot.
* **A parked identity can be convicted.** The registry on `main` convicts a
  dormant leaf by a duplicity proof against its recorded key state (its
  story 13, D-030); the checkpoint machine admits the same edge with no
  value flow, so that the two machines compose.
* **The registry's grace window is not the checkpoint's `W`.** Juvenility
  `W` stays consumer policy (T9); no grace window exists in this machine.

Kept from the second slice (D-036, D-037, D-038): evidence as guards on the
constructors, actions carrying their parameters, addressed component-wise
flows, the functional `stepFn` mirroring the relation, positive bonds, the
signed intent, the leaf map as the registry's interface.

No cryptography. Keys are abstracted to an epoch counter: a rotation opens
the next epoch. Two details of D-034 stay fixed here as modelling
assumptions, documented on the constructor: a freeze is not enabled from a
poisoned state, and conviction sends the freeze bond and the pool to the
refund address while the conviction bond goes to the convictor. Validity
(D-027, A11) is reserved in the datum and not modelled; threshold
satisfaction by a consumer's own signature is the consumer's check, outside
this machine — `consumableState` names exactly the state-side conjuncts.
Not modelled either: the MPFS request mechanics that land leaf changes
(batches, appliers, tips, windows) — the leaf map is the interface the
registry provides; the hash function and the pre-image a revival presents —
the leaf holds the key state and the check is equality; who pays the
transaction fee.
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

/-- The bond option a rotation carries (D-033 as amended by D-040): `keep`,
or `deposit` — the unfreeze, which refills the freeze bond when it is
missing and brings nothing otherwise. The withdraw option is gone: leaving
is the close. -/
inductive BondOp where
  | keep
  | deposit
  deriving DecidableEq, Repr

/-- What the new keys sign along with the refund address (D-038): the bond
option of a rotation, or the close naming its payee (D-039: the close message
names who is paid, so a copied reap with the payee rewritten is refused).
`keep` with no new address is the empty message and needs no signature. -/
inductive Intent where
  | keep
  | deposit
  | close (payee : Addr)
  deriving DecidableEq, Repr

/-- The intent of a bond option. -/
def BondOp.intent : BondOp → Intent
  | .keep => .keep
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
  the close evidence (D-036) and, from a parked leaf, the revival
  evidence: a witnessed rotation path from the parked key state to `sn'`
  (several off-chain rotations collapse into one predicate). Only the
  holder of the next keys of `(e, sn)` can make it true: a thief of the
  current keys cannot. -/
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
  /-- Close — the reap (D-036, D-039, D-040): a witnessed rotation to `sn'`
  naming the payee of its premium, that pays everything else to the refund
  address (optionally a new one the new keys authorized), burns the UTxO
  and parks the leaf with the hash. The payee and the address are one
  message the new keys sign (D-038, D-039). -/
  | close (sn' : Seq) (payee : Addr) (refund' : Option Addr)
  /-- Reopen — the revival (D-036, D-040): from a parked leaf, a witnessed
  rotation later than the parked key state, fresh bonds, a first pool and a
  refund address chosen by whoever pays. -/
  | reopen (sn' : Seq) (refund : Addr) (pool0 : Value)
  deriving Repr

/-- The actor an action needs: the party whose signature or evidence the
validator checks. `proof` is a permissionless party presenting witnessed
evidence — a freeze, a conviction, and a reopen (its rotation path from
the parked key state, D-036); `anyone` presents nothing but money and a
public inception. -/
def Action.actor : Action → Actor
  | .register .. => .anyone
  | .rotate .. => .nextKeys
  | .poison => .currentQuorum
  | .freeze .. => .proof
  | .topUp .. => .anyone
  | .convict .. => .proof
  | .close .. => .nextKeys
  | .reopen .. => .proof

/-- The key state a checkpoint records: the epoch of its current keys and
the sequence of the establishment event reflected. -/
structure KeyState where
  epoch : Epoch
  sn : Seq
  deriving Repr, DecidableEq

/-- What the parked leaf holds: the hash of the last checkpoint (D-040).
With no cryptography in the model the hash *is* the key state it commits
to — a revival presents the key state and the registry checks it against
the leaf, which here is equality. The refund address, the pool and the
juvenility slot are not committed: a revival brings fresh bonds, a first
pool, a refund address chosen by whoever pays, and is born now. -/
abbrev Hash := KeyState

/-- The datum plus the value of a present checkpoint. The conviction bond is
always held in full (D-040: no unbonded on-chain state), so it is not a
field; the freeze bond is held unless `frozen`. -/
structure Live where
  /-- `native_sn` of the establishment event reflected. -/
  sn : Seq
  /-- The key epoch: which pre-rotation commitment is current. -/
  epoch : Epoch
  /-- The declared poison bit, local to the current keys (D-022). -/
  poisoned : Bool
  /-- The freeze bond is missing: taken by a hunter's freeze, restored by a
  depositing rotation (D-034, D-040). -/
  frozen : Bool
  /-- Slot of the bonding: register or reopen (juvenility, A9). -/
  bornAt : Slot
  /-- Where the bonds go at close (D-032). -/
  refundTo : Addr
  /-- Advance funds. -/
  pool : Value
  deriving Repr, DecidableEq

/-- The key state a present checkpoint records: what its hash commits to. -/
def Live.hash (l : Live) : Hash := ⟨l.epoch, l.sn⟩

/-- The freeze bond a present checkpoint holds: `B`, or nothing while frozen. -/
def Live.bHeld (p : Params) (l : Live) : Value := if l.frozen then 0 else p.B

/-- The datum a rotation to `sn'` leaves before its bond option is applied
(D-033, D-034, D-032, D-038): next epoch, poison cleared, the refund address
moved only if the new keys authorized it, the premium taken from the pool
when the pool covers it; the freeze bit and the juvenility slot untouched.
The constructors of `Step` spell this out field by field; the theorems use
this name to say "keep-shaped" (`T5_keep_is_rotated`,
`T5_deposit_on_full_is_keep`, `T16_parked_hash_is_the_closed_checkpoints`). -/
def Live.rotated (p : Params) (l : Live) (sn' : Seq) (refund' : Option Addr) : Live :=
  { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
           refundTo := refund'.getD l.refundTo,
           pool := if p.P ≤ l.pool then l.pool - p.P else l.pool }

/-- The lifecycle states — D-040's three registry states and `absent`. -/
inductive State where
  /-- Never registered. -/
  | absent
  /-- Active: the checkpoint UTxO exists — live, poisoned or frozen;
  consumable or not according to `consumableState`. -/
  | present (l : Live)
  /-- Parked (D-036, D-040): the UTxO is burned; the registry leaf holds the
  hash of the last checkpoint — the key state the closing rotation reached.
  Not terminal: a witnessed rotation later than it revives; a duplicity
  proof against it convicts. -/
  | parked (h : Hash)
  /-- Convicted (D-030, D-040): terminal; the leaf holds nothing but the
  mark. No transition leaves it. -/
  | convicted
  deriving Repr, DecidableEq

/-- The sequence a state records, when it records one. -/
def State.sn? : State → Option Seq
  | .present l => some l.sn
  | .parked h => some h.sn
  | .absent => none
  | .convicted => none

/-- One payment line: an address and how much of each component it receives. -/
structure Payment where
  addr : Addr
  dreg : Value := 0
  b : Value := 0
  pool : Value := 0
  deriving Repr, DecidableEq

/-- The premium a landed rotation pays its payee: `P` from the pool when the
pool covers it, nothing otherwise — payment is never a gate (D-034, T14). -/
def Params.premium (p : Params) (l : Live) (payee : Addr) : Option Payment :=
  if p.P ≤ l.pool then some { addr := payee, pool := p.P } else none

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

/-- Component held by a state: the conviction bond in full by every present
checkpoint, nothing by a parked or convicted leaf (D-040). -/
def State.dregHeld (p : Params) : State → Value
  | .present _ => p.D
  | _ => 0

def State.bHeld (p : Params) : State → Value
  | .present l => l.bHeld p
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

/-- The state-side conjuncts of what a consumer accepts: the freeze bond
held, unpoisoned, past juvenility (the conviction bond is always held). The
consumer's own threshold check on its transaction, and validity once A11
ships, are outside this machine. -/
def consumableState (p : Params) (now : Slot) : State → Prop
  | .present l => l.frozen = false ∧ l.poisoned = false ∧ l.bornAt + p.W ≤ now
  | _ => False

/-- The decidable mirror of `consumableState`: what a consumer, the trace
driver and the simulator actually run. `consumableStateB_iff` ties the two. -/
def consumableStateB (p : Params) (now : Slot) : State → Bool
  | .present l => l.frozen == false && l.poisoned == false && decide (l.bornAt + p.W ≤ now)
  | _ => false

/-- The transition relation: exactly the spends the validator family admits. -/
inductive Step (p : Params) (env : Env) : Action → Slot → State → Flow → State → Prop
  /-- Absent → Present. The inception is public, so registration is
  permissionless; mint-once is the registry's job (`Sys`). Both bonds come
  in with the first pool. -/
  | register (now : Slot) (refund : Addr) (pool0 : Value) :
      Step p env (.register refund pool0) now .absent
        { dregIn := p.D, bIn := p.B, poolIn := pool0 }
        (.present ⟨0, 0, false, false, now, refund, pool0⟩)
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
  /-- A depositing rotation, paid: the unfreeze (D-034, D-040). It brings the
  freeze bond back when it is missing and nothing otherwise — on full bonds
  it is exactly a paid keep — and the new keys sign the intent (D-038). The
  juvenility slot is untouched: a deposit is not a bonding. -/
  | rotateDepositPaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .deposit refund' = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.rotate sn' .deposit payee refund') now (.present l)
        { bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                           refundTo := refund'.getD l.refundTo, pool := l.pool - p.P })
  /-- A depositing rotation when the pool does not cover the premium. -/
  | rotateDepositUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) .deposit refund' = true)
      (hnopay : l.pool < p.P) :
      Step p env (.rotate sn' .deposit payee refund') now (.present l)
        { bIn := p.B - l.bHeld p }
        (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false,
                           refundTo := refund'.getD l.refundTo })
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
      (hpool : l.pool < p.P) (hb : l.frozen = false) (hclean : l.poisoned = false) :
      Step p env (.freeze sn' payee) now (.present l)
        { hunter := some { addr := payee, b := p.B } }
        (.present { l with frozen := true })
  /-- Anyone may add to the pool; the datum is untouched. -/
  | topUp {l : Live} (now : Slot) (x : Value) :
      Step p env (.topUp x) now (.present l) { poolIn := x } (.present { l with pool := l.pool + x })
  /-- Conviction (D-030, D-031): a verified duplicity proof against the
  checkpoint's key state seizes the conviction bond to the convictor and
  ends the machine. Modelling assumption: the freeze bond, if held, and the
  pool return to the refund address. -/
  | convict {l : Live} (now : Slot) (payee : Addr)
      (hdup : env.duplicityAt l.epoch l.sn = true) :
      Step p env (.convict payee) now (.present l)
        { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
          convictor := some { addr := payee, dreg := p.D } }
        .convicted
  /-- Conviction of a parked identity (D-030; the registry's story 13): a
  verified duplicity proof against the parked key state marks the leaf
  convicted. Nothing is held, so nothing moves; the mark is what a
  conviction buys here: no revival, ever. -/
  | convictParked {h : Hash} (now : Slot) (payee : Addr)
      (hdup : env.duplicityAt h.epoch h.sn = true) :
      Step p env (.convict payee) now (.parked h) {} .convicted
  /-- Close — the reap (D-036, D-032, D-038, D-039, D-040), when the pool
  covers the premium: a witnessed rotation to `sn'`, poisoned or frozen or
  not, whose new keys signed the close intent naming the payee (and the new
  refund address, if any); `P` to the signed payee, everything else the UTxO
  holds to the refund address it results in — the closer chooses when,
  never where, and never who is paid — the UTxO is burned and the leaf is
  parked with the hash of the checkpoint the rotation reached: the epoch it
  opened and its sequence. A copied reap with the payee rewritten presents
  a message the keys never signed and is refused. -/
  | closePaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) (.close payee) refund' = true)
      (hpay : p.P ≤ l.pool) :
      Step p env (.close sn' payee refund') now (.present l)
        { refund := some { addr := refund'.getD l.refundTo, dreg := p.D, b := l.bHeld p, pool := l.pool - p.P },
          hunter := some { addr := payee, pool := p.P } }
        (.parked ⟨l.epoch + 1, sn'⟩)
  /-- The same close when the pool does not cover the premium: nothing to
  the payee, everything to the refund address; payment is never a gate. -/
  | closeUnpaid {l : Live} (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr)
      (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
      (hauth : env.intentOk (l.epoch + 1) (.close payee) refund' = true)
      (hnopay : l.pool < p.P) :
      Step p env (.close sn' payee refund') now (.present l)
        { refund := some { addr := refund'.getD l.refundTo, dreg := p.D, b := l.bHeld p, pool := l.pool } }
        (.parked ⟨l.epoch + 1, sn'⟩)
  /-- Reopen — the revival (D-036, D-040): from a parked leaf, a witnessed
  rotation path from exactly the parked key state to a later sequence, fresh
  bonds and a first pool bring the checkpoint back at the next epoch,
  juvenile, with the refund address whoever pays chose (as at registration:
  the owner moves it at her next rotation). A rotation at the parked
  sequence or earlier cannot revive — the close's own rotation included: no
  stale resurrection. -/
  | reopen {h : Hash} (now : Slot) (sn' : Seq) (refund : Addr) (pool0 : Value)
      (hev : env.rotationTo h.epoch h.sn sn' = true) (hsn : h.sn < sn') :
      Step p env (.reopen sn' refund pool0) now (.parked h)
        { dregIn := p.D, bIn := p.B, poolIn := pool0 }
        (.present ⟨sn', h.epoch + 1, false, false, now, refund, pool0⟩)

/-! ## The functional step: one executable source for the relation, the
fold theorem and the simulator's transcription -/

/-- The functional mirror of `Step`. `T7_step_iff_stepFn` states that the two
agree exactly. -/
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
              .convicted)
      else none
  | .convict _, .parked h =>
      if env.duplicityAt h.epoch h.sn = true then
        some ({}, .convicted)
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

/-! ## The system level: the registry leaf, one per AID (D-036, D-037, D-040) -/

/-- The registry leaf of an AID: D-040's three states and absence. `active`
means the checkpoint UTxO exists and every key-state fact lives in it;
`parked` holds the hash of the last checkpoint and nothing else exists;
`convicted` holds nothing but the mark and is terminal. -/
inductive Leaf where
  | absent
  | active
  | parked (h : Hash)
  | convicted
  deriving DecidableEq, Repr

/-- The leaf a state projects to. -/
def State.leaf : State → Leaf
  | .absent => .absent
  | .present _ => .active
  | .parked h => .parked h
  | .convicted => .convicted

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
reopen the presence proof of the parked leaf with its hash; every other
action is a step on the AID's state, and the leaf follows. -/
inductive SysStep (p : Params) (env : Env) : Sys → Sys → Prop
  | register {s : Sys} {aid : AID} {now : Slot} {refund : Addr} {pool0 : Value} {f : Flow} {st' : State}
      (habs : s.leaves aid = .absent)
      (hstep : Step p env (.register refund pool0) now (s.states aid) f st') :
      SysStep p env s (s.set aid st')
  | reopen {s : Sys} {aid : AID} {now : Slot} {sn' : Seq} {refund : Addr} {pool0 : Value} {f : Flow} {st' : State}
      {h : Hash}
      (hparked : s.leaves aid = .parked h)
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
