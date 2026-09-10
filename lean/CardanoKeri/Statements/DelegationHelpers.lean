import CardanoKeri.Statements.Delegation
import CardanoKeri.Statements.HistoryHelpers
import CardanoKeri.Statements.HistoryGoals

/-!
# Inversion helpers and reachability invariants for delegation

Proof-side lemmas only.
-/

namespace CardanoKeri.Delegation

open CardanoKeri.History

/-! ## Step inversions -/

theorem mint_some {p : Params} {env : DEnv} {s s' : Sys} {parent child : AID} {ev : ChildEvent} {w : WalkCore}
    (h : stepFn p env s (.mint parent child ev w) = some s') :
    ∃ pc v a, s.ckpt parent = some pc ∧ walkOn p env.toEnv pc (approvalSeal env child ev) w = some v ∧
      (∀ c ∈ s.certs, c.named parent child ev.sn (env.eventDigest ev) = false) ∧
      anchorOf pc w v = some a ∧
      s' = { s with certs := ⟨parent, child, ev.sn, env.eventDigest ev,
                               ⟨w.kel.sn, w.kel.establishment, w.idx⟩, a⟩ :: s.certs } := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i pc hpc
    split at h
    · simp at h
    · rename_i v hv
      split at h
      · simp at h
      · rename_i hany
        cases ha : anchorOf pc w v with
        | none => rw [ha] at h; simp at h
        | some a =>
          rw [ha] at h; simp at h
          refine ⟨pc, v, a, hpc, hv, ?_, (by first | rfl | exact ha), h.symm⟩
          intro c hc
          have := List.any_eq_false.mp (Bool.not_eq_true _ |>.mp hany) c hc
          simpa using this

theorem mint_of {p : Params} {env : DEnv} {s : Sys} {parent child : AID} {ev : ChildEvent} {w : WalkCore}
    {pc : Checkpoint} (hpc : s.ckpt parent = some pc) {v : Verdict}
    (hv : walkOn p env.toEnv pc (approvalSeal env child ev) w = some v)
    (hfresh : ∀ c ∈ s.certs, c.named parent child ev.sn (env.eventDigest ev) = false) {a : Anchor}
    (ha : anchorOf pc w v = some a) :
    stepFn p env s (.mint parent child ev w) =
      some { s with certs := ⟨parent, child, ev.sn, env.eventDigest ev,
                              ⟨w.kel.sn, w.kel.establishment, w.idx⟩, a⟩ :: s.certs } := by
  have hany : s.certs.any (fun c => c.named parent child ev.sn (env.eventDigest ev)) = false :=
    List.any_eq_false.mpr fun c hc => by simp [hfresh c hc]
  simp [stepFn, hpc, hv, hany, ha]

theorem takeCert_some {s s' : Sys} {parent child : AID} {sn : Seq} {said : Digest} {cert : Cert}
    (h : s.takeCert parent child sn said = some (cert, s')) :
    s.certs.find? (fun c => c.named parent child sn said) = some cert ∧
      s' = { s with certs := s.certs.eraseP (fun c => c.named parent child sn said) } := by
  simp only [Sys.takeCert] at h
  split at h
  · simp at h
  · rename_i c hc
    simp at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨hc, rfl⟩

theorem takeCert_of {s : Sys} {parent child : AID} {sn : Seq} {said : Digest} {cert : Cert}
    (h : s.certs.find? (fun c => c.named parent child sn said) = some cert) :
    s.takeCert parent child sn said =
      some (cert, { s with certs := s.certs.eraseP (fun c => c.named parent child sn said) }) := by
  simp [Sys.takeCert, h]

theorem registerPlain_some {p : Params} {env : DEnv} {s s' : Sys} {aid : AID} {ep : Epoch} {t : Nat}
    (h : stepFn p env s (.registerPlain aid ep t) = some s') :
    s.ckpt aid = none ∧ (s.known aid = none ∨ s.known aid = some none) ∧
      s'.ckpt = (s.setCkpt aid (some (inception aid ep t none none))).ckpt ∧
      s'.certs = s.certs ∧ (∀ a, a ≠ aid → s'.known a = s.known a) ∧ s'.known aid = some none := by
  simp only [stepFn] at h
  split at h
  · rename_i hc hk
    cases Option.some.inj h
    refine ⟨hc, Or.inl hk, rfl, rfl, fun a ha => by simp [Sys.setKnown, Sys.setCkpt, ha], by simp [Sys.setKnown]⟩
  · rename_i hc hk
    cases Option.some.inj h
    refine ⟨hc, Or.inr hk, rfl, rfl, fun a ha => rfl, ?_⟩
    show s.known aid = some none; exact hk
  · simp at h

theorem registerDelegated_some {p : Params} {env : DEnv} {s s' : Sys} {child parent : AID} {ev : ChildEvent}
    {proof : Option Seq} (h : stepFn p env s (.registerDelegated child parent ev proof) = some s') :
    s.ckpt child = none ∧ ev.sn = 0 ∧ (s.known child = none ∨ s.known child = some (some parent)) ∧
      ∃ cert, s.certs.find? (fun c => c.named parent child 0 (env.eventDigest ev)) = some cert ∧
        s.certStands cert proof = true ∧
        s' = (({ s with certs := s.certs.eraseP (fun c => c.named parent child 0 (env.eventDigest ev)) } : Sys).setCkpt
          child (some (inception child 0 ev.toad (some parent) (some cert.approval)))).setKnown child (some parent) := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i hc
    split at h
    · simp at h
    · rename_i hsn
      split at h
      · simp at h
      · rename_i hk
        split at h
        · simp at h
        · rename_i cert s₁ htake
          split at h
          · simp at h
          · rename_i hst
            obtain ⟨hfind, rfl⟩ := takeCert_some htake
            refine ⟨hc, by simpa using hsn, ?_, cert, hfind, by simpa using hst, (Option.some.inj h).symm⟩
            by_cases h1 : s.known child = none
            · exact Or.inl h1
            · right
              have := not_and.mp hk h1
              simpa using this

theorem advancePlain_some {p : Params} {env : DEnv} {s s' : Sys} {aid : AID} {sn' : Seq} {t : Nat}
    (h : stepFn p env s (.advancePlain aid sn' t) = some s') :
    ∃ c c', s.ckpt aid = some c ∧ c.parent = none ∧ advance c sn' t none = some c' ∧
      s' = s.setCkpt aid (some c') := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i c hc
    split at h
    · simp at h
    · rename_i hpar
      cases ha : advance c sn' t none with
      | none => rw [ha] at h; simp at h
      | some c' =>
        rw [ha] at h; simp at h
        exact ⟨c, c', hc, by simpa using hpar, (by first | rfl | exact ha), h.symm⟩

theorem advanceDelegated_some {p : Params} {env : DEnv} {s s' : Sys} {child : AID} {ev : ChildEvent}
    {proof : Option Seq} (h : stepFn p env s (.advanceDelegated child ev proof) = some s') :
    ∃ c par cert c', s.ckpt child = some c ∧ c.parent = some par ∧
      s.certs.find? (fun x => x.named par child ev.sn (env.eventDigest ev)) = some cert ∧
      s.certStands cert proof = true ∧ advance c ev.sn ev.toad (some cert.approval) = some c' ∧
      s' = ({ s with certs := s.certs.eraseP (fun x => x.named par child ev.sn (env.eventDigest ev)) } : Sys).setCkpt
        child (some c') := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i c hc
    split at h
    · simp at h
    · rename_i par hpar
      split at h
      · simp at h
      · rename_i cert s₁ htake
        split at h
        · simp at h
        · rename_i hst
          obtain ⟨hfind, rfl⟩ := takeCert_some htake
          cases ha : advance c ev.sn ev.toad (some cert.approval) with
          | none => rw [ha] at h; simp at h
          | some c' =>
            rw [ha] at h; simp at h
            exact ⟨c, par, cert, c', hc, hpar, hfind, by simpa using hst, (by first | rfl | exact ha), h.symm⟩

theorem supersedeDelegated_some {p : Params} {env : DEnv} {s s' : Sys} {child : AID} {ev : ChildEvent}
    {proof : Option Seq} (h : stepFn p env s (.supersedeDelegated child ev proof) = some s') :
    ∃ c par cert c', s.ckpt child = some c ∧ c.parent = some par ∧
      s.certs.find? (fun x => x.named par child ev.sn (env.eventDigest ev)) = some cert ∧
      s.certStands cert proof = true ∧ supersede c ev.sn ev.toad cert.approval = some c' ∧
      s' = ({ s with certs := s.certs.eraseP (fun x => x.named par child ev.sn (env.eventDigest ev)) } : Sys).setCkpt
        child (some c') := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i c hc
    split at h
    · simp at h
    · rename_i par hpar
      split at h
      · simp at h
      · rename_i cert s₁ htake
        split at h
        · simp at h
        · rename_i hst
          obtain ⟨hfind, rfl⟩ := takeCert_some htake
          cases ha : supersede c ev.sn ev.toad cert.approval with
          | none => rw [ha] at h; simp at h
          | some c' =>
            rw [ha] at h; simp at h
            exact ⟨c, par, cert, c', hc, hpar, hfind, by simpa using hst, (by first | rfl | exact ha), h.symm⟩

theorem leave_some {p : Params} {env : DEnv} {s s' : Sys} {aid : AID}
    (h : stepFn p env s (.leave aid) = some s') :
    (∃ c, s.ckpt aid = some c) ∧ s' = s.setCkpt aid none := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i c hc; exact ⟨⟨c, hc⟩, (Option.some.inj h).symm⟩

/-! ## Names -/

theorem named_self (c : Cert) : c.named c.parent c.child c.childSn c.childSaid = true := by
  simp [Cert.named]

theorem named_iff (c : Cert) (parent child : AID) (sn : Seq) (said : Digest) :
    c.named parent child sn said = true ↔
      c.parent = parent ∧ c.child = child ∧ c.childSn = sn ∧ c.childSaid = said := by
  simp [Cert.named, and_assoc]

/-- The token name. -/
def Cert.name (c : Cert) : AID × AID × Seq × Digest := (c.parent, c.child, c.childSn, c.childSaid)

theorem named_iff_name (c : Cert) (parent child : AID) (sn : Seq) (said : Digest) :
    c.named parent child sn said = true ↔ c.name = (parent, child, sn, said) := by
  simp [named_iff, Cert.name]

/-- After erasing the found certificate from a list of distinct names, no
certificate of that name remains. -/
theorem eraseP_no_name {l : List Cert} (hnd : (l.map Cert.name).Nodup) {parent child : AID} {sn : Seq}
    {said : Digest} {cert : Cert}
    (hfind : l.find? (fun c => c.named parent child sn said) = some cert) :
    ∀ c ∈ l.eraseP (fun c => c.named parent child sn said), c.named parent child sn said = false := by
  have hmem := List.mem_of_find?_eq_some hfind
  have hp := List.find?_some hfind
  obtain ⟨a, l₁, l₂, hl₁, ha, hl, hel⟩ :=
    List.exists_of_eraseP (p := fun c => c.named parent child sn said) hmem hp
  rw [hel]
  intro c hc
  rw [hl] at hnd
  rw [List.map_append, List.map_cons] at hnd
  obtain ⟨_, hnd₂, hdisj⟩ := List.nodup_append.mp hnd
  obtain ⟨hnotin, _⟩ := List.nodup_cons.mp hnd₂
  have hname_a : a.name = (parent, child, sn, said) := (named_iff_name a parent child sn said).1 ha
  cases hcname : c.named parent child sn said with
  | false => rfl
  | true =>
    exfalso
    have hname_c : c.name = (parent, child, sn, said) := (named_iff_name c parent child sn said).1 hcname
    rw [List.mem_append] at hc
    rcases hc with hc | hc
    · have h1 : c.name ∈ List.map Cert.name l₁ := List.mem_map.mpr ⟨c, hc, rfl⟩
      exact hdisj c.name h1 a.name (List.mem_cons_self ..)
        (hname_c.trans hname_a.symm)
    · exact hnotin (by rw [hname_a, ← hname_c]; exact List.mem_map.mpr ⟨c, hc, rfl⟩)

/-! ## Reachability -/

theorem reachFrom_snoc {p : Params} {env : DEnv} {s s' s'' : Sys} {a : Action}
    (h : ReachFrom p env s s') (hs : stepFn p env s' a = some s'') : ReachFrom p env s s'' := by
  induction h with
  | refl s => exact ReachFrom.step hs (ReachFrom.refl _)
  | step hs' _ ih => exact ReachFrom.step hs' (ih hs)

theorem reach_ind {p : Params} {env : DEnv} {P : Sys → Prop} (hinit : P Sys.init)
    (hstep : ∀ s s' a, Reach p env s → P s → stepFn p env s a = some s' → P s') :
    ∀ {s}, Reach p env s → P s := by
  have key : ∀ s s'', ReachFrom p env s s'' → Reach p env s → P s → P s'' := by
    intro s s'' h
    induction h with
    | refl _ => exact fun _ hp => hp
    | step hs _ ih => intro hr hp; exact ih (reachFrom_snoc hr hs) (hstep _ _ _ hr hp hs)
  intro s hr; exact key _ _ hr (ReachFrom.refl _) hinit

/-- The parent relation as `known` records it. -/
def KnownRel (s : Sys) (a b : AID) : Prop := s.known a = some (some b)

/-- The structural invariants: every present checkpoint agrees with `known`
and is well-formed; an unknown AID has no checkpoint and no certificate
names it as parent; every `known` edge leads to a known AID and the edges
admit a strict ranking; certificate names are distinct. -/
structure Ok (s : Sys) : Prop where
  known_of_ckpt : ∀ a c, s.ckpt a = some c → s.known a = some c.parent
  wf : ∀ a c, s.ckpt a = some c → WF c
  unknown_no_ckpt : ∀ a, s.known a = none → s.ckpt a = none
  unknown_no_cert : ∀ a, s.known a = none → ∀ cert ∈ s.certs, cert.parent ≠ a
  edge_known : ∀ a b, KnownRel s a b → s.known b ≠ none
  ranked : ∃ rank : AID → Nat, ∀ a b, KnownRel s a b → rank b < rank a
  names : (s.certs.map Cert.name).Nodup

theorem ok_init : Ok Sys.init where
  known_of_ckpt := fun _ _ h => by simp [Sys.init] at h
  wf := fun _ _ h => by simp [Sys.init] at h
  unknown_no_ckpt := fun _ _ => rfl
  unknown_no_cert := fun _ _ cert h => by simp [Sys.init] at h
  edge_known := fun _ _ h => by simp [KnownRel, Sys.init] at h
  ranked := ⟨fun _ => 0, fun _ _ h => by simp [KnownRel, Sys.init] at h⟩
  names := by simp [Sys.init]

theorem eraseP_sublist_map {l : List Cert} (hnd : (l.map Cert.name).Nodup) (f : Cert → Bool) :
    ((l.eraseP f).map Cert.name).Nodup :=
  (List.Sublist.map Cert.name List.eraseP_sublist).nodup hnd

theorem ok_step {p : Params} {env : DEnv} {s s' : Sys} (hok : Ok s) {a : Action}
    (hs : stepFn p env s a = some s') : Ok s' := by
  obtain ⟨hkc, hwf, hunk, hunc, hedge, ⟨rank, hrank⟩, hnames⟩ := hok
  cases a with
  | mint parent child ev w =>
    obtain ⟨pc, v, an, hpc, hv, hfresh, ha, rfl⟩ := mint_some hs
    refine ⟨hkc, hwf, hunk, ?_, hedge, ⟨rank, hrank⟩, ?_⟩
    · intro a hka cert hcert
      simp only [List.mem_cons] at hcert
      rcases hcert with rfl | hcert
      · intro hx; simp only at hx; subst hx
        have := hkc _ _ hpc; rw [this] at hka; simp at hka
      · exact hunc a hka cert hcert
    · simp only [List.map_cons, List.nodup_cons]
      refine ⟨?_, hnames⟩
      intro hin
      obtain ⟨c, hc, hname⟩ := List.mem_map.mp hin
      have := hfresh c hc
      rw [(named_iff_name c parent child ev.sn (env.eventDigest ev)).2 hname] at this
      simp at this
  | registerPlain aid ep t =>
    obtain ⟨hc, hk, hckpt, hcerts, hkother, hkaid⟩ := registerPlain_some hs
    have hkn : ∀ a, s'.known a = if a = aid then some none else s.known a := by
      intro a; by_cases ha : a = aid
      · subst ha; simp [hkaid]
      · simp [ha, hkother a ha]
    refine ⟨?_, ?_, ?_, ?_, ?_, ⟨rank, ?_⟩, by rw [hcerts]; exact hnames⟩
    · intro a c hac; rw [hckpt] at hac; simp only [Sys.setCkpt] at hac; rw [hkn]
      split at hac
      · rename_i hx; cases Option.some.inj hac; simp [hx, inception]
      · rename_i hx; simp [hx]; exact hkc a c hac
    · intro a c hac; rw [hckpt] at hac; simp only [Sys.setCkpt] at hac
      split at hac
      · cases Option.some.inj hac; exact WF_inception _ _ _ _ _
      · exact hwf a c hac
    · intro a hka; rw [hkn] at hka; rw [hckpt]; simp only [Sys.setCkpt]
      split at hka
      · simp at hka
      · rename_i hx; simp [hx]; exact hunk a hka
    · intro a hka cert hcert; rw [hkn] at hka; rw [hcerts] at hcert
      split at hka
      · simp at hka
      · exact hunc a hka cert hcert
    · intro a b hab; simp only [KnownRel] at hab; rw [hkn] at hab; rw [hkn]
      split at hab
      · simp at hab
      · rename_i hx; split
        · simp
        · exact hedge a b hab
    · intro a b hab; simp only [KnownRel] at hab; rw [hkn] at hab
      split at hab
      · simp at hab
      · exact hrank a b hab
  | registerDelegated child parent ev proof =>
    obtain ⟨hc, hsn, hk, cert, hfind, hst, rfl⟩ := registerDelegated_some hs
    have hmem := List.mem_of_find?_eq_some hfind
    have hp := List.find?_some hfind
    have hcp : cert.parent = parent := ((named_iff cert _ _ _ _).1 hp).1
    have hparent_known : s.known parent ≠ none := by
      intro hn; exact hunc parent hn cert hmem hcp
    have hpc : parent ≠ child := by
      intro hx; subst hx
      rcases hk with hk | hk
      · exact hparent_known hk
      · exact absurd (hrank _ _ hk) (Nat.lt_irrefl _)
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, eraseP_sublist_map hnames _⟩
    · intro a c hac; simp only [Sys.setKnown, Sys.setCkpt] at hac ⊢
      split at hac
      · cases Option.some.inj hac; rename_i hx; simp [hx, inception]
      · rename_i hx; simp [hx]; exact hkc a c hac
    · intro a c hac; simp only [Sys.setKnown, Sys.setCkpt] at hac
      split at hac
      · cases Option.some.inj hac; exact WF_inception _ _ _ _ _
      · exact hwf a c hac
    · intro a hka; simp only [Sys.setKnown, Sys.setCkpt] at hka ⊢
      split at hka
      · simp at hka
      · rename_i hx; simp [hx]; exact hunk a hka
    · intro a hka c hcert; simp only [Sys.setKnown, Sys.setCkpt] at hka
      split at hka
      · simp at hka
      · have hcert' := List.mem_of_mem_eraseP hcert
        exact hunc a hka c hcert'
    · intro a b hab; simp only [KnownRel, Sys.setKnown, Sys.setCkpt] at hab ⊢
      split at hab
      · rename_i hx; cases Option.some.inj (Option.some.inj hab)
        split
        · simp
        · exact hparent_known
      · rename_i hx; split
        · simp
        · exact hedge a b hab
    · -- ranking: child gets rank parent + 1 when it was unknown; unchanged otherwise
      rcases hk with hk | hk
      · refine ⟨fun a => if a = child then rank parent + 1 else rank a, fun a b hab => ?_⟩
        simp only [KnownRel, Sys.setKnown, Sys.setCkpt] at hab
        have hb : b ≠ child := by
          intro hx; subst hx
          split at hab
          · cases Option.some.inj (Option.some.inj hab); exact hpc rfl
          · exact hedge a b hab hk
        split at hab
        · rename_i hx; cases Option.some.inj (Option.some.inj hab); subst hx
          simp [hb, hpc]
        · rename_i hx; simp only [hx, hb, if_false]; exact hrank a b hab
      · refine ⟨rank, fun a b hab => ?_⟩
        simp only [KnownRel, Sys.setKnown, Sys.setCkpt] at hab
        split at hab
        · rename_i hx; cases Option.some.inj (Option.some.inj hab); subst hx; exact hrank _ _ hk
        · exact hrank a b hab
  | advancePlain aid sn' t =>
    obtain ⟨c, c', hc, hpar, ha, rfl⟩ := advancePlain_some hs
    obtain ⟨hlt, rfl⟩ := advance_some ha
    refine ⟨?_, ?_, ?_, hunc, hedge, ⟨rank, hrank⟩, hnames⟩
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · rename_i hx; cases Option.some.inj hax; subst hx; show s.known _ = some c.parent; exact hkc _ _ hc
      · exact hkc a x hax
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · cases Option.some.inj hax; exact WF_advanced (hwf _ _ hc) hlt _ _
      · exact hwf a x hax
    · intro a hka; simp only [Sys.setCkpt] at hka ⊢
      split
      · rename_i hx; subst hx; have := hkc _ _ hc; rw [this] at hka; simp at hka
      · exact hunk a hka
  | advanceDelegated child ev proof =>
    obtain ⟨c, par, cert, c', hc, hpar, hfind, hst, ha, rfl⟩ := advanceDelegated_some hs
    obtain ⟨hlt, rfl⟩ := advance_some ha
    refine ⟨?_, ?_, ?_, ?_, hedge, ⟨rank, hrank⟩, eraseP_sublist_map hnames _⟩
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · rename_i hx; cases Option.some.inj hax; subst hx; show s.known _ = some c.parent; exact hkc _ _ hc
      · exact hkc a x hax
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · cases Option.some.inj hax; exact WF_advanced (hwf _ _ hc) hlt _ _
      · exact hwf a x hax
    · intro a hka; simp only [Sys.setCkpt] at hka ⊢
      split
      · rename_i hx; subst hx; have := hkc _ _ hc; rw [this] at hka; simp at hka
      · exact hunk a hka
    · intro a hka x hx; exact hunc a hka x (List.mem_of_mem_eraseP hx)
  | supersedeDelegated child ev proof =>
    obtain ⟨c, par, cert, c', hc, hpar, hfind, hst, ha, rfl⟩ := supersedeDelegated_some hs
    obtain ⟨_, l, _, _, hl, _, hsn, _, rfl⟩ := supersede_some ha
    refine ⟨?_, ?_, ?_, ?_, hedge, ⟨rank, hrank⟩, eraseP_sublist_map hnames _⟩
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · rename_i hx; cases Option.some.inj hax; subst hx; show s.known _ = some c.parent; exact hkc _ _ hc
      · exact hkc a x hax
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · cases Option.some.inj hax
        have := WF_superseded (hwf _ _ hc) hl ev.toad cert.approval
        rw [← hsn] at this; exact this
      · exact hwf a x hax
    · intro a hka; simp only [Sys.setCkpt] at hka ⊢
      split
      · rename_i hx; subst hx; have := hkc _ _ hc; rw [this] at hka; simp at hka
      · exact hunk a hka
    · intro a hka x hx; exact hunc a hka x (List.mem_of_mem_eraseP hx)
  | leave aid =>
    obtain ⟨_, rfl⟩ := leave_some hs
    refine ⟨?_, ?_, ?_, hunc, hedge, ⟨rank, hrank⟩, hnames⟩
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · simp at hax
      · exact hkc a x hax
    · intro a x hax; simp only [Sys.setCkpt] at hax
      split at hax
      · simp at hax
      · exact hwf a x hax
    · intro a hka; simp only [Sys.setCkpt]
      split
      · rfl
      · exact hunk a hka

theorem reach_ok {p : Params} {env : DEnv} {s : Sys} (h : Reach p env s) : Ok s :=
  reach_ind (P := Ok) ok_init (fun _ _ _ _ hok hs => ok_step hok hs) h

/-! ## Ancestry -/

theorem ancestorWithin_rank {s : Sys} (hok : Ok s) {rank : AID → Nat}
    (hrank : ∀ a b, KnownRel s a b → rank b < rank a) :
    ∀ n a r, ancestorWithin s n a r = true → rank r < rank a := by
  intro n
  induction n with
  | zero => intro a r h; simp [ancestorWithin] at h
  | succ n ih =>
    intro a r h
    simp only [ancestorWithin] at h
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i par hpar
        have hedge : KnownRel s a par := by
          simp only [KnownRel]; rw [hok.known_of_ckpt a c hc, hpar]
        have h1 := hrank a par hedge
        simp only [Bool.or_eq_true, beq_iff_eq] at h
        rcases h with rfl | h
        · exact h1
        · exact Nat.lt_trans (ih par r h) h1

theorem ancestorWithin_absent {s : Sys} {par : AID} (hpar : s.ckpt par = none) :
    ∀ n r, ancestorWithin s n par r = false := by
  intro n r
  cases n with
  | zero => rfl
  | succ n => simp [ancestorWithin, hpar]

/-- Every outstanding certificate came from a mint whose walk succeeded. -/
def CertOrigin (p : Params) (env : DEnv) (s : Sys) : Prop :=
  ∀ cert ∈ s.certs, ∃ s₀ s₁ ev w pc v, ReachFrom p env Sys.init s₀ ∧
    stepFn p env s₀ (.mint cert.parent cert.child ev w) = some s₁ ∧ ReachFrom p env s₁ s ∧
    ev.sn = cert.childSn ∧ env.eventDigest ev = cert.childSaid ∧ s₀.ckpt cert.parent = some pc ∧
    walkOn p env.toEnv pc (approvalSeal env cert.child ev) w = some v

theorem certOrigin_step {p : Params} {env : DEnv} {s s' : Sys} (hreach : Reach p env s)
    (hco : CertOrigin p env s) {a : Action} (hs : stepFn p env s a = some s') : CertOrigin p env s' := by
  have ext : ∀ cert ∈ s.certs, ∃ s₀ s₁ ev w pc v, ReachFrom p env Sys.init s₀ ∧
      stepFn p env s₀ (.mint cert.parent cert.child ev w) = some s₁ ∧ ReachFrom p env s₁ s' ∧
      ev.sn = cert.childSn ∧ env.eventDigest ev = cert.childSaid ∧ s₀.ckpt cert.parent = some pc ∧
      walkOn p env.toEnv pc (approvalSeal env cert.child ev) w = some v := by
    intro cert hc
    obtain ⟨s₀, s₁, ev, w, pc, v, h1, h2, h3, h4, h5, h6, h7⟩ := hco cert hc
    exact ⟨s₀, s₁, ev, w, pc, v, h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7⟩
  cases a with
  | mint parent child ev w =>
    obtain ⟨pc, v, an, hpc, hv, hfresh, ha, rfl⟩ := mint_some hs
    intro cert hcert
    simp only [List.mem_cons] at hcert
    rcases hcert with rfl | hcert
    · exact ⟨s, _, ev, w, pc, v, hreach, hs, ReachFrom.refl _, rfl, rfl, hpc, hv⟩
    · exact ext cert hcert
  | registerPlain aid ep t =>
    obtain ⟨_, _, _, hcerts, _, _⟩ := registerPlain_some hs
    intro cert hcert; rw [hcerts] at hcert; exact ext cert hcert
  | registerDelegated child parent ev proof =>
    obtain ⟨_, _, _, cert', _, _, rfl⟩ := registerDelegated_some hs
    intro cert hcert
    exact ext cert (List.mem_of_mem_eraseP hcert)
  | advancePlain aid sn' t =>
    obtain ⟨_, _, _, _, _, rfl⟩ := advancePlain_some hs
    intro cert hcert; exact ext cert hcert
  | advanceDelegated child ev proof =>
    obtain ⟨_, _, _, _, _, _, _, _, _, rfl⟩ := advanceDelegated_some hs
    intro cert hcert; exact ext cert (List.mem_of_mem_eraseP hcert)
  | supersedeDelegated child ev proof =>
    obtain ⟨_, _, _, _, _, _, _, _, _, rfl⟩ := supersedeDelegated_some hs
    intro cert hcert; exact ext cert (List.mem_of_mem_eraseP hcert)
  | leave aid =>
    obtain ⟨_, rfl⟩ := leave_some hs
    intro cert hcert; exact ext cert hcert

theorem reach_certOrigin {p : Params} {env : DEnv} {s : Sys} (h : Reach p env s) : CertOrigin p env s :=
  reach_ind (P := CertOrigin p env) (fun _ hc => by simp [Sys.init] at hc)
    (fun _ _ _ hr hco hs => certOrigin_step hr hco hs) h

end CardanoKeri.Delegation
