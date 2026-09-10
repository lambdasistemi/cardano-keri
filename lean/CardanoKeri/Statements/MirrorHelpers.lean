import CardanoKeri.Statements.Mirror
import CardanoKeri.Statements.HistoryHelpers
import CardanoKeri.Statements.HistoryGoals

/-!
# Inversion helpers and reachability invariants for the mirror

Proof-side lemmas only.
-/

namespace CardanoKeri.Mirror

open CardanoKeri.History

theorem Sys.ext' {s t : Sys} (h1 : s.ckpt = t.ckpt) (h2 : s.reg = t.reg) : s = t := by
  cases s; cases t; cases h1; cases h2; rfl

theorem Registry.ext' {r t : Registry} (h1 : r.issuer = t.issuer) (h2 : r.rid = t.rid)
    (h3 : r.inception = t.inception) (h4 : r.revoked = t.revoked) : r = t := by
  cases r; cases t; cases h1; cases h2; cases h3; cases h4; rfl

/-! ## Step inversions -/

theorem register_some {p : Params} {env : TelEnv} {s s' : Sys} {aid : AID} {ep : Epoch} {t : Nat}
    {par : Option AID} (h : stepFn p env s (.register aid ep t par) = some s') :
    s.ckpt aid = none ∧ s' = s.setCkpt aid (some (inception aid ep t par none)) := by
  simp only [stepFn] at h
  split at h
  · exact ⟨‹_›, (Option.some.inj h).symm⟩
  · simp at h

theorem history_some {p : Params} {env : TelEnv} {s s' : Sys} {aid : AID} {a : HAction}
    (h : stepFn p env s (.history aid a) = some s') :
    ∃ c c', s.ckpt aid = some c ∧ hstep c a = some c' ∧ s' = s.setCkpt aid (some c') := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i c hc
    cases hh : hstep c a with
    | none => simp [hh] at h
    | some c' =>
      simp [hh] at h
      exact ⟨c, c', hc, hh, h.symm⟩

theorem open_some {p : Params} {env : TelEnv} {s s' : Sys} {issuer : AID} {w : Walk}
    (h : stepFn p env s (.open issuer w) = some s') :
    ∃ c v a, s.reg w.tel.i = none ∧ s.ckpt issuer = some c ∧ w.tel.kind = .vcp ∧
      sealWalk p env c w.tel.i w = some v ∧ anchorOf c w.core v = some a ∧
      s' = s.setReg w.tel.i (some ⟨issuer, w.tel.i, a, fun _ => false⟩) := by
  simp only [stepFn] at h
  split at h
  · rename_i c hr hc
    split at h
    · rename_i hk
      split at h
      · simp at h
      · rename_i v hv
        cases ha : anchorOf c w.core v with
        | none => rw [ha] at h; simp at h
        | some a => rw [ha] at h; simp at h; exact ⟨c, v, a, hr, hc, hk, hv, ha, h.symm⟩
    · simp at h
  · simp at h

theorem reanchor_some {p : Params} {env : TelEnv} {s s' : Sys} {w : Walk}
    (h : stepFn p env s (.reanchor w) = some s') :
    ∃ r c v a, s.reg w.tel.i = some r ∧ s.ckpt r.issuer = some c ∧ w.tel.kind = .vcp ∧
      sealWalk p env c r.rid w = some v ∧ anchorOf c w.core v = some a ∧
      s' = s.setReg r.rid (some { r with inception := a }) := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i r hr
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · rename_i hk
        split at h
        · simp at h
        · rename_i v hv
          cases ha : anchorOf c w.core v with
          | none => rw [ha] at h; simp at h
          | some a => rw [ha] at h; simp at h; exact ⟨r, c, v, a, hr, hc, hk, hv, ha, h.symm⟩
      · simp at h

theorem push_some {p : Params} {env : TelEnv} {s s' : Sys} {w : Walk}
    (h : stepFn p env s (.push w) = some s') :
    ∃ r c, s.reg w.tel.ri = some r ∧ s.ckpt r.issuer = some c ∧ w.tel.kind = .rev ∧
      r.revoked w.tel.i = false ∧ (∃ v, sealWalk p env c r.rid w = some v) ∧
      s' = s.setReg r.rid (some (r.insert w.tel.i)) := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i r hr
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · rename_i hcond
        obtain ⟨hk, hrev, hsome⟩ := hcond
        cases hv : sealWalk p env c r.rid w with
        | none => rw [hv] at hsome; simp at hsome
        | some v => exact ⟨r, c, hr, hc, hk, hrev, ⟨v, hv⟩, (Option.some.inj h).symm⟩
      · simp at h

theorem push_of {p : Params} {env : TelEnv} {s : Sys} {w : Walk} {r : Registry} {c : Checkpoint}
    (hr : s.reg w.tel.ri = some r) (hc : s.ckpt r.issuer = some c) (hk : w.tel.kind = .rev)
    (hrev : r.revoked w.tel.i = false) {v : Verdict} (hv : sealWalk p env c r.rid w = some v) :
    stepFn p env s (.push w) = some (s.setReg r.rid (some (r.insert w.tel.i))) := by
  simp [stepFn, hr, hc, hk, hrev, hv]

theorem open_of {p : Params} {env : TelEnv} {s : Sys} {issuer : AID} {w : Walk} {c : Checkpoint}
    (hr : s.reg w.tel.i = none) (hc : s.ckpt issuer = some c) (hk : w.tel.kind = .vcp)
    {v : Verdict} (hv : sealWalk p env c w.tel.i w = some v) {a : Anchor} (ha : anchorOf c w.core v = some a) :
    stepFn p env s (.open issuer w) = some (s.setReg w.tel.i (some ⟨issuer, w.tel.i, a, fun _ => false⟩)) := by
  simp [stepFn, hr, hc, hk, hv, ha]

/-! ## Reachability -/

theorem reachFrom_snoc {p : Params} {env : TelEnv} {s s' s'' : Sys} {a : Action}
    (h : ReachFrom p env s s') (hs : stepFn p env s' a = some s'') : ReachFrom p env s s'' := by
  induction h with
  | refl s => exact ReachFrom.step hs (ReachFrom.refl _)
  | step hs' _ ih => exact ReachFrom.step hs' (ih hs)

theorem reachFrom_trans {p : Params} {env : TelEnv} {s s' s'' : Sys}
    (h1 : ReachFrom p env s s') (h2 : ReachFrom p env s' s'') : ReachFrom p env s s'' := by
  induction h1 with
  | refl _ => exact h2
  | step hs _ ih => exact ReachFrom.step hs (ih h2)

theorem reach_ind {p : Params} {env : TelEnv} {P : Sys → Prop} (hinit : P Sys.init)
    (hstep : ∀ s s' a, Reach p env s → P s → stepFn p env s a = some s' → P s') :
    ∀ {s}, Reach p env s → P s := by
  have key : ∀ s s'', ReachFrom p env s s'' → Reach p env s → P s → P s'' := by
    intro s s'' h
    induction h with
    | refl _ => exact fun _ hp => hp
    | step hs _ ih => intro hr hp; exact ih (reachFrom_snoc hr hs) (hstep _ _ _ hr hp hs)
  intro s hr; exact key _ _ hr (ReachFrom.refl _) hinit

/-- A registry is stored under its own id; a checkpoint under its own AID. -/
def Ok (s : Sys) : Prop :=
  (∀ rid r, s.reg rid = some r → r.rid = rid) ∧ (∀ a c, s.ckpt a = some c → c.aid = a)

theorem ok_step {p : Params} {env : TelEnv} {s s' : Sys} {a : Action} (hok : Ok s)
    (hs : stepFn p env s a = some s') : Ok s' := by
  obtain ⟨hR, hC⟩ := hok
  cases a with
  | register aid ep t par =>
    obtain ⟨_, rfl⟩ := register_some hs
    refine ⟨hR, fun a c hc => ?_⟩
    simp only [Sys.setCkpt] at hc
    split at hc
    · rename_i hx; cases Option.some.inj hc; exact hx.symm
    · exact hC a c hc
  | history aid ha =>
    obtain ⟨c, c', hc, hh, rfl⟩ := history_some hs
    refine ⟨hR, fun a x hx => ?_⟩
    simp only [Sys.setCkpt] at hx
    split at hx
    · rename_i hxa; cases Option.some.inj hx
      have haid : c'.aid = c.aid := by
        cases ha with
        | advance n t appr => obtain ⟨_, rfl⟩ := advance_some hh; rfl
        | supersede n t appr => obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := supersede_some hh; rfl
      rw [haid, hxa]; exact hC aid c hc
    · exact hC a x hx
  | «open» issuer w =>
    obtain ⟨c, v, a, _, _, _, _, _, rfl⟩ := open_some hs
    refine ⟨fun rid r hr => ?_, hC⟩
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr; exact hx.symm
    · exact hR rid r hr
  | push w =>
    obtain ⟨r₀, c, hr₀, _, _, _, _, rfl⟩ := push_some hs
    refine ⟨fun rid r hr => ?_, hC⟩
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr; exact hx.symm
    · exact hR rid r hr
  | reanchor w =>
    obtain ⟨r₀, c, v, a, hr₀, _, _, _, _, rfl⟩ := reanchor_some hs
    refine ⟨fun rid r hr => ?_, hC⟩
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr; exact hx.symm
    · exact hR rid r hr

theorem reach_ok {p : Params} {env : TelEnv} {s : Sys} (h : Reach p env s) : Ok s :=
  reach_ind (P := Ok) ⟨fun _ _ h => by simp [Sys.init] at h, fun _ _ h => by simp [Sys.init] at h⟩
    (fun _ _ _ _ hok hs => ok_step hok hs) h

/-- A walk whose range proof fails, fails. -/
theorem walkOn_none_of_cover_none {p : Params} {env : Env} {c : Checkpoint} {sl : Seal} {w : WalkCore}
    (hcov : cover c w.e w.kel.sn w.succ = none) : walkOn p env c sl w = none := by
  cases hce : c.hist w.e <;> simp [walkOn, hce, hcov]

theorem sealWalk_setCur (p : Params) (env : TelEnv) (c : Checkpoint) (x : Epoch) (rid : RegistryId)
    (w : Walk) : sealWalk p env { c with cur := x } rid w = sealWalk p env c rid w := rfl

end CardanoKeri.Mirror

namespace CardanoKeri.Mirror

open CardanoKeri.History

theorem wf_hstep {c c' : Checkpoint} (hwf : WF c) {a : HAction} (hs : hstep c a = some c') : WF c' := by
  cases a with
  | advance n t appr =>
    obtain ⟨hlt, rfl⟩ := advance_some hs
    exact WF_advanced hwf hlt t appr
  | supersede n t appr =>
    obtain ⟨par, l, a, hpar, hl, ha, rfl, hb, rfl⟩ := supersede_some hs
    exact WF_superseded hwf hl t appr

/-- Every reachable checkpoint is well-formed. -/
theorem reach_wf {p : Params} {env : TelEnv} {s : Sys} (h : Reach p env s) :
    ∀ a c, s.ckpt a = some c → WF c := by
  refine reach_ind (P := fun s => ∀ a c, s.ckpt a = some c → WF c) (fun _ _ h => by simp [Sys.init] at h)
    (fun s s' a _ hP hs => ?_) h
  cases a with
  | register aid ep t par =>
    obtain ⟨_, rfl⟩ := register_some hs
    intro b c hc; simp only [Sys.setCkpt] at hc; split at hc
    · cases Option.some.inj hc; exact WF_inception _ _ _ _ _
    · exact hP b c hc
  | history aid ha =>
    obtain ⟨c, c', hc, hh, rfl⟩ := history_some hs
    intro b x hx; simp only [Sys.setCkpt] at hx; split at hx
    · cases Option.some.inj hx; exact wf_hstep (hP aid c hc) hh
    · exact hP b x hx
  | «open» issuer w =>
    obtain ⟨c, v, a, _, _, _, _, _, rfl⟩ := open_some hs
    exact hP
  | push w =>
    obtain ⟨r₀, c, hr₀, _, _, _, _, rfl⟩ := push_some hs
    exact hP
  | reanchor w =>
    obtain ⟨r₀, c, v, a, hr₀, _, _, _, _, rfl⟩ := reanchor_some hs
    exact hP

theorem anchorOf_setCur (c : Checkpoint) (x : Epoch) (w : WalkCore) (v : Verdict) :
    anchorOf { c with cur := x } w v = anchorOf c w v := rfl

/-- Extending the reachable prefix of a witness by one step. -/
theorem reachFrom_step_right {p : Params} {env : TelEnv} {s₁ s s' : Sys} {a : Action}
    (h : ReachFrom p env s₁ s) (hs : stepFn p env s a = some s') : ReachFrom p env s₁ s' :=
  reachFrom_snoc h hs

end CardanoKeri.Mirror
