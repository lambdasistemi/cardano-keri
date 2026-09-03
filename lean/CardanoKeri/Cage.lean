import CardanoKeri.Registry

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
* **`Plugin`** — what the hook checks per request beyond the cage's own
  phase and inbox checks, and whether processing mints the checkpoint token.
  `Plugin.registry` is the mint-coupled registry plugin (#102);
  `Plugin.trivial` is `staking.ak` as shipped, which returns `True`.
* **`ValueMode`** — where a processed request's value goes: refunded to the
  owner as `validModify` does today, or routed by the plugin into the new
  checkpoint (#101).

The cage's own checks — the inbox, the phases, the generation, the
non-empty batch — are `CardanoKeri.Registry`'s and are shared.

The theorems at the end are the divergence:

* under the owner-keyed modes the owner inserts a row with no token and
  swaps the plugin, so the registry invariant does not hold
  (`owner_bypass_breaks_row_iff_token`, `owner_swaps_plugin`);
* under owner-and-hook nobody but the owner can fold, so the registry is not
  permissionless (`ownerAndHook_needs_owner`);
* under the delegated mode with the registry plugin and delegated routing
  the cage *is* `CardanoKeri.Registry.stepFn`, for every transaction that
  ran the plugin, whoever signed it (`delegated_is_registry`,
  `delegated_permissionless`), so every theorem of `RegistryGoals` holds of
  it;
* under `refundAll` no checkpoint is ever funded (`refundAll_never_locks`).

This file has no dependency on anything keri-specific except the shared
types of `CardanoKeri.Registry`; it is written to be lifted into
`cardano-mpfs-onchain/lean/MpfsCage` unchanged.
-/

namespace CardanoKeri.Cage

open CardanoKeri.Registry

/-- How `Modify` is authorized (`validateOwnership`). -/
inductive AuthMode where
  /-- `stake_script = None`: the owner's signature. -/
  | ownerKeyed
  /-- `stake_script = Some`, as shipped: the owner's signature and the hook's
  withdrawal (#79 as it stands). -/
  | ownerAndHook
  /-- `stake_script = Some` with replace semantics: the hook's withdrawal only. -/
  | delegated
  deriving DecidableEq, Repr

/-- What the transaction presents for authorization. -/
structure TxAuth where
  /-- The cage owner signed. -/
  signedByOwner : Bool
  /-- The withdrawal under the cage's `stake_script` is present, so the plugin
  script ran and accepted the transaction. -/
  pluginRan : Bool
  deriving DecidableEq, Repr

/-- `validateOwnership` under each mode. -/
def authorized : AuthMode → TxAuth → Bool
  | .ownerKeyed, t => t.signedByOwner
  | .ownerAndHook, t => t.signedByOwner && t.pluginRan
  | .delegated, t => t.pluginRan

/-- Where a processed request's value goes. -/
inductive ValueMode where
  /-- `validModify` as shipped: every request's value is refunded to its owner. -/
  | refundAll
  /-- #101: the plugin routes a processed request's value into the checkpoint. -/
  | delegatedRouting
  deriving DecidableEq, Repr

/-- What the hook checks per request beyond the cage's own checks, and
whether processing mints the checkpoint token. -/
structure Plugin where
  /-- Admission of one request under the fold's current accumulator. -/
  admit : Env → Slot → Acc → Request → FoldAction → Prop
  /-- The admission is decidable: the hook is a validator. -/
  dec : ∀ env now acc r fa, Decidable (admit env now acc r fa)
  /-- Processing mints the token (the plugin couples the insert to a mint). -/
  mints : Bool

instance (pl : Plugin) (env : Env) (now : Slot) (acc : Acc) (r : Request) (fa : FoldAction) :
    Decidable (pl.admit env now acc r fa) := pl.dec env now acc r fa

/-- The mint-coupled registry plugin (#102): a process needs the inception
evidence and the absence of the AID from the root; a reject needs nothing
beyond the cage's checks. -/
def Plugin.registry : Plugin :=
  { admit := fun env _ acc r fa =>
      match fa with
      | .process => env.inception r.aid = true ∧ r.aid ∉ acc.root
      | .reject => True,
    dec := fun env now acc r fa => by cases fa <;> dsimp only <;> infer_instance,
    mints := true }

/-- `staking.ak` as shipped: `withdraw` returns `True`; nothing is minted. -/
def Plugin.trivial : Plugin :=
  { admit := fun _ _ _ _ _ => True, dec := fun _ _ _ _ _ => inferInstance, mints := false }

/-- The plugin's checks apply only when the hook ran. -/
def admits (pl : Plugin) (ran : Bool) (env : Env) (now : Slot) (acc : Acc) (r : Request)
    (fa : FoldAction) : Prop :=
  ran = true → pl.admit env now acc r fa

instance (pl : Plugin) (ran : Bool) (env : Env) (now : Slot) (acc : Acc) (r : Request)
    (fa : FoldAction) : Decidable (admits pl ran env now acc r fa) := by
  unfold admits; infer_instance

/-- The cage's fold, generic in the plugin and the value mode. The cage's own
checks are exactly `CardanoKeri.Registry.applyBatch`'s; the plugin's admission
is added, the mint depends on the plugin having run, and the value goes where
the mode says. -/
def applyBatch (pl : Plugin) (vm : ValueMode) (ran : Bool) (p : Params) (env : Env) (now : Slot) :
    Acc → List (ReqId × FoldAction) → Option Acc
  | acc, [] => some acc
  | acc, (id, fa) :: rest =>
    match lookup acc.requests id with
    | none => none
    | some r =>
      match fa with
      | .process =>
        if inPhase1 p r now ∧ admits pl ran env now acc r .process then
          applyBatch pl vm ran p env now
            { root := r.aid :: acc.root,
              live := if ran && pl.mints then r.aid :: acc.live else acc.live,
              requests := remove acc.requests id,
              locked := match vm with
                | .delegatedRouting => acc.locked ++ [(r.aid, p.D)]
                | .refundAll => acc.locked,
              refunds := match vm with
                | .delegatedRouting => acc.refunds
                | .refundAll => acc.refunds ++ [(r.owner, p.D)] } rest
        else none
      | .reject =>
        if rejectable p r now ∧ admits pl ran env now acc r .reject then
          applyBatch pl vm ran p env now
            { acc with requests := remove acc.requests id,
                       refunds := acc.refunds ++ [(r.owner, p.D)] } rest
        else none

/-- The cage's step. Contribute, retract and convict are the registry's
(the divergence is in `Modify`). A fold needs `authorized`, the current
generation, a non-empty batch, and — on the delegated path only (#100) — the
plugin pinned. -/
def stepFn (mode : AuthMode) (pl : Plugin) (vm : ValueMode) (tx : TxAuth) (p : Params) (env : Env)
    (a : Action) (now : Slot) (s : Sys) : Option (Flow × Sys) :=
  match a with
  | .fold folder g pl' batch =>
      if authorized mode tx = true ∧ g = s.gen ∧ (mode = .delegated → pl' = s.plugin) ∧ batch ≠ [] then
        match applyBatch pl vm tx.pluginRan p env now ⟨s.root, s.live, s.requests, [], []⟩ batch with
        | none => none
        | some acc =>
          some ({ locked := acc.locked, refunds := acc.refunds,
                  tips := some (folder, batch.length * p.tip) },
                { s with gen := s.gen + 1, plugin := pl', root := acc.root, live := acc.live,
                         requests := acc.requests })
      else none
  | a => CardanoKeri.Registry.stepFn p env a now s

/-! ## The delegated cage with the registry plugin is the registry -/

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
        simp only [applyBatch, CardanoKeri.Registry.applyBatch, hl, admits, Plugin.registry,
          Bool.and_self, ite_true, forall_const]
        by_cases hc : inPhase1 p r now ∧ env.inception r.aid = true ∧ r.aid ∉ acc.root
        · rw [if_pos hc, if_pos hc]; exact ih _
        · rw [if_neg hc, if_neg hc]
      | reject =>
        simp only [applyBatch, CardanoKeri.Registry.applyBatch, hl, admits, Plugin.registry,
          forall_const, and_true]
        by_cases hc : rejectable p r now
        · rw [if_pos hc, if_pos hc]; exact ih _
        · rw [if_neg hc, if_neg hc]

/-- **The instantiation.** Under replace semantics, with the registry plugin
and delegated routing, every transaction that ran the plugin steps exactly as
`CardanoKeri.Registry.stepFn`, whoever signed it. Every theorem of
`RegistryGoals` therefore holds of this cage. -/
theorem delegated_is_registry (signed : Bool) (p : Params) (env : Env) (a : Action) (now : Slot) (s : Sys) :
    stepFn .delegated Plugin.registry .delegatedRouting ⟨signed, true⟩ p env a now s =
      CardanoKeri.Registry.stepFn p env a now s := by
  cases a with
  | fold folder g pl' batch =>
    simp only [stepFn, CardanoKeri.Registry.stepFn, authorized, applyBatch_delegated_eq]
    by_cases hc : g = s.gen ∧ pl' = s.plugin ∧ batch ≠ []
    · obtain ⟨hg, hpl, hb⟩ := hc
      subst hg; subst hpl
      simp [hb] <;> rfl
    · simp only [true_and, true_implies]
      rw [if_neg hc, if_neg hc]
  | contribute _ _ _ => rfl
  | retract _ => rfl
  | convict _ => rfl

/-- **Permissionless.** On the delegated path the owner's signature is
irrelevant: the fold steps the same with or without it. -/
theorem delegated_permissionless (p : Params) (env : Env) (a : Action) (now : Slot) (s : Sys) :
    stepFn .delegated Plugin.registry .delegatedRouting ⟨false, true⟩ p env a now s =
      stepFn .delegated Plugin.registry .delegatedRouting ⟨true, true⟩ p env a now s := by
  rw [delegated_is_registry, delegated_is_registry]

/-! ## The divergence: the cage as shipped -/

/-- **Owner-and-hook is not permissionless.** Under #79 as shipped, a fold
without the owner's signature is refused whatever the plugin says. -/
theorem ownerAndHook_needs_owner (pl : Plugin) (vm : ValueMode) (ran : Bool) (p : Params) (env : Env)
    (now : Slot) (s : Sys) (folder : Addr) (g : Gen) (pl' : Script) (batch : List (ReqId × FoldAction)) :
    stepFn .ownerAndHook pl vm ⟨false, ran⟩ p env (.fold folder g pl' batch) now s = none := by
  simp [stepFn, authorized]

/-- **Owner-keyed is not permissionless either.** -/
theorem ownerKeyed_needs_owner (pl : Plugin) (vm : ValueMode) (ran : Bool) (p : Params) (env : Env)
    (now : Slot) (s : Sys) (folder : Addr) (g : Gen) (pl' : Script) (batch : List (ReqId × FoldAction)) :
    stepFn .ownerKeyed pl vm ⟨false, ran⟩ p env (.fold folder g pl' batch) now s = none := by
  simp [stepFn, authorized]

/-- The deployment of the witnesses below. -/
def wp : Params := { D := 1000, tip := 2, process := 10, retract := 10,
                     hD := by decide, hProcess := by decide, hRetract := by decide }

/-- Evidence that verifies nothing: no inception, no proof. -/
def noEvidence : Env := { inception := fun _ => false, duplicity := fun _ => false }

/-- A registry with one pending request for AID 11 whose inception does not
verify. -/
def pending : Sys := { gen := 0, plugin := 7, root := [], live := [], tomb := [],
                       requests := [(0, ⟨11, 1, 0⟩)], nextReq := 1 }

/-- **The owner bypass.** Under the owner-keyed cage (`stake_script = None`),
the owner folds the request without the plugin: the row is inserted with no
inception evidence and no token — `Inv.rowIffToken` is false in the result.
The registry invariant therefore does not hold of the cage as shipped. -/
theorem owner_bypass_breaks_row_iff_token :
    stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨true, false⟩ wp noEvidence
        (.fold 1 0 7 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) },
            { gen := 1, plugin := 7, root := [11], live := [], tomb := [], requests := [], nextReq := 1 }) ∧
    ¬ Inv { gen := 1, plugin := 7, root := [11], live := [], tomb := [], requests := [], nextReq := 1 } := by
  refine ⟨by decide, fun h => ?_⟩
  have := (h.rowIffToken 11).1 (by decide)
  simp at this

/-- **The same bypass under owner-and-hook with the shipped stub.** The
withdrawal ran, but `staking.ak` admits everything and mints nothing. -/
theorem ownerAndHook_trivial_breaks_row_iff_token :
    stepFn .ownerAndHook Plugin.trivial .delegatedRouting ⟨true, true⟩ wp noEvidence
        (.fold 1 0 7 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) },
            { gen := 1, plugin := 7, root := [11], live := [], tomb := [], requests := [], nextReq := 1 }) := by
  decide

/-- **The owner swaps the plugin.** Off the delegated path the plugin is not
pinned: the owner re-creates the cage with plugin 8 (#100). -/
theorem owner_swaps_plugin :
    stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨true, false⟩ wp noEvidence
        (.fold 1 0 8 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) },
            { gen := 1, plugin := 8, root := [11], live := [], tomb := [], requests := [], nextReq := 1 }) := by
  decide

/-- **Delegated pins the plugin.** The same swap is refused on the delegated
path, whoever built the transaction. -/
theorem delegated_pins_plugin (signed ran : Bool) (p : Params) (env : Env) (now : Slot) (s : Sys)
    (folder : Addr) (g : Gen) {pl' : Script} (batch : List (ReqId × FoldAction)) (hpl : pl' ≠ s.plugin) :
    stepFn .delegated Plugin.registry .delegatedRouting ⟨signed, ran⟩ p env
      (.fold folder g pl' batch) now s = none := by
  simp [stepFn, hpl]

/-- **`refundAll` never funds a checkpoint.** Under `validModify` as shipped
a fold locks nothing: every processed request's bond goes back to its owner,
so the registration cannot fund the checkpoint (#101). -/
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
    cases fa <;> simp only [applyBatch] at h <;> split at h <;> try cases h
    all_goals split at h
    all_goals try cases h
    · have e := ih _ _ h; exact e
    · have e := ih _ _ h; exact e

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
