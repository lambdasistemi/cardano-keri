import CardanoKeri.Registry

/-!
# The registry machine: theorems R1 … R12

Every theorem below is a property of the model in `CardanoKeri.Registry`.
Whether the model is the right model is settled against D-024, the mpfs
plugin-cage epic and the stories, not by `lake build`.

Numbering:

* R1 — row if and only if token; an AID absent from the root has no token.
* R2 — at most one live checkpoint per AID; a tombstone is never live.
* R3 — conviction is permanent: the tombstone stays and the AID is never
  processed again.
* R4 — a closed AID may return: close deletes the row, and a fresh request
  can then be processed.
* R5 — the plugin is pinned.
* R6 — the generation moves exactly on registry spends; requests and
  retracts never contend; conviction does not spend the registry.
* R7 — a stale fold is refused with no state change; one fold per generation.
* R8 — an empty fold and a plugin swap are refused.
* R9 — requester exit: retract is enabled in phase 2, rejection by anyone
  when rejectable; neither elsewhere.
* R10 — the phases are exclusive.
* R11 — value: bonds lock or refund exactly, tips are `tip` per request,
  refunds go to request owners only.
* R12 — the root changes only by fold (insert) and close (delete).
-/

namespace CardanoKeri.Registry

/-- `omega` after unfolding the `Nat` abbreviations, which it does not see
through. -/
macro "omega'" : tactic =>
  `(tactic| ((try dsimp only [Slot, Addr, Value, AID, Gen, ReqId, Script] at *); omega))

/-- Given `hs : stepFn p env a now s = some (f, s')` for a concrete action,
close every refused branch and substitute the post-state for `s'` in the
applied ones. -/
macro "unstep" hs:ident : tactic =>
  `(tactic| (simp only [stepFn] at $hs:ident <;> (try (repeat' split at $hs:ident)) <;>
      first
      | cases $hs:ident
      | (simp only [Option.some.injEq, Prod.mk.injEq] at $hs:ident
         obtain ⟨_, rfl⟩ := $hs:ident)))

/-! ## Inbox lemmas -/

theorem lookup_some_mem {rs : List (ReqId × Request)} {id : ReqId} {r : Request}
    (h : lookup rs id = some r) : (id, r) ∈ rs := by
  induction rs with
  | nil => simp [lookup] at h
  | cons x xs ih =>
    obtain ⟨i, r'⟩ := x
    simp only [lookup] at h
    split at h
    · rename_i hi
      subst hi
      cases h
      exact List.mem_cons.2 (Or.inl rfl)
    · exact List.mem_cons_of_mem _ (ih h)

theorem mem_remove {rs : List (ReqId × Request)} {id : ReqId} {x : ReqId × Request}
    (h : x ∈ remove rs id) : x ∈ rs := by
  induction rs with
  | nil => simp [remove] at h
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [remove] at h
    split at h
    · exact List.mem_cons_of_mem _ (ih h)
    · rcases List.mem_cons.1 h with h | h
      · subst h; exact List.mem_cons.2 (Or.inl rfl)
      · exact List.mem_cons_of_mem _ (ih h)

theorem nodup_map_remove {rs : List (ReqId × Request)} {id : ReqId}
    (h : (rs.map (·.1)).Nodup) : ((remove rs id).map (·.1)).Nodup := by
  induction rs with
  | nil => simp [remove]
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    rw [List.map_cons, List.nodup_cons] at h
    obtain ⟨hi, hys⟩ := h
    simp only [remove]
    split
    · exact ih hys
    · rw [List.map_cons]
      refine List.nodup_cons.2 ⟨?_, ih hys⟩
      intro hm
      obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
      exact hi (List.mem_map.2 ⟨y, mem_remove hy, hyi⟩)

theorem lookup_remove_ne {rs : List (ReqId × Request)} {id id' : ReqId} (h : id ≠ id') :
    lookup (remove rs id') id = lookup rs id := by
  induction rs with
  | nil => rfl
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    by_cases h1 : i = id'
    · subst h1
      have h2 : i ≠ id := fun e => h e.symm
      simp [remove, lookup, h2, ih]
    · simp [remove, lookup, h1, ih]

theorem lookup_remove_none {rs : List (ReqId × Request)} {id i : ReqId}
    (h : lookup rs id = none) : lookup (remove rs i) id = none := by
  induction rs with
  | nil => rfl
  | cons y ys ih =>
    obtain ⟨j, r⟩ := y
    simp only [lookup] at h
    split at h
    · cases h
    · rename_i hj
      simp only [remove]
      split
      · exact ih h
      · simp [lookup, hj, ih h]

theorem lookup_remove_self {rs : List (ReqId × Request)} {id : ReqId} :
    lookup (remove rs id) id = none := by
  induction rs with
  | nil => rfl
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [remove]
    split
    · exact ih
    · rename_i hi
      simp [lookup, hi, ih]

/-! ## Batch lemmas -/

/-- What a fold preserves while threading its batch: `Inv` restricted to the
fields a batch touches, with the tombstones and the next identifier fixed. -/
structure AccInv (tomb : List AID) (n : ReqId) (acc : Acc) : Prop where
  rowIffToken : ∀ aid, aid ∈ acc.root ↔ (aid ∈ acc.live ∨ aid ∈ tomb)
  liveNodup : acc.live.Nodup
  rootNodup : acc.root.Nodup
  tombNotLive : ∀ aid, aid ∈ tomb → aid ∉ acc.live
  reqNodup : (acc.requests.map (·.1)).Nodup
  reqBelowNext : ∀ x, x ∈ acc.requests → x.1 < n

theorem applyBatch_inv (p : Params) (env : Env) (now : Slot) {tomb : List AID} {n : ReqId} :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {acc' : Acc},
      AccInv tomb n acc → applyBatch p env now acc batch = some acc' → AccInv tomb n acc' := by
  intro acc batch
  induction batch generalizing acc with
  | nil =>
    intro acc' hi h
    simp only [applyBatch, Option.some.injEq] at h
    subst h
    exact hi
  | cons x rest ih =>
    intro acc' hi h
    obtain ⟨id, fa⟩ := x
    cases fa with
    | process =>
      simp only [applyBatch] at h
      split at h
      · cases h
      · rename_i r hr
        split at h
        · rename_i hc
          obtain ⟨_, _, h3⟩ := hc
          refine ih ?_ h
          have hnl : r.aid ∉ acc.live := fun hm => h3 ((hi.rowIffToken r.aid).2 (Or.inl hm))
          have hnt : r.aid ∉ tomb := fun hm => h3 ((hi.rowIffToken r.aid).2 (Or.inr hm))
          exact {
            rowIffToken := by
              intro a
              have e := hi.rowIffToken a
              simp only [List.mem_cons]
              constructor
              · rintro (h | h)
                · exact Or.inl (Or.inl h)
                · rcases e.1 h with h' | h'
                  · exact Or.inl (Or.inr h')
                  · exact Or.inr h'
              · rintro ((h | h) | h)
                · exact Or.inl h
                · exact Or.inr (e.2 (Or.inl h))
                · exact Or.inr (e.2 (Or.inr h))
            liveNodup := List.nodup_cons.2 ⟨hnl, hi.liveNodup⟩
            rootNodup := List.nodup_cons.2 ⟨h3, hi.rootNodup⟩
            tombNotLive := by
              intro a ha hm
              rcases List.mem_cons.1 hm with hm | hm
              · subst hm; exact hnt ha
              · exact hi.tombNotLive a ha hm
            reqNodup := nodup_map_remove hi.reqNodup
            reqBelowNext := fun x hx => hi.reqBelowNext x (mem_remove hx) }
        · cases h
    | reject =>
      simp only [applyBatch] at h
      split at h
      · cases h
      · rename_i r hr
        split at h
        · refine ih ?_ h
          exact {
            rowIffToken := hi.rowIffToken
            liveNodup := hi.liveNodup
            rootNodup := hi.rootNodup
            tombNotLive := hi.tombNotLive
            reqNodup := nodup_map_remove hi.reqNodup
            reqBelowNext := fun x hx => hi.reqBelowNext x (mem_remove hx) }
        · cases h

theorem applyBatch_root_mono (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {acc' : Acc},
      applyBatch p env now acc batch = some acc' → ∀ a, a ∈ acc.root → a ∈ acc'.root := by
  intro acc batch
  induction batch generalizing acc with
  | nil =>
    intro acc' h a ha
    simp only [applyBatch, Option.some.injEq] at h
    subst h; exact ha
  | cons x rest ih =>
    intro acc' h a ha
    obtain ⟨id, fa⟩ := x
    cases fa <;> simp only [applyBatch] at h <;> split at h <;> try cases h
    all_goals split at h
    all_goals try cases h
    · exact ih h a (List.mem_cons_of_mem _ ha)
    · exact ih h a ha

theorem applyBatch_live_mono (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {acc' : Acc},
      applyBatch p env now acc batch = some acc' → ∀ a, a ∈ acc.live → a ∈ acc'.live := by
  intro acc batch
  induction batch generalizing acc with
  | nil =>
    intro acc' h a ha
    simp only [applyBatch, Option.some.injEq] at h
    subst h; exact ha
  | cons x rest ih =>
    intro acc' h a ha
    obtain ⟨id, fa⟩ := x
    cases fa <;> simp only [applyBatch] at h <;> split at h <;> try cases h
    all_goals split at h
    all_goals try cases h
    · exact ih h a (List.mem_cons_of_mem _ ha)
    · exact ih h a ha

theorem applyBatch_requests_sub (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {acc' : Acc},
      applyBatch p env now acc batch = some acc' → ∀ x, x ∈ acc'.requests → x ∈ acc.requests := by
  intro acc batch
  induction batch generalizing acc with
  | nil =>
    intro acc' h x hx
    simp only [applyBatch, Option.some.injEq] at h
    subst h; exact hx
  | cons y rest ih =>
    intro acc' h x hx
    obtain ⟨id, fa⟩ := y
    cases fa <;> simp only [applyBatch] at h <;> split at h <;> try cases h
    all_goals split at h
    all_goals try cases h
    · exact mem_remove (ih h x hx)
    · exact mem_remove (ih h x hx)

/-- Every locked entry a batch adds is a bond of exactly `D`, and every refund
it adds is exactly `D` to the owner of a request that was pending. -/
theorem applyBatch_value (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {acc' : Acc},
      applyBatch p env now acc batch = some acc' →
        (∀ x, x ∈ acc'.locked → x ∈ acc.locked ∨ x.2 = p.D) ∧
        (∀ x, x ∈ acc'.refunds → x ∈ acc.refunds ∨
          ∃ id r, (id, r) ∈ acc.requests ∧ x = (r.owner, p.D)) ∧
        acc'.locked.length + acc'.refunds.length = acc.locked.length + acc.refunds.length + batch.length := by
  intro acc batch
  induction batch generalizing acc with
  | nil =>
    intro acc' h
    simp only [applyBatch, Option.some.injEq] at h
    subst h
    exact ⟨fun x hx => Or.inl hx, fun x hx => Or.inl hx, by simp⟩
  | cons y rest ih =>
    intro acc' h
    obtain ⟨id, fa⟩ := y
    cases fa <;> simp only [applyBatch] at h <;> split at h <;> try cases h
    all_goals split at h
    all_goals try cases h
    · rename_i r hr _
      obtain ⟨hl, hrf, hlen⟩ := ih h
      refine ⟨?_, ?_, ?_⟩
      · intro x hx
        rcases hl x hx with hx | hx
        · rcases List.mem_append.1 hx with hx | hx
          · exact Or.inl hx
          · simp at hx; subst hx; exact Or.inr rfl
        · exact Or.inr hx
      · intro x hx
        rcases hrf x hx with hx | ⟨id', r', hm, he⟩
        · exact Or.inl hx
        · exact Or.inr ⟨id', r', mem_remove hm, he⟩
      · simp only [List.length_append, List.length_cons, List.length_nil] at hlen ⊢
        omega
    · rename_i r hr _
      obtain ⟨hl, hrf, hlen⟩ := ih h
      refine ⟨?_, ?_, ?_⟩
      · exact hl
      · intro x hx
        rcases hrf x hx with hx | ⟨id', r', hm, he⟩
        · rcases List.mem_append.1 hx with hx | hx
          · exact Or.inl hx
          · simp at hx; subst hx; exact Or.inr ⟨id, r, lookup_some_mem hr, rfl⟩
        · exact Or.inr ⟨id', r', mem_remove hm, he⟩
      · simp only [List.length_append, List.length_cons, List.length_nil] at hlen ⊢
        omega

/-- A batch that names a request the inbox does not hold is refused. -/
theorem applyBatch_unknown (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {id : ReqId} {fa : FoldAction},
      (id, fa) ∈ batch → lookup acc.requests id = none → applyBatch p env now acc batch = none := by
  intro acc batch
  induction batch generalizing acc with
  | nil => intro id fa hm; simp at hm
  | cons y rest ih =>
    intro id fa hm hl
    obtain ⟨i, fa'⟩ := y
    rcases List.mem_cons.1 hm with hm2 | hm2
    · cases hm2
      cases fa <;> simp [applyBatch, hl]
    · cases fa' <;> simp only [applyBatch] <;> split
      · rfl
      · split
        · exact ih hm2 (lookup_remove_none hl)
        · rfl
      · rfl
      · split
        · exact ih hm2 (lookup_remove_none hl)
        · rfl

/-- **The absence proof.** A batch that processes a request whose AID is
already in the root is refused, wherever in the batch it sits. -/
theorem applyBatch_process_registered (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {id : ReqId} {r : Request},
      (id, .process) ∈ batch → lookup acc.requests id = some r → r.aid ∈ acc.root →
        applyBatch p env now acc batch = none := by
  intro acc batch
  induction batch generalizing acc with
  | nil => intro id r hm; simp at hm
  | cons y rest ih =>
    intro id r hm hl hroot
    obtain ⟨i, fa⟩ := y
    by_cases hi : i = id
    · subst hi
      cases fa with
      | process =>
        simp only [applyBatch, hl]
        split
        · rename_i hc; exact absurd hroot hc.2.2
        · rfl
      | reject =>
        have hm' : (i, FoldAction.process) ∈ rest := by
          rcases List.mem_cons.1 hm with hm | hm
          · cases hm
          · exact hm
        simp only [applyBatch]
        split
        · rfl
        · rename_i r' hr'
          split
          · exact applyBatch_unknown p env now hm' lookup_remove_self
          · rfl
    · have hm' : (id, FoldAction.process) ∈ rest := by
        rcases List.mem_cons.1 hm with hm | hm
        · cases hm; exact absurd rfl hi
        · exact hm
      cases fa <;> simp only [applyBatch] <;> split
      · rfl
      · split
        · rename_i r' hr' hc
          exact ih hm' (by rw [lookup_remove_ne (Ne.symm hi)]; exact hl)
            (List.mem_cons_of_mem _ hroot)
        · rfl
      · rfl
      · split
        · exact ih hm' (by rw [lookup_remove_ne (Ne.symm hi)]; exact hl) hroot
        · rfl

/-! ## The invariant is reachable-preserved -/

theorem inv_init (plugin : Script) : Inv (Sys.init plugin) := by
  exact {
    rowIffToken := by intro a; simp [Sys.init]
    liveNodup := List.nodup_nil
    tombNodup := List.nodup_nil
    tombNotLive := by intro a ha; simp [Sys.init] at ha
    rootNodup := List.nodup_nil
    reqNodup := List.nodup_nil
    reqBelowNext := by intro x hx; simp [Sys.init] at hx }

/-- `Inv` transfers to and from a batch accumulator. -/
theorem accInv_of_inv {s : Sys} (hi : Inv s) :
    AccInv s.tomb s.nextReq ⟨s.root, s.live, s.requests, [], []⟩ :=
  { rowIffToken := hi.rowIffToken, liveNodup := hi.liveNodup, rootNodup := hi.rootNodup,
    tombNotLive := hi.tombNotLive, reqNodup := hi.reqNodup, reqBelowNext := hi.reqBelowNext }

theorem inv_step (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    (hi : Inv s) (hs : stepFn p env a now s = some (f, s')) : Inv s' := by
  cases a with
  | contribute aid owner t =>
    simp only [stepFn, Option.some.injEq, Prod.mk.injEq] at hs
    obtain ⟨_, rfl⟩ := hs
    exact {
      rowIffToken := hi.rowIffToken
      liveNodup := hi.liveNodup
      tombNodup := hi.tombNodup
      tombNotLive := hi.tombNotLive
      rootNodup := hi.rootNodup
      reqNodup := by
        rw [List.map_cons]
        refine List.nodup_cons.2 ⟨?_, hi.reqNodup⟩
        intro hm
        obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
        have hlt := hi.reqBelowNext y hy
        simp only at hyi
        rw [hyi] at hlt
        exact Nat.lt_irrefl _ hlt
      reqBelowNext := by
        intro x hx
        rcases List.mem_cons.1 hx with hx | hx
        · subst hx; exact Nat.lt_succ_self _
        · exact Nat.lt_succ_of_lt (hi.reqBelowNext x hx) }
  | retract id =>
    simp only [stepFn] at hs
    split at hs
    · cases hs
    · split at hs
      · simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        exact {
          rowIffToken := hi.rowIffToken
          liveNodup := hi.liveNodup
          tombNodup := hi.tombNodup
          tombNotLive := hi.tombNotLive
          rootNodup := hi.rootNodup
          reqNodup := nodup_map_remove hi.reqNodup
          reqBelowNext := fun x hx => hi.reqBelowNext x (mem_remove hx) }
      · cases hs
  | fold folder g pl batch =>
    simp only [stepFn] at hs
    split at hs
    · split at hs
      · cases hs
      · rename_i acc hacc
        simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        have ha := applyBatch_inv p env now (accInv_of_inv hi) hacc
        exact {
          rowIffToken := ha.rowIffToken
          liveNodup := ha.liveNodup
          tombNodup := hi.tombNodup
          tombNotLive := ha.tombNotLive
          rootNodup := ha.rootNodup
          reqNodup := ha.reqNodup
          reqBelowNext := ha.reqBelowNext }
    · cases hs
  | close aid =>
    simp only [stepFn] at hs
    split at hs
    · rename_i hc
      obtain ⟨hlive, _⟩ := hc
      simp only [Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨_, rfl⟩ := hs
      exact {
        rowIffToken := by
          intro a
          simp only
          rw [hi.rootNodup.mem_erase_iff, hi.liveNodup.mem_erase_iff]
          have e := hi.rowIffToken a
          constructor
          · rintro ⟨hne, hr⟩
            rcases e.1 hr with h | h
            · exact Or.inl ⟨hne, h⟩
            · exact Or.inr h
          · rintro (⟨hne, hl⟩ | ht)
            · exact ⟨hne, e.2 (Or.inl hl)⟩
            · refine ⟨?_, e.2 (Or.inr ht)⟩
              intro heq
              subst heq
              exact hi.tombNotLive a ht hlive
        liveNodup := hi.liveNodup.erase aid
        tombNodup := hi.tombNodup
        tombNotLive := fun a ha hm => hi.tombNotLive a ha (List.mem_of_mem_erase hm)
        rootNodup := hi.rootNodup.erase aid
        reqNodup := hi.reqNodup
        reqBelowNext := hi.reqBelowNext }
    · cases hs
  | convict aid =>
    simp only [stepFn] at hs
    split at hs
    · rename_i hc
      obtain ⟨hlive, _⟩ := hc
      simp only [Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨_, rfl⟩ := hs
      have hnt : aid ∉ s.tomb := fun ht => hi.tombNotLive aid ht hlive
      exact {
        rowIffToken := by
          intro a
          simp only [List.mem_cons]
          rw [hi.liveNodup.mem_erase_iff]
          have e := hi.rowIffToken a
          by_cases ha : a = aid
          · subst ha
            constructor
            · intro _; exact Or.inr (Or.inl rfl)
            · intro _; exact e.2 (Or.inl hlive)
          · constructor
            · intro hr
              rcases e.1 hr with h | h
              · exact Or.inl ⟨ha, h⟩
              · exact Or.inr (Or.inr h)
            · rintro (⟨_, hl⟩ | h | ht)
              · exact e.2 (Or.inl hl)
              · exact absurd h ha
              · exact e.2 (Or.inr ht)
        liveNodup := hi.liveNodup.erase aid
        tombNodup := List.nodup_cons.2 ⟨hnt, hi.tombNodup⟩
        tombNotLive := by
          intro a ha hm
          rcases List.mem_cons.1 ha with ha | ha
          · subst ha; exact hi.liveNodup.not_mem_erase hm
          · exact hi.tombNotLive a ha (List.mem_of_mem_erase hm)
        rootNodup := hi.rootNodup
        reqNodup := hi.reqNodup
        reqBelowNext := hi.reqBelowNext }
    · cases hs

theorem reach_inv (p : Params) (env : Env) {s : Sys} (h : Reach p env s) : Inv s := by
  induction h with
  | init plugin => exact inv_init plugin
  | step _ hs ih => exact inv_step p env ih hs

/-! ## R1 — row if and only if token -/

/-- **R1a.** In every reachable system an AID is in the root exactly when it
has a live checkpoint or a tombstone. -/
theorem R1_row_iff_token (p : Params) (env : Env) {s : Sys} (h : Reach p env s) (aid : AID) :
    aid ∈ s.root ↔ (aid ∈ s.live ∨ aid ∈ s.tomb) :=
  (reach_inv p env h).rowIffToken aid

/-- **R1b.** An AID absent from the root has no token of any kind: the
absence proof a registration presents is a proof that no checkpoint exists. -/
theorem R1_absent_no_token (p : Params) (env : Env) {s : Sys} (h : Reach p env s) (aid : AID)
    (habs : aid ∉ s.root) : aid ∉ s.live ∧ aid ∉ s.tomb :=
  ⟨fun hl => habs ((R1_row_iff_token p env h aid).2 (Or.inl hl)),
   fun ht => habs ((R1_row_iff_token p env h aid).2 (Or.inr ht))⟩

/-- **R1c.** A fold that processes a request for an AID already in the root
is refused, wherever the request sits in the batch: mint-once while the row
stands. -/
theorem R1_registered_refused (p : Params) (env : Env) (now : Slot) (s : Sys)
    (folder : Addr) (batch : List (ReqId × FoldAction)) {id : ReqId} {r : Request}
    (hm : (id, .process) ∈ batch) (hl : lookup s.requests id = some r) (hr : r.aid ∈ s.root) :
    stepFn p env (.fold folder s.gen s.plugin batch) now s = none := by
  simp only [stepFn]
  split
  · rw [applyBatch_process_registered p env now hm hl hr]
  · rfl

/-! ## R2 — at most one live checkpoint per AID -/

/-- **R2a.** No AID has two live checkpoints. -/
theorem R2_one_live_checkpoint (p : Params) (env : Env) {s : Sys} (h : Reach p env s) :
    s.live.Nodup :=
  (reach_inv p env h).liveNodup

/-- **R2b.** A convicted AID has no live checkpoint. -/
theorem R2_tomb_not_live (p : Params) (env : Env) {s : Sys} (h : Reach p env s) (aid : AID)
    (ht : aid ∈ s.tomb) : aid ∉ s.live :=
  (reach_inv p env h).tombNotLive aid ht

/-! ## R3 — conviction is permanent -/

/-- **R3a.** No step removes a tombstone. -/
theorem R3_tomb_permanent (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (aid : AID) (ht : aid ∈ s.tomb) :
    aid ∈ s'.tomb := by
  cases a <;> unstep hs <;> first | exact ht | exact List.mem_cons_of_mem _ ht

/-- **R3b.** A request for a convicted AID can never be processed: the row
stays, so the absence proof fails. -/
theorem R3_convicted_never_processed (p : Params) (env : Env) (now : Slot) {s : Sys}
    (h : Reach p env s) (folder : Addr) (batch : List (ReqId × FoldAction)) {id : ReqId} {r : Request}
    (hm : (id, .process) ∈ batch) (hl : lookup s.requests id = some r) (ht : r.aid ∈ s.tomb) :
    stepFn p env (.fold folder s.gen s.plugin batch) now s = none :=
  R1_registered_refused p env now s folder batch hm hl ((R1_row_iff_token p env h r.aid).2 (Or.inr ht))

/-- **R3c.** A convicted AID cannot be closed: its token is not live. -/
theorem R3_convicted_not_closable (p : Params) (env : Env) (now : Slot) {s : Sys}
    (h : Reach p env s) (aid : AID) (ht : aid ∈ s.tomb) :
    stepFn p env (.close aid) now s = none := by
  have := R2_tomb_not_live p env h aid ht
  simp [stepFn, this]

/-! ## R4 — a closed AID may return -/

/-- **R4a.** Close deletes the row. -/
theorem R4_close_deletes_row (p : Params) (env : Env) {now : Slot} {s : Sys} (h : Reach p env s)
    {aid : AID} {f : Flow} {s' : Sys} (hs : stepFn p env (.close aid) now s = some (f, s')) :
    aid ∉ s'.root ∧ aid ∉ s'.live := by
  simp only [stepFn] at hs
  split at hs
  · simp only [Option.some.injEq, Prod.mk.injEq] at hs
    obtain ⟨_, rfl⟩ := hs
    exact ⟨(reach_inv p env h).rootNodup.not_mem_erase, (reach_inv p env h).liveNodup.not_mem_erase⟩
  · cases hs

/-- **R4b.** An AID absent from the root with a pending request in phase 1
and valid inception evidence can be processed by anyone at the current
generation, and is then live and registered. -/
theorem R4_reregistrable (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    {id : ReqId} {r : Request} (hl : lookup s.requests id = some r) (habs : r.aid ∉ s.root)
    (h1 : inPhase1 p r now) (hev : env.inception r.aid = true) :
    ∃ f s', stepFn p env (.fold folder s.gen s.plugin [(id, .process)]) now s = some (f, s') ∧
      r.aid ∈ s'.live ∧ r.aid ∈ s'.root := by
  refine ⟨{ locked := [(r.aid, p.D)], tips := some (folder, 1 * p.tip) },
    { s with gen := s.gen + 1, root := r.aid :: s.root, live := r.aid :: s.live,
             requests := remove s.requests id }, ?_, ?_, ?_⟩
  · simp [stepFn, applyBatch, hl, h1, hev, habs]
  · exact List.mem_cons.2 (Or.inl rfl)
  · exact List.mem_cons.2 (Or.inl rfl)

/-! ## R5 — the plugin is pinned -/

theorem R5_plugin_pinned (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s')) : s'.plugin = s.plugin := by
  cases a <;> unstep hs <;> rfl

/-! ## R6 — the generation moves exactly on registry spends -/

/-- **R6a.** Every step moves the generation by zero or one. -/
theorem R6_gen_step (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s')) :
    s'.gen = s.gen ∨ s'.gen = s.gen + 1 := by
  cases a <;> unstep hs <;> first | exact Or.inl rfl | exact Or.inr rfl

/-- **R6b.** Requests never contend: a contribute or a retract leaves the
registry UTxO, the root and the tokens untouched. -/
theorem R6_requests_never_contend (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys}
    {f : Flow} {s' : Sys} (hs : stepFn p env a now s = some (f, s'))
    (ha : (∃ aid owner t, a = .contribute aid owner t) ∨ ∃ id, a = .retract id) :
    s'.gen = s.gen ∧ s'.root = s.root ∧ s'.live = s.live ∧ s'.tomb = s.tomb := by
  rcases ha with ⟨aid, owner, t, rfl⟩ | ⟨id, rfl⟩
  · simp only [stepFn, Option.some.injEq, Prod.mk.injEq] at hs
    obtain ⟨_, rfl⟩ := hs
    exact ⟨rfl, rfl, rfl, rfl⟩
  · simp only [stepFn] at hs
    split at hs
    · cases hs
    · split at hs
      · simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        exact ⟨rfl, rfl, rfl, rfl⟩
      · cases hs

/-- **R6c.** Only a fold or a close spends the registry. -/
theorem R6_spend_is_fold_or_close (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys}
    {f : Flow} {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (hg : s'.gen ≠ s.gen) :
    (∃ folder g pl batch, a = .fold folder g pl batch) ∨ ∃ aid, a = .close aid := by
  cases a with
  | contribute aid owner t =>
    exact absurd (R6_requests_never_contend p env hs (Or.inl ⟨aid, owner, t, rfl⟩)).1 hg
  | retract id =>
    exact absurd (R6_requests_never_contend p env hs (Or.inr ⟨id, rfl⟩)).1 hg
  | fold folder g pl batch => exact Or.inl ⟨folder, g, pl, batch, rfl⟩
  | close aid => exact Or.inr ⟨aid, rfl⟩
  | convict aid =>
    simp only [stepFn] at hs
    split at hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨_, rfl⟩ := hs
      exact absurd rfl hg
    · cases hs

/-- **R6d.** A fold and a close each spend the registry: the generation
advances by exactly one. -/
theorem R6_fold_advances (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {folder : Addr} {g : Gen} {pl : Script} {batch : List (ReqId × FoldAction)}
    (hs : stepFn p env (.fold folder g pl batch) now s = some (f, s')) : s'.gen = s.gen + 1 := by
  simp only [stepFn] at hs
  split at hs
  · split at hs
    · cases hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨_, rfl⟩ := hs; rfl
  · cases hs

/-! ## R7 — contention: a stale fold is refused, one fold per generation -/

/-- **R7a.** A fold naming a generation other than the registry's is refused:
no state changes, nothing is paid. -/
theorem R7_stale_fold_refused (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    {g : Gen} (pl : Script) (batch : List (ReqId × FoldAction)) (hg : g ≠ s.gen) :
    stepFn p env (.fold folder g pl batch) now s = none := by
  simp [stepFn, hg]

/-- **R7b.** Two folds cannot land on one generation: after a fold at `g`,
any fold at `g` is refused. -/
theorem R7_one_fold_per_generation (p : Params) (env : Env) {now now' : Slot} {s : Sys} {f : Flow}
    {s' : Sys} {folder folder' : Addr} {g : Gen} {pl pl' : Script}
    {batch batch' : List (ReqId × FoldAction)}
    (hs : stepFn p env (.fold folder g pl batch) now s = some (f, s')) :
    stepFn p env (.fold folder' g pl' batch') now' s' = none := by
  have hg' := R6_fold_advances p env hs
  have hg : g = s.gen := by
    simp only [stepFn] at hs
    split at hs
    · rename_i hc; exact hc.1
    · cases hs
  exact R7_stale_fold_refused p env now' s' folder' pl' batch' (by omega')

/-! ## R8 — an empty fold and a plugin swap are refused -/

theorem R8_empty_fold_refused (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) (pl : Script) : stepFn p env (.fold folder g pl []) now s = none := by
  simp [stepFn]

theorem R8_plugin_swap_refused (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) {pl : Script} (batch : List (ReqId × FoldAction)) (hpl : pl ≠ s.plugin) :
    stepFn p env (.fold folder g pl batch) now s = none := by
  simp [stepFn, hpl]

/-! ## R9 — requester exit -/

/-- **R9a.** In phase 2 the owner retracts and gets everything back. -/
theorem R9_retract_enabled (p : Params) (env : Env) (now : Slot) (s : Sys) {id : ReqId} {r : Request}
    (hl : lookup s.requests id = some r) (h2 : inPhase2 p r now) :
    stepFn p env (.retract id) now s =
      some ({ refunds := [(r.owner, p.D + p.tip)] }, { s with requests := remove s.requests id }) := by
  simp [stepFn, hl, h2]

/-- **R9b.** Outside phase 2 a retract is refused. -/
theorem R9_retract_needs_phase2 (p : Params) (env : Env) (now : Slot) (s : Sys) {id : ReqId}
    {r : Request} (hl : lookup s.requests id = some r) (h2 : ¬ inPhase2 p r now) :
    stepFn p env (.retract id) now s = none := by
  simp [stepFn, hl, h2]

/-- **R9c.** When a request is rejectable, anyone can reject it at the
current generation, and the bond goes back to its owner. -/
theorem R9_reject_enabled (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    {id : ReqId} {r : Request} (hl : lookup s.requests id = some r) (h3 : rejectable p r now) :
    stepFn p env (.fold folder s.gen s.plugin [(id, .reject)]) now s =
      some ({ refunds := [(r.owner, p.D)], tips := some (folder, 1 * p.tip) },
            { s with gen := s.gen + 1, requests := remove s.requests id }) := by
  simp [stepFn, applyBatch, hl, h3]

/-- **R9d.** A request that is not rejectable cannot be rejected. -/
theorem R9_reject_needs_rejectable (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) (pl : Script) {id : ReqId} {r : Request} (hl : lookup s.requests id = some r)
    (h3 : ¬ rejectable p r now) :
    stepFn p env (.fold folder g pl [(id, .reject)]) now s = none := by
  simp only [stepFn]
  split
  · simp [applyBatch, hl, h3]
  · rfl

/-- **R9e.** A request outside phase 1 cannot be processed. -/
theorem R9_process_needs_phase1 (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) (pl : Script) {id : ReqId} {r : Request} (hl : lookup s.requests id = some r)
    (h1 : ¬ inPhase1 p r now) :
    stepFn p env (.fold folder g pl [(id, .process)]) now s = none := by
  simp only [stepFn]
  split
  · simp [applyBatch, hl, h1]
  · rfl

/-! ## R10 — the phases are exclusive -/

theorem R10_phase1_phase2_exclusive (p : Params) (r : Request) (now : Slot) :
    ¬ (inPhase1 p r now ∧ inPhase2 p r now) := by
  unfold inPhase1 inPhase2; omega'

theorem R10_phase2_reject_exclusive (p : Params) (r : Request) (now : Slot) :
    ¬ (inPhase2 p r now ∧ rejectable p r now) := by
  unfold inPhase2 rejectable; omega'

/-- For an honest timestamp, phase 1 and rejectability exclude each other;
a request dated in the future is both processable and rejectable, as on
chain. -/
theorem R10_honest_phase1_reject_exclusive (p : Params) (r : Request) (now : Slot)
    (hhonest : r.submittedAt ≤ now) : ¬ (inPhase1 p r now ∧ rejectable p r now) := by
  unfold inPhase1 rejectable; have := p.hRetract; omega'

/-! ## R11 — value -/

/-- **R11a.** A fold locks exactly `D` per processed request, refunds exactly
`D` per rejected request to the owner of a pending request, pays the folder
exactly `tip` per request of the batch, and accounts for every request. -/
theorem R11_fold_value (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {folder : Addr} {g : Gen} {pl : Script} {batch : List (ReqId × FoldAction)}
    (hs : stepFn p env (.fold folder g pl batch) now s = some (f, s')) :
    (∀ x, x ∈ f.locked → x.2 = p.D) ∧
    (∀ x, x ∈ f.refunds → ∃ id r, (id, r) ∈ s.requests ∧ x = (r.owner, p.D)) ∧
    f.tips = some (folder, batch.length * p.tip) ∧
    f.locked.length + f.refunds.length = batch.length ∧ f.deposited = 0 := by
  simp only [stepFn] at hs
  split at hs
  · split at hs
    · cases hs
    · rename_i acc hacc
      simp only [Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨rfl, _⟩ := hs
      obtain ⟨hl, hrf, hlen⟩ := applyBatch_value p env now hacc
      refine ⟨?_, ?_, rfl, ?_, rfl⟩
      · intro x hx
        rcases hl x hx with hx | hx
        · simp at hx
        · exact hx
      · intro x hx
        rcases hrf x hx with hx | hx
        · simp at hx
        · exact hx
      · simpa using hlen
  · cases hs

/-- **R11b.** A retract returns the bond and the tip to the owner. -/
theorem R11_retract_value (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {id : ReqId} (hs : stepFn p env (.retract id) now s = some (f, s')) :
    ∃ r, lookup s.requests id = some r ∧ f.refunds = [(r.owner, p.D + p.tip)] ∧
      f.locked = [] ∧ f.tips = none := by
  simp only [stepFn] at hs
  split at hs
  · cases hs
  · rename_i r hr
    split at hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨rfl, _⟩ := hs
      exact ⟨r, hr, rfl, rfl, rfl⟩
    · cases hs

/-- **R11c.** A request deposits exactly the bond and the tip. -/
theorem R11_contribute_value (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {aid : AID} {owner : Addr} {t : Slot}
    (hs : stepFn p env (.contribute aid owner t) now s = some (f, s')) :
    f.deposited = p.D + p.tip ∧ f.refunds = [] ∧ f.locked = [] ∧ f.tips = none := by
  simp only [stepFn, Option.some.injEq, Prod.mk.injEq] at hs
  obtain ⟨rfl, _⟩ := hs
  exact ⟨rfl, rfl, rfl, rfl⟩

/-- **R11d.** Close and convict move no request value. -/
theorem R11_token_edges_move_no_value (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} {a : Action} (hs : stepFn p env a now s = some (f, s'))
    (ha : (∃ aid, a = .close aid) ∨ ∃ aid, a = .convict aid) : f = {} := by
  rcases ha with ⟨aid, rfl⟩ | ⟨aid, rfl⟩ <;> unstep hs <;> rfl

/-! ## R12 — the root changes only by fold and close -/

/-- **R12a.** A row leaves the root only by closing that AID. -/
theorem R12_row_leaves_only_by_close (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys}
    {f : Flow} {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (aid : AID)
    (hin : aid ∈ s.root) (hout : aid ∉ s'.root) : a = .close aid := by
  cases a with
  | contribute aid' owner t =>
    have := R6_requests_never_contend p env hs (Or.inl ⟨aid', owner, t, rfl⟩)
    rw [this.2.1] at hout; exact absurd hin hout
  | retract id =>
    have := R6_requests_never_contend p env hs (Or.inr ⟨id, rfl⟩)
    rw [this.2.1] at hout; exact absurd hin hout
  | fold folder g pl batch =>
    simp only [stepFn] at hs
    split at hs
    · split at hs
      · cases hs
      · rename_i acc hacc
        simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        exact absurd (applyBatch_root_mono p env now hacc aid hin) hout
    · cases hs
  | close aid' =>
    unstep hs
    by_cases h : aid = aid'
    · subst h; rfl
    · exact absurd ((List.mem_erase_of_ne h).2 hin) hout
  | convict aid' =>
    unstep hs
    exact absurd hin hout

/-- **R12b.** A row enters the root only by a fold. -/
theorem R12_row_enters_only_by_fold (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys}
    {f : Flow} {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (aid : AID)
    (hout : aid ∉ s.root) (hin : aid ∈ s'.root) : ∃ folder g pl batch, a = .fold folder g pl batch := by
  cases a with
  | contribute aid' owner t =>
    have := R6_requests_never_contend p env hs (Or.inl ⟨aid', owner, t, rfl⟩)
    rw [this.2.1] at hin; exact absurd hin hout
  | retract id =>
    have := R6_requests_never_contend p env hs (Or.inr ⟨id, rfl⟩)
    rw [this.2.1] at hin; exact absurd hin hout
  | fold folder g pl batch => exact ⟨folder, g, pl, batch, rfl⟩
  | close aid' =>
    simp only [stepFn] at hs
    split at hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨_, rfl⟩ := hs
      exact absurd (List.mem_of_mem_erase hin) hout
    · cases hs
  | convict aid' =>
    simp only [stepFn] at hs
    split at hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨_, rfl⟩ := hs
      exact absurd hin hout
    · cases hs

end CardanoKeri.Registry
