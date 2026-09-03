/-!
# The AID registry as an MPFS instance: the registry machine

Abstract model of the registry ruled by D-024 — one UTxO holding the MPF root
over every AID ever registered — built as a cage of cardano-mpfs-onchain on
the plugin path (cardano-foundation/cardano-mpfs-onchain#99), after the
rulings of 2026-09-02/03:

* the cage never interprets a leaf; the **leaf value** is the protocol's:
  `active token` while a checkpoint carries that token, `dormant k` when the
  checkpoint has left the chain and `k` is the key state a revival must
  rotate from, `convicted` for ever;
* **requests** are inbox UTxOs and never contend: a registration, a revival
  or a conviction of a dormant AID is posted by anyone with the evidence and
  a bond; a **go-request** (`goDormant k`, `goConvicted`) is created only by
  a *reap* of a bondless checkpoint, funded from that checkpoint's min-ADA,
  dated at the end of time so that it can never be retracted, and refused by
  the plugin for rejection so that `k` can never be lost;
* a **fold** is a permissionless `Modify`: anyone spends the registry at its
  current generation with a non-empty batch; the cage applies the leaf
  operation each request declares and the plugin admits it and mints or
  couples what the transition needs; a stale generation is refused with no
  state change; the plugin is pinned;
* **rotations, pauses, resumes and convictions of a live checkpoint never
  write the registry**: the indirection is the token, which survives every
  rotation; the checkpoint carries live, parked (bonds withdrawn) and
  tombstone;
* a **reap** (anyone) spends a parked checkpoint after the grace window, or
  earlier with the owner's keys, or a tombstone at once: it burns the token,
  keeps the min-ADA less the go-request as premium, and posts the go-request.

There is no close: a leaf, once inserted, is permanent.

No cryptography, no MPF: the root is the association list of leaves and the
absence proof is membership. The evidence a step needs is an `Env` of
decidable predicates standing for the checks the plugin, the checkpoint
policy and the observers perform. Key states are abstracted to a counter
advanced by every rotation. A functional `stepFn` is the one executable
source: the theorems are stated over it, the simulator transcribes it, and
the trace driver runs it.
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
/-- A checkpoint token: the incarnation number under the checkpoint policy;
the indirection a leaf stores while active. -/
abbrev Token := Nat
/-- An abstract key state: advanced by every rotation. -/
abbrev KeyState := Nat

/-- Deployment parameters. -/
structure Params where
  /-- The registration bond (all three checkpoint components, abstracted to one). -/
  D : Value
  /-- The tip a request carries and a fold pays to the folder per request. -/
  tip : Value
  /-- A checkpoint's min-ADA: all a parked or convicted checkpoint holds. -/
  Mc : Value
  /-- A request's min-ADA. -/
  Mr : Value
  /-- `process_time`: the length of phase 1 in slots. -/
  process : Nat
  /-- `retract_time`: the length of phase 2 in slots. -/
  retract : Nat
  /-- The grace window: a parked checkpoint is reapable by a stranger only
  this many slots after it was parked. -/
  W : Nat
  /-- The end of time: the `submitted_at` a reap writes into a go-request, so
  that phase 2 never comes. -/
  far : Slot
  hD : 0 < D
  hProcess : 0 < process
  hRetract : 0 < retract
  /-- The reap validator's value guard: a checkpoint funds its go-request. -/
  hFund : Mr + tip ≤ Mc

/-- The evidence the plugin, the checkpoint policy and the observers verify,
abstracted at the KEL boundary. -/
structure Env where
  /-- `inception aid`: the request's inception bytes self-address to `aid`
  with signatures and receipts at the inception's own thresholds (#114). -/
  inception : AID → Bool
  /-- `rotationFrom aid k`: a witnessed rotation from key state `k` was
  presented (the advance predicate). Used by pause, resume and revive. -/
  rotationFrom : AID → KeyState → Bool
  /-- `duplicity aid k`: a verified duplicity proof against key state `k`
  (D-030). -/
  duplicity : AID → KeyState → Bool
  /-- `quorum aid`: the checkpoint's current keys signed (the owner reaping
  their own parked checkpoint before the grace window). -/
  quorum : AID → Bool

