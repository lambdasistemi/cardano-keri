/-!
# The AID registry as an MPFS instance: the registry machine

Abstract model of the registry ruled by D-024 (one UTxO holding the MPF root
of every registered AID; registration inserts with an absence proof and mints
the checkpoint token in the same transaction) when it is built as a cage of
cardano-mpfs-onchain on the plugin path (cardano-foundation/cardano-mpfs-onchain#99):

* **requests** are inbox UTxOs — an AID, an owner, a bond, a tip, a
  `submitted_at` the requester wrote — and never contend on anything;
* a **fold** is a permissionless `Modify`: anyone spends the registry at its
  current generation with a non-empty batch, each request processed (phase 1,
  inception evidence, the AID absent from the root → row inserted, checkpoint
  token minted, bond locked into the checkpoint, tip to the folder) or
  rejected (phase 3, or a dishonest timestamp → bond refunded to the owner,
  tip to the folder); a stale generation is refused with no state change; the
  plugin is pinned;
* a **retract** (phase 2, the owner) returns everything and leaves the
  registry alone;
* a **convict** turns the live token into a tombstone and leaves the row.

There is no close: the permissionless registry cannot be left (ruling of
2026-09-03). A row, once inserted, is permanent — D-024's "once ever per
AID" — and a token is live or a tombstone for the rest of the chain's life.
Leaving the checkpoint's economy is the checkpoint machine's pause, which
touches no token. The invariant is *row if and only if token*: an AID is in
the root exactly when it has a live token or a tombstone.

The checkpoint's own life (rotations, bonds, poison) is the machine of
`CardanoKeri.Checkpoint`; here a checkpoint is only its token: absent, live,
or a tombstone. `live` and `tomb` are lists so that "at most one live
checkpoint per AID" is a theorem about counts (`live.Nodup`), not a fact of
the representation.

No cryptography, no MPF: the root is the set of registered AIDs and the
absence proof is membership. The evidence a fold needs is an `Env` of
decidable predicates standing for the checks the plugin and the checkpoint
policy perform. Contention is one counter, the registry UTxO's generation:
a fold names the generation it spends and is refused when it is stale, which
is the transaction failing phase 1 on a spent input, at no cost.

A functional `stepFn` is the one executable source: the theorems are stated
over it, the simulator transcribes it, and the trace driver runs it.
-/

namespace CardanoKeri.Registry

/-- Chain time; a transition's `now` abstracts the transaction validity range
to a point. -/
abbrev Slot := Nat

/-- Abstract addresses. -/
abbrev Addr := Nat

/-- Lovelace. -/
abbrev Value := Nat

/-- AIDs. -/
abbrev AID := Nat

/-- The registry UTxO's generation: incremented by every spend of it. -/
abbrev Gen := Nat

/-- Request identifiers: the inbox UTxOs, numbered at creation. -/
abbrev ReqId := Nat

/-- A script hash: the plugin the cage delegates to. -/
abbrev Script := Nat

/-- Deployment parameters. -/
structure Params where
  /-- The registration bond a request carries and a processed request locks
  into the new checkpoint. -/
  D : Value
  /-- The tip a request carries and a fold pays to the folder per request. -/
  tip : Value
  /-- `process_time`: the length of phase 1 in slots. -/
  process : Nat
  /-- `retract_time`: the length of phase 2 in slots. -/
  retract : Nat
  hD : 0 < D
  hProcess : 0 < process
  hRetract : 0 < retract

/-- The evidence the plugin and the checkpoint policy verify, abstracted at
the KEL boundary. -/
structure Env where
  /-- `inception aid`: the request's inception bytes self-address to `aid`
  and carry controller signatures and receipts at the inception's own
  thresholds (the #114 rule), so the checkpoint policy may mint. -/
  inception : AID → Bool
  /-- `duplicity aid`: a verified duplicity proof against `aid`'s checkpoint
  tip was presented (D-030). -/
  duplicity : AID → Bool

/-- An inbox UTxO. Its bond and tip are the deployment's `D` and `tip`
(`Contribute` pins the tip to the cage's; the bond is the request's value). -/
structure Request where
  aid : AID
  owner : Addr
  /-- Written by the requester; the validators never compare it with the
  creating transaction's validity range. -/
  submittedAt : Slot
  deriving Repr, DecidableEq

/-- What a fold does with one request. -/
inductive FoldAction where
  | process
  | reject
  deriving Repr, DecidableEq

/-- The system: the registry UTxO, the inbox, and every checkpoint's token. -/
structure Sys where
  /-- The registry UTxO's generation. -/
  gen : Gen
  /-- The plugin recorded in the cage datum. -/
  plugin : Script
  /-- The MPF root, as the set of registered AIDs. -/
  root : List AID
  /-- AIDs with a live checkpoint token. -/
  live : List AID
  /-- AIDs whose checkpoint is a tombstone (convicted). -/
  tomb : List AID
  /-- Pending requests. -/
  requests : List (ReqId × Request)
  /-- The next request identifier. -/
  nextReq : ReqId
  deriving Repr, DecidableEq

/-- The registry at genesis: empty root, no tokens, no requests. -/
def Sys.init (plugin : Script) : Sys :=
  ⟨0, plugin, [], [], [], [], 0⟩

/-- Who authorizes a transition; derived from the action. -/
inductive Actor where
  | anyone
  | owner
  | proof
  deriving DecidableEq, Repr

/-- The actions: the redeemers of the cage family and the one checkpoint edge
that touches a token. -/
inductive Action where
  /-- Create a request UTxO. `submittedAt` is the requester's claim. -/
  | contribute (aid : AID) (owner : Addr) (submittedAt : Slot)
  /-- Spend the registry at generation `gen`, re-creating it with plugin
  `plugin`, processing or rejecting each request of `batch` in order. -/
  | fold (folder : Addr) (gen : Gen) (plugin : Script) (batch : List (ReqId × FoldAction))
  /-- The owner takes a request back in phase 2. -/
  | retract (req : ReqId)
  /-- A duplicity proof convicts the checkpoint: token kept as a tombstone. -/
  | convict (aid : AID)
  deriving Repr, DecidableEq

/-- The actor an action needs. -/
def Action.actor : Action → Actor
  | .contribute .. => .anyone
  | .fold .. => .anyone
  | .retract .. => .owner
  | .convict .. => .proof

/-- Value movements of one transition. -/
structure Flow where
  /-- Brought by the requester into a new request: `D + tip`. -/
  deposited : Value := 0
  /-- Bonds locked into new checkpoints, one per processed request. -/
  locked : List (AID × Value) := []
  /-- Paid back to request owners: `D` on a reject, `D + tip` on a retract. -/
  refunds : List (Addr × Value) := []
  /-- Paid to the folder: `tip` per request of the batch. -/
  tips : Option (Addr × Value) := none
  deriving Repr, DecidableEq

/-! ## Phases (the cage's `in_phase1`, `in_phase2`, `is_rejectable`, at a point) -/

/-- Phase 1: before `submitted_at + process_time`. A future `submitted_at`
is in phase 1 too, as on chain. -/
def inPhase1 (p : Params) (r : Request) (now : Slot) : Prop :=
  now < r.submittedAt + p.process

/-- Phase 2: from `submitted_at + process_time` for `retract_time` slots. -/
def inPhase2 (p : Params) (r : Request) (now : Slot) : Prop :=
  r.submittedAt + p.process ≤ now ∧ now < r.submittedAt + p.process + p.retract

/-- Rejectable: phase 3, or a `submitted_at` in the future. -/
def rejectable (p : Params) (r : Request) (now : Slot) : Prop :=
  r.submittedAt + p.process + p.retract ≤ now ∨ now < r.submittedAt

instance (p : Params) (r : Request) (now : Slot) : Decidable (inPhase1 p r now) := by
  unfold inPhase1; infer_instance
instance (p : Params) (r : Request) (now : Slot) : Decidable (inPhase2 p r now) := by
  unfold inPhase2; infer_instance
instance (p : Params) (r : Request) (now : Slot) : Decidable (rejectable p r now) := by
  unfold rejectable; infer_instance

/-! ## The inbox -/

/-- The request with identifier `id`, if pending: the first entry with that
identifier (under `Inv` there is at most one). -/
def lookup : List (ReqId × Request) → ReqId → Option Request
  | [], _ => none
  | (i, r) :: rs, id => if i = id then some r else lookup rs id

/-- The inbox without every entry with identifier `id`. -/
def remove : List (ReqId × Request) → ReqId → List (ReqId × Request)
  | [], _ => []
  | (i, r) :: rs, id => if i = id then remove rs id else (i, r) :: remove rs id

/-! ## The fold -/

/-- What a fold threads through its batch. -/
structure Acc where
  root : List AID
  live : List AID
  requests : List (ReqId × Request)
  locked : List (AID × Value)
  refunds : List (Addr × Value)
  deriving Repr, DecidableEq

/-- Apply a batch in order. A processed request needs phase 1, inception
evidence and the AID absent from the root (the MPF absence proof); it inserts
the row, mints the token and locks the bond. A rejected request needs to be
rejectable; it refunds the bond. A request that is not pending — including
one the same batch already consumed — refuses the whole fold. -/
def applyBatch (p : Params) (env : Env) (now : Slot) :
    Acc → List (ReqId × FoldAction) → Option Acc
  | acc, [] => some acc
  | acc, (id, fa) :: rest =>
    match lookup acc.requests id with
    | none => none
    | some r =>
      match fa with
      | .process =>
        if inPhase1 p r now ∧ env.inception r.aid = true ∧ r.aid ∉ acc.root then
          applyBatch p env now
            { root := r.aid :: acc.root, live := r.aid :: acc.live,
              requests := remove acc.requests id,
              locked := acc.locked ++ [(r.aid, p.D)], refunds := acc.refunds } rest
        else none
      | .reject =>
        if rejectable p r now then
          applyBatch p env now
            { acc with requests := remove acc.requests id,
                       refunds := acc.refunds ++ [(r.owner, p.D)] } rest
        else none

/-! ## The functional step: the one executable source -/

/-- The step. `none` is a refusal; the simulator names the first failing
conjunct in this order. -/
def stepFn (p : Params) (env : Env) (a : Action) (now : Slot) (s : Sys) : Option (Flow × Sys) :=
  match a with
  | .contribute aid owner t =>
      some ({ deposited := p.D + p.tip },
            { s with requests := (s.nextReq, ⟨aid, owner, t⟩) :: s.requests,
                     nextReq := s.nextReq + 1 })
  | .retract id =>
      match lookup s.requests id with
      | none => none
      | some r =>
        if inPhase2 p r now then
          some ({ refunds := [(r.owner, p.D + p.tip)] }, { s with requests := remove s.requests id })
        else none
  | .fold folder g pl batch =>
      if g = s.gen ∧ pl = s.plugin ∧ batch ≠ [] then
        match applyBatch p env now ⟨s.root, s.live, s.requests, [], []⟩ batch with
        | none => none
        | some acc =>
          some ({ locked := acc.locked, refunds := acc.refunds,
                  tips := some (folder, batch.length * p.tip) },
                { s with gen := s.gen + 1, root := acc.root, live := acc.live,
                         requests := acc.requests })
      else none
  | .convict aid =>
      if aid ∈ s.live ∧ env.duplicity aid = true then
        some ({}, { s with live := s.live.erase aid, tomb := aid :: s.tomb })
      else none

/-! ## Traces and reachability -/

/-- Replay of a timestamped action list, at non-decreasing slots. -/
def replay (p : Params) (env : Env) : Slot → Sys → List (Slot × Action) → Option Sys
  | _, s, [] => some s
  | t, s, (t', a) :: rest =>
      if t ≤ t' then
        match stepFn p env a t' s with
        | some (_, s') => replay p env t' s' rest
        | none => none
      else none

/-- Reachable from a genesis by applied steps. -/
inductive Reach (p : Params) (env : Env) : Sys → Prop
  | init (plugin : Script) : Reach p env (Sys.init plugin)
  | step {s : Sys} (h : Reach p env s) {a : Action} {now : Slot} {f : Flow} {s' : Sys}
      (hs : stepFn p env a now s = some (f, s')) : Reach p env s'

/-- The structural invariant every reachable system satisfies. -/
structure Inv (s : Sys) : Prop where
  /-- Row if and only if token: an AID is in the root exactly when it has a
  live token or a tombstone. -/
  rowIffToken : ∀ aid, aid ∈ s.root ↔ (aid ∈ s.live ∨ aid ∈ s.tomb)
  /-- At most one live checkpoint per AID. -/
  liveNodup : s.live.Nodup
  /-- At most one tombstone per AID. -/
  tombNodup : s.tomb.Nodup
  /-- A convicted AID has no live token. -/
  tombNotLive : ∀ aid, aid ∈ s.tomb → aid ∉ s.live
  /-- The root has no duplicate rows. -/
  rootNodup : s.root.Nodup
  /-- Request identifiers are unique. -/
  reqNodup : (s.requests.map (·.1)).Nodup
  /-- Every pending identifier is below the next one. -/
  reqBelowNext : ∀ x, x ∈ s.requests → x.1 < s.nextReq

end CardanoKeri.Registry
