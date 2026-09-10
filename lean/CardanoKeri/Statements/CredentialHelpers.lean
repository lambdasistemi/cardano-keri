import CardanoKeri.Statements.Credential
import CardanoKeri.Statements.MirrorHelpers
import CardanoKeri.Statements.MirrorGoals

/-!
# Inversion helpers for credential admission and the cage

Proof-side lemmas only.
-/

namespace CardanoKeri.Credential

open CardanoKeri.History
open CardanoKeri.Mirror

/-! ## One hop -/

theorem hopVerdict_some {p : Params} {env : CEnv} {s : Mirror.Sys} {parent : Option Said} {h : Hop} {v : Verdict}
    (hv : hopVerdict p env s parent h = some v) :
    env.saidOf h.acdc.body = h.acdc.said ∧ h.acdc.body.edge = parent ∧
      h.walk.tel.kind = .iss ∧ h.walk.tel.i = h.acdc.said ∧
      ∃ c r, s.ckpt h.acdc.body.issuer = some c ∧ s.reg h.acdc.body.registry = some r ∧
        r.issuer = h.acdc.body.issuer ∧ r.revoked h.acdc.said = false ∧
        r.inception.stands c h.regProof = true ∧
        sealWalk p env.toTelEnv c h.acdc.body.registry h.walk = some v := by
  simp only [hopVerdict] at hv
  split at hv
  · simp at hv
  · rename_i h1
    split at hv
    · simp at hv
    · rename_i h2
      split at hv
      · simp at hv
      · rename_i h3
        split at hv
        · rename_i c r hc hr
          split at hv
          · simp at hv
          · rename_i h4
            split at hv
            · simp at hv
            · rename_i h5
              split at hv
              · simp at hv
              · rename_i h6
                refine ⟨by simpa using h1, by simpa using h2, ?_, ?_, c, r, hc, hr, by simpa using h4,
                  by simpa using h5, by simpa using h6, hv⟩
                · have := not_or.mp h3; exact by simpa using this.1
                · have := not_or.mp h3; exact by simpa using this.2
        · simp at hv

theorem hopVerdict_none_of_revoked {p : Params} {env : CEnv} {s : Mirror.Sys} (parent : Option Said) {h : Hop}
    {r : Registry} (hr : s.reg h.acdc.body.registry = some r) (hrev : r.revoked h.acdc.said = true) :
    hopVerdict p env s parent h = none := by
  cases hv : hopVerdict p env s parent h with
  | none => rfl
  | some v =>
    obtain ⟨_, _, _, _, c, r', hc, hr', _, hrev', _, _⟩ := hopVerdict_some hv
    rw [hr] at hr'; cases Option.some.inj hr'; rw [hrev] at hrev'; simp at hrev'

theorem hopVerdict_none_of_registry {p : Params} {env : CEnv} {s : Mirror.Sys} (parent : Option Said) {h : Hop}
    (hreg : s.reg h.acdc.body.registry = none ∨
      ∃ r, s.reg h.acdc.body.registry = some r ∧ r.issuer ≠ h.acdc.body.issuer) :
    hopVerdict p env s parent h = none := by
  cases hv : hopVerdict p env s parent h with
  | none => rfl
  | some v =>
    obtain ⟨_, _, _, _, c, r', hc, hr', hiss, _, _, _⟩ := hopVerdict_some hv
    rcases hreg with hn | ⟨r, hr, hne⟩
    · rw [hn] at hr'; simp at hr'
    · rw [hr] at hr'; cases Option.some.inj hr'; exact absurd hiss hne

theorem hopVerdict_none_of_stands {p : Params} {env : CEnv} {s : Mirror.Sys} (parent : Option Said) {h : Hop}
    {c : Checkpoint} {r : Registry} (hc : s.ckpt h.acdc.body.issuer = some c)
    (hr : s.reg h.acdc.body.registry = some r) (hst : r.inception.stands c h.regProof = false) :
    hopVerdict p env s parent h = none := by
  cases hv : hopVerdict p env s parent h with
  | none => rfl
  | some v =>
    obtain ⟨_, _, _, _, c', r', hc', hr', _, _, hst', _⟩ := hopVerdict_some hv
    rw [hr] at hr'; cases Option.some.inj hr'
    rw [hc] at hc'; cases Option.some.inj hc'
    rw [hst] at hst'; simp at hst'