/-- A leaf value. -/
inductive Status where
  | active (token : Token)
  | dormant (k : KeyState)
  | convicted
  deriving Repr, DecidableEq

/-- What a checkpoint UTxO is, for the registry's purposes. -/
inductive CkState where
  /-- Bonded (live or frozen): not reapable. -/
  | live
  /-- Bonds withdrawn at `since`: reapable after the grace window, or by the owner. -/
  | parked (since : Slot)
  /-- Convicted: reapable at once. -/
  | tomb
  deriving Repr, DecidableEq

/-- A checkpoint UTxO: its token, its key state, its state. -/
structure Ckpt where
  token : Token
  k : KeyState
  st : CkState
  deriving Repr, DecidableEq

/-- What a request asks of the leaf. -/
inductive Op where
  /-- `Insert aid ↦ active _`: registration. Posted by anyone. -/
  | register
  /-- `Update dormant k → active _`: revival. Posted by anyone. -/
  | revive
  /-- `Update active _ → dormant k`: created by a reap of a parked checkpoint. -/
  | goDormant (k : KeyState)
  /-- `Update active _ → convicted`: created by a reap of a tombstone. -/
  | goConvicted
  /-- `Update dormant k → convicted`: a duplicity proof against a dormant AID. Posted by anyone. -/
  | convict
  deriving Repr, DecidableEq

/-- Only a reap creates a go-request. -/
def Op.userPostable : Op → Bool
  | .register => true
  | .revive => true
  | .convict => true
  | _ => false

/-- The value a request of this kind carries besides the tip. -/
def Op.bond (p : Params) : Op → Value
  | .register => p.D
  | .revive => p.D
  | _ => p.Mr

/-- An inbox UTxO. -/
structure Request where
  aid : AID
  owner : Addr
  submittedAt : Slot
  op : Op
  deriving Repr, DecidableEq

/-- What a fold does with one request. -/
inductive FoldAction where
  | process
  | reject
  deriving Repr, DecidableEq

/-- The system: the registry UTxO, the checkpoints, the inbox. -/
structure Sys where
  gen : Gen
  plugin : Script
  /-- The root: every registered AID with its leaf. -/
  leaves : List (AID × Status)
  /-- The checkpoint UTxOs on chain. -/
  ckpts : List (AID × Ckpt)
  requests : List (ReqId × Request)
  nextReq : ReqId
  /-- The next token the checkpoint policy mints. -/
  nextToken : Token
  deriving Repr, DecidableEq

def Sys.init (plugin : Script) : Sys :=
  ⟨0, plugin, [], [], [], 0, 0⟩

/-- Who authorizes a transition; derived from the action. -/
inductive Actor where
  | anyone
  | owner
  | nextKeys
  | proof
  deriving DecidableEq, Repr

/-- The actions: the cage's redeemers, the reap, and the checkpoint edges the
registry must never see. -/
inductive Action where
  /-- Create a request UTxO for a user-postable op. -/
  | contribute (aid : AID) (owner : Addr) (submittedAt : Slot) (op : Op)
  /-- Spend the registry at generation `gen`, re-creating it with plugin
  `plugin`, processing or rejecting each request of `batch` in order. -/
  | fold (folder : Addr) (gen : Gen) (plugin : Script) (batch : List (ReqId × FoldAction))
  /-- The owner takes a request back in phase 2. -/
  | retract (req : ReqId)
  /-- Anyone spends a bondless checkpoint, burns its token, posts the go-request. -/
  | reap (reaper : Addr) (aid : AID)
  /-- A withdrawing rotation: bonds leave, the checkpoint stays parked. -/
  | pause (aid : AID)
  /-- A depositing rotation on a parked checkpoint: live again, no registry write. -/
  | resume (aid : AID)
  /-- A duplicity proof against a live or parked checkpoint: tombstone. -/
  | convictCkpt (aid : AID)
  deriving Repr, DecidableEq

def Action.actor : Action → Actor
  | .contribute .. => .anyone
  | .fold .. => .anyone
  | .retract .. => .owner
  | .reap .. => .anyone
  | .pause .. => .nextKeys
  | .resume .. => .nextKeys
  | .convictCkpt .. => .proof

