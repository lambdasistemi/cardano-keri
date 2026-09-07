import CardanoKeri.Registry
import CardanoKeri.Samaritan

/-!
# The registry machine: theorems R1 … R13

Every theorem below is a property of the model in `CardanoKeri.Registry`.
Whether the model is the right model is settled against D-024, the rulings
of 2026-09-02/03, the mpfs plugin-cage epic and the stories, not by
`lake build`.

* R1 — leaf and checkpoint: a checkpoint implies an active leaf; an active
  leaf has its checkpoint or a pending go-request; a dormant or convicted
  leaf has no checkpoint; a registered AID cannot be registered again.
* R2 — at most one checkpoint, one leaf, one go-request per AID.
* R3 — conviction is permanent: a convicted leaf never changes.
* R4 — leaves are permanent: a leaf never leaves the root.
* R5 — the plugin is pinned.
* R6 — the generation moves exactly on the fold; contribute, retract, reap,
  pause, resume and a checkpoint conviction never write the registry.
* R7 — a stale fold is refused with no state change; one fold per generation.
* R8 — an empty fold and a plugin swap are refused.
* R9 — requester exit and no bricking: a posted request is retractable in
  phase 2 and rejectable when rejectable; a go-request is never retractable
  before the end of time and never rejectable, so `k` is never lost.
* R10 — the phases are exclusive.
* R11 — value: registration and revival lock `D`; rejects and retracts refund
  the request's own bond to its owner; a processed go-request refunds its
  min-ADA to the reaper; the reap's premium and request add up to the
  checkpoint's min-ADA, so the good samaritan theorems apply.
* R12 — a leaf enters and changes only by a fold.
* R13 — the reap: never a bonded checkpoint; a tombstone at once; a parked
  checkpoint by a stranger only after the grace window.
-/

namespace CardanoKeri.Registry

