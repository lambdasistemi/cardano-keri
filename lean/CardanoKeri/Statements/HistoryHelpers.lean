import CardanoKeri.Statements.History

/-!
# Inversion helpers for the history model

Proof-side lemmas only: each characterises one executable definition of
`History.lean` in terms of its guards and effects. No theorem of the
statement surface lives here.
-/

namespace CardanoKeri.History

/-- The checkpoint an accepted advance produces. -/
def advanced (c : Checkpoint) (sn' : Seq) (t : Nat) (appr : Option Approval) : Checkpoint :=
  { c with latest := sn', cur := c.cur + 1, approval := appr,
           hist := fun sn => if sn = sn' then some ⟨some c.latest, c.cur + 1, t⟩ else c.hist sn }

/-- The checkpoint an accepted superseding produces, given the replaced leaf. -/
def superseded (c : Checkpoint) (l : Leaf) (sn' : Seq) (t : Nat) (appr : Approval) : Checkpoint :=
  { c with cur := c.cur + 1, approval := some appr,
           hist := fun sn => if sn = sn' then some ⟨l.prev, c.cur + 1, t⟩ else c.hist sn }

theorem advance_some {c c' : Checkpoint} {sn' : Seq} {t : Nat} {appr : Option Approval}
    (h : advance c sn' t appr = some c') :
    c.latest < sn' ∧ c' = advanced c sn' t appr := by
  simp only [advance] at h
  split at h
  · exact ⟨‹_›, (Option.some.inj h).symm⟩
  · exact absurd h (by simp)

theorem advance_of_lt {c : Checkpoint} {sn' : Seq} (t : Nat) (appr : Option Approval)
    (h : c.latest < sn') : advance c sn' t appr = some (advanced c sn' t appr) := by
  simp [advance, h, advanced]

theorem supersede_some {c c' : Checkpoint} {sn' : Seq} {t : Nat} {appr : Approval}
    (h : supersede c sn' t appr = some c') :
    ∃ par l a, c.parent = some par ∧ c.hist c.latest = some l ∧ c.approval = some a ∧
      sn' = c.latest ∧ a.before appr ∧ c' = superseded c l sn' t appr := by
  simp only [supersede] at h
  split at h
  · rename_i par l a hpar hl ha
    split at h
    · rename_i hc
      exact ⟨par, l, a, hpar, hl, ha, hc.1, hc.2, (Option.some.inj h).symm⟩
    · exact absurd h (by simp)
  · exact absurd h (by simp)

theorem cover_some_succ {c : Checkpoint} {e k e' : Seq} {v : Verdict}
    (h : cover c e k (some e') = some v) :
    (∃ l, c.hist e = some l) ∧ ∃ l', c.hist e' = some l' ∧ l'.prev = some e ∧ e ≤ k ∧ k < e' ∧ v = .final := by
  cases hce : c.hist e with
  | none => simp [cover, hce] at h
  | some l =>
    cases hce' : c.hist e' with
    | none => simp [cover, hce, hce'] at h
    | some l' =>
      simp only [cover, hce, hce'] at h
      split at h
      · rename_i hc
        exact ⟨⟨l, rfl⟩, l', rfl, hc.1, hc.2.1, hc.2.2, (Option.some.inj h).symm⟩
      · exact absurd h (by simp)

theorem cover_some_none {c : Checkpoint} {e k : Seq} {v : Verdict}
    (h : cover c e k none = some v) :
    (∃ l, c.hist e = some l) ∧ e = c.latest ∧ e ≤ k ∧ v = .provisional := by
  cases hce : c.hist e with
  | none => simp [cover, hce] at h
  | some l =>
    simp only [cover, hce] at h
    split at h
    · rename_i hc
      exact ⟨⟨l, rfl⟩, hc.1, hc.2, (Option.some.inj h).symm⟩
    · exact absurd h (by simp)

theorem cover_succ_final {c : Checkpoint} {e k e' : Seq} {l l' : Leaf}
    (hl : c.hist e = some l) (hl' : c.hist e' = some l') (hp : l'.prev = some e)
    (hek : e ≤ k) (hke : k < e') : cover c e k (some e') = some .final := by
  simp [cover, hl, hl', hp, hek, hke]

theorem cover_none_provisional {c : Checkpoint} {e k : Seq} {l : Leaf}
    (hl : c.hist e = some l) (he : e = c.latest) (hek : e ≤ k) :
    cover c e k none = some .provisional := by
  subst he
  simp [cover, hl, hek]

theorem walkOn_some {p : Params} {env : Env} {c : Checkpoint} {sl : Seal} {w : WalkCore} {v : Verdict}
    (h : walkOn p env c sl w = some v) :
    w.kel.seals[w.idx]? = some sl ∧ ∃ l, c.hist w.e = some l ∧ p.toadFloor ≤ l.toad ∧
      env.signed l.epoch w.kel = true ∧ env.receipted l.epoch w.kel = true ∧
      (w.kel.establishment = true → w.e = w.kel.sn) ∧ cover c w.e w.kel.sn w.succ = some v := by
  cases hce : c.hist w.e with
  | none =>
    simp only [walkOn, hce] at h
    split at h <;> simp at h
  | some l =>
    simp only [walkOn, hce] at h
    split at h
    · simp at h
    · rename_i hs
      split at h
      · simp at h
      · rename_i ht
        split at h
        · simp at h
        · rename_i hsr
          have hsr' : env.signed l.epoch w.kel = true ∧ env.receipted l.epoch w.kel = true := by
            constructor
            · cases hx : env.signed l.epoch w.kel <;> simp_all
            · cases hx : env.receipted l.epoch w.kel <;> simp_all
          split at h
          · rename_i hest
            split at h
            · exact ⟨by simpa using hs, l, rfl, by omega, hsr'.1, hsr'.2, fun _ => ‹_›, h⟩
            · simp at h
          · rename_i hest
            exact ⟨by simpa using hs, l, rfl, by omega, hsr'.1, hsr'.2,
              fun hx => absurd hx (by simpa using hest), h⟩

/-- `walkOn` never reads `cur`: it is a function of the history, the latest
sequence and the evidence. -/
theorem walkOn_setCur (p : Params) (env : Env) (c : Checkpoint) (x : Epoch) (sl : Seal) (w : WalkCore) :
    walkOn p env { c with cur := x } sl w = walkOn p env c sl w := rfl

end CardanoKeri.History