/-- Value movements of one transition. -/
structure Flow where
  /-- Brought by the requester into a new request: bond + tip. -/
  deposited : Value := 0
  /-- Bonds locked into new checkpoints, one per registration or revival. -/
  locked : List (AID × Value) := []
  /-- Paid back to request owners. -/
  refunds : List (Addr × Value) := []
  /-- Paid to the folder: `tip` per request of the batch. -/
  tips : Option (Addr × Value) := none
  /-- A reap: what the reaper keeps of the checkpoint's min-ADA. -/
  premium : Option (Addr × Value) := none
  /-- A reap: what goes into the go-request (`Mr + tip`). -/
  intoRequest : Value := 0
  deriving Repr, DecidableEq

/-! ## Phases (the cage's `in_phase1`, `in_phase2`, `is_rejectable`, at a point) -/

def inPhase1 (p : Params) (r : Request) (now : Slot) : Prop :=
  now < r.submittedAt + p.process
def inPhase2 (p : Params) (r : Request) (now : Slot) : Prop :=
  r.submittedAt + p.process ≤ now ∧ now < r.submittedAt + p.process + p.retract
def rejectable (p : Params) (r : Request) (now : Slot) : Prop :=
  r.submittedAt + p.process + p.retract ≤ now ∨ now < r.submittedAt

instance (p : Params) (r : Request) (now : Slot) : Decidable (inPhase1 p r now) := by
  unfold inPhase1; infer_instance
instance (p : Params) (r : Request) (now : Slot) : Decidable (inPhase2 p r now) := by
  unfold inPhase2; infer_instance
instance (p : Params) (r : Request) (now : Slot) : Decidable (rejectable p r now) := by
  unfold rejectable; infer_instance

/-! ## Association lists -/

def lookup {α : Type} : List (Nat × α) → Nat → Option α
  | [], _ => none
  | (i, r) :: rs, id => if i = id then some r else lookup rs id

def remove {α : Type} : List (Nat × α) → Nat → List (Nat × α)
  | [], _ => []
  | (i, r) :: rs, id => if i = id then remove rs id else (i, r) :: remove rs id

/-- Replace the leaf of `aid` (which must be present) by `v`. -/
def setLeaf : List (AID × Status) → AID → Status → List (AID × Status)
  | [], _, _ => []
  | (a, s) :: rest, aid, v => if a = aid then (aid, v) :: rest else (a, s) :: setLeaf rest aid v

/-! ## The fold -/

/-- What a fold threads through its batch. -/
structure Acc where
  leaves : List (AID × Status)
  ckpts : List (AID × Ckpt)
  requests : List (ReqId × Request)
  nextToken : Token
  locked : List (AID × Value)
  refunds : List (Addr × Value)
  deriving Repr, DecidableEq

/-- What the plugin does with one request in phase 1: the leaf operation the
request declares, its admission, and its coupling (the mint, the bond, the
refund). This is the registry plugin's body; the cage's own phase check is
`processOne`. -/
def processBody (p : Params) (env : Env) (acc : Acc) (r : Request) : Option Acc :=
    match r.op with
    | .register =>
      if env.inception r.aid = true ∧ lookup acc.leaves r.aid = none then
        some { acc with leaves := (r.aid, .active acc.nextToken) :: acc.leaves,
                        ckpts := (r.aid, ⟨acc.nextToken, 0, .live⟩) :: acc.ckpts,
                        nextToken := acc.nextToken + 1,
                        locked := acc.locked ++ [(r.aid, p.D)] }
      else none
    | .revive =>
      match lookup acc.leaves r.aid with
      | some (.dormant k) =>
        if env.rotationFrom r.aid k = true ∧ lookup acc.ckpts r.aid = none then
          some { acc with leaves := setLeaf acc.leaves r.aid (.active acc.nextToken),
                          ckpts := (r.aid, ⟨acc.nextToken, k + 1, .live⟩) :: acc.ckpts,
                          nextToken := acc.nextToken + 1,
                          locked := acc.locked ++ [(r.aid, p.D)] }
        else none
      | _ => none
    | .goDormant k =>
      match lookup acc.leaves r.aid with
      | some (.active _) =>
        some { acc with leaves := setLeaf acc.leaves r.aid (.dormant k),
                        refunds := acc.refunds ++ [(r.owner, p.Mr)] }
      | _ => none
    | .goConvicted =>
      match lookup acc.leaves r.aid with
      | some (.active _) =>
        some { acc with leaves := setLeaf acc.leaves r.aid .convicted,
                        refunds := acc.refunds ++ [(r.owner, p.Mr)] }
      | _ => none
    | .convict =>
      match lookup acc.leaves r.aid with
      | some (.dormant k) =>
        if env.duplicity r.aid k = true then
          some { acc with leaves := setLeaf acc.leaves r.aid .convicted,
                          refunds := acc.refunds ++ [(r.owner, p.Mr)] }
        else none
      | _ => none

