import CardanoKeri.Registry
import CardanoKeri.RegistryGoals

/-!
# The generic cage, its plugin, and the permissioning divergence

`CardanoKeri.Registry` is the registry as it must behave *after* the mpfs
plugin-cage epic (cardano-foundation/cardano-mpfs-onchain#99). This file is
the cage as mpfs ships it, parameterised by the three things the epic
changes, so that the registry is an *instantiation* and the difference
between today's cage and the one the registry needs is a set of theorems:

* **`AuthMode`** — how `Modify` is authorized (`shared.ak validateOwnership`):
  the owner's signature (`stake_script = None`); the owner's signature *and*
  the hook's withdrawal (the `Some` branch as shipped — #79); the hook's
  withdrawal alone (#79 replace semantics, the epic's ask).
* **`Plugin`** — what the hook does with a request in phase 1 beyond the
  cage's own checks, and whether it may veto a rejection. `Plugin.registry`
  is the keri plugin (#102): its body is `CardanoKeri.Registry.processBody`,
  the leaf transitions with their evidence and their coupled mints; it vetoes
  the rejection of a go-request. `Plugin.trivial` is `staking.ak` as
  shipped, which returns `True`: it applies the leaf operation the request
  declares and nothing else — no evidence, no checkpoint — and vetoes nothing.
* **`ValueMode`** — where a processed request's value goes: refunded to the
  owner as `validModify` does today (#101 not landed), or routed by the
  plugin (into the checkpoint for a registration or a revival, back to the
  reaper for a go-request).

The cage's own checks — the inbox, the phases, the generation, the
non-empty batch — are `CardanoKeri.Registry`'s and are shared.

The theorems at the end are the divergence:

* `delegated_is_registry`: under replace semantics, with the keri plugin and
  delegated routing, the cage *is* `CardanoKeri.Registry.stepFn` for every
  transaction that ran the plugin, whoever signed it; every theorem of
  `RegistryGoals` holds of it, and `delegated_permissionless` says the
  owner's signature is irrelevant;
* `ownerKeyed_needs_owner`, `ownerAndHook_needs_owner`: on the shipped
  paths nobody but the owner folds — not permissionless;
* `owner_bypass_breaks_inv`: on the owner-keyed path the owner registers an
  AID with no inception evidence and no checkpoint, so the registry
  invariant `Inv` fails in the result; `ownerAndHook_trivial_breaks_inv`:
  the same through the shipped stub;
* `owner_swaps_plugin` / `delegated_pins_plugin`: the plugin is mutable off
  the delegated path and pinned on it (#100);
* `refundAll_never_locks`: under `validModify` as shipped no checkpoint is
  ever funded (#101).

Nothing here is keri-specific except the shared types of
`CardanoKeri.Registry`; the file is written to be lifted into
`cardano-mpfs-onchain/lean/MpfsCage`.
-/

namespace CardanoKeri.Cage

open CardanoKeri.Registry

inductive AuthMode where
  | ownerKeyed
  | ownerAndHook
  | delegated
  deriving DecidableEq, Repr

structure TxAuth where
  signedByOwner : Bool
  pluginRan : Bool
  deriving DecidableEq, Repr

def authorized : AuthMode → TxAuth → Bool
  | .ownerKeyed, t => t.signedByOwner
  | .ownerAndHook, t => t.signedByOwner && t.pluginRan
  | .delegated, t => t.pluginRan

inductive ValueMode where
  | refundAll
  | delegatedRouting
  deriving DecidableEq, Repr

/-- What the hook does with a request in phase 1, and whether it vetoes a
rejection. -/
structure Plugin where
  body : Params → Env → Acc → Request → Option Acc
  allowReject : Request → Bool

/-- The keri plugin (#102). -/
def Plugin.registry : Plugin :=
  { body := processBody, allowReject := fun r => r.op.userPostable }

/-- The leaf operation a request declares, applied with no evidence and no
coupling: what the cage alone does when the hook is `staking.ak`. -/
def cageOnlyBody (p : Params) (acc : Acc) (r : Request) : Option Acc :=
  match r.op with
  | .register =>
    if lookup acc.leaves r.aid = none then
      some { acc with leaves := (r.aid, .active acc.nextToken) :: acc.leaves, nextToken := acc.nextToken + 1,
                      locked := acc.locked ++ [(r.aid, p.D)] }
    else none
  | .revive =>
    match lookup acc.leaves r.aid with
    | some (.dormant _) => some { acc with leaves := setLeaf acc.leaves r.aid (.active acc.nextToken),
                                           nextToken := acc.nextToken + 1, locked := acc.locked ++ [(r.aid, p.D)] }
    | _ => none
  | .goDormant k =>
    match lookup acc.leaves r.aid with
    | some (.active _) => some { acc with leaves := setLeaf acc.leaves r.aid (.dormant k),
                                          refunds := acc.refunds ++ [(r.owner, p.Mr)] }
    | _ => none
  | .goConvicted =>
    match lookup acc.leaves r.aid with
    | some (.active _) => some { acc with leaves := setLeaf acc.leaves r.aid .convicted,
                                          refunds := acc.refunds ++ [(r.owner, p.Mr)] }
    | _ => none
  | .convict =>
    match lookup acc.leaves r.aid with
    | some (.dormant _) => some { acc with leaves := setLeaf acc.leaves r.aid .convicted,
                                           refunds := acc.refunds ++ [(r.owner, p.Mr)] }
    | _ => none

/-- `staking.ak` as shipped. -/
def Plugin.trivial : Plugin :=
  { body := fun p _ acc r => cageOnlyBody p acc r, allowReject := fun _ => true }

/-- The body that runs: the plugin's when the hook ran, the cage's alone
otherwise. -/
def runBody (pl : Plugin) (ran : Bool) (p : Params) (env : Env) (acc : Acc) (r : Request) : Option Acc :=
  if ran then pl.body p env acc r else cageOnlyBody p acc r

/-- `validModify` as shipped refunds every request's bond to its owner and
locks nothing. -/
def routeValue (vm : ValueMode) (p : Params) (acc : Acc) (r : Request) (acc'' : Acc) : Acc :=
  match vm with
  | .delegatedRouting => acc''
  | .refundAll => { acc'' with locked := acc.locked, refunds := acc.refunds ++ [(r.owner, r.op.bond p)] }

def rejectAllowed (pl : Plugin) (ran : Bool) (r : Request) : Prop :=
  ran = true → pl.allowReject r = true

instance (pl : Plugin) (ran : Bool) (r : Request) : Decidable (rejectAllowed pl ran r) := by
  unfold rejectAllowed; infer_instance

def applyBatch (pl : Plugin) (vm : ValueMode) (ran : Bool) (p : Params) (env : Env) (now : Slot) :
    Acc → List (ReqId × FoldAction) → Option Acc
  | acc, [] => some acc
  | acc, (id, fa) :: rest =>
    match lookup acc.requests id with
    | none => none
    | some r =>
      let acc' := { acc with requests := remove acc.requests id }
      match (match fa with
             | .process =>
               if inPhase1 p r now then
                 match runBody pl ran p env acc' r with
                 | some acc'' => some (routeValue vm p acc' r acc'')
                 | none => none
               else none
             | .reject =>
               if rejectable p r now ∧ rejectAllowed pl ran r then
                 some { acc' with refunds := acc'.refunds ++ [(r.owner, r.op.bond p)] }
               else none) with
      | none => none
      | some acc'' => applyBatch pl vm ran p env now acc'' rest

def stepFn (mode : AuthMode) (pl : Plugin) (vm : ValueMode) (tx : TxAuth) (p : Params) (env : Env)
    (a : Action) (now : Slot) (s : Sys) : Option (Flow × Sys) :=
  match a with
  | .fold folder g pl' batch =>
      if authorized mode tx = true ∧ g = s.gen ∧ (mode = .delegated → pl' = s.plugin) ∧ batch ≠ [] then
        match applyBatch pl vm tx.pluginRan p env now ⟨s.leaves, s.ckpts, s.requests, s.nextToken, [], []⟩ batch with
        | none => none
        | some acc =>
          some ({ locked := acc.locked, refunds := acc.refunds,
                  tips := some (folder, batch.length * p.tip) },
                { s with gen := s.gen + 1, plugin := pl', leaves := acc.leaves, ckpts := acc.ckpts,
                         requests := acc.requests, nextToken := acc.nextToken })
      else none
  | a => CardanoKeri.Registry.stepFn p env a now s

/-! ## The delegated cage with the keri plugin is the registry -/

theorem applyBatch_delegated_eq (p : Params) (env : Env) (now : Slot) :
    ∀ (acc : Acc) (batch : List (ReqId × FoldAction)),
      applyBatch Plugin.registry .delegatedRouting true p env now acc batch =
        CardanoKeri.Registry.applyBatch p env now acc batch := by
  intro acc batch
  induction batch generalizing acc with
  | nil => rfl
  | cons x rest ih =>
    obtain ⟨id, fa⟩ := x
    rcases hl : lookup acc.requests id with _ | r
    · cases fa <;> simp [applyBatch, CardanoKeri.Registry.applyBatch, hl]
    · cases fa with
      | process =>
        simp only [applyBatch, CardanoKeri.Registry.applyBatch, hl, runBody, Plugin.registry, routeValue,
          ite_true, processOne]
        by_cases h1 : inPhase1 p r now
        · simp only [h1, ite_true]
          rcases processBody p env { acc with requests := remove acc.requests id } r with _ | acc''
          · rfl
          · exact ih _
        · simp only [h1, ite_false]
      | reject =>
        simp only [applyBatch, CardanoKeri.Registry.applyBatch, hl, rejectOne, rejectAllowed, Plugin.registry,
          forall_const, true_implies]
        by_cases hc : rejectable p r now ∧ r.op.userPostable = true
        · simp only [hc, ite_true]; exact ih _
        · simp only [hc, ite_false]

/-- **The instantiation.** -/
theorem delegated_is_registry (signed : Bool) (p : Params) (env : Env) (a : Action) (now : Slot) (s : Sys) :
    stepFn .delegated Plugin.registry .delegatedRouting ⟨signed, true⟩ p env a now s =
      CardanoKeri.Registry.stepFn p env a now s := by
  cases a with
  | fold folder g pl' batch =>
    simp only [stepFn, CardanoKeri.Registry.stepFn, authorized, applyBatch_delegated_eq, true_and, true_implies]
    by_cases hc : g = s.gen ∧ pl' = s.plugin ∧ batch ≠ []
    · obtain ⟨hg, hpl, hb⟩ := hc
      subst hg; subst hpl
      simp [hb]
      try rfl
    · simp only [hc, ite_false]
  | contribute _ _ _ _ => rfl
  | retract _ => rfl
  | reap _ _ => rfl
  | pause _ => rfl
  | resume _ => rfl
  | convictCkpt _ => rfl

theorem delegated_permissionless (p : Params) (env : Env) (a : Action) (now : Slot) (s : Sys) :
    stepFn .delegated Plugin.registry .delegatedRouting ⟨false, true⟩ p env a now s =
      stepFn .delegated Plugin.registry .delegatedRouting ⟨true, true⟩ p env a now s := by
  rw [delegated_is_registry, delegated_is_registry]

/-! ## The divergence: the cage as shipped -/

theorem ownerAndHook_needs_owner (pl : Plugin) (vm : ValueMode) (ran : Bool) (p : Params) (env : Env)
    (now : Slot) (s : Sys) (folder : Addr) (g : Gen) (pl' : Script) (batch : List (ReqId × FoldAction)) :
    stepFn .ownerAndHook pl vm ⟨false, ran⟩ p env (.fold folder g pl' batch) now s = none := by
  simp [stepFn, authorized]

theorem ownerKeyed_needs_owner (pl : Plugin) (vm : ValueMode) (ran : Bool) (p : Params) (env : Env)
    (now : Slot) (s : Sys) (folder : Addr) (g : Gen) (pl' : Script) (batch : List (ReqId × FoldAction)) :
    stepFn .ownerKeyed pl vm ⟨false, ran⟩ p env (.fold folder g pl' batch) now s = none := by
  simp [stepFn, authorized]

/-- The deployment of the witnesses below. -/
def wp : Params := { D := 1000, tip := 2, Mc := 4, Mr := 1, process := 10, retract := 10, W := 5,
                     far := 1000000000, hD := by decide, hProcess := by decide, hRetract := by decide,
                     hFund := by decide }

/-- Evidence that verifies nothing. -/
def noEvidence : Env :=
  { inception := fun _ => false, rotationFrom := fun _ _ => false, duplicity := fun _ _ => false,
    quorum := fun _ => false }

/-- A registry with one pending registration for AID 11 whose inception does
not verify. -/
def pending : Sys := { gen := 0, plugin := 7, leaves := [], ckpts := [], requests := [(0, ⟨11, 1, 0, .register⟩)],
                       nextReq := 1, nextToken := 0 }

/-- The result of the owner's bypass: a leaf with no checkpoint and no
go-request. -/
def bypassed : Sys := { gen := 1, plugin := 7, leaves := [(11, .active 0)], ckpts := [], requests := [],
                        nextReq := 1, nextToken := 1 }

theorem bypassed_breaks_inv : ¬ Inv wp bypassed := by
  intro h
  rcases h.activeCkpt 11 0 (by decide) with ⟨c, hc⟩ | ⟨x, hx, _⟩
  · simp [bypassed, lookup] at hc
  · simp [bypassed] at hx

/-- **The owner bypass.** Under the owner-keyed cage the owner folds the
registration without the plugin: no inception evidence, no checkpoint; the
registry invariant fails in the result. -/
theorem owner_bypass_breaks_inv :
    stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨true, false⟩ wp noEvidence
        (.fold 1 0 7 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) }, bypassed) ∧ ¬ Inv wp bypassed :=
  ⟨by decide, bypassed_breaks_inv⟩

/-- **The same bypass under owner-and-hook with the shipped stub.** -/
theorem ownerAndHook_trivial_breaks_inv :
    stepFn .ownerAndHook Plugin.trivial .delegatedRouting ⟨true, true⟩ wp noEvidence
        (.fold 1 0 7 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) }, bypassed) ∧ ¬ Inv wp bypassed :=
  ⟨by decide, bypassed_breaks_inv⟩

theorem owner_swaps_plugin :
    stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨true, false⟩ wp noEvidence
        (.fold 1 0 8 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) }, { bypassed with plugin := 8 }) := by
  decide

theorem delegated_pins_plugin (signed ran : Bool) (p : Params) (env : Env) (now : Slot) (s : Sys)
    (folder : Addr) (g : Gen) {pl' : Script} (batch : List (ReqId × FoldAction)) (hpl : pl' ≠ s.plugin) :
    stepFn .delegated Plugin.registry .delegatedRouting ⟨signed, ran⟩ p env
      (.fold folder g pl' batch) now s = none := by
  simp [stepFn, hpl]

theorem refundAll_never_locks (pl : Plugin) (ran : Bool) (p : Params) (env : Env) (now : Slot) :
    ∀ (acc : Acc) (batch : List (ReqId × FoldAction)) (acc' : Acc),
      applyBatch pl .refundAll ran p env now acc batch = some acc' → acc'.locked = acc.locked := by
  intro acc batch
  induction batch generalizing acc with
  | nil =>
    intro acc' h
    simp only [applyBatch, Option.some.injEq] at h
    subst h; rfl
  | cons x rest ih =>
    intro acc' h
    obtain ⟨id, fa⟩ := x
    rcases hl : lookup acc.requests id with _ | r
    · cases fa <;> simp [applyBatch, hl] at h
    · cases fa with
      | process =>
        by_cases h1 : inPhase1 p r now
        · rcases hb : runBody pl ran p env { acc with requests := remove acc.requests id } r with _ | acc''
          · simp [applyBatch, hl, h1, hb] at h
          · simp only [applyBatch, hl, h1, hb, ite_true] at h
            have e := ih _ _ h
            simp only [routeValue] at e
            exact e
        · simp [applyBatch, hl, h1] at h
      | reject =>
        by_cases hc : rejectable p r now ∧ rejectAllowed pl ran r
        · simp only [applyBatch, hl, hc, ite_true] at h
          have e := ih _ _ h
          exact e
        · simp [applyBatch, hl, hc] at h

theorem refundAll_fold_locks_nothing (mode : AuthMode) (pl : Plugin) (tx : TxAuth) (p : Params) (env : Env)
    {now : Slot} {s : Sys} {f : Flow} {s' : Sys} {folder : Addr} {g : Gen} {pl' : Script}
    {batch : List (ReqId × FoldAction)}
    (hs : stepFn mode pl .refundAll tx p env (.fold folder g pl' batch) now s = some (f, s')) :
    f.locked = [] := by
  simp only [stepFn] at hs
  split at hs
  · split at hs
    · cases hs
    · rename_i acc hacc
      simp only [Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨rfl, _⟩ := hs
      exact refundAll_never_locks pl tx.pluginRan p env now _ _ _ hacc
  · cases hs

end CardanoKeri.Cage
