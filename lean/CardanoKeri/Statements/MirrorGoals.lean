import CardanoKeri.Statements.Mirror
import CardanoKeri.Statements.MirrorHelpers

/-!
# Mirror statements M1 … M13

Statements frozen in STATEMENTS mode (2026-09-10, repairs 1–3); proved in
PROOFS mode without change. Rulings: #392 and
`docs/design/credential-verification.md` ("The revocation mirror").
Mutants named per theorem; the ledger is `STATEMENTS-ATOMS.md`.

Repair 2: M2, M4 and M9 take a reachability premise. Over arbitrary
systems a registry stored under a key other than its own id makes them
false; reachable systems store every registry under its id.
-/

namespace CardanoKeri.Mirror

open CardanoKeri.History

/-- **M1. Only the issuer revokes.** Every SAID in a reachable registry's
set got there by a push whose `rev` walked against the checkpoint of that
registry's issuer at the time (the issuer's own cryptography is the
permission). Mutant: `push` that skips `sealWalk`. -/
theorem M1_only_the_issuer_revokes (p : Params) (env : TelEnv) {s : Sys} (h : Reach p env s)
    {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) {said : Said}
    (hrev : r.revoked said = true) :
    ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.push w) = some s₁ ∧
      ReachFrom p env s₁ s ∧ w.tel.kind = .rev ∧ w.tel.i = said ∧ w.tel.ri = rid ∧
      s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧ sealWalk p env c rid w = some v := by
  refine reach_ind (p := p) (env := env)
    (P := fun s => ∀ rid r said, s.reg rid = some r → r.revoked said = true →
      ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.push w) = some s₁ ∧
        ReachFrom p env s₁ s ∧ w.tel.kind = .rev ∧ w.tel.i = said ∧ w.tel.ri = rid ∧
        s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧ sealWalk p env c rid w = some v)
    (fun _ _ _ h => by simp [Sys.init] at h) (fun s s' a hreach hP hs => ?_) h rid r said hr hrev
  intro rid r said hr hrev
  have ext : ∀ rid r said, s.reg rid = some r → r.revoked said = true →
      ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.push w) = some s₁ ∧
        ReachFrom p env s₁ s' ∧ w.tel.kind = .rev ∧ w.tel.i = said ∧ w.tel.ri = rid ∧
        s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧ sealWalk p env c rid w = some v := by
    intro rid r said hr hrev
    obtain ⟨s₀, s₁, w, c, v, h1, h2, h3, h4, h5, h6, h7, h8, h9⟩ := hP rid r said hr hrev
    exact ⟨s₀, s₁, w, c, v, h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7, h8, h9⟩
  obtain ⟨hR, hC⟩ := reach_ok hreach
  cases a with
  | register aid ep t par =>
    obtain ⟨_, rfl⟩ := register_some hs
    exact ext rid r said hr hrev
  | history aid ha =>
    obtain ⟨c, c', _, _, rfl⟩ := history_some hs
    exact ext rid r said hr hrev
  | «open» issuer w =>
    obtain ⟨c, v, a, hnone, hc, hk, hv, ha, rfl⟩ := open_some hs
    simp only [Sys.setReg] at hr
    split at hr
    · cases Option.some.inj hr; simp at hrev
    · exact ext rid r said hr hrev
  | push w =>
    obtain ⟨r₀, c, hr₀, hc, hk, hrev₀, ⟨v, hv⟩, rfl⟩ := push_some hs
    have hrid : r₀.rid = w.tel.ri := hR _ _ hr₀
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      by_cases hsaid : said = w.tel.i
      · subst hsaid
        refine ⟨s, _, w, c, v, hreach, hs, ReachFrom.refl _, hk, rfl, by rw [hx, hrid], hc,
          hC _ _ hc, ?_⟩
        rw [hx]; exact hv
      · have hrev' : r₀.revoked said = true := by
          simp only [Registry.insert, hsaid, if_false] at hrev; exact hrev
        have hr' : s.reg rid = some r₀ := by rw [hx, hrid]; exact hr₀
        obtain ⟨s₀, s₁, w', c', v', h1, h2, h3, h4, h5, h6, h7, h8, h9⟩ := hP rid r₀ said hr' hrev'
        exact ⟨s₀, s₁, w', c', v', h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7, h8, h9⟩
    · exact ext rid r said hr hrev
  | reanchor w =>
    obtain ⟨r₀, c, v, a, hr₀, hc, hk, hv, ha, rfl⟩ := reanchor_some hs
    have hrid : r₀.rid = w.tel.i := hR _ _ hr₀
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      have hr' : s.reg rid = some r₀ := by rw [hx, hrid]; exact hr₀
      obtain ⟨s₀, s₁, w', c', v', h1, h2, h3, h4, h5, h6, h7, h8, h9⟩ := hP rid r₀ said hr' hrev
      exact ⟨s₀, s₁, w', c', v', h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7, h8, h9⟩
    · exact ext rid r said hr hrev