/-- Processing one request: the cage's phase check, then the plugin's body. -/
def processOne (p : Params) (env : Env) (now : Slot) (acc : Acc) (r : Request) : Option Acc :=
  if inPhase1 p r now then processBody p env acc r else none

/-- Rejecting one request: the cage's rejectability, and the plugin's refusal
on a go-request (its `k` must never be lost). -/
def rejectOne (p : Params) (now : Slot) (acc : Acc) (r : Request) : Option Acc :=
  if rejectable p r now ∧ r.op.userPostable = true then
    some { acc with refunds := acc.refunds ++ [(r.owner, r.op.bond p)] }
  else none

def applyBatch (p : Params) (env : Env) (now : Slot) :
    Acc → List (ReqId × FoldAction) → Option Acc
  | acc, [] => some acc
  | acc, (id, fa) :: rest =>
    match lookup acc.requests id with
    | none => none
    | some r =>
      let acc' := { acc with requests := remove acc.requests id }
      match (match fa with
             | .process => processOne p env now acc' r
             | .reject => rejectOne p now acc' r) with
      | none => none
      | some acc'' => applyBatch p env now acc'' rest

/-! ## The functional step: the one executable source -/

/-- A stranger may reap a parked checkpoint after the grace window; the owner
at any time; a tombstone at once. -/
def reapable (p : Params) (env : Env) (now : Slot) (aid : AID) (c : Ckpt) : Prop :=
  match c.st with
  | .live => False
  | .parked since => since + p.W ≤ now ∨ env.quorum aid = true
  | .tomb => True

instance (p : Params) (env : Env) (now : Slot) (aid : AID) (c : Ckpt) :
    Decidable (reapable p env now aid c) := by
  unfold reapable; cases c.st <;> infer_instance

/-- The go-request a reap posts. -/
def goOp (c : Ckpt) : Op :=
  match c.st with
  | .tomb => .goConvicted
  | _ => .goDormant c.k

def stepFn (p : Params) (env : Env) (a : Action) (now : Slot) (s : Sys) : Option (Flow × Sys) :=
  match a with
  | .contribute aid owner t op =>
      if op.userPostable = true then
        some ({ deposited := op.bond p + p.tip },
              { s with requests := (s.nextReq, ⟨aid, owner, t, op⟩) :: s.requests,
                       nextReq := s.nextReq + 1 })
      else none
  | .retract id =>
      match lookup s.requests id with
      | none => none
      | some r =>
        if inPhase2 p r now then
          some ({ refunds := [(r.owner, r.op.bond p + p.tip)] }, { s with requests := remove s.requests id })
        else none
  | .fold folder g pl batch =>
      if g = s.gen ∧ pl = s.plugin ∧ batch ≠ [] then
        match applyBatch p env now ⟨s.leaves, s.ckpts, s.requests, s.nextToken, [], []⟩ batch with
        | none => none
        | some acc =>
          some ({ locked := acc.locked, refunds := acc.refunds,
                  tips := some (folder, batch.length * p.tip) },
                { s with gen := s.gen + 1, leaves := acc.leaves, ckpts := acc.ckpts,
                         requests := acc.requests, nextToken := acc.nextToken })
      else none
  | .reap reaper aid =>
      match lookup s.ckpts aid with
      | none => none
      | some c =>
        if reapable p env now aid c then
          some ({ premium := some (reaper, p.Mc - p.Mr - p.tip), intoRequest := p.Mr + p.tip },
                { s with ckpts := remove s.ckpts aid,
                         requests := (s.nextReq, ⟨aid, reaper, p.far, goOp c⟩) :: s.requests,
                         nextReq := s.nextReq + 1 })
        else none
  | .pause aid =>
      match lookup s.ckpts aid with
      | some ⟨tok, k, .live⟩ =>
        if env.rotationFrom aid k = true then
          some ({}, { s with ckpts := (aid, ⟨tok, k + 1, .parked now⟩) :: remove s.ckpts aid })
        else none
      | _ => none
  | .resume aid =>
      match lookup s.ckpts aid with
      | some ⟨tok, k, .parked _⟩ =>
        if env.rotationFrom aid k = true then
          some ({}, { s with ckpts := (aid, ⟨tok, k + 1, .live⟩) :: remove s.ckpts aid })
        else none
      | _ => none
  | .convictCkpt aid =>
      match lookup s.ckpts aid with
      | some ⟨tok, k, st⟩ =>
        if st ≠ .tomb ∧ env.duplicity aid k = true then
          some ({}, { s with ckpts := (aid, ⟨tok, k, .tomb⟩) :: remove s.ckpts aid })
        else none
      | none => none

/-! ## Traces and reachability -/

def replay (p : Params) (env : Env) : Slot → Sys → List (Slot × Action) → Option Sys
  | _, s, [] => some s
  | t, s, (t', a) :: rest =>
      if t ≤ t' then
        match stepFn p env a t' s with
        | some (_, s') => replay p env t' s' rest
        | none => none
      else none

inductive Reach (p : Params) (env : Env) : Sys → Prop
  | init (plugin : Script) : Reach p env (Sys.init plugin)
  | step {s : Sys} (h : Reach p env s) {a : Action} {now : Slot} {f : Flow} {s' : Sys}
      (hs : stepFn p env a now s = some (f, s')) : Reach p env s'

/-- A go-request for `aid` is pending. -/
def goPending (s : Sys) (aid : AID) : Prop :=
  ∃ x, x ∈ s.requests ∧ x.2.aid = aid ∧ x.2.op.userPostable = false

/-- The structural invariant every reachable system satisfies. Membership is
by `lookup`: the first entry with a key is the entry, and the key lists are
without duplicates. -/
structure Inv (p : Params) (s : Sys) : Prop where
  /-- A checkpoint exists only for an AID whose leaf is active. -/
  ckptActive : ∀ aid c, lookup s.ckpts aid = some c → ∃ tok, lookup s.leaves aid = some (.active tok)
  /-- An active leaf has the checkpoint carrying its token, or a go-request is
  pending for it: the leaf's token is the indirection. -/
  activeCkpt : ∀ aid tok, lookup s.leaves aid = some (.active tok) →
    (∃ c, lookup s.ckpts aid = some c ∧ c.token = tok) ∨ goPending s aid
  /-- While a go-request is pending there is no checkpoint. -/
  goNoCkpt : ∀ aid, goPending s aid → lookup s.ckpts aid = none
  /-- While a go-request is pending the leaf is active. -/
  goActive : ∀ aid, goPending s aid → ∃ tok, lookup s.leaves aid = some (.active tok)
  /-- At most one go-request per AID. -/
  goUnique : ∀ x y, x ∈ s.requests → y ∈ s.requests → x.2.op.userPostable = false →
    y.2.op.userPostable = false → x.2.aid = y.2.aid → x = y
  /-- A go-request is dated at the end of time. -/
  goFar : ∀ x, x ∈ s.requests → x.2.op.userPostable = false → x.2.submittedAt = p.far
  /-- At most one checkpoint per AID. -/
  ckptNodup : (s.ckpts.map (·.1)).Nodup
  /-- At most one leaf per AID. -/
  leafNodup : (s.leaves.map (·.1)).Nodup
  /-- Request identifiers are unique. -/
  reqNodup : (s.requests.map (·.1)).Nodup
  reqBelowNext : ∀ x, x ∈ s.requests → x.1 < s.nextReq

end CardanoKeri.Registry
