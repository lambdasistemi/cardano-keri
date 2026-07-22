/-!
# The M1 checkpoint lifecycle as the validator's transition system

Abstract model of exactly what the on-chain validator admits or rejects
(epic #24, ticket #124). No cryptography: signatures, witness receipts and
fork proofs are abstracted into guard predicates (see the KEL-abstraction
boundary note in `lean/README.md`). No actors, honesty labels, fairness or
economics: those are off-chain concerns (scope correction, 2026-07-21).

Sources: "Permissionless bridging + incentivised freeze" design note
(LOCKED 2026-07-21) and the epic-owner verification note (2026-07-21).
-/

namespace CardanoKeri

/-- Chain time. A transition's single `slot` abstracts the validity range the
real transaction carries (deadline semantics via validity ranges: responses
carry an upper bound `< deadline`, claims/finalizations a lower bound
`≥ deadline`). -/
abbrev Slot := Nat

/-- KEL sequence numbers. -/
abbrev Seq := Nat

/-- Abstract addresses (hunter pkhs, convictor payout targets, refund
addresses). -/
abbrev Addr := Nat

/-- Lovelace amounts; `B` and `D` are both lovelace, so value accounting is
pure arithmetic. -/
abbrev Value := Nat

/-- Deployment parameters. -/
structure Params where
  /-- min-ADA riding on the checkpoint UTxO; released (burnt out) on every
  exit — close, reap, or convict. Nothing keeps a UTxO just to remember. -/
  minAda : Value
  /-- `D_reg`, the conviction deposit — forfeit to a convictor on a fork. -/
  D : Value
  /-- `B`, the freeze bond — paid to a hunter on abandonment. Separate from `D`. -/
  B : Value
  /-- `W_freeze`: the ARMED response window, in slots. -/
  Wf : Nat
  /-- `W_close`: the CLOSING challenge window, in slots. -/
  Wc : Nat
  /-- `W_reap`: the REAPING abandonment window, in slots (third challenge
  window; months-scale, `≫ Wf`). -/
  Wr : Nat

/-- An abstract KEL event; only its sequence number is visible to the model. -/
structure Event where
  seq : Seq

/-- The abstract KEL of one AID: the event list the validator's per-event
verification (own signatures + witness receipts over `event_bytes`) gives
access to. -/
structure Kel where
  events : List Event
  /-- Well-formedness: the i-th event carries sequence number i. -/
  wf : ∀ (i : Nat) (h : i < events.length), (events[i]'h).seq = i

/-- The KEL contains a validly-signed, witnessed event at sequence `s`.
This is the whole verification stack collapsed to a predicate. -/
def Kel.hasEvent (kel : Kel) (s : Seq) : Prop := s < kel.events.length

/-- The last event position (meaningful only for a non-empty KEL). -/
def Kel.tip (kel : Kel) : Seq := kel.events.length - 1

/-- A checkpoint at position `k` is behind iff the real successor event
exists: `tip > k ↔ hasEvent (k+1)`. -/
def Kel.behind (kel : Kel) (k : Seq) : Prop := kel.hasEvent (k + 1)

/-- The per-trace environment: what proofs the outside world can present to
the validator. Fixed for the duration of a trace (modeling boundary — see
README). -/
structure Env where
  kel : Kel
  /-- Verifiable fork evidence for this AID is presentable (convict guard). -/
  fork : Prop
  /-- A valid signature by the seq-`k` datum keys is presentable — models the
  closeIntent datum-key signature check ONLY, not key custody or honesty. -/
  canClose : Seq → Prop

/-- Where a REAPING state was entered from — the only thing that distinguishes
a reap of an abandoned FROZEN checkpoint (escrow `min + D`, bond already paid
out) from a reap of a stale-and-behind CLOSING checkpoint (escrow
`min + D + B`). Fixes the reaping UTxO's value and the thaw top-up. -/
inductive ReapOrigin where
  | fromFrozen
  | fromClosing

/-- Machine states of one token instance. The burn axiom removed the eternal
`tombstone` residue (convict now burns straight to `absent`); `reaping` — the
third, abandonment challenge window — replaces it as a live, transient role. -/
inductive MachState where
  | absent
  | active (k : Seq)
  | armed (k : Seq) (hunter : Addr) (deadline : Slot)
  | frozen (k : Seq)
  | closing (k : Seq) (refund : Addr) (deadline : Slot)
  | reaping (k : Seq) (reaper : Addr) (deadline : Slot) (origin : ReapOrigin)

/-- The mirrored KEL position, when the instance exists on-chain. -/
def MachState.seq? : MachState → Option Seq
  | .absent => none
  | .active k => some k
  | .armed k _ _ => some k
  | .frozen k => some k
  | .closing k _ _ => some k
  | .reaping k _ _ _ => some k

/-- Live (non-terminal, on-chain) states: the five spendable role states —
the reaping challenge window is live (advance-voidable / reap-executable),
never an absorbing residue. -/
def MachState.live : MachState → Prop
  | .active _ => True
  | .armed _ _ _ => True
  | .frozen _ => True
  | .closing _ _ _ => True
  | .reaping _ _ _ _ => True
  | _ => False

/-- The escrow a REAPING UTxO carries, by origin: a FROZEN reap keeps
`min + D` (the bond already left as a bounty); a stale-CLOSING reap keeps the
full `min + D + B`. -/
def reapEscrow (p : Params) : ReapOrigin → Value
  | .fromFrozen => p.minAda + p.D
  | .fromClosing => p.minAda + p.D + p.B

/-- The deposit a thaw-out-of-reaping must re-post to top the successor escrow
back to exactly `min + D + B` (generalises the frozen thaw's `B` re-post):
`reapEscrow o + reapTopUp o = min + D + B` for either origin. -/
def reapTopUp (p : Params) : ReapOrigin → Value
  | .fromFrozen => p.B
  | .fromClosing => 0

/-- The value-ledger rule: what each state's UTxO carries.
Active/Armed/Closing: `min + D + B`; Frozen: `min + D` (B paid out);
Reaping: its origin's escrow; Absent: nothing (everything burnt/paid out). -/
def carried (p : Params) : MachState → Value
  | .absent => 0
  | .active _ => p.minAda + p.D + p.B
  | .armed _ _ _ => p.minAda + p.D + p.B
  | .frozen _ => p.minAda + p.D
  | .closing _ _ _ => p.minAda + p.D + p.B
  | .reaping _ _ _ o => reapEscrow p o

/-- Why a payout left the machine. -/
inductive TransferKind where
  /-- The bond `B` paid to a hunter (claim; convict from Armed). -/
  | bounty
  /-- Value forfeited to a convictor on a fork. -/
  | forfeiture
  /-- `min + D + B` returned by an unchallenged finalized close. -/
  | refund
  /-- The whole remaining escrow taken by a reaper on an untouched
  abandonment window (the reap burn). -/
  | reap

/-- One payout out of the machine. -/
structure Transfer where
  dest : Addr
  amount : Value
  kind : TransferKind

/-- Cumulative value accounting, so conservation is statable:
everything paid in, and an append-only log of everything paid out. -/
structure Ledger where
  /-- Total value ever paid INTO the machine (register; thaw re-post). -/
  deposits : Value
  /-- Append-only log of payouts. -/
  outflows : List Transfer

def outflowTotal : List Transfer → Value
  | [] => 0
  | tr :: trs => tr.amount + outflowTotal trs

/-- One instance's full configuration: machine state + value accounting. -/
structure Config where
  state : MachState
  ledger : Ledger

def initConfig : Config := ⟨.absent, ⟨0, []⟩⟩

/-- Conservation: value carried on the UTxO plus value paid out equals value
paid in. -/
def Config.balanced (p : Params) (cfg : Config) : Prop :=
  carried p cfg.state + outflowTotal cfg.ledger.outflows = cfg.ledger.deposits

/-- Validator redeemers. Addresses carried by an action are submitter-chosen
inputs the validator records or pays to — never authority. -/
inductive Action where
  | register
  | advance
  | arm (hunter : Addr)
  | claim
  | closeIntent (refund : Addr)
  | challengeClose (challenger : Addr)
  | finalizeClose
  | convict (convictor : Addr)
  /-- Post a reap-intent (abandonment challenge) recording the reaper. -/
  | reapIntent (reaper : Addr)
  /-- Execute a reap after an untouched window: burn the UTxO, pay the reaper. -/
  | reapExecute

/-- A transition occurrence: the slot it happens at and the action taken. -/
structure Tx where
  slot : Slot
  act : Action

/-- The transition relation: exactly the spends the validator admits.
Everything is permissionless except `closeIntent` (datum-key capability) and
`convict` (fork evidence); those guards live in `Env`. -/
inductive Step (p : Params) (env : Env) : Config → Tx → Config → Prop
  /-- Absent → Active 0. Requires the (verified) inception event; escrows
  `min + D + B`. -/
  | register {led : Ledger} {t : Slot}
      (hicp : env.kel.hasEvent 0) :
      Step p env ⟨.absent, led⟩ ⟨t, .register⟩
        ⟨.active 0, { led with deposits := led.deposits + (p.minAda + p.D + p.B) }⟩
  /-- Active k → Active (k+1). Projection determinism: the only admissible
  target is the real event `k+1`. -/
  | advanceActive {led : Ledger} {k : Seq} {t : Slot}
      (hnext : env.kel.hasEvent (k + 1)) :
      Step p env ⟨.active k, led⟩ ⟨t, .advance⟩ ⟨.active (k + 1), led⟩
  /-- Armed k → Active (k+1): the freeze response, strictly before the
  deadline. `B` is reconstituted (it never left). -/
  | advanceArmed {led : Ledger} {k : Seq} {hunter : Addr} {d : Slot} {t : Slot}
      (hnext : env.kel.hasEvent (k + 1)) (hwin : t < d) :
      Step p env ⟨.armed k hunter d, led⟩ ⟨t, .advance⟩ ⟨.active (k + 1), led⟩
  /-- Frozen k → Active (k+1): thaw; the advancer re-posts `B`. -/
  | advanceFrozen {led : Ledger} {k : Seq} {t : Slot}
      (hnext : env.kel.hasEvent (k + 1)) :
      Step p env ⟨.frozen k, led⟩ ⟨t, .advance⟩
        ⟨.active (k + 1), { led with deposits := led.deposits + p.B }⟩
  /-- Closing k → Active (k+1): the direct void — an ordinary advance IS a
  later-event proof and applies it. REQUIRED; admissible at every slot while
  the state is Closing. -/
  | advanceClosing {led : Ledger} {k : Seq} {r : Addr} {d : Slot} {t : Slot}
      (hnext : env.kel.hasEvent (k + 1)) :
      Step p env ⟨.closing k r d, led⟩ ⟨t, .advance⟩ ⟨.active (k + 1), led⟩
  /-- Active k → Armed: permissionless freeze-arm on a provably-behind
  checkpoint; records the hunter and `deadline = slot + Wf`. -/
  | arm {led : Ledger} {k : Seq} {t : Slot} (hunter : Addr)
      (hbehind : env.kel.behind k) :
      Step p env ⟨.active k, led⟩ ⟨t, .arm hunter⟩
        ⟨.armed k hunter (t + p.Wf), led⟩
  /-- Armed k → Frozen k: at/after the deadline, pays exactly `B` to the
  hunter recorded at arm time. -/
  | claim {led : Ledger} {k : Seq} {hunter : Addr} {d : Slot} {t : Slot}
      (hdeadline : d ≤ t) :
      Step p env ⟨.armed k hunter d, led⟩ ⟨t, .claim⟩
        ⟨.frozen k, { led with outflows := led.outflows ++ [⟨hunter, p.B, .bounty⟩] }⟩
  /-- Active k → Closing: close-intent, the one capability-gated action
  (datum-key signature at `k`); records the refund address and
  `deadline = slot + Wc`. No tip check — the intent is optimistic. -/
  | closeIntent {led : Ledger} {k : Seq} {t : Slot} (refund : Addr)
      (hcap : env.canClose k) :
      Step p env ⟨.active k, led⟩ ⟨t, .closeIntent refund⟩
        ⟨.closing k refund (t + p.Wc), led⟩
  /-- Closing k → Armed k: a later-event proof voids the intent; the
  challenger is recorded as hunter with a fresh `Wf` deadline. Admissible at
  every slot while the state is Closing. -/
  | challengeClose {led : Ledger} {k : Seq} {r : Addr} {d : Slot} {t : Slot}
      (challenger : Addr) (hbehind : env.kel.behind k) :
      Step p env ⟨.closing k r d, led⟩ ⟨t, .challengeClose challenger⟩
        ⟨.armed k challenger (t + p.Wf), led⟩
  /-- Closing k → Absent: unchallenged intent finalizes at/after the
  deadline; burns the token and refunds `min + D + B` to the recorded
  address. Permissionless to trigger. -/
  | finalizeClose {led : Ledger} {k : Seq} {r : Addr} {d : Slot} {t : Slot}
      (hdeadline : d ≤ t) :
      Step p env ⟨.closing k r d, led⟩ ⟨t, .finalizeClose⟩
        ⟨.absent, { led with outflows := led.outflows ++ [⟨r, p.minAda + p.D + p.B, .refund⟩] }⟩
  /-- Active k → Absent on fork evidence (the burn axiom: convict BURNS, no
  tombstone residue). Full escrow out: `D` and `B` and the freed min-ADA to
  the convictor. -/
  | convictActive {led : Ledger} {k : Seq} {t : Slot} (c : Addr)
      (hfork : env.fork) :
      Step p env ⟨.active k, led⟩ ⟨t, .convict c⟩
        ⟨.absent, { led with outflows := led.outflows ++
          [⟨c, p.D, .forfeiture⟩, ⟨c, p.B, .forfeiture⟩, ⟨c, p.minAda, .forfeiture⟩] }⟩
  /-- Armed k → Absent on fork evidence: `D` and the freed min-ADA to the
  convictor, `B` to the armed hunter (the one routing exception). -/
  | convictArmed {led : Ledger} {k : Seq} {hunter : Addr} {d : Slot} {t : Slot}
      (c : Addr) (hfork : env.fork) :
      Step p env ⟨.armed k hunter d, led⟩ ⟨t, .convict c⟩
        ⟨.absent, { led with outflows := led.outflows ++
          [⟨c, p.D, .forfeiture⟩, ⟨hunter, p.B, .bounty⟩, ⟨c, p.minAda, .forfeiture⟩] }⟩
  /-- Frozen k → Absent on fork evidence: `D` and the freed min-ADA to the
  convictor (`B` is already gone). -/
  | convictFrozen {led : Ledger} {k : Seq} {t : Slot} (c : Addr)
      (hfork : env.fork) :
      Step p env ⟨.frozen k, led⟩ ⟨t, .convict c⟩
        ⟨.absent, { led with outflows := led.outflows ++
          [⟨c, p.D, .forfeiture⟩, ⟨c, p.minAda, .forfeiture⟩] }⟩
  /-- Closing k → Absent on fork evidence: `D` and `B` and the freed min-ADA
  to the convictor (convict dominates every live state). -/
  | convictClosing {led : Ledger} {k : Seq} {r : Addr} {d : Slot} {t : Slot}
      (c : Addr) (hfork : env.fork) :
      Step p env ⟨.closing k r d, led⟩ ⟨t, .convict c⟩
        ⟨.absent, { led with outflows := led.outflows ++
          [⟨c, p.D, .forfeiture⟩, ⟨c, p.B, .forfeiture⟩, ⟨c, p.minAda, .forfeiture⟩] }⟩
  /-- Reaping → Absent on fork evidence: the whole carried escrow to the
  convictor (not armed, so no hunter exception). -/
  | convictReaping {led : Ledger} {k : Seq} {reaper : Addr} {d : Slot}
      {o : ReapOrigin} {t : Slot} (c : Addr) (hfork : env.fork) :
      Step p env ⟨.reaping k reaper d o, led⟩ ⟨t, .convict c⟩
        ⟨.absent, { led with outflows := led.outflows ++ [⟨c, reapEscrow p o, .forfeiture⟩] }⟩
  /-- Frozen k → Reaping: the abandonment challenge. Permissionless (anyone
  may reap a truly-abandoned checkpoint); records the reaper and
  `deadline = slot + Wr`. Escrow (`min + D`) is untouched. -/
  | reapIntentFrozen {led : Ledger} {k : Seq} {t : Slot} (reaper : Addr) :
      Step p env ⟨.frozen k, led⟩ ⟨t, .reapIntent reaper⟩
        ⟨.reaping k reaper (t + p.Wr) .fromFrozen, led⟩
  /-- Closing k → Reaping: reap-intent on a stale-and-behind CLOSING (deadline
  passed unfinalized, and a later event exists — a genuinely non-current
  close). The behind guard is a soundness strengthening over the brief's
  "stale only" (see Q-B01): it keeps reap off an honest tip-close's refund and
  makes every reachable reaping behind. Escrow (`min + D + B`) is untouched. -/
  | reapIntentClosing {led : Ledger} {k : Seq} {r : Addr} {d : Slot} {t : Slot}
      (reaper : Addr) (hstale : d ≤ t) (hbehind : env.kel.behind k) :
      Step p env ⟨.closing k r d, led⟩ ⟨t, .reapIntent reaper⟩
        ⟨.reaping k reaper (t + p.Wr) .fromClosing, led⟩
  /-- Reaping → Active (k+1): the advance-void — a later-event proof voids the
  reap and applies it; the advancer tops the successor escrow back to exactly
  `min + D + B` (generalises thaw). REQUIRED, admissible at every slot while
  reaping. -/
  | advanceReaping {led : Ledger} {k : Seq} {reaper : Addr} {d : Slot}
      {o : ReapOrigin} {t : Slot} (hnext : env.kel.hasEvent (k + 1)) :
      Step p env ⟨.reaping k reaper d o, led⟩ ⟨t, .advance⟩
        ⟨.active (k + 1), { led with deposits := led.deposits + reapTopUp p o }⟩
  /-- Reaping → Absent: an untouched full window lets the reaper burn the UTxO
  and take the whole remaining escrow (the `.reap` transfer). -/
  | reapExecute {led : Ledger} {k : Seq} {reaper : Addr} {d : Slot}
      {o : ReapOrigin} {t : Slot} (hdeadline : d ≤ t) :
      Step p env ⟨.reaping k reaper d o, led⟩ ⟨t, .reapExecute⟩
        ⟨.absent, { led with outflows := led.outflows ++ [⟨reaper, reapEscrow p o, .reap⟩] }⟩

/-- A slot-monotone (non-strict) run of the machine, starting no earlier than
the given slot. -/
inductive TraceFrom (p : Params) (env : Env) : Slot → Config → List Tx → Config → Prop
  | nil (t : Slot) (cfg : Config) : TraceFrom p env t cfg [] cfg
  | cons {t : Slot} {cfg cfg' cfg'' : Config} {tx : Tx} {txs : List Tx}
      (hmono : t ≤ tx.slot)
      (hstep : Step p env cfg tx cfg')
      (hrest : TraceFrom p env tx.slot cfg' txs cfg'') :
      TraceFrom p env t cfg (tx :: txs) cfg''

/-- Reachable from the empty instance. -/
def Reachable (p : Params) (env : Env) (cfg : Config) : Prop :=
  ∃ txs, TraceFrom p env 0 initConfig txs cfg

/-- Instance identifiers: distinct checkpoint UTxOs for the same AID
(duplicate registration is allowed — no mint-once). -/
abbrev InstanceId := Nat

/-- A family of instances of the SAME AID, sharing one `Env`. Needed only to
state that a burnt (convicted) instance bars nothing on a fresh one. -/
abbrev Sys := InstanceId → Config

/-- One instance steps; the others are untouched. -/
inductive SysStep (p : Params) (env : Env) : Sys → InstanceId → Tx → Sys → Prop
  | step {sys : Sys} {i : InstanceId} {tx : Tx} {cfg' : Config}
      (h : Step p env (sys i) tx cfg') :
      SysStep p env sys i tx (fun j => if j = i then cfg' else sys j)

end CardanoKeri
