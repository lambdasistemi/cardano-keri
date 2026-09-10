import CardanoKeri.Statements.History
import CardanoKeri.Statements.HistoryHelpers

/-!
# History and seal-walk statements H1 … H10, S1 … S7

Statements frozen in STATEMENTS mode (2026-09-10, repair 1); proved in
PROOFS mode without change. Each carries, in its docstring, the ruling it
answers to and the single-atom mutant expected to falsify it (the
semantic-atom ledger `STATEMENTS-ATOMS.md` lists them by row).

Every statement is a property of this model. Whether the model is the right
model is settled against `docs/design/credential-verification.md`, #391 and
the KERI superseding rules, not by `lake build`.
-/

namespace CardanoKeri.History

/-- `omega` after unfolding the `Nat` abbreviations, which it does not see
through. -/
macro "omega'" : tactic =>
  `(tactic| ((try dsimp only [Seq, Epoch, Slot, AID, Digest, Said, RegistryId] at *); omega))

/-! ## Well-formedness is preserved -/

theorem WF_inception (aid : AID) (epoch : Epoch) (toad : Nat) (parent : Option AID) (appr : Option Approval) :
    WF (inception aid epoch toad parent appr) where
  inception := ⟨⟨none, epoch, toad⟩, by simp [inception], rfl⟩
  prev_none_at_zero := by
    intro sn l h _; simp only [inception] at h; split at h <;> simp_all
  prev_exists := by
    intro sn l e h hp; simp only [inception] at h; split at h
    · cases Option.some.inj h; simp at hp
    · simp at h
  contiguous := by
    intro sn l e h hp m _ _; simp only [inception] at h; split at h
    · cases Option.some.inj h; simp at hp
    · simp at h
  bounded := by
    intro sn l h; simp only [inception] at h; split at h
    · rename_i hsn; simp [inception, hsn]
    · simp at h
  latest_current := ⟨⟨none, epoch, toad⟩, by simp [inception], rfl⟩
  epoch_monotone := by
    intro sn sn' l l' h h' hlt; simp only [inception] at h h'
    split at h <;> split at h'
    · omega'
    · simp at h'
    · simp at h
    · simp at h

/-- Every leaf's key state is at most the current one. -/
theorem epoch_le_cur {c : Checkpoint} (hwf : WF c) {sn : Seq} {l : Leaf} (h : c.hist sn = some l) :
    l.epoch ≤ c.cur := by
  obtain ⟨ll, hll, hle⟩ := hwf.latest_current
  rcases Nat.lt_trichotomy sn c.latest with hlt | heq | hgt
  · have := hwf.epoch_monotone sn c.latest l ll h hll hlt; omega'
  · subst heq; rw [h] at hll; cases Option.some.inj hll; omega'
  · have := hwf.bounded sn l h; omega'

theorem WF_advanced {c : Checkpoint} (hwf : WF c) {n : Seq} (hlt : c.latest < n) (t : Nat)
    (appr : Option Approval) : WF (advanced c n t appr) where
  inception := by
    obtain ⟨l, hl, hp⟩ := hwf.inception
    exact ⟨l, by simp only [advanced]; rw [if_neg (by omega')]; exact hl, hp⟩
  prev_none_at_zero := by
    intro sn l h hp; simp only [advanced] at h; split at h
    · cases Option.some.inj h; simp at hp
    · exact hwf.prev_none_at_zero sn l h hp
  prev_exists := by
    intro sn l e h hp; simp only [advanced] at h ⊢; split at h
    · rename_i hsn; cases Option.some.inj h; cases Option.some.inj hp
      obtain ⟨ll, hll, _⟩ := hwf.latest_current
      exact ⟨by omega', ll, by rw [if_neg (by omega')]; exact hll⟩
    · obtain ⟨hes, l', hl'⟩ := hwf.prev_exists sn l e h hp
      have := hwf.bounded sn l h
      exact ⟨hes, l', by rw [if_neg (by omega')]; exact hl'⟩
  contiguous := by
    intro sn l e h hp m hem hms; simp only [advanced] at h ⊢; split at h
    · rename_i hsn; cases Option.some.inj h; cases Option.some.inj hp
      rw [if_neg (by omega')]
      cases hm : c.hist m with
      | none => rfl
      | some lm => have := hwf.bounded m lm hm; omega'
    · have := hwf.bounded sn l h
      rw [if_neg (by omega')]
      exact hwf.contiguous sn l e h hp m hem hms
  bounded := by
    intro sn l h; simp only [advanced] at h ⊢; split at h
    · omega'
    · have := hwf.bounded sn l h; omega'
  latest_current := ⟨⟨some c.latest, c.cur + 1, t⟩, by simp [advanced], rfl⟩
  epoch_monotone := by
    intro sn sn' l l' h h' hlt'; simp only [advanced] at h h' ⊢
    split at h <;> split at h'
    · omega'
    · have := hwf.bounded sn' l' h'; omega'
    · cases Option.some.inj h'; have := epoch_le_cur hwf h; simp; omega'
    · exact hwf.epoch_monotone sn sn' l l' h h' hlt'

theorem WF_superseded {c : Checkpoint} (hwf : WF c) {l : Leaf} (hl : c.hist c.latest = some l) (t : Nat)
    (appr : Approval) : WF (superseded c l c.latest t appr) where
  inception := by
    obtain ⟨l0, hl0, hp0⟩ := hwf.inception
    by_cases h0 : c.latest = 0
    · refine ⟨⟨l.prev, c.cur + 1, t⟩, by simp [superseded, h0], ?_⟩
      rw [h0] at hl; rw [hl] at hl0; cases Option.some.inj hl0; exact hp0
    · exact ⟨l0, by simp only [superseded]; rw [if_neg (Ne.symm h0)]; exact hl0, hp0⟩
  prev_none_at_zero := by
    intro sn l' h hp; simp only [superseded] at h; split at h
    · rename_i hsn; cases Option.some.inj h; subst hsn
      exact hwf.prev_none_at_zero c.latest l hl hp
    · exact hwf.prev_none_at_zero sn l' h hp
  prev_exists := by
    intro sn l' e h hp; simp only [superseded] at h ⊢; split at h
    · rename_i hsn; cases Option.some.inj h; subst hsn
      obtain ⟨hes, le, hle⟩ := hwf.prev_exists c.latest l e hl hp
      exact ⟨hes, le, by rw [if_neg (by omega')]; exact hle⟩
    · obtain ⟨hes, le, hle⟩ := hwf.prev_exists sn l' e h hp
      have := hwf.bounded sn l' h
      exact ⟨hes, le, by rw [if_neg (by omega')]; exact hle⟩
  contiguous := by
    intro sn l' e h hp m hem hms; simp only [superseded] at h ⊢; split at h
    · rename_i hsn; cases Option.some.inj h; subst hsn
      rw [if_neg (by omega')]
      exact hwf.contiguous c.latest l e hl hp m hem hms
    · have := hwf.bounded sn l' h
      rw [if_neg (by omega')]
      exact hwf.contiguous sn l' e h hp m hem hms
  bounded := by
    intro sn l' h; simp only [superseded] at h ⊢; split at h
    · omega'
    · exact hwf.bounded sn l' h
  latest_current := ⟨⟨l.prev, c.cur + 1, t⟩, by simp [superseded], rfl⟩
  epoch_monotone := by
    intro sn sn' l1 l2 h h' hlt'; simp only [superseded] at h h' ⊢
    obtain ⟨ll, hll, hle⟩ := hwf.latest_current
    rw [hl] at hll; cases Option.some.inj hll
    split at h <;> split at h'
    · omega'
    · have := hwf.bounded sn' l2 h'; omega'
    · rename_i hsn hsn'; cases Option.some.inj h'; subst hsn'
      have := hwf.epoch_monotone sn c.latest l1 l h hl hlt'; simp; omega'
    · exact hwf.epoch_monotone sn sn' l1 l2 h h' hlt'

/-! ## The history accumulator -/

/-- **H1.** Well-formedness is what registration creates and every history
step preserves. Mutant: `advance` that forgets the back-pointer
(`prev := none`), or `supersede` that moves the back-pointer. -/
theorem H1_wf_reachable {c : Checkpoint} (h : HReach c) : WF c := by
  induction h with
  | init aid epoch toad parent appr => exact WF_inception aid epoch toad parent appr
  | @step c c' a _ hs ih =>
    cases a with
      | advance n t appr =>
      obtain ⟨hlt, rfl⟩ := advance_some hs
      exact WF_advanced ih hlt t appr
      | supersede n t appr =>
      obtain ⟨par, l, a, hpar, hl, ha, rfl, hb, rfl⟩ := supersede_some hs
      exact WF_superseded ih hl t appr

/-- **H2. The range proof is sound.** On a well-formed history, whatever
`cover` accepts is the greatest establishment at or below `k`: nothing
rotated between `e` and `k`. This is the whole point of the back-pointer
(#391: "two exact lookups and two integer comparisons"). Mutant: drop
`k < e'` from `cover`. -/
theorem H2_cover_sound {c : Checkpoint} (hwf : WF c) {e k : Seq} {succ : Option Seq} {v : Verdict}
    (h : cover c e k succ = some v) : Governs c e k := by
  cases succ with
  | none =>
    obtain ⟨hl, he, hek, _⟩ := cover_some_none h
    refine ⟨hl, hek, fun m hem hmk => ?_⟩
    cases hm : c.hist m with
    | none => rfl
    | some lm => have := hwf.bounded m lm hm; omega'
  | some e' =>
    obtain ⟨hl, l', hl', hp, hek, hke, _⟩ := cover_some_succ h
    exact ⟨hl, hek, fun m hem hmk => hwf.contiguous e' l' e hl' hp m hem (by omega')⟩