/-- **M2. A revocation is permanent, and a registry never closes or changes
hands.** No step removes a SAID from a set, or the registry, or alters its
issuer or id. Over-revocation therefore fails closed. Mutant: an action
that deletes from the set. -/
theorem M2_revocation_is_permanent (p : Params) (env : TelEnv) {s s' : Sys} (h : Reach p env s) {a : Action}
    (hs : stepFn p env s a = some s') {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) :
    ∃ r', s'.reg rid = some r' ∧ r'.issuer = r.issuer ∧ r'.rid = r.rid ∧
      ∀ said, r.revoked said = true → r'.revoked said = true := by
  obtain ⟨hR, hC⟩ := reach_ok h
  cases a with
  | register aid ep t par =>
    obtain ⟨_, rfl⟩ := register_some hs
    exact ⟨r, hr, rfl, rfl, fun _ h => h⟩
  | history aid ha =>
    obtain ⟨c, c', _, _, rfl⟩ := history_some hs
    exact ⟨r, hr, rfl, rfl, fun _ h => h⟩
  | «open» issuer w =>
    obtain ⟨c, v, a, hnone, _, _, _, _, rfl⟩ := open_some hs
    refine ⟨r, ?_, rfl, rfl, fun _ h => h⟩
    simp only [Sys.setReg]
    rw [if_neg]
    · exact hr
    · intro hx; rw [hx] at hr; rw [hnone] at hr; exact absurd hr (by simp)
  | push w =>
    obtain ⟨r₀, c, hr₀, _, _, _, _, rfl⟩ := push_some hs
    have hrid : r₀.rid = w.tel.ri := hR _ _ hr₀
    by_cases hx : rid = r₀.rid
    · have : r = r₀ := by rw [hx, hrid] at hr; rw [hr] at hr₀; exact Option.some.inj hr₀
      subst this
      refine ⟨r.insert w.tel.i, by simp [Sys.setReg, hx], rfl, rfl, fun said hsaid => ?_⟩
      simp only [Registry.insert]
      split <;> simp [hsaid]
    · exact ⟨r, by simp [Sys.setReg, hx]; exact hr, rfl, rfl, fun _ h => h⟩
  | reanchor w =>
    obtain ⟨r₀, c, v, a, hr₀, _, _, _, _, rfl⟩ := reanchor_some hs
    have hrid : r₀.rid = w.tel.i := hR _ _ hr₀
    by_cases hx : rid = r₀.rid
    · have : r = r₀ := by rw [hx, hrid] at hr; rw [hr] at hr₀; exact Option.some.inj hr₀
      subst this
      exact ⟨{ r with inception := a }, by simp [Sys.setReg, hx], rfl, rfl, fun _ h => h⟩
    · exact ⟨r, by simp [Sys.setReg, hx]; exact hr, rfl, rfl, fun _ h => h⟩

/-- **M3. A duplicate push is refused and harmless.** Pushing a SAID already
in the set fails on the insert; nothing else could have changed. Mutant:
`push` that re-inserts and, say, resets the registry. -/
theorem M3_duplicate_push_refused (p : Params) (env : TelEnv) {s : Sys} {w : Walk} {r : Registry}
    (hr : s.reg w.tel.ri = some r) (hin : r.revoked w.tel.i = true) :
    stepFn p env s (.push w) = none := by
  simp only [stepFn, hr]
  split
  · rfl
  · rw [if_neg]
    intro hc
    rw [hin] at hc
    exact absurd hc.2.1 (by simp)

/-- **M4. Pushes commute.** Two pushes of distinct SAIDs enabled from the
same reachable system land in either order on the same system: the set
converges however it is filled, which is why the mirror needs no
completeness guarantee. Mutant: a push that records its position (an
order-dependent accumulator). -/
theorem M4_pushes_commute (p : Params) (env : TelEnv) {s s₁ s₂ : Sys} (h : Reach p env s) {w₁ w₂ : Walk}
    (hne : w₁.tel.i ≠ w₂.tel.i)
    (h₁ : stepFn p env s (.push w₁) = some s₁) (h₂ : stepFn p env s (.push w₂) = some s₂) :
    ∃ s₁₂ s₂₁, stepFn p env s₁ (.push w₂) = some s₁₂ ∧ stepFn p env s₂ (.push w₁) = some s₂₁ ∧
      s₁₂ = s₂₁ := by
  obtain ⟨hR, hC⟩ := reach_ok h
  obtain ⟨r₁, c₁, hr₁, hc₁, hk₁, hrev₁, ⟨v₁, hv₁⟩, rfl⟩ := push_some h₁
  obtain ⟨r₂, c₂, hr₂, hc₂, hk₂, hrev₂, ⟨v₂, hv₂⟩, rfl⟩ := push_some h₂
  have hrid₁ : r₁.rid = w₁.tel.ri := hR _ _ hr₁
  have hrid₂ : r₂.rid = w₂.tel.ri := hR _ _ hr₂
  by_cases hsame : w₁.tel.ri = w₂.tel.ri
  · have hrr : r₁ = r₂ := by rw [hsame] at hr₁; rw [hr₁] at hr₂; exact Option.some.inj hr₂
    subst hrr
    have hcc : c₁ = c₂ := by rw [hc₁] at hc₂; exact Option.some.inj hc₂
    subst hcc
    have hne' : w₂.tel.i ≠ w₁.tel.i := fun hx => hne hx.symm
    refine ⟨_, _, push_of (r := r₁.insert w₁.tel.i) (c := c₁) ?_ hc₁ hk₂ ?_ hv₂,
      push_of (r := r₁.insert w₂.tel.i) (c := c₁) ?_ hc₁ hk₁ ?_ hv₁, ?_⟩
    · simp [Sys.setReg, ← hsame, ← hrid₁]
    · simp only [Registry.insert, hne', if_false]; exact hrev₂
    · simp [Sys.setReg, hsame, ← hrid₂]
    · simp only [Registry.insert, hne, if_false]; exact hrev₁
    · refine Sys.ext' rfl ?_
      funext x
      simp only [Sys.setReg, Registry.insert]
      by_cases hx : x = r₁.rid
      · simp only [hx, if_true]
        congr 1
        refine Registry.ext' rfl rfl rfl ?_
        funext y
        by_cases hy₁ : y = w₁.tel.i <;> by_cases hy₂ : y = w₂.tel.i <;> simp [hy₁, hy₂]
      · simp [hx]
  · refine ⟨_, _, push_of (r := r₂) (c := c₂) ?_ hc₂ hk₂ hrev₂ hv₂,
      push_of (r := r₁) (c := c₁) ?_ hc₁ hk₁ hrev₁ hv₁, ?_⟩
    · simp only [Sys.setReg]; rw [if_neg]; exact hr₂
      rw [hrid₁]; exact fun hx => hsame hx.symm
    · simp only [Sys.setReg]; rw [if_neg]; exact hr₁
      rw [hrid₂]; exact hsame
    · refine Sys.ext' rfl ?_
      funext x
      simp only [Sys.setReg]
      have hrr : r₁.rid ≠ r₂.rid := by rw [hrid₁, hrid₂]; exact hsame
      by_cases hx₁ : x = r₁.rid
      · subst hx₁; simp [hrr]
      · by_cases hx₂ : x = r₂.rid
        · subst hx₂; simp [Ne.symm hrr]
        · simp [hx₁, hx₂]

/-- **M5. A registry is bound to its issuer by the `vcp` seal.** Every
reachable registry was opened by a walk of a `vcp` naming its id, against
the checkpoint of the AID it records as issuer. Mutant: `open` that trusts
the `issuer` argument without the walk. -/
theorem M5_registry_bound_to_issuer (p : Params) (env : TelEnv) {s : Sys} (h : Reach p env s)
    {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) :
    r.rid = rid ∧ ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧
      stepFn p env s₀ (.open r.issuer w) = some s₁ ∧ ReachFrom p env s₁ s ∧
      w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧
      sealWalk p env c rid w = some v := by
  refine ⟨(reach_ok h).1 _ _ hr, ?_⟩
  refine reach_ind (p := p) (env := env)
    (P := fun s => ∀ rid r, s.reg rid = some r →
      ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧
        stepFn p env s₀ (.open r.issuer w) = some s₁ ∧ ReachFrom p env s₁ s ∧
        w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧
        sealWalk p env c rid w = some v)
    (fun _ _ h => by simp [Sys.init] at h) (fun s s' a hreach hP hs => ?_) h rid r hr
  intro rid r hr
  have ext : ∀ rid r, s.reg rid = some r →
      ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧
        stepFn p env s₀ (.open r.issuer w) = some s₁ ∧ ReachFrom p env s₁ s' ∧
        w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧
        sealWalk p env c rid w = some v := by
    intro rid r hr
    obtain ⟨s₀, s₁, w, c, v, h1, h2, h3, h4, h5, h6, h7, h8⟩ := hP rid r hr
    exact ⟨s₀, s₁, w, c, v, h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7, h8⟩
  obtain ⟨hR, hC⟩ := reach_ok hreach
  cases a with
  | register aid ep t par =>
    obtain ⟨_, rfl⟩ := register_some hs
    exact ext rid r hr
  | history aid ha =>
    obtain ⟨c, c', _, _, rfl⟩ := history_some hs
    exact ext rid r hr
  | «open» issuer w =>
    obtain ⟨c, v, a, hnone, hc, hk, hv, ha, rfl⟩ := open_some hs
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      subst hx
      exact ⟨s, _, w, c, v, hreach, hs, ReachFrom.refl _, hk, rfl, hc, hC _ _ hc, hv⟩
    · exact ext rid r hr
  | push w =>
    obtain ⟨r₀, c, hr₀, _, _, _, _, rfl⟩ := push_some hs
    have hrid : r₀.rid = w.tel.ri := hR _ _ hr₀
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      have hr' : s.reg rid = some r₀ := by rw [hx, hrid]; exact hr₀
      obtain ⟨s₀, s₁, w', c', v', h1, h2, h3, h4, h5, h6, h7, h8⟩ := hP rid r₀ hr'
      exact ⟨s₀, s₁, w', c', v', h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7, h8⟩
    · exact ext rid r hr
  | reanchor w =>
    obtain ⟨r₀, c, v, a, hr₀, _, _, _, _, rfl⟩ := reanchor_some hs
    have hrid : r₀.rid = w.tel.i := hR _ _ hr₀
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      have hr' : s.reg rid = some r₀ := by rw [hx, hrid]; exact hr₀
      obtain ⟨s₀, s₁, w', c', v', h1, h2, h3, h4, h5, h6, h7, h8⟩ := hP rid r₀ hr'
      exact ⟨s₀, s₁, w', c', v', h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7, h8⟩
    · exact ext rid r hr

/-- **M6. Push, exactly** (public inversion). A push is enabled iff the
registry exists, its issuer has a checkpoint, the event is a `rev` not
yet in the set, and its seal walks with any verdict — no owner, no current
key, no deadline appears. Mutant: a push guard on the issuer's `cur`. -/
theorem M6_push_iff (p : Params) (env : TelEnv) (s : Sys) (w : Walk) (s' : Sys) :
    stepFn p env s (.push w) = some s' ↔
      ∃ r c, s.reg w.tel.ri = some r ∧ s.ckpt r.issuer = some c ∧ w.tel.kind = .rev ∧
        r.revoked w.tel.i = false ∧ (∃ v, sealWalk p env c r.rid w = some v) ∧
        s' = s.setReg r.rid (some (r.insert w.tel.i)) := by
  constructor
  · intro h
    obtain ⟨r, c, hr, hc, hk, hrev, hv, rfl⟩ := push_some h
    exact ⟨r, c, hr, hc, hk, hrev, hv, rfl⟩
  · rintro ⟨r, c, hr, hc, hk, hrev, ⟨v, hv⟩, rfl⟩
    exact push_of hr hc hk hrev hv

/-- **M7. Open, exactly** (public inversion). A registry opens iff no
registry of that id exists, the issuer has a checkpoint, the event is a
`vcp` whose seal walks, and the new registry records the walk's anchor
with an empty set. Mutant: `open` accepting an `iss` as the inception. -/
theorem M7_open_iff (p : Params) (env : TelEnv) (s : Sys) (issuer : AID) (w : Walk) (s' : Sys) :
    stepFn p env s (.open issuer w) = some s' ↔
      ∃ c v a, s.reg w.tel.i = none ∧ s.ckpt issuer = some c ∧ w.tel.kind = .vcp ∧
        sealWalk p env c w.tel.i w = some v ∧ anchorOf c w.core v = some a ∧
        s' = s.setReg w.tel.i (some ⟨issuer, w.tel.i, a, fun _ => false⟩) := by
  constructor
  · intro h
    obtain ⟨c, v, a, hr, hc, hk, hv, ha, rfl⟩ := open_some h
    exact ⟨c, v, a, hr, hc, hk, hv, ha, rfl⟩
  · rintro ⟨c, v, a, hr, hc, hk, hv, ha, rfl⟩
    exact open_of hr hc hk hv ha

theorem ckpt_setCur_of {s : Sys} {aid : AID} {x : Epoch} {i : AID} {c : Checkpoint} (hc : s.ckpt i = some c) :
    (s.setCur aid x).ckpt i = some (if i = aid then { c with cur := x } else c) := by
  simp only [Sys.setCur]
  split <;> simp [hc]

theorem ckpt_setCur_cases {s : Sys} {aid : AID} {x : Epoch} {i : AID} {c' : Checkpoint}
    (hc' : (s.setCur aid x).ckpt i = some c') :
    ∃ c, s.ckpt i = some c ∧ (c' = c ∨ c' = { c with cur := x }) := by
  simp only [Sys.setCur] at hc'
  split at hc'
  · cases hc : s.ckpt i with
    | none => rw [hc] at hc'; simp at hc'
    | some c => rw [hc] at hc'; simp at hc'; exact ⟨c, rfl, Or.inr hc'.symm⟩
  · exact ⟨c', hc', Or.inl rfl⟩

theorem sealWalk_cases {p : Params} {env : TelEnv} {c c' : Checkpoint} {x : Epoch}
    (hcc : c' = c ∨ c' = { c with cur := x }) (rid : RegistryId) (w : Walk) :
    sealWalk p env c' rid w = sealWalk p env c rid w := by
  rcases hcc with rfl | rfl <;> rfl

theorem anchorOf_cases {c c' : Checkpoint} {x : Epoch} (hcc : c' = c ∨ c' = { c with cur := x })
    (w : WalkCore) (v : Verdict) : anchorOf c' w v = anchorOf c w v := by
  rcases hcc with rfl | rfl <;> rfl

theorem sealWalk_ite {p : Params} {env : TelEnv} (c : Checkpoint) (x : Epoch) (b : Prop) [Decidable b]
    (rid : RegistryId) (w : Walk) :
    sealWalk p env (if b then { c with cur := x } else c) rid w = sealWalk p env c rid w := by
  split <;> rfl

theorem anchorOf_ite (c : Checkpoint) (x : Epoch) (b : Prop) [Decidable b] (w : WalkCore) (v : Verdict) :
    anchorOf (if b then { c with cur := x } else c) w v = anchorOf c w v := by
  split <;> rfl

/-- **M8. The mirror never reads current keys.** Opening, pushing and
re-anchoring are invariant under the issuer's current key state (S3
lifted to the system): "current keys cannot vouch for past events" and
cannot block them either. Mutant: `push` requiring `env.signed c.cur`. -/
theorem M8_mirror_ignores_current_keys (p : Params) (env : TelEnv) (s : Sys) (aid : AID) (x : Epoch)
    (a : Action) (hmirror : (∃ i w, a = .open i w) ∨ (∃ w, a = .push w) ∨ ∃ w, a = .reanchor w) :
    (stepFn p env (s.setCur aid x) a).map (fun t => t.reg) = (stepFn p env s a).map (fun t => t.reg) := by
  rcases hmirror with ⟨i, w, rfl⟩ | ⟨w, rfl⟩ | ⟨w, rfl⟩
  · cases h1 : stepFn p env s (.open i w) with
    | none =>
      cases h2 : stepFn p env (s.setCur aid x) (.open i w) with
      | none => rfl
      | some t =>
        exfalso
        obtain ⟨c', v, a, hr, hc', hk, hv, ha, rfl⟩ := open_some h2
        obtain ⟨c, hc, hcc⟩ := ckpt_setCur_cases hc'
        rw [sealWalk_cases hcc] at hv
        rw [anchorOf_cases hcc] at ha
        rw [open_of (s := s) hr hc hk hv ha] at h1
        exact absurd h1 (by simp)
    | some t =>
      obtain ⟨c, v, a, hr, hc, hk, hv, ha, rfl⟩ := open_some h1
      rw [open_of (s := s.setCur aid x) hr (ckpt_setCur_of (aid := aid) (x := x) hc) hk
        (by rw [sealWalk_ite]; exact hv) (by rw [anchorOf_ite]; exact ha)]
      rfl
  · cases h1 : stepFn p env s (.push w) with
    | none =>
      cases h2 : stepFn p env (s.setCur aid x) (.push w) with
      | none => rfl
      | some t =>
        exfalso
        obtain ⟨r, c', hr, hc', hk, hrev, ⟨v, hv⟩, rfl⟩ := push_some h2
        obtain ⟨c, hc, hcc⟩ := ckpt_setCur_cases hc'
        rw [sealWalk_cases hcc] at hv
        rw [push_of (s := s) hr hc hk hrev hv] at h1
        exact absurd h1 (by simp)
    | some t =>
      obtain ⟨r, c, hr, hc, hk, hrev, ⟨v, hv⟩, rfl⟩ := push_some h1
      rw [push_of (s := s.setCur aid x) hr (ckpt_setCur_of (aid := aid) (x := x) hc) hk hrev
        (by rw [sealWalk_ite]; exact hv)]
      rfl
  · cases h1 : stepFn p env s (.reanchor w) with
    | none =>
      cases h2 : stepFn p env (s.setCur aid x) (.reanchor w) with
      | none => rfl
      | some t =>
        exfalso
        obtain ⟨r, c', v, a, hr, hc', hk, hv, ha, rfl⟩ := reanchor_some h2
        obtain ⟨c, hc, hcc⟩ := ckpt_setCur_cases hc'
        rw [sealWalk_cases hcc] at hv
        rw [anchorOf_cases hcc] at ha
        have hr' : s.reg w.tel.i = some r := hr
        have : stepFn p env s (.reanchor w) = some (s.setReg r.rid (some { r with inception := a })) := by
          simp [stepFn, hr', hc, hk, hv, ha]
        rw [this] at h1
        exact absurd h1 (by simp)
    | some t =>
      obtain ⟨r, c, v, a, hr, hc, hk, hv, ha, rfl⟩ := reanchor_some h1
      have : stepFn p env (s.setCur aid x) (.reanchor w) =
          some ((s.setCur aid x).setReg r.rid (some { r with inception := a })) := by
        have hc' := ckpt_setCur_of (aid := aid) (x := x) hc
        have hr' : (s.setCur aid x).reg w.tel.i = some r := hr
        simp [stepFn, hr', hc', hk, sealWalk_ite, anchorOf_ite, hv, ha]
      rw [this]
      rfl

/-- **M9. A superseded push over-revokes.** A `rev` pushed under a
provisional walk whose issuer then rotates at or below the sealing
sequence stays in the set, while the same walk now fails: the mirror fails
closed. Mutant: an eviction of revocations on superseding. -/
theorem M9_superseded_push_over_revokes (p : Params) (env : TelEnv) {s s₁ s₂ : Sys} (h : Reach p env s)
    {w : Walk} {r : Registry} {c c' : Checkpoint} {e' : Seq} {t : Nat} {appr : Option Approval}
    (hr : s.reg w.tel.ri = some r) (hc : s.ckpt r.issuer = some c)
    (hprov : sealWalk p env c r.rid w = some .provisional)
    (h₁ : stepFn p env s (.push w) = some s₁)
    (h₂ : stepFn p env s₁ (.history r.issuer (.advance e' t appr)) = some s₂)
    (hle : e' ≤ w.core.kel.sn) (hc' : s₂.ckpt r.issuer = some c') :
    (∃ r', s₂.reg w.tel.ri = some r' ∧ r'.revoked w.tel.i = true) ∧
      sealWalk p env c' r.rid w = none := by
  obtain ⟨hR, hC⟩ := reach_ok h
  have hwf : WF c := reach_wf h _ _ hc
  obtain ⟨r₀, c₀, hr₀, hc₀, hk, hrev, _, rfl⟩ := push_some h₁
  rw [hr] at hr₀; cases Option.some.inj hr₀
  rw [hc] at hc₀; cases Option.some.inj hc₀
  have hrid : r.rid = w.tel.ri := hR _ _ hr
  obtain ⟨c₁, c₂, hc₁, hh, rfl⟩ := history_some h₂
  have hcc : c₁ = c := by
    simp only [Sys.setReg] at hc₁; rw [hc] at hc₁; exact (Option.some.inj hc₁).symm
  subst hcc
  have hcc' : c₂ = c' := by
    simp only [Sys.setCkpt, Sys.setReg, if_true] at hc'; exact Option.some.inj hc'
  subst hcc'
  refine ⟨⟨r.insert w.tel.i, ?_, by simp [Registry.insert]⟩, ?_⟩
  · simp [Sys.setCkpt, Sys.setReg, hrid]
  · simp only [sealWalk] at hprov ⊢
    split at hprov
    · simp at hprov
    · rename_i hcond
      rw [if_neg hcond]
      obtain ⟨_, l, hl, _, _, _, _, hcov⟩ := walkOn_some hprov
      have h4 := (H4_provisional_iff_latest hwf).1 hcov
      obtain ⟨hsucc, hlatest, hek, _⟩ := h4
      rw [hsucc] at hcov
      have h6 := H6_superseding_excludes hwf hcov hh hle
      exact walkOn_none_of_cover_none (h6 _)

/-- **M10. Freshness is not enforced** (a witness, not a guarantee). There
is a reachable system, an issuer and a `rev` whose seal walks — the issuer
anchored the revocation — while the mirror still reports absence, because
nobody pushed it. Refuting this would mean the model enforces a freshness
it does not have. Mutant: none — this documents a stated limit (#398). -/
theorem M10_freshness_unenforced :
    ∃ (p : Params) (env : TelEnv) (s : Sys) (issuer : AID) (c : Checkpoint) (rid : RegistryId)
      (w : Walk) (v : Verdict),
      Reach p env s ∧ s.ckpt issuer = some c ∧ (∃ r, s.reg rid = some r ∧ r.issuer = issuer) ∧
      w.tel.kind = .rev ∧ w.tel.ri = rid ∧ sealWalk p env c rid w = some v ∧
      miss s rid w.tel.i = true := by
  let p : Params := ⟨0⟩
  let env : TelEnv := { signed := fun _ _ => true, receipted := fun _ _ => true, digest := fun t => t.i }
  let wv : Walk := ⟨⟨.vcp, 5, 5, 0⟩, ⟨⟨1, false, [⟨5, 0, 5⟩]⟩, 0, none, 0⟩⟩
  let wr : Walk := ⟨⟨.rev, 7, 5, 1⟩, ⟨⟨2, false, [⟨7, 1, 7⟩]⟩, 0, none, 0⟩⟩
  let c : Checkpoint := inception 1 0 0 none none
  let s₁ : Sys := Sys.init.setCkpt 1 (some c)
  let s₂ : Sys := s₁.setReg 5 (some ⟨1, 5, ⟨0, 0, 1, .provisional⟩, fun _ => false⟩)
  refine ⟨p, env, s₂, 1, c, 5, wr, .provisional, ?_, rfl, ⟨_, rfl, rfl⟩, rfl, rfl, by decide, by decide⟩
  exact ReachFrom.step (a := .register 1 0 0 none) rfl
    (ReachFrom.step (a := .open 1 wv) rfl (ReachFrom.refl _))

/-- **M11. No registry, no absence.** The gate's absence check fails closed
on a registry that was never opened. Mutant: `miss` returning `true` on
`none`. -/
theorem M11_miss_fails_closed (s : Sys) (rid : RegistryId) (said : Said) (h : s.reg rid = none) :
    miss s rid said = false := by
  simp [miss, h]

/-- **M12. Re-anchor, exactly** (public inversion). A registry's inception
anchor is replaced iff the registry exists, its issuer has a checkpoint, a
`vcp` naming the registry walks, and the new anchor is that walk's; the
set and the issuer are untouched. Anyone may do it: the issuer's own seal
on its accepted branch is the permission. Mutant: `reanchor` that also
resets the set. -/
theorem M12_reanchor_iff (p : Params) (env : TelEnv) (s : Sys) (w : Walk) (s' : Sys) :
    stepFn p env s (.reanchor w) = some s' ↔
      ∃ r c v a, s.reg w.tel.i = some r ∧ s.ckpt r.issuer = some c ∧ w.tel.kind = .vcp ∧
        sealWalk p env c r.rid w = some v ∧ anchorOf c w.core v = some a ∧
        s' = s.setReg r.rid (some { r with inception := a }) := by
  constructor
  · intro h
    obtain ⟨r, c, v, a, hr, hc, hk, hv, ha, rfl⟩ := reanchor_some h
    exact ⟨r, c, v, a, hr, hc, hk, hv, ha, rfl⟩
  · rintro ⟨r, c, v, a, hr, hc, hk, hv, ha, rfl⟩
    simp [stepFn, hr, hc, hk, hv, ha]

/-- **M13. A registry's inception anchor is a walk's anchor.** In a
reachable system every registry's inception anchor was produced, by an
open or a re-anchor, from a successful walk of a `vcp` naming the registry
against the checkpoint of its issuer at the time. Mutant: `reanchor`
storing a caller-supplied anchor. -/
theorem M13_inception_is_a_walk_anchor (p : Params) (env : TelEnv) {s : Sys} (h : Reach p env s)
    {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) :
    ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ ReachFrom p env s₁ s ∧
      (stepFn p env s₀ (.open r.issuer w) = some s₁ ∨ stepFn p env s₀ (.reanchor w) = some s₁) ∧
      w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧
      sealWalk p env c rid w = some v ∧ anchorOf c w.core v = some r.inception := by
  refine reach_ind (p := p) (env := env)
    (P := fun s => ∀ rid r, s.reg rid = some r →
      ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ ReachFrom p env s₁ s ∧
        (stepFn p env s₀ (.open r.issuer w) = some s₁ ∨ stepFn p env s₀ (.reanchor w) = some s₁) ∧
        w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧
        sealWalk p env c rid w = some v ∧ anchorOf c w.core v = some r.inception)
    (fun _ _ h => by simp [Sys.init] at h) (fun s s' a hreach hP hs => ?_) h rid r hr
  intro rid r hr
  have ext : ∀ rid r, s.reg rid = some r →
      ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ ReachFrom p env s₁ s' ∧
        (stepFn p env s₀ (.open r.issuer w) = some s₁ ∨ stepFn p env s₀ (.reanchor w) = some s₁) ∧
        w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧
        sealWalk p env c rid w = some v ∧ anchorOf c w.core v = some r.inception := by
    intro rid r hr
    obtain ⟨s₀, s₁, w, c, v, h1, h2, h3, h4, h5, h6, h7, h8⟩ := hP rid r hr
    exact ⟨s₀, s₁, w, c, v, h1, reachFrom_snoc h2 hs, h3, h4, h5, h6, h7, h8⟩
  obtain ⟨hR, hC⟩ := reach_ok hreach
  cases a with
  | register aid ep t par =>
    obtain ⟨_, rfl⟩ := register_some hs
    exact ext rid r hr
  | history aid ha =>
    obtain ⟨c, c', _, _, rfl⟩ := history_some hs
    exact ext rid r hr
  | «open» issuer w =>
    obtain ⟨c, v, a, hnone, hc, hk, hv, ha, rfl⟩ := open_some hs
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      subst hx
      exact ⟨s, _, w, c, v, hreach, ReachFrom.refl _, Or.inl hs, hk, rfl, hc, hv, ha⟩
    · exact ext rid r hr
  | push w =>
    obtain ⟨r₀, c, hr₀, _, _, _, _, rfl⟩ := push_some hs
    have hrid : r₀.rid = w.tel.ri := hR _ _ hr₀
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      have hr' : s.reg rid = some r₀ := by rw [hx, hrid]; exact hr₀
      obtain ⟨s₀, s₁, w', c', v', h1, h2, h3, h4, h5, h6, h7, h8⟩ := hP rid r₀ hr'
      exact ⟨s₀, s₁, w', c', v', h1, reachFrom_snoc h2 hs, h3, h4, h5, h6, h7, h8⟩
    · exact ext rid r hr
  | reanchor w =>
    obtain ⟨r₀, c, v, a, hr₀, hc, hk, hv, ha, rfl⟩ := reanchor_some hs
    have hrid : r₀.rid = w.tel.i := hR _ _ hr₀
    simp only [Sys.setReg] at hr
    split at hr
    · rename_i hx; cases Option.some.inj hr
      have hx' : rid = w.tel.i := hx.trans hrid
      subst hx'
      refine ⟨s, _, w, c, v, hreach, ReachFrom.refl _, Or.inr hs, hk, rfl, hc, ?_, ha⟩
      rw [← hrid]; exact hv
    · exact ext rid r hr

end CardanoKeri.Mirror