macro "omega'" : tactic =>
  `(tactic| ((try dsimp only [Slot, Addr, Value, AID, Gen, ReqId, Script, Token, KeyState] at *); omega))

/-- Given `hs : stepFn p env a now s = some (f, s')` for a concrete action,
close every refused branch and substitute the post-state for `s'` in the
applied ones. -/
macro "unstep" hs:ident : tactic =>
  `(tactic| (simp only [stepFn] at $hs:ident <;> (try (repeat' split at $hs:ident)) <;>
      first
      | cases $hs:ident
      | (simp only [Option.some.injEq, Prod.mk.injEq] at $hs:ident
         obtain ⟨_, rfl⟩ := $hs:ident)))

/-! ## Association-list lemmas -/

section Assoc
variable {α : Type}

theorem lookup_some_mem {rs : List (Nat × α)} {id : Nat} {r : α}
    (h : lookup rs id = some r) : (id, r) ∈ rs := by
  induction rs with
  | nil => simp [lookup] at h
  | cons x xs ih =>
    obtain ⟨i, r'⟩ := x
    simp only [lookup] at h
    split at h
    · rename_i hi; subst hi; cases h; exact List.mem_cons.2 (Or.inl rfl)
    · exact List.mem_cons_of_mem _ (ih h)

theorem lookup_none_of_not_mem {rs : List (Nat × α)} {id : Nat}
    (h : ∀ x, x ∈ rs → x.1 ≠ id) : lookup rs id = none := by
  induction rs with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨i, r⟩ := x
    simp only [lookup]
    have hi : i ≠ id := h (i, r) (List.mem_cons.2 (Or.inl rfl))
    rw [if_neg hi]
    exact ih (fun y hy => h y (List.mem_cons_of_mem _ hy))

theorem not_mem_of_lookup_none {rs : List (Nat × α)} {id : Nat} (h : lookup rs id = none) :
    ∀ x, x ∈ rs → x.1 ≠ id := by
  induction rs with
  | nil => intro x hx; simp at hx
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [lookup] at h
    split at h
    · cases h
    · rename_i hi
      intro x hx
      rcases List.mem_cons.1 hx with hx | hx
      · subst hx; exact hi
      · exact ih h x hx

theorem key_not_mem_of_lookup_none {rs : List (Nat × α)} {id : Nat} (h : lookup rs id = none) :
    id ∉ rs.map (·.1) := by
  intro hm
  obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
  exact not_mem_of_lookup_none h y hy hyi

theorem lookup_some_of_mem {rs : List (Nat × α)} {id : Nat} {r : α}
    (hn : (rs.map (·.1)).Nodup) (h : (id, r) ∈ rs) : lookup rs id = some r := by
  induction rs with
  | nil => simp at h
  | cons y ys ih =>
    obtain ⟨i, r'⟩ := y
    rw [List.map_cons, List.nodup_cons] at hn
    simp only [lookup]
    rcases List.mem_cons.1 h with h | h
    · cases h; simp
    · have hi : i ≠ id := by
        intro e; subst e
        exact hn.1 (List.mem_map.2 ⟨(i, r), h, rfl⟩)
      rw [if_neg hi]
      exact ih hn.2 h

theorem lookup_cons_self {rs : List (Nat × α)} {id : Nat} {r : α} :
    lookup ((id, r) :: rs) id = some r := by simp [lookup]

theorem lookup_cons_ne {rs : List (Nat × α)} {id i : Nat} {r : α} (h : i ≠ id) :
    lookup ((i, r) :: rs) id = lookup rs id := by simp [lookup, h]

theorem mem_remove {rs : List (Nat × α)} {id : Nat} {x : Nat × α}
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

theorem fst_ne_of_mem_remove {rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ remove rs id) : x.1 ≠ id := by
  induction rs with
  | nil => simp [remove] at h
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [remove] at h
    split at h
    · exact ih h
    · rename_i hi
      rcases List.mem_cons.1 h with h | h
      · subst h; exact hi
      · exact ih h

theorem mem_remove_of_mem {rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ rs) (hne : x.1 ≠ id) : x ∈ remove rs id := by
  induction rs with
  | nil => simp at h
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [remove]
    rcases List.mem_cons.1 h with h | h
    · subst h
      rw [if_neg hne]
      exact List.mem_cons.2 (Or.inl rfl)
    · split
      · exact ih h
      · exact List.mem_cons_of_mem _ (ih h)

theorem nodup_map_remove {rs : List (Nat × α)} {id : Nat}
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

theorem lookup_remove_self {rs : List (Nat × α)} {id : Nat} :
    lookup (remove rs id) id = none :=
  lookup_none_of_not_mem (fun _ hx => fst_ne_of_mem_remove hx)

theorem lookup_remove_ne {rs : List (Nat × α)} {id id' : Nat} (h : id ≠ id') :
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

theorem key_not_mem_map_fst_remove_self {rs : List (Nat × α)} {id : Nat} :
    id ∉ (remove rs id).map (·.1) := by
  intro hm
  obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
  exact fst_ne_of_mem_remove hy hyi

/-- Under unique identifiers, an entry of `rs` with the removed identifier is
the entry `lookup` returns. -/
theorem eq_of_mem_of_fst_eq {rs : List (Nat × α)} {id : Nat} {r : α} {x : Nat × α}
    (hn : (rs.map (·.1)).Nodup) (hl : lookup rs id = some r) (hx : x ∈ rs) (hid : x.1 = id) :
    x = (id, r) := by
  obtain ⟨i, r'⟩ := x
  simp only at hid
  subst hid
  have := lookup_some_of_mem hn hx
  rw [hl] at this
  cases this
  rfl

end Assoc

/-! ## Leaf lemmas -/

theorem setLeaf_map_fst (l : List (AID × Status)) (aid : AID) (v : Status) :
    (setLeaf l aid v).map (·.1) = l.map (·.1) := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨a, s⟩ := x
    simp only [setLeaf]
    split
    · rename_i h; subst h; rfl
    · simp [ih]

theorem lookup_setLeaf_self {l : List (AID × Status)} {aid : AID} {v : Status}
    (hmem : lookup l aid ≠ none) : lookup (setLeaf l aid v) aid = some v := by
  induction l with
  | nil => simp [lookup] at hmem
  | cons x xs ih =>
    obtain ⟨b, t⟩ := x
    simp only [setLeaf]
    split
    · rename_i hb; subst hb; simp [lookup]
    · rename_i hb
      simp only [lookup] at hmem
      rw [if_neg hb] at hmem
      simp only [lookup]
      rw [if_neg hb]
      exact ih hmem

theorem lookup_setLeaf_ne {l : List (AID × Status)} {aid a : AID} {v : Status} (h : a ≠ aid) :
    lookup (setLeaf l aid v) a = lookup l a := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨b, t⟩ := x
    simp only [setLeaf]
    split
    · rename_i hb; subst hb
      simp only [lookup]
      have : b ≠ a := fun e => h e.symm
      rw [if_neg this, if_neg this]
    · simp only [lookup]
      split
      · rfl
      · exact ih

/-! ## Go-request lemmas -/

/-- `goPending` over a request list. -/
def goIn (rs : List (ReqId × Request)) (aid : AID) : Prop :=
  ∃ x, x ∈ rs ∧ x.2.aid = aid ∧ x.2.op.userPostable = false

theorem goPending_iff (s : Sys) (aid : AID) : goPending s aid ↔ goIn s.requests aid := Iff.rfl

/-- Removing a postable request changes no go-pending fact. -/
theorem goIn_remove_postable {rs : List (ReqId × Request)} {id : ReqId} {r : Request}
    (hn : (rs.map (·.1)).Nodup) (hl : lookup rs id = some r) (hp : r.op.userPostable = true)
    (aid : AID) : goIn (remove rs id) aid ↔ goIn rs aid := by
  constructor
  · rintro ⟨x, hx, ha, hg⟩
    exact ⟨x, mem_remove hx, ha, hg⟩
  · rintro ⟨x, hx, ha, hg⟩
    refine ⟨x, mem_remove_of_mem hx ?_, ha, hg⟩
    intro hid
    have := eq_of_mem_of_fst_eq hn hl hx hid
    subst this
    simp only at hg
    rw [hp] at hg
    cases hg

/-- Removing a go-request for `aid'` changes no go-pending fact for another AID. -/
theorem goIn_remove_other {rs : List (ReqId × Request)} {id : ReqId} {r : Request}
    (hn : (rs.map (·.1)).Nodup) (hl : lookup rs id = some r) {aid : AID} (hne : aid ≠ r.aid) :
    goIn (remove rs id) aid ↔ goIn rs aid := by
  constructor
  · rintro ⟨x, hx, ha, hg⟩
    exact ⟨x, mem_remove hx, ha, hg⟩
  · rintro ⟨x, hx, ha, hg⟩
    refine ⟨x, mem_remove_of_mem hx ?_, ha, hg⟩
    intro hid
    have := eq_of_mem_of_fst_eq hn hl hx hid
    subst this
    exact hne ha.symm

theorem goIn_cons_postable {rs : List (ReqId × Request)} {id : ReqId} {r : Request}
    (hp : r.op.userPostable = true) (aid : AID) : goIn ((id, r) :: rs) aid ↔ goIn rs aid := by
  constructor
  · rintro ⟨x, hx, ha, hg⟩
    rcases List.mem_cons.1 hx with hx | hx
    · subst hx; simp only at hg; rw [hp] at hg; cases hg
    · exact ⟨x, hx, ha, hg⟩
  · rintro ⟨x, hx, ha, hg⟩
    exact ⟨x, List.mem_cons_of_mem _ hx, ha, hg⟩

theorem goOp_not_postable (c : Ckpt) : (goOp c).userPostable = false := by
  unfold goOp; cases c.st <;> rfl

theorem goIn_cons_go {rs : List (ReqId × Request)} {id : ReqId} {r : Request}
    (hg : r.op.userPostable = false) (aid : AID) :
    goIn ((id, r) :: rs) aid ↔ (aid = r.aid ∨ goIn rs aid) := by
  constructor
  · rintro ⟨x, hx, ha, hx2⟩
    rcases List.mem_cons.1 hx with hx | hx
    · subst hx; exact Or.inl ha.symm
    · exact Or.inr ⟨x, hx, ha, hx2⟩
  · rintro (h | ⟨x, hx, ha, hx2⟩)
    · exact ⟨(id, r), List.mem_cons.2 (Or.inl rfl), h.symm, hg⟩
    · exact ⟨x, List.mem_cons_of_mem _ hx, ha, hx2⟩

/-! ## The batch invariant -/

/-- `Inv` on a fold's accumulator, with the next request identifier fixed. -/
structure AccInv (p : Params) (n : ReqId) (acc : Acc) : Prop where
  ckptActive : ∀ aid c, lookup acc.ckpts aid = some c → ∃ tok, lookup acc.leaves aid = some (.active tok)
  activeCkpt : ∀ aid tok, lookup acc.leaves aid = some (.active tok) →
    (∃ c, lookup acc.ckpts aid = some c ∧ c.token = tok) ∨ goIn acc.requests aid
  goNoCkpt : ∀ aid, goIn acc.requests aid → lookup acc.ckpts aid = none
  goActive : ∀ aid, goIn acc.requests aid → ∃ tok, lookup acc.leaves aid = some (.active tok)
  goUnique : ∀ x y, x ∈ acc.requests → y ∈ acc.requests → x.2.op.userPostable = false →
    y.2.op.userPostable = false → x.2.aid = y.2.aid → x = y
  goFar : ∀ x, x ∈ acc.requests → x.2.op.userPostable = false → x.2.submittedAt = p.far
  ckptNodup : (acc.ckpts.map (·.1)).Nodup
  leafNodup : (acc.leaves.map (·.1)).Nodup
  reqNodup : (acc.requests.map (·.1)).Nodup
  reqBelowNext : ∀ x, x ∈ acc.requests → x.1 < n

/-- Removing a postable request, and changing only the value fields, keeps
the invariant. -/
theorem accInv_remove_postable {p : Params} {n : ReqId} {acc : Acc} (hi : AccInv p n acc)
    {id : ReqId} {r : Request} (hl : lookup acc.requests id = some r) (hp : r.op.userPostable = true)
    (L : List (AID × Value)) (R : List (Addr × Value)) :
    AccInv p n { acc with requests := remove acc.requests id, locked := L, refunds := R } := by
  have hgo := goIn_remove_postable hi.reqNodup hl hp
  exact {
    ckptActive := hi.ckptActive
    activeCkpt := by
      intro aid tok h
      rcases hi.activeCkpt aid tok h with h | h
      · exact Or.inl h
      · exact Or.inr ((hgo aid).2 h)
    goNoCkpt := fun aid h => hi.goNoCkpt aid ((hgo aid).1 h)
    goActive := fun aid h => hi.goActive aid ((hgo aid).1 h)
    goUnique := fun x y hx hy => hi.goUnique x y (mem_remove hx) (mem_remove hy)
    goFar := fun x hx => hi.goFar x (mem_remove hx)
    ckptNodup := hi.ckptNodup
    leafNodup := hi.leafNodup
    reqNodup := nodup_map_remove hi.reqNodup
    reqBelowNext := fun x hx => hi.reqBelowNext x (mem_remove hx) }

/-- A key without a leaf has no checkpoint: the contrapositive of `ckptActive`. -/
theorem no_ckpt_of_no_leaf {p : Params} {n : ReqId} {acc : Acc} (hi : AccInv p n acc) {aid : AID}
    (h : lookup acc.leaves aid = none) : lookup acc.ckpts aid = none := by
  rcases hc : lookup acc.ckpts aid with _ | c
  · rfl
  · obtain ⟨tok, ht⟩ := hi.ckptActive aid c hc
    rw [h] at ht; cases ht

theorem no_ckpt_of_not_active {p : Params} {n : ReqId} {acc : Acc} (hi : AccInv p n acc) {aid : AID}
    {v : Status} (h : lookup acc.leaves aid = some v) (hv : ∀ tok, v ≠ .active tok) :
    lookup acc.ckpts aid = none := by
  rcases hc : lookup acc.ckpts aid with _ | c
  · rfl
  · obtain ⟨tok, ht⟩ := hi.ckptActive aid c hc
    rw [h] at ht
    cases ht
    exact absurd rfl (hv tok)

/-- Processing a go-request: the leaf leaves `active`, the request leaves the
inbox, and nothing else changes. -/
theorem goInv_after_go {p : Params} {n : ReqId} {acc : Acc} (hi : AccInv p n acc) {id : ReqId}
    {r : Request} (hl : lookup acc.requests id = some r) (hg : r.op.userPostable = false)
    {tok : Token} (hk : lookup acc.leaves r.aid = some (.active tok)) (v : Status)
    (hv : ∀ t, v ≠ .active t) (R : List (Addr × Value)) :
    AccInv p n { acc with requests := remove acc.requests id, leaves := setLeaf acc.leaves r.aid v,
                          refunds := R } := by
  have hpend : goIn acc.requests r.aid := ⟨(id, r), lookup_some_mem hl, rfl, hg⟩
  have hnock : lookup acc.ckpts r.aid = none := hi.goNoCkpt r.aid hpend
  have hne : lookup acc.leaves r.aid ≠ none := by rw [hk]; exact Option.some_ne_none _
  exact {
    ckptActive := by
      intro a c hc
      have ha : a ≠ r.aid := by intro e; subst e; rw [hnock] at hc; cases hc
      rw [lookup_setLeaf_ne ha]
      exact hi.ckptActive a c hc
    activeCkpt := by
      intro a tok' h
      have ha : a ≠ r.aid := by
        intro e; subst e
        rw [lookup_setLeaf_self hne] at h
        cases h
        exact absurd rfl (hv tok')
      rw [lookup_setLeaf_ne ha] at h
      rcases hi.activeCkpt a tok' h with h | h
      · exact Or.inl h
      · exact Or.inr ((goIn_remove_other hi.reqNodup hl ha).2 h)
    goNoCkpt := by
      intro a h
      obtain ⟨x, hx, hxa, hxg⟩ := h
      exact hi.goNoCkpt a ⟨x, mem_remove hx, hxa, hxg⟩
    goActive := by
      intro a h
      obtain ⟨x, hx, hxa, hxg⟩ := h
      have ha : a ≠ r.aid := by
        intro e; subst e
        have := hi.goUnique x (id, r) (mem_remove hx) (lookup_some_mem hl) hxg hg hxa
        subst this
        exact fst_ne_of_mem_remove hx rfl
      rw [lookup_setLeaf_ne ha]
      exact hi.goActive a ⟨x, mem_remove hx, hxa, hxg⟩
    goUnique := fun x y hx hy => hi.goUnique x y (mem_remove hx) (mem_remove hy)
    goFar := fun x hx => hi.goFar x (mem_remove hx)
    ckptNodup := hi.ckptNodup
    leafNodup := by rw [setLeaf_map_fst]; exact hi.leafNodup
    reqNodup := nodup_map_remove hi.reqNodup
    reqBelowNext := fun x hx => hi.reqBelowNext x (mem_remove hx) }

theorem processOne_inv (p : Params) (env : Env) (now : Slot) {n : ReqId} {acc : Acc}
    (hi : AccInv p n acc) {id : ReqId} {r : Request} (hl : lookup acc.requests id = some r)
    {acc'' : Acc}
    (h : processOne p env now { acc with requests := remove acc.requests id } r = some acc'') :
    AccInv p n acc'' := by
  obtain ⟨aid, owner, t, op⟩ := r
  cases op with
  | register =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i hc
        obtain ⟨_, habs⟩ := hc
        simp only [Option.some.injEq] at h
        subst h
        have base := accInv_remove_postable hi hl rfl acc.locked acc.refunds
        have hgo := goIn_remove_postable hi.reqNodup hl rfl
        have hnock : lookup acc.ckpts aid = none := no_ckpt_of_no_leaf hi habs
        exact {
          ckptActive := by
            intro a c hc
            by_cases ha : a = aid
            · subst ha; exact ⟨acc.nextToken, lookup_cons_self⟩
            · rw [lookup_cons_ne (Ne.symm ha)] at hc ⊢
              exact hi.ckptActive a c hc
          activeCkpt := by
            intro a tok h
            by_cases ha : a = aid
            · subst ha; rw [lookup_cons_self] at h; cases h; exact Or.inl ⟨_, lookup_cons_self, rfl⟩
            · rw [lookup_cons_ne (Ne.symm ha)] at h ⊢
              rcases hi.activeCkpt a tok h with h | h
              · exact Or.inl h
              · exact Or.inr ((hgo a).2 h)
          goNoCkpt := by
            intro a h
            have h' := (hgo a).1 h
            have ha : a ≠ aid := by
              intro e; subst e
              obtain ⟨tok, ht⟩ := hi.goActive a h'
              rw [habs] at ht; cases ht
            rw [lookup_cons_ne (Ne.symm ha)]
            exact hi.goNoCkpt a h'
          goActive := by
            intro a h
            have h' := (hgo a).1 h
            have ha : a ≠ aid := by
              intro e; subst e
              obtain ⟨tok, ht⟩ := hi.goActive a h'
              rw [habs] at ht; cases ht
            rw [lookup_cons_ne (Ne.symm ha)]
            exact hi.goActive a h'
          goUnique := base.goUnique
          goFar := base.goFar
          ckptNodup := List.nodup_cons.2 ⟨key_not_mem_of_lookup_none hnock, hi.ckptNodup⟩
          leafNodup := List.nodup_cons.2 ⟨key_not_mem_of_lookup_none habs, hi.leafNodup⟩
          reqNodup := base.reqNodup
          reqBelowNext := base.reqBelowNext }
      all_goals cases h
    · cases h
  | revive =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i k hk
        split at h
        · rename_i hc
          obtain ⟨_, hnock⟩ := hc
          simp only [Option.some.injEq] at h
          subst h
          have base := accInv_remove_postable hi hl rfl acc.locked acc.refunds
          have hgo := goIn_remove_postable hi.reqNodup hl rfl
          have hne : lookup acc.leaves aid ≠ none := by rw [hk]; exact Option.some_ne_none _
          exact {
            ckptActive := by
              intro a c hc
              by_cases ha : a = aid
              · subst ha; exact ⟨acc.nextToken, lookup_setLeaf_self hne⟩
              · rw [lookup_cons_ne (Ne.symm ha)] at hc
                rw [lookup_setLeaf_ne ha]
                exact hi.ckptActive a c hc
            activeCkpt := by
              intro a tok h
              by_cases ha : a = aid
              · subst ha; rw [lookup_setLeaf_self hne] at h; cases h; exact Or.inl ⟨_, lookup_cons_self, rfl⟩
              · rw [lookup_setLeaf_ne ha] at h
                rw [lookup_cons_ne (Ne.symm ha)]
                rcases hi.activeCkpt a tok h with h | h
                · exact Or.inl h
                · exact Or.inr ((hgo a).2 h)
            goNoCkpt := by
              intro a h
              have h' := (hgo a).1 h
              have ha : a ≠ aid := by
                intro e; subst e
                obtain ⟨tok, ht⟩ := hi.goActive a h'
                rw [hk] at ht; cases ht
              rw [lookup_cons_ne (Ne.symm ha)]
              exact hi.goNoCkpt a h'
            goActive := by
              intro a h
              have h' := (hgo a).1 h
              have ha : a ≠ aid := by
                intro e; subst e
                obtain ⟨tok, ht⟩ := hi.goActive a h'
                rw [hk] at ht; cases ht
              rw [lookup_setLeaf_ne ha]
              exact hi.goActive a h'
            goUnique := base.goUnique
            goFar := base.goFar
            ckptNodup := List.nodup_cons.2 ⟨key_not_mem_of_lookup_none hnock, hi.ckptNodup⟩
            leafNodup := by rw [setLeaf_map_fst]; exact hi.leafNodup
            reqNodup := base.reqNodup
            reqBelowNext := base.reqBelowNext }
        · cases h
      all_goals cases h
    · cases h
  | goDormant k =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i tok hk
        simp only [Option.some.injEq] at h
        subst h
        exact goInv_after_go hi hl rfl hk (.dormant k) (fun _ => Status.noConfusion) _
      all_goals cases h
    · cases h
  | goConvicted =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i tok hk
        simp only [Option.some.injEq] at h
        subst h
        exact goInv_after_go hi hl rfl hk .convicted (fun _ => Status.noConfusion) _
      all_goals cases h
    · cases h
  | convict =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i k hk
        split at h
        · simp only [Option.some.injEq] at h
          subst h
          have base := accInv_remove_postable hi hl rfl acc.locked (acc.refunds ++ [(owner, p.Mr)])
          have hgo := goIn_remove_postable hi.reqNodup hl rfl
          have hnock : lookup acc.ckpts aid = none := no_ckpt_of_not_active hi hk (fun _ => Status.noConfusion)
          have hne : lookup acc.leaves aid ≠ none := by rw [hk]; exact Option.some_ne_none _
          exact {
            ckptActive := by
              intro a c hc
              have ha : a ≠ aid := by
                intro e; subst e; rw [hnock] at hc; cases hc
              rw [lookup_setLeaf_ne ha]
              exact hi.ckptActive a c hc
            activeCkpt := by
              intro a tok h
              have ha : a ≠ aid := by
                intro e; subst e
                rw [lookup_setLeaf_self hne] at h
                cases h
              rw [lookup_setLeaf_ne ha] at h
              rcases hi.activeCkpt a tok h with h | h
              · exact Or.inl h
              · exact Or.inr ((hgo a).2 h)
            goNoCkpt := fun a h => hi.goNoCkpt a ((hgo a).1 h)
            goActive := by
              intro a h
              have h' := (hgo a).1 h
              have ha : a ≠ aid := by
                intro e; subst e
                obtain ⟨tok, ht⟩ := hi.goActive a h'
                rw [hk] at ht; cases ht
              rw [lookup_setLeaf_ne ha]
              exact hi.goActive a h'
            goUnique := base.goUnique
            goFar := base.goFar
            ckptNodup := hi.ckptNodup
            leafNodup := by rw [setLeaf_map_fst]; exact hi.leafNodup
            reqNodup := base.reqNodup
            reqBelowNext := base.reqBelowNext }
        · cases h
      all_goals cases h
    · cases h

theorem rejectOne_inv (p : Params) (now : Slot) {n : ReqId} {acc : Acc} (hi : AccInv p n acc)
    {id : ReqId} {r : Request} (hl : lookup acc.requests id = some r) {acc'' : Acc}
    (h : rejectOne p now { acc with requests := remove acc.requests id } r = some acc'') :
    AccInv p n acc'' := by
  simp only [rejectOne] at h
  split at h
  · rename_i hc
    simp only [Option.some.injEq] at h
    subst h
    exact accInv_remove_postable hi hl hc.2 _ _
  · cases h

theorem applyBatch_inv (p : Params) (env : Env) (now : Slot) {n : ReqId} :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {acc' : Acc},
      AccInv p n acc → applyBatch p env now acc batch = some acc' → AccInv p n acc' := by
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
    rcases hl : lookup acc.requests id with _ | r
    · simp [applyBatch, hl] at h
    · cases fa with
      | process =>
        rcases hres : processOne p env now { acc with requests := remove acc.requests id } r with _ | acc''
        · simp [applyBatch, hl, hres] at h
        · simp only [applyBatch, hl, hres] at h
          exact ih (processOne_inv p env now hi hl hres) h
      | reject =>
        rcases hres : rejectOne p now { acc with requests := remove acc.requests id } r with _ | acc''
        · simp [applyBatch, hl, hres] at h
        · simp only [applyBatch, hl, hres] at h
          exact ih (rejectOne_inv p now hi hl hres) h

/-! ## The invariant is reachable-preserved -/

theorem inv_init (p : Params) (plugin : Script) : Inv p (Sys.init plugin) := by
  exact {
    ckptActive := by intro aid c h; simp [Sys.init, lookup] at h
    activeCkpt := by intro aid tok h; simp [Sys.init, lookup] at h
    goNoCkpt := by intro aid h; obtain ⟨x, hx, _⟩ := h; simp [Sys.init] at hx
    goActive := by intro aid h; obtain ⟨x, hx, _⟩ := h; simp [Sys.init] at hx
    goUnique := by intro x y hx; simp [Sys.init] at hx
    goFar := by intro x hx; simp [Sys.init] at hx
    ckptNodup := List.nodup_nil
    leafNodup := List.nodup_nil
    reqNodup := List.nodup_nil
    reqBelowNext := by intro x hx; simp [Sys.init] at hx }

theorem accInv_of_inv {p : Params} {s : Sys} (hi : Inv p s) :
    AccInv p s.nextReq ⟨s.leaves, s.ckpts, s.requests, s.nextToken, [], []⟩ :=
  { ckptActive := hi.ckptActive, activeCkpt := hi.activeCkpt, goNoCkpt := hi.goNoCkpt,
    goActive := hi.goActive, goUnique := hi.goUnique, goFar := hi.goFar, ckptNodup := hi.ckptNodup,
    leafNodup := hi.leafNodup, reqNodup := hi.reqNodup, reqBelowNext := hi.reqBelowNext }

theorem inv_of_accInv {p : Params} {n : ReqId} {acc : Acc} (hi : AccInv p n acc) (g : Gen) (pl : Script) :
    Inv p { gen := g, plugin := pl, leaves := acc.leaves, ckpts := acc.ckpts, requests := acc.requests,
            nextReq := n, nextToken := acc.nextToken } :=
  { ckptActive := hi.ckptActive, activeCkpt := hi.activeCkpt, goNoCkpt := hi.goNoCkpt,
    goActive := hi.goActive, goUnique := hi.goUnique, goFar := hi.goFar, ckptNodup := hi.ckptNodup,
    leafNodup := hi.leafNodup, reqNodup := hi.reqNodup, reqBelowNext := hi.reqBelowNext }

/-- Replacing the checkpoint of an AID that has one keeps the invariant. -/
theorem inv_replace_ckpt {p : Params} {s : Sys} (hi : Inv p s) {aid : AID} {c c' : Ckpt}
    (hc : lookup s.ckpts aid = some c) (htok : c'.token = c.token) :
    Inv p { s with ckpts := (aid, c') :: remove s.ckpts aid } := by
  exact {
    ckptActive := by
      intro a d hd
      by_cases ha : a = aid
      · subst ha; exact hi.ckptActive a c hc
      · rw [lookup_cons_ne (Ne.symm ha), lookup_remove_ne ha] at hd
        exact hi.ckptActive a d hd
    activeCkpt := by
      intro a tok h
      by_cases ha : a = aid
      · subst ha
        rcases hi.activeCkpt a tok h with ⟨d, hd, hdt⟩ | hg
        · rw [hc] at hd; cases hd
          exact Or.inl ⟨c', lookup_cons_self, by rw [htok, hdt]⟩
        · have := hi.goNoCkpt a hg; rw [hc] at this; cases this
      · rcases hi.activeCkpt a tok h with h | h
        · rw [lookup_cons_ne (Ne.symm ha), lookup_remove_ne ha]; exact Or.inl h
        · exact Or.inr h
    goNoCkpt := by
      intro a h
      have h' := hi.goNoCkpt a h
      have ha : a ≠ aid := by intro e; subst e; rw [hc] at h'; cases h'
      rw [lookup_cons_ne (Ne.symm ha), lookup_remove_ne ha]
      exact h'
    goActive := hi.goActive
    goUnique := hi.goUnique
    goFar := hi.goFar
    ckptNodup := by
      rw [List.map_cons]
      exact List.nodup_cons.2 ⟨key_not_mem_map_fst_remove_self, nodup_map_remove hi.ckptNodup⟩
    leafNodup := hi.leafNodup
    reqNodup := hi.reqNodup
    reqBelowNext := hi.reqBelowNext }

/-- A go-request is never in phase 2 before the end of time. -/
theorem go_not_phase2 {p : Params} {s : Sys} (hi : Inv p s) {now : Slot} (hnow : now < p.far)
    {id : ReqId} {r : Request} (hl : lookup s.requests id = some r) (h2 : inPhase2 p r now) :
    r.op.userPostable = true := by
  cases hp : r.op.userPostable
  · have := hi.goFar (id, r) (lookup_some_mem hl) hp
    simp only at this
    unfold inPhase2 at h2
    rw [this] at h2
    exfalso; omega'
  · rfl

theorem inv_step (p : Params) (env : Env) {a : Action} {now : Slot} (hnow : now < p.far) {s : Sys}
    {f : Flow} {s' : Sys} (hi : Inv p s) (hs : stepFn p env a now s = some (f, s')) : Inv p s' := by
  cases a with
  | contribute aid owner t op =>
    simp only [stepFn] at hs
    split at hs
    · rename_i hp
      simp only [Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨_, rfl⟩ := hs
      have hgo := goIn_cons_postable (rs := s.requests) (id := s.nextReq) (r := ⟨aid, owner, t, op⟩) hp
      exact {
        ckptActive := hi.ckptActive
        activeCkpt := by
          intro a tok h
          rcases hi.activeCkpt a tok h with h | h
          · exact Or.inl h
          · exact Or.inr ((hgo a).2 h)
        goNoCkpt := fun a h => hi.goNoCkpt a ((hgo a).1 h)
        goActive := fun a h => hi.goActive a ((hgo a).1 h)
        goUnique := by
          intro x y hx hy hxg hyg he
          rcases List.mem_cons.1 hx with hx | hx
          · subst hx; simp only at hxg; rw [hp] at hxg; cases hxg
          rcases List.mem_cons.1 hy with hy | hy
          · subst hy; simp only at hyg; rw [hp] at hyg; cases hyg
          exact hi.goUnique x y hx hy hxg hyg he
        goFar := by
          intro x hx hxg
          rcases List.mem_cons.1 hx with hx | hx
          · subst hx; simp only at hxg; rw [hp] at hxg; cases hxg
          · exact hi.goFar x hx hxg
        ckptNodup := hi.ckptNodup
        leafNodup := hi.leafNodup
        reqNodup := by
          rw [List.map_cons]
          refine List.nodup_cons.2 ⟨?_, hi.reqNodup⟩
          intro hm
          obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
          have := hi.reqBelowNext y hy
          simp only at hyi
          omega'
        reqBelowNext := by
          intro x hx
          rcases List.mem_cons.1 hx with hx | hx
          · subst hx; exact Nat.lt_succ_self _
          · exact Nat.lt_succ_of_lt (hi.reqBelowNext x hx) }
    · cases hs
  | retract id =>
    simp only [stepFn] at hs
    split at hs
    · cases hs
    · rename_i r hl
      split at hs
      · rename_i h2
        simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        have hp := go_not_phase2 hi hnow hl h2
        exact inv_of_accInv (accInv_remove_postable (accInv_of_inv hi) hl hp [] []) s.gen s.plugin
      · cases hs
  | fold folder g pl batch =>
    simp only [stepFn] at hs
    split at hs
    · split at hs
      · cases hs
      · rename_i acc hacc
        simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        exact inv_of_accInv (applyBatch_inv p env now (accInv_of_inv hi) hacc) (s.gen + 1) s.plugin
    · cases hs
  | reap reaper aid =>
    simp only [stepFn] at hs
    split at hs
    · cases hs
    · rename_i c hc
      split at hs
      · simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        have hnp := goOp_not_postable c
        have hgo := goIn_cons_go (rs := s.requests) (id := s.nextReq) (r := ⟨aid, reaper, p.far, goOp c⟩) hnp
        have hnogo : ¬ goIn s.requests aid := by
          intro h; have := hi.goNoCkpt aid h; rw [hc] at this; cases this
        exact {
          ckptActive := by
            intro a d hd
            have ha : a ≠ aid := by intro e; subst e; rw [lookup_remove_self] at hd; cases hd
            rw [lookup_remove_ne ha] at hd
            exact hi.ckptActive a d hd
          activeCkpt := by
            intro a tok h
            by_cases ha : a = aid
            · subst ha; exact Or.inr ((hgo a).2 (Or.inl rfl))
            · rcases hi.activeCkpt a tok h with h | h
              · rw [lookup_remove_ne ha]; exact Or.inl h
              · exact Or.inr ((hgo a).2 (Or.inr h))
          goNoCkpt := by
            intro a h
            rcases (hgo a).1 h with h2 | h2
            · subst h2; exact lookup_remove_self
            · have h' := hi.goNoCkpt a h2
              have ha : a ≠ aid := by intro e; subst e; exact hnogo h2
              rw [lookup_remove_ne ha]; exact h'
          goActive := by
            intro a h
            rcases (hgo a).1 h with h | h
            · subst h; exact hi.ckptActive a c hc
            · exact hi.goActive a h
          goUnique := by
            intro x y hx hy hxg hyg he
            rcases List.mem_cons.1 hx with hx | hx <;> rcases List.mem_cons.1 hy with hy | hy
            · subst hx; subst hy; rfl
            · subst hx; exact absurd ⟨y, hy, he.symm, hyg⟩ hnogo
            · subst hy; exact absurd ⟨x, hx, he, hxg⟩ hnogo
            · exact hi.goUnique x y hx hy hxg hyg he
          goFar := by
            intro x hx hxg
            rcases List.mem_cons.1 hx with hx | hx
            · subst hx; rfl
            · exact hi.goFar x hx hxg
          ckptNodup := nodup_map_remove hi.ckptNodup
          leafNodup := hi.leafNodup
          reqNodup := by
            rw [List.map_cons]
            refine List.nodup_cons.2 ⟨?_, hi.reqNodup⟩
            intro hm
            obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
            have := hi.reqBelowNext y hy
            simp only at hyi
            omega'
          reqBelowNext := by
            intro x hx
            rcases List.mem_cons.1 hx with hx | hx
            · subst hx; exact Nat.lt_succ_self _
            · exact Nat.lt_succ_of_lt (hi.reqBelowNext x hx) }
      · cases hs
  | pause aid =>
    simp only [stepFn] at hs
    split at hs
    · rename_i hc
      split at hs
      · simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        exact inv_replace_ckpt hi hc rfl
      · cases hs
    · cases hs
  | resume aid =>
    simp only [stepFn] at hs
    split at hs
    · rename_i hc
      split at hs
      · simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        exact inv_replace_ckpt hi hc rfl
      · cases hs
    · cases hs
  | convictCkpt aid =>
    simp only [stepFn] at hs
    split at hs
    · rename_i hc
      split at hs
      · simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        exact inv_replace_ckpt hi hc rfl
      · cases hs
    · cases hs

/-- Reachability before the end of time. -/
inductive ReachFar (p : Params) (env : Env) : Sys → Prop
  | init (plugin : Script) : ReachFar p env (Sys.init plugin)
  | step {s : Sys} (h : ReachFar p env s) {a : Action} {now : Slot} (hnow : now < p.far) {f : Flow}
      {s' : Sys} (hs : stepFn p env a now s = some (f, s')) : ReachFar p env s'

theorem reach_inv (p : Params) (env : Env) {s : Sys} (h : ReachFar p env s) : Inv p s := by
  induction h with
  | init plugin => exact inv_init p plugin
  | step _ hnow hs ih => exact inv_step p env hnow ih hs

/-! ## Batch lemmas for the named theorems -/

/-- A leaf never leaves the root during a batch, and a convicted leaf stays
convicted. -/
theorem processOne_leaf_mono (p : Params) (env : Env) (now : Slot) {acc : Acc} {r : Request} {acc'' : Acc}
    (h : processOne p env now acc r = some acc'') (aid : AID) :
    (lookup acc.leaves aid ≠ none → lookup acc''.leaves aid ≠ none) ∧
    (lookup acc.leaves aid = some .convicted → lookup acc''.leaves aid = some .convicted) := by
  obtain ⟨a, owner, t, op⟩ := r
  cases op with
  | register =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i hc
        simp only [Option.some.injEq] at h; subst h
        by_cases ha : aid = a
        · subst ha
          refine ⟨fun _ => by simp [lookup], fun hc' => ?_⟩
          rw [hc.2] at hc'; cases hc'
        · simp only [lookup_cons_ne (Ne.symm ha)]; exact ⟨id, id⟩
      · cases h
    · cases h
  | revive =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i k hk
        split at h
        · simp only [Option.some.injEq] at h; subst h
          by_cases ha : aid = a
          · subst ha
            refine ⟨fun _ => ?_, fun hc' => ?_⟩
            · rw [lookup_setLeaf_self (by rw [hk]; exact Option.some_ne_none _)]; exact Option.some_ne_none _
            · rw [hk] at hc'; cases hc'
          · simp only [lookup_setLeaf_ne ha]; exact ⟨id, id⟩
        · cases h
      all_goals cases h
    · cases h
  | goDormant k =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i tok hk
        simp only [Option.some.injEq] at h; subst h
        by_cases ha : aid = a
        · subst ha
          refine ⟨fun _ => ?_, fun hc' => ?_⟩
          · rw [lookup_setLeaf_self (by rw [hk]; exact Option.some_ne_none _)]; exact Option.some_ne_none _
          · rw [hk] at hc'; cases hc'
        · simp only [lookup_setLeaf_ne ha]; exact ⟨id, id⟩
      all_goals cases h
    · cases h
  | goConvicted =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i tok hk
        simp only [Option.some.injEq] at h; subst h
        by_cases ha : aid = a
        · subst ha
          refine ⟨fun _ => ?_, fun hc' => ?_⟩
          · rw [lookup_setLeaf_self (by rw [hk]; exact Option.some_ne_none _)]; exact Option.some_ne_none _
          · rw [hk] at hc'; cases hc'
        · simp only [lookup_setLeaf_ne ha]; exact ⟨id, id⟩
      all_goals cases h
    · cases h
  | convict =>
    simp only [processOne, processBody] at h
    split at h
    · split at h
      · rename_i k hk
        split at h
        · simp only [Option.some.injEq] at h; subst h
          by_cases ha : aid = a
          · subst ha
            have hne : lookup acc.leaves aid ≠ none := by rw [hk]; exact Option.some_ne_none _
            refine ⟨fun _ => ?_, fun _ => ?_⟩
            · rw [lookup_setLeaf_self hne]; exact Option.some_ne_none _
            · rw [lookup_setLeaf_self hne]
          · simp only [lookup_setLeaf_ne ha]; exact ⟨id, id⟩
        · cases h
      all_goals cases h
    · cases h

theorem rejectOne_leaves (p : Params) (now : Slot) {acc : Acc} {r : Request} {acc'' : Acc}
    (h : rejectOne p now acc r = some acc'') : acc''.leaves = acc.leaves := by
  simp only [rejectOne] at h
  split at h
  · simp only [Option.some.injEq] at h; subst h; rfl
  · cases h

theorem applyBatch_leaf_mono (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {acc' : Acc},
      applyBatch p env now acc batch = some acc' → ∀ aid,
      (lookup acc.leaves aid ≠ none → lookup acc'.leaves aid ≠ none) ∧
      (lookup acc.leaves aid = some .convicted → lookup acc'.leaves aid = some .convicted) := by
  intro acc batch
  induction batch generalizing acc with
  | nil =>
    intro acc' h aid
    simp only [applyBatch, Option.some.injEq] at h
    subst h; exact ⟨id, id⟩
  | cons x rest ih =>
    intro acc' h aid
    obtain ⟨id, fa⟩ := x
    rcases hl : lookup acc.requests id with _ | r
    · simp [applyBatch, hl] at h
    · cases fa with
      | process =>
        rcases hres : processOne p env now { acc with requests := remove acc.requests id } r with _ | acc''
        · simp [applyBatch, hl, hres] at h
        · simp only [applyBatch, hl, hres] at h
          have h1 := processOne_leaf_mono p env now hres aid
          have h2 := ih h aid
          exact ⟨fun hn => h2.1 (h1.1 hn), fun hc => h2.2 (h1.2 hc)⟩
      | reject =>
        rcases hres : rejectOne p now { acc with requests := remove acc.requests id } r with _ | acc''
        · simp [applyBatch, hl, hres] at h
        · simp only [applyBatch, hl, hres] at h
          have h2 := ih h aid
          rw [rejectOne_leaves p now hres] at h2
          exact h2

/-- Processing never touches the inbox beyond the request already removed. -/
theorem processOne_requests (p : Params) (env : Env) (now : Slot) {acc : Acc} {r : Request} {acc'' : Acc}
    (h : processOne p env now acc r = some acc'') : acc''.requests = acc.requests := by
  obtain ⟨a, o, t, op⟩ := r
  cases op
  all_goals
    simp only [processOne, processBody] at h
    (repeat' split at h)
    all_goals (cases h <;> rfl)

/-- A registration of an AID that has a leaf is refused by `processOne`. -/
theorem processOne_register_registered (p : Params) (env : Env) (now : Slot) {acc : Acc} {r : Request}
    (hop : r.op = .register) (hleaf : lookup acc.leaves r.aid ≠ none) :
    processOne p env now acc r = none := by
  simp only [processOne, processBody, hop]
  split
  · split
    · rename_i hc; exact absurd hc.2 hleaf
    · rfl
  · rfl

/-- A rejection of a go-request is refused by `rejectOne`. -/
theorem rejectOne_go (p : Params) (now : Slot) {acc : Acc} {r : Request}
    (hg : r.op.userPostable = false) : rejectOne p now acc r = none := by
  simp only [rejectOne]
  split
  · rename_i hc; rw [hg] at hc; cases hc.2
  · rfl

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
    · cases hm2; simp [applyBatch, hl]
    · rcases hl' : lookup acc.requests i with _ | r
      · simp [applyBatch, hl']
      · cases fa' with
        | process =>
          rcases hres : processOne p env now { acc with requests := remove acc.requests i } r with _ | acc''
          · simp [applyBatch, hl', hres]
          · simp only [applyBatch, hl', hres]
            refine ih hm2 ?_
            rw [processOne_requests p env now hres]
            simp only
            exact lookup_none_of_not_mem (fun x hx => not_mem_of_lookup_none hl x (mem_remove hx))
        | reject =>
          rcases hres : rejectOne p now { acc with requests := remove acc.requests i } r with _ | acc''
          · simp [applyBatch, hl', hres]
          · simp only [applyBatch, hl', hres]
            refine ih hm2 ?_
            have hreq : acc''.requests = remove acc.requests i := by
              simp only [rejectOne] at hres
              split at hres
              · simp only [Option.some.injEq] at hres; subst hres; rfl
              · cases hres
            rw [hreq]
            exact lookup_none_of_not_mem (fun x hx => not_mem_of_lookup_none hl x (mem_remove hx))

/-- **The absence proof.** A batch that registers an AID already in the root
is refused, wherever the request sits in the batch. -/
theorem applyBatch_register_registered (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {id : ReqId} {r : Request},
      (id, .process) ∈ batch → lookup acc.requests id = some r → r.op = .register →
      lookup acc.leaves r.aid ≠ none → applyBatch p env now acc batch = none := by
  intro acc batch
  induction batch generalizing acc with
  | nil => intro id r hm; simp at hm
  | cons y rest ih =>
    intro id r hm hl hop hleaf
    obtain ⟨i, fa⟩ := y
    by_cases hi : i = id
    · subst hi
      cases fa with
      | process =>
        have hnone := processOne_register_registered p env now (acc := { acc with requests := remove acc.requests i }) hop hleaf
        simp [applyBatch, hl, hnone]
      | reject =>
        have hm' : (i, FoldAction.process) ∈ rest := by
          rcases List.mem_cons.1 hm with hm | hm
          · cases hm
          · exact hm
        rcases hres : rejectOne p now { acc with requests := remove acc.requests i } r with _ | acc''
        · simp [applyBatch, hl, hres]
        · simp only [applyBatch, hl, hres]
          have hreq : acc''.requests = remove acc.requests i := by
            simp only [rejectOne] at hres
            split at hres
            · simp only [Option.some.injEq] at hres; subst hres; rfl
            · cases hres
          exact applyBatch_unknown p env now hm' (by rw [hreq]; exact lookup_remove_self)
    · have hm' : (id, FoldAction.process) ∈ rest := by
        rcases List.mem_cons.1 hm with hm | hm
        · cases hm; exact absurd rfl hi
        · exact hm
      rcases hl' : lookup acc.requests i with _ | r'
      · simp [applyBatch, hl']
      · cases fa with
        | process =>
          rcases hres : processOne p env now { acc with requests := remove acc.requests i } r' with _ | acc''
          · simp [applyBatch, hl', hres]
          · simp only [applyBatch, hl', hres]
            refine ih hm' ?_ hop ?_
            · rw [processOne_requests p env now hres]
              simp only
              rw [lookup_remove_ne (Ne.symm hi)]; exact hl
            · exact (processOne_leaf_mono p env now hres r.aid).1 hleaf
        | reject =>
          rcases hres : rejectOne p now { acc with requests := remove acc.requests i } r' with _ | acc''
          · simp [applyBatch, hl', hres]
          · simp only [applyBatch, hl', hres]
            have hreq : acc''.requests = remove acc.requests i := by
              simp only [rejectOne] at hres
              split at hres
              · simp only [Option.some.injEq] at hres; subst hres; rfl
              · cases hres
            refine ih hm' ?_ hop ?_
            · rw [hreq, lookup_remove_ne (Ne.symm hi)]; exact hl
            · rw [rejectOne_leaves p now hres]; exact hleaf

/-- **No bricking.** A batch that rejects a go-request is refused, wherever
it sits: the plugin refuses `Rejected` on a receipt-carrying request. -/
theorem applyBatch_reject_go (p : Params) (env : Env) (now : Slot) :
    ∀ {acc : Acc} {batch : List (ReqId × FoldAction)} {id : ReqId} {r : Request},
      (id, .reject) ∈ batch → lookup acc.requests id = some r → r.op.userPostable = false →
      applyBatch p env now acc batch = none := by
  intro acc batch
  induction batch generalizing acc with
  | nil => intro id r hm; simp at hm
  | cons y rest ih =>
    intro id r hm hl hg
    obtain ⟨i, fa⟩ := y
    by_cases hi : i = id
    · subst hi
      cases fa with
      | reject =>
        have hnone := rejectOne_go p now (acc := { acc with requests := remove acc.requests i }) hg
        simp [applyBatch, hl, hnone]
      | process =>
        have hm' : (i, FoldAction.reject) ∈ rest := by
          rcases List.mem_cons.1 hm with hm | hm
          · cases hm
          · exact hm
        rcases hres : processOne p env now { acc with requests := remove acc.requests i } r with _ | acc''
        · simp [applyBatch, hl, hres]
        · simp only [applyBatch, hl, hres]
          exact applyBatch_unknown p env now hm' (by rw [processOne_requests p env now hres]; exact lookup_remove_self)
    · have hm' : (id, FoldAction.reject) ∈ rest := by
        rcases List.mem_cons.1 hm with hm | hm
        · cases hm; exact absurd rfl hi
        · exact hm
      rcases hl' : lookup acc.requests i with _ | r'
      · simp [applyBatch, hl']
      · cases fa with
        | process =>
          rcases hres : processOne p env now { acc with requests := remove acc.requests i } r' with _ | acc''
          · simp [applyBatch, hl', hres]
          · simp only [applyBatch, hl', hres]
            refine ih hm' ?_ hg
            rw [processOne_requests p env now hres]
            simp only
            rw [lookup_remove_ne (Ne.symm hi)]; exact hl
        | reject =>
          rcases hres : rejectOne p now { acc with requests := remove acc.requests i } r' with _ | acc''
          · simp [applyBatch, hl', hres]
          · simp only [applyBatch, hl', hres]
            have hreq : acc''.requests = remove acc.requests i := by
              simp only [rejectOne] at hres
              split at hres
              · simp only [Option.some.injEq] at hres; subst hres; rfl
              · cases hres
            refine ih hm' ?_ hg
            rw [hreq, lookup_remove_ne (Ne.symm hi)]; exact hl

/-! ## R1 — leaf and checkpoint -/

/-- **R1a.** A checkpoint exists only for an AID whose leaf is active. -/
theorem R1_ckpt_implies_active (p : Params) (env : Env) {s : Sys} (h : ReachFar p env s) (aid : AID)
    {c : Ckpt} (hc : lookup s.ckpts aid = some c) : ∃ tok, lookup s.leaves aid = some (.active tok) :=
  (reach_inv p env h).ckptActive aid c hc

/-- **R1b.** An active leaf has its checkpoint, or a go-request is pending. -/
theorem R1_active_ckpt_or_go (p : Params) (env : Env) {s : Sys} (h : ReachFar p env s) (aid : AID)
    {tok : Token} (hl : lookup s.leaves aid = some (.active tok)) :
    (∃ c, lookup s.ckpts aid = some c ∧ c.token = tok) ∨ goPending s aid :=
  (reach_inv p env h).activeCkpt aid tok hl

/-- **R1c.** A dormant or convicted leaf has no checkpoint. -/
theorem R1_not_active_no_ckpt (p : Params) (env : Env) {s : Sys} (h : ReachFar p env s) (aid : AID)
    {v : Status} (hl : lookup s.leaves aid = some v) (hv : ∀ tok, v ≠ .active tok) :
    lookup s.ckpts aid = none :=
  no_ckpt_of_not_active (accInv_of_inv (reach_inv p env h)) hl hv

/-- **R1d.** A registration of an AID that has a leaf — active, dormant or
convicted — is refused wherever it sits in the batch: mint-once, ever. -/
theorem R1_registered_refused (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (batch : List (ReqId × FoldAction)) {id : ReqId} {r : Request}
    (hm : (id, .process) ∈ batch) (hl : lookup s.requests id = some r) (hop : r.op = .register)
    (hleaf : lookup s.leaves r.aid ≠ none) :
    stepFn p env (.fold folder s.gen s.plugin batch) now s = none := by
  simp only [stepFn]
  split
  · rw [applyBatch_register_registered p env now hm hl hop hleaf]
  · rfl

/-! ## R2 — uniqueness -/

theorem R2_one_ckpt_per_aid (p : Params) (env : Env) {s : Sys} (h : ReachFar p env s) :
    (s.ckpts.map (·.1)).Nodup := (reach_inv p env h).ckptNodup

theorem R2_one_leaf_per_aid (p : Params) (env : Env) {s : Sys} (h : ReachFar p env s) :
    (s.leaves.map (·.1)).Nodup := (reach_inv p env h).leafNodup

theorem R2_one_go_per_aid (p : Params) (env : Env) {s : Sys} (h : ReachFar p env s) :
    ∀ x y, x ∈ s.requests → y ∈ s.requests → x.2.op.userPostable = false →
      y.2.op.userPostable = false → x.2.aid = y.2.aid → x = y := (reach_inv p env h).goUnique

/-! ## R3, R4 — permanence -/

/-- **R4a.** A leaf never leaves the root. -/
theorem R4_leaf_permanent (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (aid : AID)
    (hin : lookup s.leaves aid ≠ none) : lookup s'.leaves aid ≠ none := by
  cases a with
  | fold folder g pl batch =>
    simp only [stepFn] at hs
    split at hs
    · split at hs
      · cases hs
      · rename_i acc hacc
        simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨_, rfl⟩ := hs
        exact (applyBatch_leaf_mono p env now hacc aid).1 hin
    · cases hs
  | contribute _ _ _ _ => unstep hs; exact hin
  | retract _ => unstep hs; exact hin
  | reap _ _ => unstep hs; exact hin
  | pause _ => unstep hs; exact hin
  | resume _ => unstep hs; exact hin
  | convictCkpt _ => unstep hs; exact hin

/-- **R3.** A convicted leaf stays convicted. -/
theorem R3_convicted_permanent (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (aid : AID)
    (hc : lookup s.leaves aid = some .convicted) : lookup s'.leaves aid = some .convicted := by
  cases a with
  | fold folder g pl batch =>
    simp only [stepFn] at hs
    split at hs
    · split at hs
      · cases hs
      · rename_i acc hacc
        simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨_, rfl⟩ := hs
        exact (applyBatch_leaf_mono p env now hacc aid).2 hc
    · cases hs
  | contribute _ _ _ _ => unstep hs; exact hc
  | retract _ => unstep hs; exact hc
  | reap _ _ => unstep hs; exact hc
  | pause _ => unstep hs; exact hc
  | resume _ => unstep hs; exact hc
  | convictCkpt _ => unstep hs; exact hc

/-- **R3b.** A convicted AID can never be registered again. -/
theorem R3_convicted_never_registered (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (batch : List (ReqId × FoldAction)) {id : ReqId} {r : Request}
    (hm : (id, .process) ∈ batch) (hl : lookup s.requests id = some r) (hop : r.op = .register)
    (hc : lookup s.leaves r.aid = some .convicted) :
    stepFn p env (.fold folder s.gen s.plugin batch) now s = none :=
  R1_registered_refused p env now s folder batch hm hl hop (by rw [hc]; exact Option.some_ne_none _)

/-! ## R5, R6 — the plugin and the generation -/

theorem R5_plugin_pinned (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s')) : s'.plugin = s.plugin := by
  cases a <;> unstep hs <;> rfl

/-- **R6a.** Every step moves the generation by zero or one. -/
theorem R6_gen_step (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s')) :
    s'.gen = s.gen ∨ s'.gen = s.gen + 1 := by
  cases a <;> unstep hs <;> first | exact Or.inl rfl | exact Or.inr rfl

/-- **R6b.** Nothing but a fold writes the registry: contribute, retract,
reap, pause, resume and a checkpoint conviction leave the generation, the
plugin and every leaf untouched. -/
theorem R6_registry_untouched (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} (hs : stepFn p env a now s = some (f, s'))
    (hnf : ∀ folder g pl batch, a ≠ .fold folder g pl batch) :
    s'.gen = s.gen ∧ s'.plugin = s.plugin ∧ s'.leaves = s.leaves := by
  cases a with
  | fold folder g pl batch => exact absurd rfl (hnf folder g pl batch)
  | contribute _ _ _ _ => unstep hs; exact ⟨rfl, rfl, rfl⟩
  | retract _ => unstep hs; exact ⟨rfl, rfl, rfl⟩
  | reap _ _ => unstep hs; exact ⟨rfl, rfl, rfl⟩
  | pause _ => unstep hs; exact ⟨rfl, rfl, rfl⟩
  | resume _ => unstep hs; exact ⟨rfl, rfl, rfl⟩
  | convictCkpt _ => unstep hs; exact ⟨rfl, rfl, rfl⟩

/-- **R6c.** A fold advances the generation by exactly one. -/
theorem R6_fold_advances (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {folder : Addr} {g : Gen} {pl : Script} {batch : List (ReqId × FoldAction)}
    (hs : stepFn p env (.fold folder g pl batch) now s = some (f, s')) : s'.gen = s.gen + 1 := by
  simp only [stepFn] at hs
  split at hs
  · split at hs
    · cases hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨_, rfl⟩ := hs; rfl
  · cases hs

/-! ## R7, R8 — contention -/

theorem R7_stale_fold_refused (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    {g : Gen} (pl : Script) (batch : List (ReqId × FoldAction)) (hg : g ≠ s.gen) :
    stepFn p env (.fold folder g pl batch) now s = none := by
  simp [stepFn, hg]

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

theorem R8_empty_fold_refused (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) (pl : Script) : stepFn p env (.fold folder g pl []) now s = none := by
  simp [stepFn]

theorem R8_plugin_swap_refused (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) {pl : Script} (batch : List (ReqId × FoldAction)) (hpl : pl ≠ s.plugin) :
    stepFn p env (.fold folder g pl batch) now s = none := by
  simp [stepFn, hpl]

/-! ## R9 — requester exit, and no bricking -/

/-- **R9a.** In phase 2 the owner retracts a posted request and gets bond and
tip back. -/
theorem R9_retract_enabled (p : Params) (env : Env) (now : Slot) (s : Sys) {id : ReqId} {r : Request}
    (hl : lookup s.requests id = some r) (h2 : inPhase2 p r now) :
    stepFn p env (.retract id) now s =
      some ({ refunds := [(r.owner, r.op.bond p + p.tip)] }, { s with requests := remove s.requests id }) := by
  simp [stepFn, hl, h2]

theorem R9_retract_needs_phase2 (p : Params) (env : Env) (now : Slot) (s : Sys) {id : ReqId}
    {r : Request} (hl : lookup s.requests id = some r) (h2 : ¬ inPhase2 p r now) :
    stepFn p env (.retract id) now s = none := by
  simp [stepFn, hl, h2]

/-- **R9b.** A rejectable posted request is rejected by anyone at the
current generation, and its bond goes back to its owner. -/
theorem R9_reject_enabled (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    {id : ReqId} {r : Request} (hl : lookup s.requests id = some r) (h3 : rejectable p r now)
    (hp : r.op.userPostable = true) :
    stepFn p env (.fold folder s.gen s.plugin [(id, .reject)]) now s =
      some ({ refunds := [(r.owner, r.op.bond p)], tips := some (folder, 1 * p.tip) },
            { s with gen := s.gen + 1, requests := remove s.requests id }) := by
  simp [stepFn, applyBatch, rejectOne, hl, h3, hp]

theorem R9_reject_needs_rejectable (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) (pl : Script) {id : ReqId} {r : Request} (hl : lookup s.requests id = some r)
    (h3 : ¬ rejectable p r now) :
    stepFn p env (.fold folder g pl [(id, .reject)]) now s = none := by
  simp only [stepFn]
  split
  · simp [applyBatch, rejectOne, hl, h3]
  · rfl

/-- **R9c. No bricking, part one.** Before the end of time a go-request
cannot be retracted: phase 2 never comes for it. -/
theorem R9_go_never_retracted (p : Params) (env : Env) {now : Slot} (hnow : now < p.far) {s : Sys}
    (h : ReachFar p env s) {id : ReqId} {r : Request} (hl : lookup s.requests id = some r)
    (hg : r.op.userPostable = false) : stepFn p env (.retract id) now s = none := by
  apply R9_retract_needs_phase2 p env now s hl
  intro h2
  have := go_not_phase2 (reach_inv p env h) hnow hl h2
  rw [hg] at this; cases this

/-- **R9d. No bricking, part two.** A fold that rejects a go-request is
refused wherever the request sits in the batch: `k` is never lost. -/
theorem R9_go_never_rejected (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (batch : List (ReqId × FoldAction)) {id : ReqId} {r : Request}
    (hm : (id, .reject) ∈ batch) (hl : lookup s.requests id = some r) (hg : r.op.userPostable = false) :
    stepFn p env (.fold folder s.gen s.plugin batch) now s = none := by
  simp only [stepFn]
  split
  · rw [applyBatch_reject_go p env now hm hl hg]
  · rfl

/-! ## R10 — the phases are exclusive -/

theorem R10_phase1_phase2_exclusive (p : Params) (r : Request) (now : Slot) :
    ¬ (inPhase1 p r now ∧ inPhase2 p r now) := by
  unfold inPhase1 inPhase2; omega'

theorem R10_phase2_reject_exclusive (p : Params) (r : Request) (now : Slot) :
    ¬ (inPhase2 p r now ∧ rejectable p r now) := by
  unfold inPhase2 rejectable; omega'

theorem R10_honest_phase1_reject_exclusive (p : Params) (r : Request) (now : Slot)
    (hhonest : r.submittedAt ≤ now) : ¬ (inPhase1 p r now ∧ rejectable p r now) := by
  unfold inPhase1 rejectable; have := p.hRetract; omega'

/-! ## R11 — value -/

/-- **R11a.** A processed go-request refunds its min-ADA to its owner, the
reaper. -/
theorem R11_go_refunds_reaper (p : Params) (env : Env) (now : Slot) {acc : Acc} {r : Request}
    (hg : r.op.userPostable = false) {acc'' : Acc} (h : processOne p env now acc r = some acc'') :
    acc''.refunds = acc.refunds ++ [(r.owner, p.Mr)] := by
  obtain ⟨a, o, t, op⟩ := r
  cases op
  all_goals
    simp only [Op.userPostable] at hg
    (try cases hg)
  all_goals
    simp only [processOne, processBody] at h
    (repeat' split at h)
    all_goals (cases h <;> rfl)

/-- **R11b.** A reap moves exactly the checkpoint's min-ADA: `Mr + tip` into
the go-request, the rest to the reaper. -/
theorem R11_reap_flow (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {reaper : Addr} {aid : AID} (hs : stepFn p env (.reap reaper aid) now s = some (f, s')) :
    f.premium = some (reaper, p.Mc - p.Mr - p.tip) ∧ f.intoRequest = p.Mr + p.tip ∧
      f.locked = [] ∧ f.refunds = [] ∧ f.tips = none ∧ f.deposited = 0 := by
  simp only [stepFn] at hs
  split at hs
  · cases hs
  · split at hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨rfl, _⟩ := hs
      exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
    · cases hs

/-- **R11c. The good samaritan.** The reap's numbers are exactly
`Samaritan.Reap`'s, so `samaritan_never_loses` applies: a reaper who pays a
fee below `Mc - tip` is never out of pocket, and one who also folds recovers
the whole min-ADA. -/
def samaritan (p : Params) (fReap : Nat) : Samaritan.Reap :=
  { Mc := p.Mc, Mr := p.Mr, tip := p.tip, fReap := fReap, hFund := p.hFund }

theorem R11_reap_is_samaritan (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {reaper : Addr} {aid : AID} (hs : stepFn p env (.reap reaper aid) now s = some (f, s')) (fReap : Nat) :
    f.premium = some (reaper, (Samaritan.reap (samaritan p fReap)).premium) ∧
    f.intoRequest = (Samaritan.reap (samaritan p fReap)).intoRequest := by
  obtain ⟨h1, h2, _⟩ := R11_reap_flow p env hs
  exact ⟨h1, h2⟩

theorem R11_samaritan_never_loses (p : Params) (fReap : Nat) (h : p.tip + fReap ≤ p.Mc) :
    fReap ≤ (Samaritan.reap (samaritan p fReap)).premium + (Samaritan.fold (samaritan p fReap)).toOwner :=
  Samaritan.samaritan_never_loses (samaritan p fReap) h

/-- **R11d.** A request deposits its bond and the tip; a retract returns both. -/
theorem R11_contribute_value (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {aid : AID} {owner : Addr} {t : Slot} {op : Op}
    (hs : stepFn p env (.contribute aid owner t op) now s = some (f, s')) :
    f.deposited = op.bond p + p.tip := by
  unstep hs; rfl

theorem R11_retract_value (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow} {s' : Sys}
    {id : ReqId} (hs : stepFn p env (.retract id) now s = some (f, s')) :
    ∃ r, lookup s.requests id = some r ∧ f.refunds = [(r.owner, r.op.bond p + p.tip)] := by
  simp only [stepFn] at hs
  split at hs
  · cases hs
  · rename_i r hr
    split at hs
    · simp only [Option.some.injEq, Prod.mk.injEq] at hs; obtain ⟨rfl, _⟩ := hs
      exact ⟨r, hr, rfl⟩
    · cases hs

/-- **R11e.** The checkpoint edges move no request value. -/
theorem R11_ckpt_edges_move_no_value (p : Params) (env : Env) {now : Slot} {s : Sys} {f : Flow}
    {s' : Sys} {a : Action} (hs : stepFn p env a now s = some (f, s'))
    (ha : (∃ aid, a = .pause aid) ∨ (∃ aid, a = .resume aid) ∨ ∃ aid, a = .convictCkpt aid) : f = {} := by
  rcases ha with ⟨aid, rfl⟩ | ⟨aid, rfl⟩ | ⟨aid, rfl⟩ <;> unstep hs <;> rfl

/-! ## R12 — a leaf enters and changes only by a fold -/

theorem R12_leaf_enters_only_by_fold (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys}
    {f : Flow} {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (aid : AID)
    (hout : lookup s.leaves aid = none) (hin : lookup s'.leaves aid ≠ none) :
    ∃ folder g pl batch, a = .fold folder g pl batch := by
  cases a with
  | fold folder g pl batch => exact ⟨folder, g, pl, batch, rfl⟩
  | _ =>
    have := (R6_registry_untouched p env hs (by intro _ _ _ _ h; cases h)).2.2
    rw [this] at hin; exact absurd hout hin

theorem R12_leaf_changes_only_by_fold (p : Params) (env : Env) {a : Action} {now : Slot} {s : Sys}
    {f : Flow} {s' : Sys} (hs : stepFn p env a now s = some (f, s')) (aid : AID)
    (hch : lookup s'.leaves aid ≠ lookup s.leaves aid) :
    ∃ folder g pl batch, a = .fold folder g pl batch := by
  cases a with
  | fold folder g pl batch => exact ⟨folder, g, pl, batch, rfl⟩
  | _ =>
    have := (R6_registry_untouched p env hs (by intro _ _ _ _ h; cases h)).2.2
    rw [this] at hch; exact absurd rfl hch

/-! ## R13 — the reap -/

/-- **R13a.** A bonded checkpoint is never reaped. -/
theorem R13_live_never_reaped (p : Params) (env : Env) (now : Slot) (s : Sys) (reaper : Addr) (aid : AID)
    {tok : Token} {k : KeyState} (hc : lookup s.ckpts aid = some ⟨tok, k, .live⟩) :
    stepFn p env (.reap reaper aid) now s = none := by
  simp [stepFn, hc, reapable]

/-- **R13b.** A tombstone is reapable at once, by anyone. -/
theorem R13_tomb_reaped (p : Params) (env : Env) (now : Slot) (s : Sys) (reaper : Addr) (aid : AID)
    {tok : Token} {k : KeyState} (hc : lookup s.ckpts aid = some ⟨tok, k, .tomb⟩) :
    stepFn p env (.reap reaper aid) now s =
      some ({ premium := some (reaper, p.Mc - p.Mr - p.tip), intoRequest := p.Mr + p.tip },
            { s with ckpts := remove s.ckpts aid,
                     requests := (s.nextReq, ⟨aid, reaper, p.far, .goConvicted⟩) :: s.requests,
                     nextReq := s.nextReq + 1 }) := by
  simp [stepFn, hc, reapable, goOp]

/-- **R13c.** A parked checkpoint is reapable by a stranger only after the
grace window. -/
theorem R13_parked_needs_grace (p : Params) (env : Env) (now : Slot) (s : Sys) (reaper : Addr) (aid : AID)
    {tok : Token} {k : KeyState} {since : Slot} (hc : lookup s.ckpts aid = some ⟨tok, k, .parked since⟩)
    (hearly : now < since + p.W) (hq : env.quorum aid = false) :
    stepFn p env (.reap reaper aid) now s = none := by
  have : ¬ reapable p env now aid ⟨tok, k, .parked since⟩ := by
    simp only [reapable, hq, Bool.false_eq_true, or_false]; omega'
  simp [stepFn, hc, this]

/-- **R13d.** After the grace window anyone reaps a parked checkpoint; the
go-request carries the key state a revival must rotate from. -/
theorem R13_parked_after_grace (p : Params) (env : Env) (now : Slot) (s : Sys) (reaper : Addr) (aid : AID)
    {tok : Token} {k : KeyState} {since : Slot} (hc : lookup s.ckpts aid = some ⟨tok, k, .parked since⟩)
    (hlate : since + p.W ≤ now) :
    stepFn p env (.reap reaper aid) now s =
      some ({ premium := some (reaper, p.Mc - p.Mr - p.tip), intoRequest := p.Mr + p.tip },
            { s with ckpts := remove s.ckpts aid,
                     requests := (s.nextReq, ⟨aid, reaper, p.far, .goDormant k⟩) :: s.requests,
                     nextReq := s.nextReq + 1 }) := by
  have : reapable p env now aid ⟨tok, k, .parked since⟩ := by simp only [reapable]; exact Or.inl hlate
  simp [stepFn, hc, this, goOp]

/-- **R13e.** The owner reaps their own parked checkpoint at any time. -/
theorem R13_owner_reaps_early (p : Params) (env : Env) (now : Slot) (s : Sys) (reaper : Addr) (aid : AID)
    {tok : Token} {k : KeyState} {since : Slot} (hc : lookup s.ckpts aid = some ⟨tok, k, .parked since⟩)
    (hq : env.quorum aid = true) :
    stepFn p env (.reap reaper aid) now s =
      some ({ premium := some (reaper, p.Mc - p.Mr - p.tip), intoRequest := p.Mr + p.tip },
            { s with ckpts := remove s.ckpts aid,
                     requests := (s.nextReq, ⟨aid, reaper, p.far, .goDormant k⟩) :: s.requests,
                     nextReq := s.nextReq + 1 }) := by
  have : reapable p env now aid ⟨tok, k, .parked since⟩ := by simp only [reapable]; exact Or.inr hq
  simp [stepFn, hc, this, goOp]

/-! ## R14 — every conviction needs a proof -/

/-- **R14a.** A live or parked checkpoint is convicted only by a duplicity
proof against its key state. -/
theorem R14_convictCkpt_needs_proof (p : Params) (env : Env) (now : Slot) (s : Sys) (aid : AID)
    {tok : Token} {k : KeyState} {st : CkState} (hc : lookup s.ckpts aid = some ⟨tok, k, st⟩)
    (hd : env.duplicity aid k = false) : stepFn p env (.convictCkpt aid) now s = none := by
  simp [stepFn, hc, hd]

/-- **R14b.** A dormant AID is convicted only by a duplicity proof against
its recorded key state: a conviction request without one is refused. -/
theorem R14_convict_dormant_needs_proof (p : Params) (env : Env) (now : Slot) (s : Sys) (folder : Addr)
    (g : Gen) (pl : Script) {id : ReqId} {r : Request} (hl : lookup s.requests id = some r)
    (hop : r.op = .convict) {k : KeyState} (hleaf : lookup s.leaves r.aid = some (.dormant k))
    (hd : env.duplicity r.aid k = false) :
    stepFn p env (.fold folder g pl [(id, .process)]) now s = none := by
  simp only [stepFn]
  split
  · have hnone : processOne p env now ⟨s.leaves, s.ckpts, remove s.requests id, s.nextToken, [], []⟩ r = none := by
      simp only [processOne, processBody, hop]
      split
      · simp only [hleaf]
        rw [hd]
        simp
      · rfl
    simp [applyBatch, hl, hnone]
  · rfl

/-! ## R14c: the proof is required at every position of every batch

`R14_convict_dormant_needs_proof` speaks of a singleton batch from the registry's
own leaves. A batch processes its elements on a running accumulator, so the leaf
a later element sees may have been written by an earlier one (a go-request that
makes the AID dormant, then a conviction of it in the same fold). The theorem
below quantifies over the accumulator, hence over every position of every batch:
`applyBatch` runs `processBody` at each position on the accumulator it reached,
and `R14_convict_at_position` says so of the batch itself. -/

/-- The plugin's body convicts a dormant AID only with a duplicity proof against
the key state the accumulator records — for every accumulator. -/
theorem R14_convict_in_batch_needs_proof (p : Params) (env : Env) {acc acc' : Acc} {r : Request}
    (hop : r.op = .convict) (h : processBody p env acc r = some acc') :
    ∃ k, lookup acc.leaves r.aid = some (.dormant k) ∧ env.duplicity r.aid k = true := by
  simp only [processBody, hop] at h
  split at h
  · rename_i k hk
    refine ⟨k, hk, ?_⟩
    by_cases hd : env.duplicity r.aid k = true
    · exact hd
    · simp [hd] at h
  · cases h

/-- `applyBatch` folds an appended batch prefix first. -/
theorem applyBatch_append (p : Params) (env : Env) (now : Slot) :
    ∀ (l₁ l₂ : List (ReqId × FoldAction)) (acc : Acc),
      applyBatch p env now acc (l₁ ++ l₂) =
        match applyBatch p env now acc l₁ with
        | none => none
        | some a => applyBatch p env now a l₂ := by
  intro l₁
  induction l₁ with
  | nil => intro l₂ acc; simp [applyBatch]
  | cons y rest ih =>
    intro l₂ acc
    obtain ⟨i, fa⟩ := y
    rcases hl : lookup acc.requests i with _ | r
    · simp [applyBatch, hl]
    · cases fa with
      | process =>
        rcases hres : processOne p env now { acc with requests := remove acc.requests i } r with _ | acc''
        · simp [applyBatch, hl, hres]
        · simp only [List.cons_append, applyBatch, hl, hres]; exact ih l₂ acc''
      | reject =>
        rcases hres : rejectOne p now { acc with requests := remove acc.requests i } r with _ | acc''
        · simp [applyBatch, hl, hres]
        · simp only [List.cons_append, applyBatch, hl, hres]; exact ih l₂ acc''

/-- **R14 at any position.** In an applied batch, the processed element at any
position was looked up in, and (if a conviction) proved against, the
accumulator the prefix folded to. -/
theorem R14_convict_at_position (p : Params) (env : Env) (now : Slot) {acc acc' : Acc}
    (pre rest : List (ReqId × FoldAction)) (id : ReqId)
    (h : applyBatch p env now acc (pre ++ (id, .process) :: rest) = some acc') :
    ∃ accᵢ r, applyBatch p env now acc pre = some accᵢ ∧ lookup accᵢ.requests id = some r ∧
      (r.op = .convict →
        ∃ k, lookup accᵢ.leaves r.aid = some (.dormant k) ∧ env.duplicity r.aid k = true) := by
  rw [applyBatch_append] at h
  rcases hpre : applyBatch p env now acc pre with _ | accᵢ
  · simp [hpre] at h
  · simp only [hpre] at h
    rcases hl : lookup accᵢ.requests id with _ | r
    · simp [applyBatch, hl] at h
    · refine ⟨accᵢ, r, by first | rfl | exact hpre, hl, fun hop => ?_⟩
      rcases hres : processOne p env now { accᵢ with requests := remove accᵢ.requests id } r with _ | acc''
      · simp [applyBatch, hl, hres] at h
      · have hb : processBody p env { accᵢ with requests := remove accᵢ.requests id } r = some acc'' := by
          simp only [processOne] at hres
          split at hres
          · exact hres
          · cases hres
        obtain ⟨k, hk, hd⟩ := R14_convict_in_batch_needs_proof p env hop hb
        exact ⟨k, hk, hd⟩

/-! ## S364-INV — Registry transition inversions (DEC-364-STEPFN)

The twelve bidirectional `*_iff` theorems below are the complete public
backward interface over the seven `Action` branches of `stepFn` and the five
`Op` branches of `processBody` (see DEC-364-STEPFN in `CardanoKeri.Registry`).
Each left side is successful evaluation of one live branch to explicit result
arguments; each right side is the exact input bindings, every executable
guard, and every observable result field. Refusal follows by negation:
a branch succeeds exactly when its guards hold. `ReachFar` is unchanged. -/


theorem stepFn_contribute_iff (p : Params) (env : Env) (aid : AID) (owner : Addr)
    (submittedAt now : Slot) (op : Op) (s : Sys) (f : Flow) (s' : Sys) :
    stepFn p env (.contribute aid owner submittedAt op) now s = some (f, s') ↔
      op.userPostable = true ∧
      f = { deposited := op.bond p + p.tip } ∧
      s' = { s with requests := (s.nextReq, ⟨aid, owner, submittedAt, op⟩) :: s.requests,
                    nextReq := s.nextReq + 1 } := by
  constructor
  · intro h
    simp only [stepFn] at h
    by_cases hg : op.userPostable = true
    · rw [if_pos hg] at h
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨hg, rfl, rfl⟩
    · rw [if_neg hg] at h
      cases h
  · rintro ⟨hg, rfl, rfl⟩
    simp [stepFn, hg]

theorem stepFn_fold_iff (p : Params) (env : Env) (folder : Addr) (g : Gen) (plugin : Script)
    (batch : List (ReqId × FoldAction)) (now : Slot) (s : Sys) (f : Flow) (s' : Sys) :
    stepFn p env (.fold folder g plugin batch) now s = some (f, s') ↔
      g = s.gen ∧ plugin = s.plugin ∧ batch ≠ [] ∧
      ∃ acc, applyBatch p env now ⟨s.leaves, s.ckpts, s.requests, s.nextToken, [], []⟩ batch = some acc ∧
        f = { locked := acc.locked, refunds := acc.refunds,
              tips := some (folder, batch.length * p.tip) } ∧
        s' = { s with gen := s.gen + 1, leaves := acc.leaves, ckpts := acc.ckpts,
                      requests := acc.requests, nextToken := acc.nextToken } := by
  constructor
  · intro h
    simp only [stepFn] at h
    by_cases hg : g = s.gen ∧ plugin = s.plugin ∧ batch ≠ []
    · rw [if_pos hg] at h
      obtain ⟨ab, hab⟩ : ∃ ab, (applyBatch p env now ⟨s.leaves, s.ckpts, s.requests, s.nextToken, [], []⟩ batch) = ab := ⟨_, rfl⟩
      rw [hab] at h
      cases ab with
      | none =>
        dsimp only at h
        cases h
      | some acc =>
        dsimp only at h
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨hg.1, hg.2.1, hg.2.2, acc, hab, rfl, rfl⟩
    · rw [if_neg hg] at h
      cases h
  · rintro ⟨rfl, rfl, hne, acc, hab, rfl, rfl⟩
    have hc : s.gen = s.gen ∧ s.plugin = s.plugin ∧ batch ≠ [] := ⟨rfl, rfl, hne⟩
    simp [stepFn, hc, hab]

theorem stepFn_retract_iff (p : Params) (env : Env) (id : ReqId) (now : Slot) (s : Sys)
    (f : Flow) (s' : Sys) :
    stepFn p env (.retract id) now s = some (f, s') ↔
      ∃ r, lookup s.requests id = some r ∧ inPhase2 p r now ∧
        f = { refunds := [(r.owner, r.op.bond p + p.tip)] } ∧
        s' = { s with requests := remove s.requests id } := by
  constructor
  · intro h
    simp only [stepFn] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup s.requests id) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some r =>
      dsimp only at h
      by_cases hg : inPhase2 p r now
      · rw [if_pos hg] at h
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨r, hL, hg, rfl, rfl⟩
      · rw [if_neg hg] at h
        cases h
  · rintro ⟨r, hlookup, hg, rfl, rfl⟩
    simp [stepFn, hlookup, hg]

theorem stepFn_reap_iff (p : Params) (env : Env) (reaper : Addr) (aid : AID) (now : Slot)
    (s : Sys) (f : Flow) (s' : Sys) :
    stepFn p env (.reap reaper aid) now s = some (f, s') ↔
      ∃ c, lookup s.ckpts aid = some c ∧ reapable p env now aid c ∧
        f = { premium := some (reaper, p.Mc - p.Mr - p.tip), intoRequest := p.Mr + p.tip } ∧
        s' = { s with ckpts := remove s.ckpts aid,
                      requests := (s.nextReq, ⟨aid, reaper, p.far, goOp c⟩) :: s.requests,
                      nextReq := s.nextReq + 1 } := by
  constructor
  · intro h
    simp only [stepFn] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup s.ckpts aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some c =>
      dsimp only at h
      by_cases hg : reapable p env now aid c
      · rw [if_pos hg] at h
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨c, hL, hg, rfl, rfl⟩
      · rw [if_neg hg] at h
        cases h
  · rintro ⟨c, hck, hg, rfl, rfl⟩
    simp [stepFn, hck, hg]

theorem stepFn_pause_iff (p : Params) (env : Env) (aid : AID) (now : Slot) (s : Sys)
    (f : Flow) (s' : Sys) :
    stepFn p env (.pause aid) now s = some (f, s') ↔
      ∃ tok k, lookup s.ckpts aid = some ⟨tok, k, .live⟩ ∧
        env.rotationFrom aid k = true ∧ f = {} ∧
        s' = { s with ckpts := (aid, ⟨tok, k + 1, .parked now⟩) :: remove s.ckpts aid } := by
  constructor
  · intro h
    simp only [stepFn] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup s.ckpts aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some c =>
      obtain ⟨tok, k, st⟩ := c
      cases st with
      | live =>
        dsimp only at h
        by_cases hg : env.rotationFrom aid k = true
        · rw [if_pos hg] at h
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨tok, k, hL, hg, rfl, rfl⟩
        · rw [if_neg hg] at h
          cases h
      | parked since =>
        dsimp only at h
        cases h
      | tomb =>
        dsimp only at h
        cases h
  · rintro ⟨tok, k, hck, hg, rfl, rfl⟩
    simp [stepFn, hck, hg]

theorem stepFn_resume_iff (p : Params) (env : Env) (aid : AID) (now : Slot) (s : Sys)
    (f : Flow) (s' : Sys) :
    stepFn p env (.resume aid) now s = some (f, s') ↔
      ∃ tok k since, lookup s.ckpts aid = some ⟨tok, k, .parked since⟩ ∧
        env.rotationFrom aid k = true ∧ f = {} ∧
        s' = { s with ckpts := (aid, ⟨tok, k + 1, .live⟩) :: remove s.ckpts aid } := by
  constructor
  · intro h
    simp only [stepFn] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup s.ckpts aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some c =>
      obtain ⟨tok, k, st⟩ := c
      cases st with
      | live =>
        dsimp only at h
        cases h
      | parked since =>
        dsimp only at h
        by_cases hg : env.rotationFrom aid k = true
        · rw [if_pos hg] at h
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨tok, k, since, hL, hg, rfl, rfl⟩
        · rw [if_neg hg] at h
          cases h
      | tomb =>
        dsimp only at h
        cases h
  · rintro ⟨tok, k, since, hck, hg, rfl, rfl⟩
    simp [stepFn, hck, hg]

theorem stepFn_convictCkpt_iff (p : Params) (env : Env) (aid : AID) (now : Slot) (s : Sys)
    (f : Flow) (s' : Sys) :
    stepFn p env (.convictCkpt aid) now s = some (f, s') ↔
      ∃ tok k st, lookup s.ckpts aid = some ⟨tok, k, st⟩ ∧ st ≠ .tomb ∧
        env.duplicity aid k = true ∧ f = {} ∧
        s' = { s with ckpts := (aid, ⟨tok, k, .tomb⟩) :: remove s.ckpts aid } := by
  constructor
  · intro h
    simp only [stepFn] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup s.ckpts aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some c =>
      obtain ⟨tok, k, st⟩ := c
      dsimp only at h
      by_cases hg : st ≠ .tomb ∧ env.duplicity aid k = true
      · rw [if_pos hg] at h
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨tok, k, st, hL, hg.1, hg.2, rfl, rfl⟩
      · rw [if_neg hg] at h
        cases h
  · rintro ⟨tok, k, st, hck, hne, hd, rfl, rfl⟩
    have hg : st ≠ .tomb ∧ env.duplicity aid k = true := ⟨hne, hd⟩
    simp [stepFn, hck, hg]

theorem processBody_register_iff (p : Params) (env : Env) (acc : Acc) (aid : AID) (owner : Addr)
    (submittedAt : Slot) (acc' : Acc) :
    processBody p env acc ⟨aid, owner, submittedAt, .register⟩ = some acc' ↔
      env.inception aid = true ∧ lookup acc.leaves aid = none ∧
      acc' = { acc with leaves := (aid, .active acc.nextToken) :: acc.leaves,
                        ckpts := (aid, ⟨acc.nextToken, 0, .live⟩) :: acc.ckpts,
                        nextToken := acc.nextToken + 1,
                        locked := acc.locked ++ [(aid, p.D)] } := by
  constructor
  · intro h
    simp only [processBody] at h
    by_cases hg : env.inception aid = true ∧ lookup acc.leaves aid = none
    · rw [if_pos hg] at h
      simp only [Option.some.injEq] at h
      obtain rfl := h
      exact ⟨hg.1, hg.2, rfl⟩
    · rw [if_neg hg] at h
      cases h
  · rintro ⟨hi, hnone, rfl⟩
    have hg : env.inception aid = true ∧ lookup acc.leaves aid = none := ⟨hi, hnone⟩
    simp [processBody, hg]

theorem processBody_revive_iff (p : Params) (env : Env) (acc : Acc) (aid : AID) (owner : Addr)
    (submittedAt : Slot) (acc' : Acc) :
    processBody p env acc ⟨aid, owner, submittedAt, .revive⟩ = some acc' ↔
      ∃ k, lookup acc.leaves aid = some (.dormant k) ∧ env.rotationFrom aid k = true ∧
        lookup acc.ckpts aid = none ∧
        acc' = { acc with leaves := setLeaf acc.leaves aid (.active acc.nextToken),
                          ckpts := (aid, ⟨acc.nextToken, k + 1, .live⟩) :: acc.ckpts,
                          nextToken := acc.nextToken + 1,
                          locked := acc.locked ++ [(aid, p.D)] } := by
  constructor
  · intro h
    simp only [processBody] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup acc.leaves aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some v =>
      cases v with
      | active tok =>
        dsimp only at h
        cases h
      | dormant k =>
        dsimp only at h
        by_cases hg : env.rotationFrom aid k = true ∧ lookup acc.ckpts aid = none
        · rw [if_pos hg] at h
          simp only [Option.some.injEq] at h
          obtain rfl := h
          exact ⟨k, hL, hg.1, hg.2, rfl⟩
        · rw [if_neg hg] at h
          cases h
      | convicted =>
        dsimp only at h
        cases h
  · rintro ⟨k, hleaf, hr, hnone, rfl⟩
    have hg : env.rotationFrom aid k = true ∧ lookup acc.ckpts aid = none := ⟨hr, hnone⟩
    simp [processBody, hleaf, hg]

theorem processBody_goDormant_iff (p : Params) (env : Env) (acc : Acc) (aid : AID) (owner : Addr)
    (submittedAt : Slot) (k : KeyState) (acc' : Acc) :
    processBody p env acc ⟨aid, owner, submittedAt, .goDormant k⟩ = some acc' ↔
      ∃ tok, lookup acc.leaves aid = some (.active tok) ∧
        acc' = { acc with leaves := setLeaf acc.leaves aid (.dormant k),
                          refunds := acc.refunds ++ [(owner, p.Mr)] } := by
  constructor
  · intro h
    simp only [processBody] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup acc.leaves aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some v =>
      cases v with
      | active tok =>
        dsimp only at h
        simp only [Option.some.injEq] at h
        obtain rfl := h
        exact ⟨tok, hL, rfl⟩
      | dormant k' =>
        dsimp only at h
        cases h
      | convicted =>
        dsimp only at h
        cases h
  · rintro ⟨tok, hleaf, rfl⟩
    simp [processBody, hleaf]

theorem processBody_goConvicted_iff (p : Params) (env : Env) (acc : Acc) (aid : AID) (owner : Addr)
    (submittedAt : Slot) (acc' : Acc) :
    processBody p env acc ⟨aid, owner, submittedAt, .goConvicted⟩ = some acc' ↔
      ∃ tok, lookup acc.leaves aid = some (.active tok) ∧
        acc' = { acc with leaves := setLeaf acc.leaves aid .convicted,
                          refunds := acc.refunds ++ [(owner, p.Mr)] } := by
  constructor
  · intro h
    simp only [processBody] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup acc.leaves aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some v =>
      cases v with
      | active tok =>
        dsimp only at h
        simp only [Option.some.injEq] at h
        obtain rfl := h
        exact ⟨tok, hL, rfl⟩
      | dormant k' =>
        dsimp only at h
        cases h
      | convicted =>
        dsimp only at h
        cases h
  · rintro ⟨tok, hleaf, rfl⟩
    simp [processBody, hleaf]

theorem processBody_convict_iff (p : Params) (env : Env) (acc : Acc) (aid : AID) (owner : Addr)
    (submittedAt : Slot) (acc' : Acc) :
    processBody p env acc ⟨aid, owner, submittedAt, .convict⟩ = some acc' ↔
      ∃ k, lookup acc.leaves aid = some (.dormant k) ∧ env.duplicity aid k = true ∧
        acc' = { acc with leaves := setLeaf acc.leaves aid .convicted,
                          refunds := acc.refunds ++ [(owner, p.Mr)] } := by
  constructor
  · intro h
    simp only [processBody] at h
    obtain ⟨x, hL⟩ : ∃ x, (lookup acc.leaves aid) = x := ⟨_, rfl⟩
    rw [hL] at h
    cases x with
    | none =>
      dsimp only at h
      cases h
    | some v =>
      cases v with
      | active tok =>
        dsimp only at h
        cases h
      | dormant k =>
        dsimp only at h
        by_cases hg : env.duplicity aid k = true
        · rw [if_pos hg] at h
          simp only [Option.some.injEq] at h
          obtain rfl := h
          exact ⟨k, hL, hg, rfl⟩
        · rw [if_neg hg] at h
          cases h
      | convicted =>
        dsimp only at h
        cases h
  · rintro ⟨k, hleaf, hd, rfl⟩
    simp [processBody, hleaf, hd]


end CardanoKeri.Registry