/-- On a well-formed history every leaf below some later leaf has a
successor leaf pointing back at it. -/
theorem successor_exists {c : Checkpoint} (hwf : WF c) {e : Seq} {l : Leaf} (hl : c.hist e = some l) :
    ∀ n sn (l'' : Leaf), sn ≤ n → c.hist sn = some l'' → e < sn →
      ∃ e' l', c.hist e' = some l' ∧ l'.prev = some e ∧ e' ≤ sn := by
  intro n
  induction n with
  | zero => intro sn _ hsn _ hlt; simp at hsn; omega'
  | succ n ih =>
    intro sn l'' hsnn hsn hlt
    cases hp : l''.prev with
    | none => have := hwf.prev_none_at_zero sn l'' hsn hp; omega'
    | some p =>
      obtain ⟨hps, lp, hlp⟩ := hwf.prev_exists sn l'' p hsn hp
      rcases Nat.lt_trichotomy p e with hpe | rfl | hep
      · have := hwf.contiguous sn l'' p hsn hp e hpe hlt
        rw [this] at hl; exact absurd hl (by simp)
      · exact ⟨sn, l'', hsn, hp, Nat.le_refl _⟩
      · obtain ⟨e', l', h1, h2, h3⟩ := ih p lp (by omega') hlp hep
        exact ⟨e', l', h1, h2, by omega'⟩

/-- **H3. The range proof is complete.** Every governing leaf has a range
proof: the successor leaf when one exists, nothing when `e` is the latest.
Mutant: `cover` that refuses `succ = none`. -/
theorem H3_cover_complete {c : Checkpoint} (hwf : WF c) {e k : Seq} (hg : Governs c e k) :
    ∃ succ v, cover c e k succ = some v := by
  obtain ⟨⟨l, hl⟩, hek, hnone⟩ := hg
  by_cases he : e = c.latest
  · exact ⟨none, .provisional, cover_none_provisional hl he hek⟩
  · have hlt : e < c.latest := by have := hwf.bounded e l hl; omega'
    obtain ⟨ll, hll, _⟩ := hwf.latest_current
    obtain ⟨e', l', hl', hp, _⟩ := successor_exists hwf hl c.latest c.latest ll (Nat.le_refl _) hll hlt
    have hee' : e < e' := (hwf.prev_exists e' l' e hl' hp).1
    have hke' : k < e' := by
      rcases Nat.lt_or_ge k e' with hk | hk
      · exact hk
      · have := hnone e' hee' hk
        rw [this] at hl'; exact absurd hl' (by simp)
    exact ⟨some e', .final, cover_succ_final hl hl' hp hek hke'⟩

/-- **H4. Provisional means exactly "the latest leaf".** A walk is
provisional iff it rests on the latest establishment event with no
successor, and final iff a successor leaf closes the range. Mutant:
`cover` returning `final` on `succ = none`. -/
theorem H4_provisional_iff_latest {c : Checkpoint} (hwf : WF c) {e k : Seq} {succ : Option Seq} :
    cover c e k succ = some .provisional ↔
      succ = none ∧ e = c.latest ∧ e ≤ k ∧ ∃ l, c.hist e = some l := by
  constructor
  · intro h
    cases succ with
    | none =>
      obtain ⟨hl, he, hek, _⟩ := cover_some_none h
      exact ⟨rfl, he, hek, hl⟩
    | some e' =>
      obtain ⟨_, _, _, _, _, _, hv⟩ := cover_some_succ h
      exact absurd hv (by simp)
  · rintro ⟨rfl, he, hek, l, hl⟩
    exact cover_none_provisional hl he hek

/-- **H5. A final verdict is stable under every later history step.** An
interaction event before a later rotation can no longer be superseded
(design: "its admission is final"). Mutant: `supersede` that touches a
non-latest leaf. -/
theorem H5_final_is_stable {c c' : Checkpoint} (hwf : WF c) {a : HAction} (hs : hstep c a = some c')
    {e k : Seq} {succ : Option Seq} (h : cover c e k succ = some .final) :
    cover c' e k succ = some .final := by
  cases succ with
  | none =>
    obtain ⟨_, _, _, hv⟩ := cover_some_none h
    exact absurd hv (by simp)
  | some e' =>
    obtain ⟨⟨l, hl⟩, l', hl', hp, hek, hke, _⟩ := cover_some_succ h
    have hee' : e < e' := (hwf.prev_exists e' l' e hl' hp).1
    have he'b := hwf.bounded e' l' hl'
    cases a with
      | advance n t appr =>
      obtain ⟨hlt, rfl⟩ := advance_some hs
      refine cover_succ_final (l := l) (l' := l') ?_ ?_ hp hek hke
      · simp only [advanced]; rw [if_neg (by omega')]; exact hl
      · simp only [advanced]; rw [if_neg (by omega')]; exact hl'
      | supersede n t appr =>
      obtain ⟨par, l0, a0, hpar, hl0, ha, rfl, hb, rfl⟩ := supersede_some hs
      by_cases he' : e' = c.latest
      · subst he'
        have hl0l' : l0 = l' := by rw [hl0] at hl'; exact Option.some.inj hl'
        refine cover_succ_final (l := l) (l' := ⟨l0.prev, c.cur + 1, t⟩) ?_ ?_ (by simp [hl0l', hp]) hek hke
        · simp only [superseded]; rw [if_neg (by omega')]; exact hl
        · simp [superseded]
      · refine cover_succ_final (l := l) (l' := l') ?_ ?_ hp hek hke
        · simp only [superseded]; rw [if_neg (by omega')]; exact hl
        · simp only [superseded]; rw [if_neg he']; exact hl'

/-- **H6. A superseding rotation at or below `k` shunts the event.** A
provisional verdict for `k` is withdrawn, under every range proof, by an
advance to `e'` with `e' ≤ k` (KERI rule A0: the superseded interaction
and its successors sit on the disputed branch). Mutant: `cover` with
`k ≤ e'` instead of `k < e'`. -/
theorem H6_superseding_excludes {c c' : Checkpoint} (hwf : WF c) {e k e' : Seq} {t : Nat}
    {appr : Option Approval} (h : cover c e k none = some .provisional)
    (hs : advance c e' t appr = some c') (hle : e' ≤ k) :
    ∀ succ, cover c' e k succ = none := by
  obtain ⟨⟨l, hl⟩, he, hek, _⟩ := cover_some_none h
  obtain ⟨hlt, rfl⟩ := advance_some hs
  intro succ
  cases succ with
  | none =>
    cases hv : cover (advanced c e' t appr) e k none with
    | none => rfl
    | some v =>
      obtain ⟨_, he2, _, _⟩ := cover_some_none hv
      simp only [advanced] at he2; omega'
  | some x =>
    cases hv : cover (advanced c e' t appr) e k (some x) with
    | none => rfl
    | some v =>
      obtain ⟨_, l', hl', hp, _, hkx, _⟩ := cover_some_succ hv
      simp only [advanced] at hl'
      split at hl'
      · omega'
      · have := hwf.bounded x l' hl'
        have := (hwf.prev_exists x l' e hl' hp).1
        omega'

/-- **H7. A later rotation makes the provisional verdict final.** An advance
to `e' > k` closes the range and the same leaf now governs `k` finally,
with the new leaf as the successor proof. Mutant: `advance` that inserts
the new leaf with the wrong back-pointer. -/
theorem H7_provisional_becomes_final {c c' : Checkpoint} (hwf : WF c) {e k e' : Seq} {t : Nat}
    {appr : Option Approval} (h : cover c e k none = some .provisional)
    (hs : advance c e' t appr = some c') (hlt : k < e') :
    cover c' e k (some e') = some .final := by
  obtain ⟨⟨l, hl⟩, he, hek, _⟩ := cover_some_none h
  obtain ⟨hlt', rfl⟩ := advance_some hs
  refine cover_succ_final (l := l) (l' := ⟨some c.latest, c.cur + 1, t⟩) ?_ ?_ (by simp [he]) hek hlt
  · simp only [advanced]; rw [if_neg (by omega')]; exact hl
  · simp [advanced]

/-- **H8. A non-delegated history is insert-only** (KERI rule A1): no step
of a well-formed non-delegated checkpoint changes or removes an existing
leaf. Well-formedness is needed: with `latest = 0` and a stray leaf at 1,
`advance 1` would overwrite it. Mutant: `supersede` without the `parent`
guard. -/
theorem H8_non_delegated_insert_only {c c' : Checkpoint} (hwf : WF c) (hnd : c.parent = none)
    {a : HAction} (hs : hstep c a = some c') {sn : Seq} {l : Leaf} (h : c.hist sn = some l) :
    c'.hist sn = some l := by
  cases a with
  | advance n t appr =>
    obtain ⟨hlt, rfl⟩ := advance_some hs
    have := hwf.bounded sn l h
    simp only [advanced]; rw [if_neg (by omega')]; exact h
  | supersede n t appr =>
    obtain ⟨par, _, _, hpar, _⟩ := supersede_some hs
    rw [hnd] at hpar; exact absurd hpar (by simp)

/-- **H9. Superseding touches only the latest leaf of a delegated identity,
keeps its back-pointer, installs a strictly later approval and changes
nothing else** (KERI rules B and B2; #391's "one case that uses a trie
update"). Mutant: `supersede` accepting `sn' ≠ latest`. -/
theorem H9_supersede_only_latest {c c' : Checkpoint} {sn' : Seq} {t : Nat} {appr : Approval}
    (hs : supersede c sn' t appr = some c') :
    (∃ par, c.parent = some par) ∧ sn' = c.latest ∧ c'.latest = c.latest ∧ c'.parent = c.parent ∧
      (∀ sn, sn ≠ c.latest → c'.hist sn = c.hist sn) ∧
      (∃ l l', c.hist c.latest = some l ∧ c'.hist c.latest = some l' ∧ l'.prev = l.prev ∧ l'.epoch = c.cur + 1) ∧
      (∃ a, c.approval = some a ∧ a.before appr) ∧ c'.approval = some appr := by
  obtain ⟨par, l, a, hpar, hl, ha, rfl, hb, rfl⟩ := supersede_some hs
  refine ⟨⟨par, hpar⟩, rfl, rfl, rfl, fun sn hsn => ?_,
    ⟨l, ⟨l.prev, c.cur + 1, t⟩, hl, ?_, rfl, rfl⟩, ⟨a, ha, hb⟩, rfl⟩
  · simp only [superseded]; rw [if_neg hsn]
  · simp [superseded]

/-- **H10. An older approval cannot supersede** (KERI rule B2: the position
of the seal decides which of two competing delegated rotations wins). A
rotation whose approval sits at or before the one that installed the
latest leaf is refused, whatever else it presents. Mutant: drop
`a.before appr` from `supersede`. -/
theorem H10_older_approval_cannot_supersede {c : Checkpoint} {a : Approval} (ha : c.approval = some a)
    {appr : Approval} (hnot : ¬ a.before appr) (sn' : Seq) (t : Nat) :
    supersede c sn' t appr = none := by
  simp only [supersede]
  split
  · rename_i par l a' hpar hl ha'
    rw [ha] at ha'
    cases Option.some.inj ha'
    rw [if_neg (fun hc => hnot hc.2)]
  · rfl

/-! ## The seal walk -/

/-- **S1. The walk needs the historical keys and witnesses.** A successful
walk rests on an existing leaf, at or above the toad floor, whose keys
signed and whose witnesses receipted the sealing event. Mutant: drop the
`receipted` conjunct (the hash-chain-free branch binding of #391). -/
theorem S1_walk_needs_leaf_signature_and_receipts (p : Params) (env : Env) {c : Checkpoint} {sl : Seal}
    {w : WalkCore} {v : Verdict} (h : walkOn p env c sl w = some v) :
    ∃ l, c.hist w.e = some l ∧ p.toadFloor ≤ l.toad ∧
      env.signed l.epoch w.kel = true ∧ env.receipted l.epoch w.kel = true := by
  obtain ⟨_, l, hl, ht, hs, hr, _, _⟩ := walkOn_some h
  exact ⟨l, hl, ht, hs, hr⟩

/-- **S2. The walk binds the sealed thing at its position.** The seal at the
named index is exactly the seal of the sealed thing; for a TEL event, the
event also names the registry. A genuine event of the issuer cannot be
presented for a thing it never sealed (#391's "without every link").
Mutant: compare `seal.i` only. -/
theorem S2_walk_binds_seal_at_index (p : Params) (env : TelEnv) {c : Checkpoint} {rid : RegistryId}
    {w : Walk} {v : Verdict} (h : sealWalk p env c rid w = some v) :
    w.core.kel.seals[w.core.idx]? = some (w.tel.sealOf env.digest) ∧ w.tel.ri = rid := by
  simp only [sealWalk] at h
  split at h
  · simp at h
  · rename_i hri
    exact ⟨(walkOn_some h).1, (by simpa using hri : w.tel.ri = rid ∧ w.tel.wellFormed = true).1⟩

/-- **S3. The walk never reads the current keys.** Historical issuance and
current control are answered by the same reference input but the walk is
invariant under the current key state (design: "the current keys in a
checkpoint say nothing about history"). Mutant: `walkOn` that checks
`env.signed c.cur` instead of the leaf's epoch. -/
theorem S3_walk_ignores_current_keys (p : Params) (env : Env) (c : Checkpoint) (x : Epoch) (sl : Seal)
    (w : WalkCore) :
    walkOn p env { c with cur := x } sl w = walkOn p env c sl w := by
  exact walkOn_setCur p env c x sl w

/-- **S4. A thief of the current keys gets at most a provisional verdict.**
If signatures verify only under the current key state, every successful
walk is provisional, and H6 says the owner's next rotation withdraws it
(design: "stolen-current-key `ixn` issuing fake creds is killed by owner
rotation"). Mutant: `cover` returning `final` for the latest leaf. -/
theorem S4_current_key_thief_only_provisional (p : Params) (env : Env) {c : Checkpoint} (hwf : WF c)
    (hthief : ∀ ep ev, env.signed ep ev = true → ep = c.cur)
    {sl : Seal} {w : WalkCore} {v : Verdict} (h : walkOn p env c sl w = some v) :
    v = .provisional := by
  obtain ⟨_, l, hl, _, hs, _, _, hc⟩ := walkOn_some h
  have hep : l.epoch = c.cur := hthief _ _ hs
  obtain ⟨ll, hll, hlle⟩ := hwf.latest_current
  have he : w.e = c.latest := by
    rcases Nat.lt_trichotomy w.e c.latest with hlt | heq | hgt
    · have := hwf.epoch_monotone w.e c.latest l ll hl hll hlt; omega'
    · exact heq
    · have := hwf.bounded w.e l hl; omega'
  cases hsucc : w.succ with
  | none => rw [hsucc] at hc; exact (cover_some_none hc).2.2.2
  | some e' =>
    rw [hsucc] at hc
    obtain ⟨_, l', hl', hp, _, _, _⟩ := cover_some_succ hc
    have := (hwf.prev_exists e' l' w.e hl' hp).1
    have := hwf.bounded e' l' hl'
    omega'

/-- **S5. The walk's verdict is the range proof's verdict.** Final iff a
successor leaf closed the range; provisional iff the covering leaf is the
latest. Mutant: `walkOn` returning a constant verdict. -/
theorem S5_walk_verdict_is_cover_verdict (p : Params) (env : Env) {c : Checkpoint} {sl : Seal}
    {w : WalkCore} {v : Verdict} (h : walkOn p env c sl w = some v) :
    cover c w.e w.kel.sn w.succ = some v := by
  obtain ⟨_, _, _, _, _, _, _, hc⟩ := walkOn_some h
  exact hc

/-- **S6. One seal, one TEL event.** With a collision-resistant digest, two
successful walks through the same seal position of the same sealing event
name the same TEL event. Stated with injectivity as a hypothesis, not a
fact of the model. Mutant: `sealOf` that omits the digest. -/
theorem S6_seal_names_one_event (p : Params) (env : TelEnv) (hinj : Function.Injective env.digest)
    {c c' : Checkpoint} {rid rid' : RegistryId} {w w' : Walk} {v v' : Verdict}
    (h : sealWalk p env c rid w = some v) (h' : sealWalk p env c' rid' w' = some v')
    (hkel : w.core.kel = w'.core.kel) (hidx : w.core.idx = w'.core.idx) :
    w.tel = w'.tel := by
  have h1 := S2_walk_binds_seal_at_index p env h
  have h2 := S2_walk_binds_seal_at_index p env h'
  rw [hkel, hidx, h2.1] at h1
  have := Option.some.inj h1.1
  simp only [TelEvent.sealOf, Seal.mk.injEq] at this
  exact (hinj this.2.2).symm

/-- **S7. An establishment event is its own leaf.** When the sealing event
is a `rot` (an establishment-only registry), the covering leaf is the event
itself. Mutant: drop the `w.e = w.kel.sn` guard. -/
theorem S7_establishment_seal_is_own_leaf (p : Params) (env : Env) {c : Checkpoint} {sl : Seal}
    {w : WalkCore} {v : Verdict} (hest : w.kel.establishment = true)
    (h : walkOn p env c sl w = some v) :
    w.e = w.kel.sn := by
  obtain ⟨_, _, _, _, _, _, hest', _⟩ := walkOn_some h
  exact hest' hest

/-- **S8. The walk accepts only well-formed TEL events** (#392: `vcp` and
`iss` at sequence 0, `rev` at 1, a `vcp` naming itself as registry). A
hash and a signature do not establish event-shape validity. Mutant: drop
`wellFormed` from `sealWalk`. -/
theorem S8_walk_needs_well_formed_event (p : Params) (env : TelEnv) {c : Checkpoint} {rid : RegistryId}
    {w : Walk} {v : Verdict} (h : sealWalk p env c rid w = some v) :
    w.tel.wellFormed = true := by
  simp only [sealWalk] at h
  split at h
  · simp at h
  · rename_i hri
    exact (by simpa using hri : w.tel.ri = rid ∧ w.tel.wellFormed = true).2

/-! ## Anchors -/

/-- **H11. A final anchor stands for ever.** Whatever the history does
next, the anchor of a final walk still stands with the same range proof
(H5 restated for consumers that outlive the walk). Mutant: `supersede`
touching a non-latest leaf. -/
theorem H11_final_anchor_stands {c c' : Checkpoint} (hwf : WF c) {a : HAction} (hs : hstep c a = some c')
    {an : Anchor} (hfin : an.verdict = .final) {proof : Option Seq} (h : an.stands c proof = true)
    (hp : proof ≠ none) :
    an.stands c' proof = true := by
  sorry

/-- **H12. Moved evidence refutes every proof of standing.** If the evictor
can show the anchor moved — the covering leaf's key state changed, or a
leaf sits in `(e, k]` — then no range proof makes the anchor stand: what
evicts a cached admission is exactly what refuses a fresh use of the same
walk. Mutant: `Anchor.moved` accepting a leaf above `k`. -/
theorem H12_moved_refutes_stands {c : Checkpoint} (hwf : WF c) {an : Anchor} {m : Option Seq}
    (h : an.moved c m = true) : ∀ proof, an.stands c proof = false := by
  sorry

end CardanoKeri.History