theorem stands_ite (c : Checkpoint) (x : Epoch) (b : Prop) [Decidable b] (a : Anchor) (proof : Option Seq) :
    a.stands (if b then { c with cur := x } else c) proof = a.stands c proof := by
  split <;> rfl

theorem hopVerdict_setCur (p : Params) (env : CEnv) (s : Mirror.Sys) (aid : AID) (x : Epoch)
    (parent : Option Said) (h : Hop) :
    hopVerdict p env (s.setCur aid x) parent h = hopVerdict p env s parent h := by
  have hreg : (s.setCur aid x).reg = s.reg := rfl
  cases hc : s.ckpt h.acdc.body.issuer with
  | none =>
    have hc' : (s.setCur aid x).ckpt h.acdc.body.issuer = none := by
      simp only [Sys.setCur]; split <;> simp [hc]
    simp only [hopVerdict, hreg, hc, hc']
  | some c =>
    by_cases hia : h.acdc.body.issuer = aid
    · have hc' : (s.setCur aid x).ckpt h.acdc.body.issuer = some { c with cur := x } := by
        rw [ckpt_setCur_of (aid := aid) (x := x) hc, if_pos hia]
      simp only [hopVerdict, hreg, hc, hc']
      cases s.reg h.acdc.body.registry <;> rfl
    · have hc' : (s.setCur aid x).ckpt h.acdc.body.issuer = some c := by
        rw [ckpt_setCur_of (aid := aid) (x := x) hc, if_neg hia]
      simp only [hopVerdict, hreg, hc, hc']

/-! ## The chain -/

theorem chainFrom_nil (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy) (scs : List Schema)
    (lks : List Link) : chainFrom p env s pol [] scs lks = none := by
  cases scs <;> cases lks <;> rfl

theorem chainFrom_single {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} {h : Hop} {scs : List Schema}
    {lks : List Link} {v : Verdict} (hc : chainFrom p env s pol [h] scs lks = some v) :
    scs = [h.acdc.body.schema] ∧ lks = [] ∧ h.acdc.body.issuer = pol.root ∧
      hopVerdict p env s none h = some v := by
  cases scs with
  | nil => cases lks <;> simp [chainFrom] at hc
  | cons sc scs' =>
    cases scs' with
    | cons _ _ => cases lks <;> simp [chainFrom] at hc
    | nil =>
      cases lks with
      | cons _ _ => simp [chainFrom] at hc
      | nil =>
        simp only [chainFrom] at hc
        split at hc
        · rename_i hcond; exact ⟨by rw [hcond.1], rfl, hcond.2, hc⟩
        · simp at hc

theorem chainFrom_cons {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} {h h₂ : Hop} {hs : List Hop}
    {scs : List Schema} {lks : List Link} {v : Verdict}
    (hc : chainFrom p env s pol (h :: h₂ :: hs) scs lks = some v) :
    ∃ sc scs' lk lks' v₁ v₂, scs = sc :: scs' ∧ lks = lk :: lks' ∧ h.acdc.body.schema = sc ∧
      lk h.acdc.body h₂.acdc.body = true ∧
      hopVerdict p env s (some h₂.acdc.said) h = some v₁ ∧
      chainFrom p env s pol (h₂ :: hs) scs' lks' = some v₂ ∧ v = v₁.meet v₂ := by
  cases scs with
  | nil => cases lks <;> simp [chainFrom] at hc
  | cons sc scs' =>
    cases lks with
    | nil => simp [chainFrom] at hc
    | cons lk lks' =>
      simp only [chainFrom] at hc
      split at hc
      · rename_i hcond
        cases hv₁ : hopVerdict p env s (some h₂.acdc.said) h with
        | none => rw [hv₁] at hc; simp at hc
        | some v₁ =>
          rw [hv₁] at hc
          cases hv₂ : chainFrom p env s pol (h₂ :: hs) scs' lks' with
          | none => rw [hv₂] at hc; simp at hc
          | some v₂ =>
            rw [hv₂] at hc; simp at hc
            exact ⟨sc, scs', lk, lks', v₁, v₂, rfl, rfl, hcond.1, hcond.2, (by first | rfl | exact hv₁),
              (by first | rfl | exact hv₂), hc.symm⟩
      · simp at hc

/-- Every hop of an admitted chain has a verdict, under the parent SAID its
position dictates. -/
theorem chainFrom_hops {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link) (v : Verdict),
      chainFrom p env s pol hops scs lks = some v →
      ∀ hop ∈ hops, ∃ parent v', hopVerdict p env s parent hop = some v' := by
  intro hops
  induction hops with
  | nil => intro scs lks v hc; rw [chainFrom_nil] at hc; simp at hc
  | cons h hs ih =>
    intro scs lks v hc hop hin
    cases hs with
    | nil =>
      obtain ⟨_, _, _, hv⟩ := chainFrom_single hc
      simp at hin; subst hin; exact ⟨none, v, hv⟩
    | cons h₂ hs' =>
      obtain ⟨sc, scs', lk, lks', v₁, v₂, _, _, _, _, hv₁, hv₂, _⟩ := chainFrom_cons hc
      simp only [List.mem_cons] at hin
      rcases hin with rfl | hin
      · exact ⟨some h₂.acdc.said, v₁, hv₁⟩
      · exact ih scs' lks' v₂ hv₂ hop (List.mem_cons.mpr hin)

theorem chainFrom_schemas {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link) (v : Verdict),
      chainFrom p env s pol hops scs lks = some v →
      hops.map (·.acdc.body.schema) = scs ∧ lks.length + 1 = hops.length := by
  intro hops
  induction hops with
  | nil => intro scs lks v hc; rw [chainFrom_nil] at hc; simp at hc
  | cons h hs ih =>
    intro scs lks v hc
    cases hs with
    | nil =>
      obtain ⟨rfl, rfl, _, _⟩ := chainFrom_single hc
      simp
    | cons h₂ hs' =>
      obtain ⟨sc, scs', lk, lks', v₁, v₂, rfl, rfl, hsc, _, _, hv₂, _⟩ := chainFrom_cons hc
      obtain ⟨h1, h2⟩ := ih scs' lks' v₂ hv₂
      refine ⟨by simp [hsc, h1], ?_⟩
      simp only [List.length_cons] at h2 ⊢; omega

theorem chainFrom_last {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link) (v : Verdict),
      chainFrom p env s pol hops scs lks = some v →
      ∃ last, hops.getLast? = some last ∧ last.acdc.body.edge = none ∧ last.acdc.body.issuer = pol.root := by
  intro hops
  induction hops with
  | nil => intro scs lks v hc; rw [chainFrom_nil] at hc; simp at hc
  | cons h hs ih =>
    intro scs lks v hc
    cases hs with
    | nil =>
      obtain ⟨_, _, hroot, hv⟩ := chainFrom_single hc
      obtain ⟨_, hedge, _⟩ := hopVerdict_some hv
      exact ⟨h, rfl, hedge, hroot⟩
    | cons h₂ hs' =>
      obtain ⟨sc, scs', lk, lks', v₁, v₂, _, _, _, _, _, hv₂, _⟩ := chainFrom_cons hc
      obtain ⟨last, hl, he, hr⟩ := ih scs' lks' v₂ hv₂
      exact ⟨last, by simpa using hl, he, hr⟩

theorem chainFrom_edges {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link) (v : Verdict),
      chainFrom p env s pol hops scs lks = some v →
      ∀ i h₁ h₂, hops[i]? = some h₁ → hops[i + 1]? = some h₂ → h₁.acdc.body.edge = some h₂.acdc.said := by
  intro hops
  induction hops with
  | nil => intro scs lks v hc; rw [chainFrom_nil] at hc; simp at hc
  | cons h hs ih =>
    intro scs lks v hc i h₁ h₂ hi hi'
    cases hs with
    | nil => cases i <;> simp at hi'
    | cons h₂' hs' =>
      obtain ⟨sc, scs', lk, lks', v₁, v₂, _, _, _, _, hv₁, hv₂, _⟩ := chainFrom_cons hc
      cases i with
      | zero =>
        simp at hi hi'; subst hi; subst hi'
        exact (hopVerdict_some hv₁).2.1
      | succ i =>
        simp at hi hi'
        exact ih scs' lks' v₂ hv₂ i h₁ h₂ hi hi'

theorem chainFrom_links {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link) (v : Verdict),
      chainFrom p env s pol hops scs lks = some v →
      ∀ i h₁ h₂ lk, hops[i]? = some h₁ → hops[i + 1]? = some h₂ → lks[i]? = some lk →
        lk h₁.acdc.body h₂.acdc.body = true := by
  intro hops
  induction hops with
  | nil => intro scs lks v hc; rw [chainFrom_nil] at hc; simp at hc
  | cons h hs ih =>
    intro scs lks v hc i h₁ h₂ lk hi hi' hlk
    cases hs with
    | nil => cases i <;> simp at hi'
    | cons h₂' hs' =>
      obtain ⟨sc, scs', lk', lks', v₁, v₂, _, rfl, _, hlink, hv₁, hv₂, _⟩ := chainFrom_cons hc
      cases i with
      | zero =>
        simp at hi hi' hlk; subst hi; subst hi'; subst hlk
        exact hlink
      | succ i =>
        simp at hi hi' hlk
        exact ih scs' lks' v₂ hv₂ i h₁ h₂ lk hi hi' hlk

/-- A hop that has no verdict under any parent refuses the chain. -/
theorem chainFrom_none_of_hop {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link) (hop : Hop), hop ∈ hops →
      (∀ parent, hopVerdict p env s parent hop = none) →
      chainFrom p env s pol hops scs lks = none := by
  intro hops scs lks hop hin hnone
  cases hc : chainFrom p env s pol hops scs lks with
  | none => rfl
  | some v =>
    obtain ⟨parent, v', hv⟩ := chainFrom_hops hops scs lks v hc hop hin
    rw [hnone parent] at hv; simp at hv

theorem chainFrom_none_of_link {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy}
    (hops : List Hop) (scs : List Schema) (lks : List Link) (i : Nat) (h₁ h₂ : Hop) (lk : Link)
    (hi : hops[i]? = some h₁) (hi' : hops[i + 1]? = some h₂) (hlk : lks[i]? = some lk)
    (hfail : lk h₁.acdc.body h₂.acdc.body = false) :
    chainFrom p env s pol hops scs lks = none := by
  cases hc : chainFrom p env s pol hops scs lks with
  | none => rfl
  | some v =>
    have := chainFrom_links hops scs lks v hc i h₁ h₂ lk hi hi' hlk
    rw [hfail] at this; simp at this

/-- The chain's verdict is provisional iff some hop's is. -/
theorem chainFrom_provisional {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link) (v : Verdict),
      chainFrom p env s pol hops scs lks = some v →
      (v = .provisional ↔ ∃ hop ∈ hops, ∃ parent, hopVerdict p env s parent hop = some .provisional) := by
  intro hops
  induction hops with
  | nil => intro scs lks v hc; rw [chainFrom_nil] at hc; simp at hc
  | cons h hs ih =>
    intro scs lks v hc
    cases hs with
    | nil =>
      obtain ⟨_, _, _, hv⟩ := chainFrom_single hc
      constructor
      · intro hp; subst hp; exact ⟨h, by simp, none, hv⟩
      · rintro ⟨hop, hin, parent, hv'⟩
        simp at hin; subst hin
        obtain ⟨_, hedge, _⟩ := hopVerdict_some hv
        obtain ⟨_, hedge', _⟩ := hopVerdict_some hv'
        rw [hedge] at hedge'; subst hedge'
        rw [hv] at hv'; exact Option.some.inj hv'
    | cons h₂ hs' =>
      obtain ⟨sc, scs', lk, lks', v₁, v₂, _, _, _, _, hv₁, hv₂, rfl⟩ := chainFrom_cons hc
      have ih' := ih scs' lks' v₂ hv₂
      constructor
      · intro hp
        cases v₁ with
        | provisional => exact ⟨h, by simp, some h₂.acdc.said, hv₁⟩
        | final =>
          cases v₂ with
          | final => simp [Verdict.meet] at hp
          | provisional =>
            obtain ⟨hop, hin, parent, hv⟩ := ih'.1 rfl
            exact ⟨hop, by simp [hin], parent, hv⟩
      · rintro ⟨hop, hin, parent, hv⟩
        simp only [List.mem_cons] at hin
        rcases hin with rfl | hin
        · obtain ⟨_, hedge, _⟩ := hopVerdict_some hv₁
          obtain ⟨_, hedge', _⟩ := hopVerdict_some hv
          rw [hedge] at hedge'; subst hedge'
          rw [hv₁] at hv; cases Option.some.inj hv
          cases v₂ <;> rfl
        · have := ih'.2 ⟨hop, List.mem_cons.mpr hin, parent, hv⟩
          subst this; cases v₁ <;> rfl

theorem chainFrom_setCur (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy) (aid : AID) (x : Epoch) :
    ∀ (hops : List Hop) (scs : List Schema) (lks : List Link),
      chainFrom p env (s.setCur aid x) pol hops scs lks = chainFrom p env s pol hops scs lks := by
  intro hops
  induction hops with
  | nil => intro scs lks; rw [chainFrom_nil, chainFrom_nil]
  | cons h hs ih =>
    intro scs lks
    cases hs with
    | nil =>
      cases scs with
      | nil => cases lks <;> rfl
      | cons sc scs' =>
        cases scs' with
        | cons _ _ => cases lks <;> rfl
        | nil =>
          cases lks with
          | cons _ _ => rfl
          | nil => simp only [chainFrom, hopVerdict_setCur]
    | cons h₂ hs' =>
      cases scs with
      | nil => cases lks <;> rfl
      | cons sc scs' =>
        cases lks with
        | nil => rfl
        | cons lk lks' => simp only [chainFrom, hopVerdict_setCur, ih]

/-! ## Lists -/

theorem zip_all_iff {α β : Type} (f : α × β → Bool) :
    ∀ (l₁ : List α) (l₂ : List β),
      (l₁.zip l₂).all f = true ↔ ∀ (i : Nat) a b, l₁[i]? = some a → l₂[i]? = some b → f (a, b) = true := by
  intro l₁
  induction l₁ with
  | nil => intro l₂; simp
  | cons a l₁ ih =>
    intro l₂
    cases l₂ with
    | nil => simp
    | cons b l₂ =>
      simp only [List.zip_cons_cons, List.all_cons, Bool.and_eq_true]
      constructor
      · rintro ⟨hf, hrest⟩ i a' b' ha hb
        cases i with
        | zero => simp at ha hb; subst ha; subst hb; exact hf
        | succ i => simp at ha hb; exact (ih l₂).1 hrest i a' b' ha hb
      · intro hall
        refine ⟨hall 0 a b rfl rfl, (ih l₂).2 fun i a' b' ha hb => hall (i + 1) a' b' (by simpa using ha) (by simpa using hb)⟩

/-! ## The cage -/

theorem moved_iff (s : Mirror.Sys) (d : Dep) (m : Option Seq) :
    d.moved s m = true ↔ ∃ c, s.ckpt d.issuer = some c ∧
      ((∀ l, c.hist d.anchor.e = some l → l.epoch ≠ d.anchor.epoch) ∨
        ∃ m', m = some m' ∧ d.anchor.e < m' ∧ m' ≤ d.anchor.k ∧ (c.hist m').isSome) := by
  simp only [Dep.moved]
  cases hc : s.ckpt d.issuer with
  | none => simp
  | some c =>
    simp only [Anchor.moved, Bool.or_eq_true, Option.some.injEq, exists_eq_left']
    constructor
    · rintro (h | h)
      · left; intro l hl; rw [hl] at h; simpa using h
      · right
        cases m with
        | none => simp at h
        | some m' =>
          simp only [Bool.and_eq_true, decide_eq_true_eq] at h
          exact ⟨m', rfl, h.1.1, h.1.2, h.2⟩
    · rintro (h | ⟨m', rfl, h1, h2, h3⟩)
      · left
        cases hl : c.hist d.anchor.e with
        | none => rfl
        | some l => simpa using h l hl
      · right; simp [h1, h2, h3]

theorem admit_some {p : Params} {env : CEnv} {pol : Policy} {s s' : Sys} {key : AID} {hops : List Hop} {now : Slot}
    (h : stepFn p env pol s (.admit key hops now) = some s') :
    ∃ hd v deps, hops.head? = some hd ∧ hd.acdc.body.issuee = key ∧
      (∀ ad, s.cage key = some ad → ad.expired pol now = true) ∧
      admitChain p env s.toSys pol hops = some v ∧ hops.mapM (Hop.dep s.toSys) = some deps ∧
      s' = s.setCage key (some ⟨hops.map (·.acdc.said), hops.map (·.acdc.body.registry), v, deps, now⟩) := by
  simp only [stepFn] at h
  split at h
  · simp at h
  · rename_i h1
    split at h
    · simp at h
    · rename_i h2
      split at h
      · rename_i v deps hv hdeps
        cases hhd : hops.head? with
        | none => rw [hhd] at h1; simp at h1
        | some hd =>
          rw [hhd] at h1; simp at h1
          refine ⟨hd, v, deps, rfl, h1, ?_, hv, hdeps, (Option.some.inj h).symm⟩
          intro ad had
          rw [had] at h2; simpa using h2
      · simp at h

theorem admit_of {p : Params} {env : CEnv} {pol : Policy} {s : Sys} {key : AID} {hops : List Hop} {now : Slot}
    {hd : Hop} (hhd : hops.head? = some hd) (hkey : hd.acdc.body.issuee = key)
    (hfree : ∀ ad, s.cage key = some ad → ad.expired pol now = true) {v : Verdict} {deps : List Dep}
    (hv : admitChain p env s.toSys pol hops = some v) (hdeps : hops.mapM (Hop.dep s.toSys) = some deps) :
    stepFn p env pol s (.admit key hops now) =
      some (s.setCage key (some ⟨hops.map (·.acdc.said), hops.map (·.acdc.body.registry), v, deps, now⟩)) := by
  have : (s.cage key).any (fun ad => !ad.expired pol now) = false := by
    cases hc : s.cage key with
    | none => rfl
    | some ad => simp [hfree ad hc]
  simp [stepFn, hhd, hkey, this, hv, hdeps]

theorem evict_some {p : Params} {env : CEnv} {pol : Policy} {s s' : Sys} {key : AID} {m : Option Seq}
    (h : stepFn p env pol s (.evict key m) = some s') :
    ∃ ad, s.cage key = some ad ∧ ad.deps.any (fun d => d.moved s.toSys m) = true ∧ s' = s.setCage key none := by
  simp only [stepFn] at h
  split at h
  · rename_i ad had
    split at h
    · exact ⟨ad, had, ‹_›, (Option.some.inj h).symm⟩
    · simp at h
  · simp at h

theorem evict_of {p : Params} {env : CEnv} {pol : Policy} {s : Sys} {key : AID} {m : Option Seq} {ad : Admission}
    (had : s.cage key = some ad) (hmoved : ad.deps.any (fun d => d.moved s.toSys m) = true) :
    stepFn p env pol s (.evict key m) = some (s.setCage key none) := by
  simp [stepFn, had, hmoved]

theorem mirror_some {p : Params} {env : CEnv} {pol : Policy} {s s' : Sys} {a : Mirror.Action}
    (h : stepFn p env pol s (.mirror a) = some s') :
    ∃ m, Mirror.stepFn p env.toTelEnv s.toSys a = some m ∧ s' = { s with toSys := m } := by
  simp only [stepFn] at h
  cases hm : Mirror.stepFn p env.toTelEnv s.toSys a with
  | none => rw [hm] at h; simp at h
  | some m => rw [hm] at h; simp at h; exact ⟨m, rfl, h.symm⟩

theorem cage_of_mirror {s : Sys} {m : Mirror.Sys} : ({ s with toSys := m } : Sys).cage = s.cage := rfl

/-- Every reachable credential system has a reachable mirror system. -/
theorem reach_mirror {p : Params} {env : CEnv} {pol : Policy} {s : Sys} (h : Reach p env pol s) :
    Mirror.Reach p env.toTelEnv s.toSys := by
  have key : ∀ s s'', ReachFrom p env pol s s'' → Mirror.Reach p env.toTelEnv s.toSys →
      Mirror.Reach p env.toTelEnv s''.toSys := by
    intro s s'' hr
    induction hr with
    | refl _ => exact id
    | @step s s' s'' a hs _ ih =>
      intro hm
      apply ih
      cases a with
        | mirror a =>
        obtain ⟨m, hm', rfl⟩ := mirror_some hs
        exact reachFrom_snoc hm hm'
        | admit key hops now =>
        obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := admit_some hs
        exact hm
        | evict key m =>
        obtain ⟨_, _, _, rfl⟩ := evict_some hs
        exact hm
        | expire key now =>
        simp only [stepFn] at hs
        split at hs
        · split at hs
          · cases Option.some.inj hs; exact hm
          · simp at hs
        · simp at hs
  exact key _ _ h (Mirror.ReachFrom.refl _)

theorem mapM_dep_mem {s : Mirror.Sys} :
    ∀ (hops : List Hop) (deps : List Dep), hops.mapM (Hop.dep s) = some deps →
      ∀ d ∈ deps, ∃ hop ∈ hops, hop.dep s = some d := by
  intro hops
  induction hops with
  | nil => intro deps h d hd; simp at h; subst h; simp at hd
  | cons hop hops ih =>
    intro deps h d hd
    simp only [List.mapM_cons, Option.bind_eq_bind, Option.bind_eq_some_iff, Option.pure_def,
      Option.some.injEq] at h
    obtain ⟨d₀, hd₀, deps', hdeps', rfl⟩ := h
    simp only [List.mem_cons] at hd
    rcases hd with rfl | hd
    · exact ⟨hop, by simp, hd₀⟩
    · obtain ⟨hop', hin, hdep⟩ := ih deps' hdeps' d hd
      exact ⟨hop', by simp [hin], hdep⟩

theorem mapM_dep_of_mem {s : Mirror.Sys} :
    ∀ (hops : List Hop) (deps : List Dep), hops.mapM (Hop.dep s) = some deps →
      ∀ hop ∈ hops, ∃ d ∈ deps, hop.dep s = some d := by
  intro hops
  induction hops with
  | nil => intro deps h hop hin; simp at hin
  | cons hop₀ hops ih =>
    intro deps h hop hin
    simp only [List.mapM_cons, Option.bind_eq_bind, Option.bind_eq_some_iff, Option.pure_def,
      Option.some.injEq] at h
    obtain ⟨d₀, hd₀, deps', hdeps', rfl⟩ := h
    simp only [List.mem_cons] at hin
    rcases hin with rfl | hin
    · exact ⟨d₀, by simp, hd₀⟩
    · obtain ⟨d, hd, hdep⟩ := ih deps' hdeps' hop hin
      exact ⟨d, by simp [hd], hdep⟩

theorem dep_some {s : Mirror.Sys} {hop : Hop} {d : Dep} (h : hop.dep s = some d) :
    ∃ c l v, s.ckpt hop.acdc.body.issuer = some c ∧ c.hist hop.walk.core.e = some l ∧
      cover c hop.walk.core.e hop.walk.core.kel.sn hop.walk.core.succ = some v ∧
      d = ⟨hop.acdc.body.issuer, ⟨hop.walk.core.e, l.epoch, hop.walk.core.kel.sn, v⟩⟩ := by
  simp only [Hop.dep] at h
  split at h
  · simp at h
  · rename_i c hc
    split at h
    · simp at h
    · rename_i v hv
      simp only [anchorOf] at h
      cases hl : c.hist hop.walk.core.e with
      | none => rw [hl] at h; simp at h
      | some l => rw [hl] at h; simp at h; exact ⟨c, l, v, hc, hl, hv, h.symm⟩

end CardanoKeri.Credential

namespace CardanoKeri.Credential

open CardanoKeri.History
open CardanoKeri.Mirror

theorem sealWalk_some_cover {p : Params} {env : TelEnv} {c : Checkpoint} {rid : RegistryId} {w : Walk}
    {v : Verdict} (h : sealWalk p env c rid w = some v) :
    cover c w.core.e w.core.kel.sn w.core.succ = some v := by
  simp only [sealWalk] at h
  split at h
  · simp at h
  · exact (walkOn_some h).2.choose_spec.2.2.2.2.2

/-- The cage invariant: every dependency of a final admission stands under
its successor proof, on the present checkpoint of its issuer. -/
def CageOk (s : Sys) : Prop :=
  ∀ key ad, s.cage key = some ad → ad.verdict = .final →
    ∀ d ∈ ad.deps, ∃ c e', s.ckpt d.issuer = some c ∧ d.anchor.verdict = .final ∧
      d.anchor.stands c (some e') = true

theorem admitChain_final_hops {p : Params} {env : CEnv} {s : Mirror.Sys} {pol : Policy} {hops : List Hop}
    (h : admitChain p env s pol hops = some .final) :
    ∀ hop ∈ hops, ∃ parent, hopVerdict p env s parent hop = some .final := by
  simp only [admitChain] at h
  split at h
  · intro hop hin
    obtain ⟨parent, v', hv⟩ := chainFrom_hops hops pol.schemas pol.links .final h hop hin
    cases v' with
    | final => exact ⟨parent, hv⟩
    | provisional =>
      have := (chainFrom_provisional hops pol.schemas pol.links .final h).2 ⟨hop, hin, parent, hv⟩
      simp at this
  · simp at h

theorem cageOk_step {p : Params} {env : CEnv} {pol : Policy} {s s' : Sys} (hreach : Reach p env pol s)
    (hok : CageOk s) {a : Action} (hs : stepFn p env pol s a = some s') : CageOk s' := by
  have hwf := reach_wf (reach_mirror hreach)
  cases a with
  | mirror a =>
    obtain ⟨m, hm, rfl⟩ := mirror_some hs
    intro key ad had hfin d hd
    obtain ⟨c, e', hc, hdf, hst⟩ := hok key ad had hfin d hd
    cases a with
    | register aid ep t par =>
      obtain ⟨hnone, rfl⟩ := register_some hm
      refine ⟨c, e', ?_, hdf, hst⟩
      simp only [Mirror.Sys.setCkpt]
      rw [if_neg]; · exact hc
      · intro hx; rw [hx] at hc; rw [hnone] at hc; simp at hc
    | history aid ha =>
      obtain ⟨c₀, c₀', hc₀, hh, rfl⟩ := history_some hm
      by_cases hx : d.issuer = aid
      · rw [hx] at hc; rw [hc₀] at hc; cases Option.some.inj hc
        refine ⟨c₀', e', by simp [Mirror.Sys.setCkpt, hx], hdf, ?_⟩
        exact H11_final_anchor_stands (hwf _ _ hc₀) hh hdf hst (by simp)
      · exact ⟨c, e', by simp [Mirror.Sys.setCkpt, hx]; exact hc, hdf, hst⟩
    | «open» issuer w =>
      obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := open_some hm
      exact ⟨c, e', hc, hdf, hst⟩
    | push w =>
      obtain ⟨_, _, _, _, _, _, _, rfl⟩ := push_some hm
      exact ⟨c, e', hc, hdf, hst⟩
    | reanchor w =>
      obtain ⟨_, _, _, _, _, _, _, _, _, rfl⟩ := reanchor_some hm
      exact ⟨c, e', hc, hdf, hst⟩
  | admit key hops now =>
    obtain ⟨hd, v, deps, hhd, hkey, hfree, hv, hdeps, rfl⟩ := admit_some hs
    intro key' ad had hfin d hd'
    simp only [Sys.setCage] at had
    split at had
    · cases Option.some.inj had
      simp only at hfin hd'
      subst hfin
      obtain ⟨hop, hin, hdep⟩ := mapM_dep_mem hops deps hdeps d hd'
      obtain ⟨c, l, v', hc, hl, hcov, rfl⟩ := dep_some hdep
      obtain ⟨parent, hvf⟩ := admitChain_final_hops hv hop hin
      obtain ⟨_, _, _, _, c', r, hc', _, _, _, _, hsw⟩ := hopVerdict_some hvf
      rw [hc] at hc'; cases Option.some.inj hc'
      have hcov' := sealWalk_some_cover hsw
      rw [hcov] at hcov'; cases Option.some.inj hcov'
      cases hsucc : hop.walk.core.succ with
      | none => rw [hsucc] at hcov; have := (cover_some_none hcov).2.2.2; simp at this
      | some e' =>
        refine ⟨c, e', hc, rfl, ?_⟩
        simp only [Anchor.stands, hl, beq_self_eq_true, Bool.true_and]
        rw [← hsucc, hcov]; rfl
    · exact hok key' ad had hfin d hd'
  | evict key m =>
    obtain ⟨_, _, _, rfl⟩ := evict_some hs
    intro key' ad had hfin d hd
    simp only [Sys.setCage] at had
    split at had
    · simp at had
    · exact hok key' ad had hfin d hd
  | expire key now =>
    simp only [stepFn] at hs
    split at hs
    · split at hs
      · cases Option.some.inj hs
        intro key' ad had hfin d hd
        simp only [Sys.setCage] at had
        split at had
        · simp at had
        · exact hok key' ad had hfin d hd
      · simp at hs
    · simp at hs

end CardanoKeri.Credential

namespace CardanoKeri.Credential

open CardanoKeri.History
open CardanoKeri.Mirror

theorem credential_reachFrom_snoc {p : Params} {env : CEnv} {pol : Policy} {s s' s'' : Sys} {a : Action}
    (h : ReachFrom p env pol s s') (hs : stepFn p env pol s' a = some s'') : ReachFrom p env pol s s'' := by
  induction h with
  | refl _ => exact ReachFrom.step hs (ReachFrom.refl _)
  | step hs' _ ih => exact ReachFrom.step hs' (ih hs)

theorem reach_cageOk {p : Params} {env : CEnv} {pol : Policy} {s : Sys} (h : Reach p env pol s) : CageOk s := by
  have key : ∀ s s'', ReachFrom p env pol s s'' → Reach p env pol s → CageOk s → CageOk s'' := by
    intro s s'' hr
    induction hr with
    | refl _ => exact fun _ hp => hp
    | @step s s' s'' a hs _ ih =>
      intro hreach hok
      exact ih (credential_reachFrom_snoc hreach hs) (cageOk_step hreach hok hs)
  exact key _ _ h (ReachFrom.refl _) (fun _ _ had => by simp [Sys.init] at had)

end CardanoKeri.Credential
