import CardanoKeri.Statements.Delegation
import CardanoKeri.Statements.DelegationHelpers

/-!
# Delegation statements D1 … D18

Statements frozen in STATEMENTS mode (2026-09-10, repairs 1–3); proved in
PROOFS mode. Rulings: #292, `docs/design/credential-verification.md`
("Delegation: recursion becomes induction", "Delegation does not touch the
TEL"), the feasibility report under `specs/134-delegated-aids/` (§4.2).
Mutants named per theorem; the ledger is `STATEMENTS-ATOMS.md`.

Repair 3 (invariant review, 2026-09-10): the approval position carries
the parent event's kind (B3: D18), certificates carry their anchor and a
provisional one is re-validated at consumption (D17), installation is
bound to the exact event (D15), a re-minted approval cannot re-install
(D16).

Repair 4 (proof work): D4 takes collision resistance of the event digest
as a hypothesis, as S6 does for the TEL digest. Without it a certificate
named by one event's digest installs another event with the same digest,
and the toad binding fails.
-/

namespace CardanoKeri.Delegation

open CardanoKeri.History

/-- **D1. No cycles.** In a reachable system no identity is its own
ancestor at any depth: a certificate needs the parent's checkpoint before
the child's, and the parent of an AID is fixed at its inception. Mutant:
`registerDelegated` that ignores `known`. -/
theorem D1_no_cycles (p : Params) (env : DEnv) {s : Sys} (h : Reach p env s) (n : Nat) (a : AID) :
    ancestorWithin s n a a = false := by
  have hok := reach_ok h
  obtain ⟨rank, hrank⟩ := hok.ranked
  cases hx : ancestorWithin s n a a with
  | false => rfl
  | true => exact absurd (ancestorWithin_rank hok hrank n a a hx) (Nat.lt_irrefl _)

/-- **D2. Mint, exactly** (public inversion). A certificate is minted iff
the parent's checkpoint is present as a reference input, the approval seal
walks against the parent's history with some verdict, and no token of that
name exists; the certificate records the approval's position (sequence,
event kind, index) and the walk's anchor. No actor, no child check: fail on
the seal, never on the chain. Mutant: `mint` requiring the child's
checkpoint. -/
theorem D2_mint_iff (p : Params) (env : DEnv) (s : Sys) (parent child : AID) (ev : ChildEvent)
    (w : WalkCore) (s' : Sys) :
    stepFn p env s (.mint parent child ev w) = some s' ↔
      ∃ pc v a, s.ckpt parent = some pc ∧ walkOn p env.toEnv pc (approvalSeal env child ev) w = some v ∧
        (∀ c ∈ s.certs, c.named parent child ev.sn (env.eventDigest ev) = false) ∧
        anchorOf pc w v = some a ∧
        s' = { s with certs := ⟨parent, child, ev.sn, env.eventDigest ev,
                                 ⟨w.kel.sn, w.kel.establishment, w.idx⟩, a⟩ :: s.certs } := by
  constructor
  · intro h
    obtain ⟨pc, v, a, hpc, hv, hfresh, ha, rfl⟩ := mint_some h
    exact ⟨pc, v, a, hpc, hv, hfresh, ha, rfl⟩
  · rintro ⟨pc, v, a, hpc, hv, hfresh, ha, rfl⟩
    exact mint_of hpc hv hfresh ha

/-- **D3. Minting spends nothing.** A mint changes no checkpoint and no
delegation record: the parent is read, never spent, so any number of
children record in one block. Mutant: `mint` that advances the parent. -/
theorem D3_mint_spends_nothing (p : Params) (env : DEnv) {s s' : Sys} {parent child : AID}
    {ev : ChildEvent} {w : WalkCore} (hs : stepFn p env s (.mint parent child ev w) = some s') :
    s'.ckpt = s.ckpt ∧ s'.known = s.known := by
  obtain ⟨_, _, _, _, _, _, _, rfl⟩ := mint_some hs
  exact ⟨rfl, rfl⟩

/-- **D4. A delegated leaf exists only because the parent's approval
walked** (recursion becomes induction). Every leaf of a reachable
delegated checkpoint consumed a certificate minted by a seal walk against
the parent's checkpoint at that time, naming that sequence, and the leaf
carries that event's toad. Collision resistance of the event digest is a
hypothesis. Mutant: `advanceDelegated` without `takeCert`. -/
theorem D4_delegated_leaf_needs_approval (p : Params) (env : DEnv)
    (hinj : Function.Injective env.eventDigest) {s : Sys} (h : Reach p env s)
    {child par : AID} {c : Checkpoint} (hc : s.ckpt child = some c) (hpar : c.parent = some par)
    {sn : Seq} {l : Leaf} (hl : c.hist sn = some l) :
    ∃ s₀ s₁ ev w pc v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint par child ev w) = some s₁ ∧
      ReachFrom p env s₁ s ∧ ev.sn = sn ∧ l.toad = ev.toad ∧ s₀.ckpt par = some pc ∧
      walkOn p env.toEnv pc (approvalSeal env child ev) w = some v := by
  refine reach_ind (p := p) (env := env)
    (P := fun s => ∀ child par c sn l, s.ckpt child = some c → c.parent = some par → c.hist sn = some l →
      ∃ s₀ s₁ ev w pc v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint par child ev w) = some s₁ ∧
        ReachFrom p env s₁ s ∧ ev.sn = sn ∧ l.toad = ev.toad ∧ s₀.ckpt par = some pc ∧
        walkOn p env.toEnv pc (approvalSeal env child ev) w = some v)
    (fun _ _ _ _ _ hc => by simp [Sys.init] at hc) (fun s s' a hreach hP hs => ?_) h child par c sn l hc hpar hl
  intro child par c sn l hc hpar hl
  have ext : ∀ child par c sn l, s.ckpt child = some c → c.parent = some par → c.hist sn = some l →
      ∃ s₀ s₁ ev w pc v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint par child ev w) = some s₁ ∧
        ReachFrom p env s₁ s' ∧ ev.sn = sn ∧ l.toad = ev.toad ∧ s₀.ckpt par = some pc ∧
        walkOn p env.toEnv pc (approvalSeal env child ev) w = some v := by
    intro child par c sn l hc hpar hl
    obtain ⟨s₀, s₁, ev, w, pc, v, h1, h2, h3, h4, h5, h6, h7⟩ := hP child par c sn l hc hpar hl
    exact ⟨s₀, s₁, ev, w, pc, v, h1, h2, reachFrom_snoc h3 hs, h4, h5, h6, h7⟩
  -- a consumed certificate's mint, for the event the action carries
  have origin : ∀ (parent : AID) (ev : ChildEvent) (cert : Cert),
      s.certs.find? (fun x => x.named parent child ev.sn (env.eventDigest ev)) = some cert →
      ∃ s₀ s₁ w pc v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint parent child ev w) = some s₁ ∧
        ReachFrom p env s₁ s' ∧ s₀.ckpt parent = some pc ∧
        walkOn p env.toEnv pc (approvalSeal env child ev) w = some v := by
    intro parent ev cert hfind
    have hmem := List.mem_of_find?_eq_some hfind
    have hp : cert.named parent child ev.sn (env.eventDigest ev) = true := List.find?_some (p := fun x : Cert => x.named _ child ev.sn (env.eventDigest ev)) hfind
    obtain ⟨hp1, hp2, hp3, hp4⟩ := (named_iff cert _ _ _ _).1 hp
    obtain ⟨s₀, s₁, ev', w, pc, v, h1, h2, h3, h4, h5, h6, h7⟩ := reach_certOrigin hreach cert hmem
    have hev : ev' = ev := hinj (by rw [h5, hp4])
    subst hev
    rw [hp1, hp2] at h2; rw [hp1] at h6; rw [hp2] at h7
    exact ⟨s₀, s₁, w, pc, v, h1, h2, reachFrom_snoc h3 hs, h6, h7⟩
  cases a with
  | mint parent' child' ev w =>
    obtain ⟨_, _, _, _, _, _, _, rfl⟩ := mint_some hs
    exact ext child par c sn l hc hpar hl
  | registerPlain aid ep t =>
    obtain ⟨_, _, hckpt, _, _, _⟩ := registerPlain_some hs
    rw [hckpt] at hc; simp only [Sys.setCkpt] at hc
    split at hc
    · cases Option.some.inj hc; simp [inception] at hpar
    · exact ext child par c sn l hc hpar hl
  | registerDelegated child' parent ev proof =>
    obtain ⟨_, hsn0, _, cert, hfind, _, rfl⟩ := registerDelegated_some hs
    simp only [Sys.setKnown, Sys.setCkpt] at hc
    split at hc
    · rename_i hx; cases Option.some.inj hc; subst hx
      simp only [inception] at hpar hl
      cases Option.some.inj hpar
      split at hl
      · rename_i hsn; cases Option.some.inj hl; subst hsn
        rw [← hsn0] at hfind
        obtain ⟨s₀, s₁, w, pc, v, h1, h2, h3, h6, h7⟩ := origin par ev cert hfind
        exact ⟨s₀, s₁, ev, w, pc, v, h1, h2, h3, hsn0, rfl, h6, h7⟩
      · simp at hl
    · exact ext child par c sn l hc hpar hl
  | advancePlain aid sn' t =>
    obtain ⟨c₀, c₀', hc₀, hpar₀, ha, rfl⟩ := advancePlain_some hs
    simp only [Sys.setCkpt] at hc
    split at hc
    · rename_i hx; cases Option.some.inj hc; subst hx
      obtain ⟨_, rfl⟩ := advance_some ha
      simp only [advanced] at hpar; rw [hpar₀] at hpar; simp at hpar
    · exact ext child par c sn l hc hpar hl
  | advanceDelegated child' ev proof =>
    obtain ⟨c₀, par₀, cert, c₀', hc₀, hpar₀, hfind, _, ha, rfl⟩ := advanceDelegated_some hs
    simp only [Sys.setCkpt] at hc
    split at hc
    · rename_i hx; cases Option.some.inj hc; subst hx
      obtain ⟨_, rfl⟩ := advance_some ha
      simp only [advanced] at hpar hl
      rw [hpar₀] at hpar; cases Option.some.inj hpar
      split at hl
      · rename_i hsn; cases Option.some.inj hl; subst hsn
        obtain ⟨s₀, s₁, w, pc, v, h1, h2, h3, h6, h7⟩ := origin par ev cert hfind
        exact ⟨s₀, s₁, ev, w, pc, v, h1, h2, h3, rfl, rfl, h6, h7⟩
      · exact ext child par c₀ sn l hc₀ hpar₀ hl
    · exact ext child par c sn l hc hpar hl
  | supersedeDelegated child' ev proof =>
    obtain ⟨c₀, par₀, cert, c₀', hc₀, hpar₀, hfind, _, ha, rfl⟩ := supersedeDelegated_some hs
    simp only [Sys.setCkpt] at hc
    split at hc
    · rename_i hx; cases Option.some.inj hc; subst hx
      obtain ⟨_, l₀, _, _, hl₀, _, hsn, _, rfl⟩ := supersede_some ha
      simp only [superseded] at hpar hl
      rw [hpar₀] at hpar; cases Option.some.inj hpar
      split at hl
      · rename_i hsn'; cases Option.some.inj hl; subst hsn'
        obtain ⟨s₀, s₁, w, pc, v, h1, h2, h3, h6, h7⟩ := origin par ev cert hfind
        exact ⟨s₀, s₁, ev, w, pc, v, h1, h2, h3, rfl, rfl, h6, h7⟩
      · exact ext child par c₀ sn l hc₀ hpar₀ hl
    · exact ext child par c sn l hc hpar hl
  | leave aid =>
    obtain ⟨_, rfl⟩ := leave_some hs
    simp only [Sys.setCkpt] at hc
    split at hc
    · simp at hc
    · exact ext child par c sn l hc hpar hl

/-- **D5. A certificate is consumed once.** After a delegated registration
or rotation, no token of the consumed name remains outstanding. (Global
single use is not claimed: the same approval may be re-minted, and D16
says what a re-mint can and cannot do.) Mutant: `takeCert` that leaves
the token in place. -/
theorem D5_certificate_consumed_once (p : Params) (env : DEnv) {s s' : Sys} (h : Reach p env s) {child : AID}
    {ev : ChildEvent} {pr : Option Seq} {a : Action}
    (ha : a = .advanceDelegated child ev pr ∨ a = .supersedeDelegated child ev pr ∨
      ∃ par, a = .registerDelegated child par ev pr)
    (hs : stepFn p env s a = some s') {c' : Checkpoint} (hc : s'.ckpt child = some c')
    {par : AID} (hpar : c'.parent = some par) :
    ∀ c ∈ s'.certs, c.named par child ev.sn (env.eventDigest ev) = false := by
  have hnames := (reach_ok h).names
  rcases ha with rfl | rfl | ⟨parent, rfl⟩
  · obtain ⟨c₀, par₀, cert, c₀', hc₀, hpar₀, hfind, _, hadv, rfl⟩ := advanceDelegated_some hs
    simp only [Sys.setCkpt, if_true] at hc
    cases Option.some.inj hc
    obtain ⟨_, rfl⟩ := advance_some hadv
    simp only [advanced] at hpar; rw [hpar₀] at hpar; cases Option.some.inj hpar
    exact eraseP_no_name hnames hfind
  · obtain ⟨c₀, par₀, cert, c₀', hc₀, hpar₀, hfind, _, hsup, rfl⟩ := supersedeDelegated_some hs
    simp only [Sys.setCkpt, if_true] at hc
    cases Option.some.inj hc
    obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := supersede_some hsup
    simp only [superseded] at hpar; rw [hpar₀] at hpar; cases Option.some.inj hpar
    exact eraseP_no_name hnames hfind
  · obtain ⟨_, hsn0, _, cert, hfind, _, rfl⟩ := registerDelegated_some hs
    simp only [Sys.setKnown, Sys.setCkpt, if_true] at hc
    cases Option.some.inj hc
    simp only [inception] at hpar; cases Option.some.inj hpar
    rw [hsn0]
    exact eraseP_no_name hnames hfind

/-- **D6. The ancestry walk reads parent fields only.** Two systems with
the same parent fields answer every ancestry question alike: no signature,
no history, no certificate is consulted. Mutant: `ancestorWithin` that
consults `certs`. -/
theorem D6_ancestry_reads_parents_only (s s' : Sys) (h : s.parents = s'.parents) (n : Nat) (a r : AID) :
    ancestorWithin s n a r = ancestorWithin s' n a r := by
  induction n generalizing a r with
  | zero => rfl
  | succ n ih =>
    have hp := congrFun h a
    simp only [Sys.parents] at hp
    simp only [ancestorWithin]
    cases hc : s.ckpt a with
    | none =>
      cases hc' : s'.ckpt a with
      | none => rfl
      | some c' => rw [hc, hc'] at hp; simp at hp
    | some c =>
      cases hc' : s'.ckpt a with
      | none => rw [hc, hc'] at hp; simp at hp
      | some c' =>
        rw [hc, hc'] at hp; simp at hp
        show (match c.parent with | none => false | some par => (par == r || ancestorWithin s n par r)) =
          (match c'.parent with | none => false | some par => (par == r || ancestorWithin s' n par r))
        rw [hp]
        cases c'.parent with
        | none => rfl
        | some par =>
          show (par == r || ancestorWithin s n par r) = (par == r || ancestorWithin s' n par r)
          rw [ih]

/-- **D7. Depth is the consumer's.** More generations never lose an
ancestor: a consumer picks its bound, and unbounded depth cannot stall it
because the walk is structural in the bound. Mutant: `ancestorWithin`
that refuses at exactly `n`. -/
theorem D7_depth_is_the_consumers (s : Sys) (n : Nat) (a r : AID) (h : ancestorWithin s n a r = true) :
    ancestorWithin s (n + 1) a r = true := by
  induction n generalizing a r with
  | zero => simp [ancestorWithin] at h
  | succ n ih =>
    simp only [ancestorWithin] at h ⊢
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i par hpar
        simp only [Bool.or_eq_true, beq_iff_eq] at h ⊢
        rcases h with h | h
        · exact Or.inl h
        · exact Or.inr (ih par r h)

/-- **D8. The seal's position binds** (KERI rules B1–B3). A minted
certificate records the exact position of the approval seal: the parent
event's sequence, whether it is a rotation, and the index; a seal for the
same child elsewhere does not mint at that position. Mutant: `walkOn`
searching the seal list. -/
theorem D8_seal_position_binds (p : Params) (env : DEnv) {s s' : Sys} {parent child : AID}
    {ev : ChildEvent} {w : WalkCore} (hs : stepFn p env s (.mint parent child ev w) = some s') :
    w.kel.seals[w.idx]? = some (approvalSeal env child ev) ∧
      ∃ c ∈ s'.certs, c.named parent child ev.sn (env.eventDigest ev) = true ∧
        c.approval = ⟨w.kel.sn, w.kel.establishment, w.idx⟩ := by
  obtain ⟨pc, v, a, hpc, hv, hfresh, ha, rfl⟩ := mint_some hs
  refine ⟨(walkOn_some hv).1, _, List.mem_cons_self .., ?_, rfl⟩
  simp [Cert.named]

/-- **D9. A parent that left the chain blocks new approvals and stops the
walk, but its children stand.** No mint against an absent parent; leaving
changes no other checkpoint; the ancestry walk through the absent parent
reaches only the parent itself. Mutant: `leave` that cascades to
children. -/
theorem D9_absent_parent (p : Params) (env : DEnv) (s : Sys) (par : AID) (hpar : s.ckpt par = none) :
    (∀ child ev w, stepFn p env s (.mint par child ev w) = none) ∧
      (∀ s' a, stepFn p env s (.leave a) = some s' → ∀ b, b ≠ a → s'.ckpt b = s.ckpt b) ∧
      (∀ child c n r, s.ckpt child = some c → c.parent = some par →
        ancestorWithin s (n + 1) child r = (par == r)) := by
  refine ⟨fun child ev w => by simp [stepFn, hpar], fun s' a hs b hb => ?_, fun child c n r hc hcp => ?_⟩
  · obtain ⟨_, rfl⟩ := leave_some hs
    simp [Sys.setCkpt, hb]
  · simp only [ancestorWithin, hc, hcp, ancestorWithin_absent hpar, Bool.or_false]

/-- **D10. Delegation does not touch the TEL.** A delegated issuer's seal
walk is the same whether or not its parent is on chain: it runs against
the issuer's own checkpoint, whose leaf already embodies the approval.
Mutant: `issuerWalk` that requires the parent's checkpoint. -/
theorem D10_delegation_does_not_touch_the_tel (p : Params) (env : DEnv) (tenv : TelEnv) {s s' : Sys}
    {par child : AID} (hne : child ≠ par) (hs : stepFn p env s (.leave par) = some s')
    (rid : RegistryId) (w : Walk) :
    issuerWalk p tenv s' child rid w = issuerWalk p tenv s child rid w := by
  obtain ⟨_, rfl⟩ := leave_some hs
  simp [issuerWalk, Sys.setCkpt, hne]

/-- **D11. Superseding, exactly** (public inversion). A delegated rotation
at the latest sequence replaces the latest leaf iff the child is
delegated, a certificate of that name is present and stands under the
consumer's proof, and the history's `supersede` accepts its approval
position. Mutant: `supersedeDelegated` on a non-delegated child. -/
theorem D11_supersede_iff (p : Params) (env : DEnv) (s : Sys) (child : AID) (ev : ChildEvent)
    (proof : Option Seq) (s' : Sys) :
    stepFn p env s (.supersedeDelegated child ev proof) = some s' ↔
      ∃ c par cert s₁ c', s.ckpt child = some c ∧ c.parent = some par ∧
        s.takeCert par child ev.sn (env.eventDigest ev) = some (cert, s₁) ∧
        s.certStands cert proof = true ∧
        supersede c ev.sn ev.toad cert.approval = some c' ∧ s' = s₁.setCkpt child (some c') := by
  constructor
  · intro h
    obtain ⟨c, par, cert, c', hc, hpar, hfind, hst, hsup, rfl⟩ := supersedeDelegated_some h
    exact ⟨c, par, cert, _, c', hc, hpar, takeCert_of hfind, hst, hsup, rfl⟩
  · rintro ⟨c, par, cert, s₁, c', hc, hpar, htake, hst, hsup, rfl⟩
    simp [stepFn, hc, hpar, htake, hst, hsup]

/-- **D12. A non-delegated history is insert-only at the system level**
(H8 lifted): in a reachable system no action changes an existing leaf of a
checkpoint with no parent. Mutant: `supersedeDelegated` accepting
`parent = none`. -/
theorem D12_plain_insert_only (p : Params) (env : DEnv) {s s' : Sys} (h : Reach p env s) {a : Action}
    (hs : stepFn p env s a = some s') {aid : AID} {c c' : Checkpoint}
    (hc : s.ckpt aid = some c) (hnd : c.parent = none) (hc' : s'.ckpt aid = some c')
    {sn : Seq} {l : Leaf} (hl : c.hist sn = some l) :
    c'.hist sn = some l := by
  have hwf := (reach_ok h).wf aid c hc
  cases a with
  | mint parent child ev w =>
    obtain ⟨_, _, _, _, _, _, _, rfl⟩ := mint_some hs
    simp only at hc'; rw [hc] at hc'; cases Option.some.inj hc'; exact hl
  | registerPlain a ep t =>
    obtain ⟨hnone, _, hckpt, _, _, _⟩ := registerPlain_some hs
    rw [hckpt] at hc'; simp only [Sys.setCkpt] at hc'
    split at hc'
    · rename_i hx; subst hx; rw [hnone] at hc; simp at hc
    · rw [hc] at hc'; cases Option.some.inj hc'; exact hl
  | registerDelegated child parent ev proof =>
    obtain ⟨hnone, _, _, _, _, _, rfl⟩ := registerDelegated_some hs
    simp only [Sys.setKnown, Sys.setCkpt] at hc'
    split at hc'
    · rename_i hx; subst hx; rw [hnone] at hc; simp at hc
    · rw [hc] at hc'; cases Option.some.inj hc'; exact hl
  | advancePlain a sn' t =>
    obtain ⟨c₀, c₀', hc₀, _, hadv, rfl⟩ := advancePlain_some hs
    simp only [Sys.setCkpt] at hc'
    split at hc'
    · rename_i hx; subst hx; rw [hc] at hc₀; cases Option.some.inj hc₀
      cases Option.some.inj hc'
      obtain ⟨hlt, rfl⟩ := advance_some hadv
      have := hwf.bounded sn l hl
      simp only [advanced]; rw [if_neg (by omega')]; exact hl
    · rw [hc] at hc'; cases Option.some.inj hc'; exact hl
  | advanceDelegated child ev proof =>
    obtain ⟨c₀, par, _, _, hc₀, hpar₀, _, _, _, rfl⟩ := advanceDelegated_some hs
    simp only [Sys.setCkpt] at hc'
    split at hc'
    · rename_i hx; subst hx; rw [hc] at hc₀; cases Option.some.inj hc₀
      rw [hnd] at hpar₀; simp at hpar₀
    · rw [hc] at hc'; cases Option.some.inj hc'; exact hl
  | supersedeDelegated child ev proof =>
    obtain ⟨c₀, par, _, _, hc₀, hpar₀, _, _, _, rfl⟩ := supersedeDelegated_some hs
    simp only [Sys.setCkpt] at hc'
    split at hc'
    · rename_i hx; subst hx; rw [hc] at hc₀; cases Option.some.inj hc₀
      rw [hnd] at hpar₀; simp at hpar₀
    · rw [hc] at hc'; cases Option.some.inj hc'; exact hl
  | leave a =>
    obtain ⟨_, rfl⟩ := leave_some hs
    simp only [Sys.setCkpt] at hc'
    split at hc'
    · simp at hc'
    · rw [hc] at hc'; cases Option.some.inj hc'; exact hl

/-- **D13. An overturned approval leaves an installed child standing** (a
witness of the explicit omission of #292, not a guarantee). There is a
reachable system in which a child's leaf consumed a certificate minted
under a provisional walk, the parent has since inserted a leaf at or below
the approving event's sequence — the approval sits on the disputed branch
— and the child's leaf is still there. A bonded challenge for this third
divergence is a later ruling; what a stale certificate can no longer do is
D17. -/
theorem D13_overturned_approval_witness :
    ∃ (p : Params) (env : DEnv) (s₀ s₁ s : Sys) (par child : AID) (ev : ChildEvent) (w : WalkCore)
      (pc pc' c : Checkpoint),
      ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint par child ev w) = some s₁ ∧
      s₀.ckpt par = some pc ∧ walkOn p env.toEnv pc (approvalSeal env child ev) w = some .provisional ∧
      ReachFrom p env s₁ s ∧ s.ckpt child = some c ∧ c.parent = some par ∧ (c.hist ev.sn).isSome ∧
      s.ckpt par = some pc' ∧ ∃ m, w.e < m ∧ m ≤ w.kel.sn ∧ (pc'.hist m).isSome := by
  let p : Params := ⟨0⟩
  let env : DEnv := { signed := fun _ _ => true, receipted := fun _ _ => true, eventDigest := fun ev => ev.nonce }
  let ev : ChildEvent := ⟨0, 0, 7⟩
  let w : WalkCore := ⟨⟨1, false, [⟨20, 0, 7⟩]⟩, 0, none, 0⟩
  let pc : Checkpoint := inception 10 0 0 none none
  let s₀ : Sys := (Sys.init.setCkpt 10 (some pc)).setKnown 10 none
  let cert : Cert := ⟨10, 20, 0, 7, ⟨1, false, 0⟩, ⟨0, 0, 1, .provisional⟩⟩
  let s₁ : Sys := { s₀ with certs := [cert] }
  let c : Checkpoint := inception 20 0 0 (some 10) (some ⟨1, false, 0⟩)
  let s₂ : Sys := (({ s₁ with certs := [] } : Sys).setCkpt 20 (some c)).setKnown 20 (some 10)
  let s₃ : Sys := s₂.setCkpt 10 (some (advanced pc 1 0 none))
  refine ⟨p, env, s₀, s₁, s₃, 10, 20, ev, w, pc, advanced pc 1 0 none, c,
    ReachFrom.step (s' := s₀) (a := .registerPlain 10 0 0) rfl (ReachFrom.refl _),
    rfl, rfl, rfl,
    ReachFrom.step (s' := s₂) (a := .registerDelegated 20 10 ev none) rfl
      (ReachFrom.step (s' := s₃) (a := .advancePlain 10 1 0) rfl (ReachFrom.refl _)),
    rfl, rfl, rfl, rfl, 1, by decide, by decide, rfl⟩

/-- **D14. Superseding needs a strictly later approval** (KERI rules B1,
B2, B3; feasibility report §4.2). The installed leaf remembers the
position of the approval that installed it; a delegated rotation at the
same sequence replaces it only with a certificate whose approval sits
later in the parent's log, and installs that position. A certificate
approved earlier — at parent sequence 2 against a leaf installed at 3 —
is refused. Mutant: `supersedeDelegated` passing a fixed position instead
of the certificate's. -/
theorem D14_supersede_needs_later_approval (p : Params) (env : DEnv) (s : Sys) (child : AID)
    (ev : ChildEvent) (proof : Option Seq) :
    (∀ s', stepFn p env s (.supersedeDelegated child ev proof) = some s' →
      ∃ c par cert a c', s.ckpt child = some c ∧ c.parent = some par ∧ c.approval = some a ∧
        cert ∈ s.certs ∧ cert.named par child ev.sn (env.eventDigest ev) = true ∧
        a.before cert.approval ∧
        s'.ckpt child = some c' ∧ c'.approval = some cert.approval) ∧
    (∀ c par cert a, s.ckpt child = some c → c.parent = some par → c.approval = some a →
      s.certs.find? (fun x => x.named par child ev.sn (env.eventDigest ev)) = some cert →
      ¬ a.before cert.approval →
      stepFn p env s (.supersedeDelegated child ev proof) = none) := by
  constructor
  · intro s' hs
    obtain ⟨c, par, cert, c', hc, hpar, hfind, hst, hsup, rfl⟩ := supersedeDelegated_some hs
    obtain ⟨_, l, a, _, hl, ha, hsn, hb, rfl⟩ := supersede_some hsup
    have hp : cert.named par child ev.sn (env.eventDigest ev) = true := List.find?_some (p := fun x : Cert => x.named _ child ev.sn (env.eventDigest ev)) hfind
    refine ⟨c, par, cert, a, superseded c l ev.sn ev.toad cert.approval, hc, hpar, ha,
      List.mem_of_find?_eq_some hfind, hp, hb, by simp [Sys.setCkpt], rfl⟩
  · intro c par cert a hc hpar ha hfind hnot
    simp only [stepFn, hc, hpar, Sys.takeCert, hfind]
    split
    · rfl
    · rw [H10_older_approval_cannot_supersede ha hnot]; rfl

/-- **D15. Installation is bound to the exact event.** A delegated rotation
that lands installs, at the event's sequence, a leaf pointing back at the
previous latest with the event's toad and the fresh key state, records the
consumed certificate's approval position, and consumed a standing
certificate named by that event's digest. Mutant: `advanceDelegated`
installing a toad other than the event's. -/
theorem D15_installation_binds_event (p : Params) (env : DEnv) {s s' : Sys} {child : AID} {ev : ChildEvent}
    {proof : Option Seq} (hs : stepFn p env s (.advanceDelegated child ev proof) = some s') :
    ∃ c par cert c', s.ckpt child = some c ∧ c.parent = some par ∧
      cert ∈ s.certs ∧ cert.named par child ev.sn (env.eventDigest ev) = true ∧
      s.certStands cert proof = true ∧
      s'.ckpt child = some c' ∧ c'.latest = ev.sn ∧ c'.approval = some cert.approval ∧
      c'.hist ev.sn = some ⟨some c.latest, c.cur + 1, ev.toad⟩ := by
  obtain ⟨c, par, cert, c', hc, hpar, hfind, hst, hadv, rfl⟩ := advanceDelegated_some hs
  obtain ⟨hlt, rfl⟩ := advance_some hadv
  have hp : cert.named par child ev.sn (env.eventDigest ev) = true := List.find?_some (p := fun x : Cert => x.named _ child ev.sn (env.eventDigest ev)) hfind
  refine ⟨c, par, cert, advanced c ev.sn ev.toad (some cert.approval), hc, hpar, List.mem_of_find?_eq_some hfind, hp, hst,
    by simp [Sys.setCkpt], rfl, rfl, by simp [advanced]⟩

theorem Approval.before_irrefl (a : Approval) : ¬ a.before a := by
  simp only [Approval.before]
  intro h
  rcases h with h | ⟨_, h | ⟨_, h⟩⟩
  · exact Nat.lt_irrefl _ h
  · cases a.establishment <;> simp at h
  · exact Nat.lt_irrefl _ h

/-- **D16. A re-minted approval cannot re-install.** Once a certificate has
installed the child's latest leaf, a token of the same name minted again —
the same approval at the same position — neither advances (the sequence is
not later) nor supersedes (the position is not later). Re-minting is
harmless. Mutant: `Approval.before` reflexive. -/
theorem D16_reminted_approval_cannot_reinstall (p : Params) (env : DEnv) (s : Sys) {child par : AID}
    {c : Checkpoint} (hc : s.ckpt child = some c) (hpar : c.parent = some par) {ev : ChildEvent}
    (hlatest : c.latest = ev.sn) {ap : Approval} (hap : c.approval = some ap)
    (hcert : ∀ cert ∈ s.certs, cert.named par child ev.sn (env.eventDigest ev) = true → cert.approval = ap)
    (proof : Option Seq) :
    stepFn p env s (.advanceDelegated child ev proof) = none ∧
      stepFn p env s (.supersedeDelegated child ev proof) = none := by
  constructor
  · cases hs : stepFn p env s (.advanceDelegated child ev proof) with
    | none => rfl
    | some s' =>
      exfalso
      obtain ⟨c₀, par₀, cert, c', hc₀, _, _, _, hadv, _⟩ := advanceDelegated_some hs
      rw [hc] at hc₀; cases Option.some.inj hc₀
      obtain ⟨hlt, _⟩ := advance_some hadv
      omega'
  · cases hs : stepFn p env s (.supersedeDelegated child ev proof) with
    | none => rfl
    | some s' =>
      exfalso
      obtain ⟨c₀, par₀, cert, c', hc₀, hpar₀, hfind, _, hsup, _⟩ := supersedeDelegated_some hs
      rw [hc] at hc₀; cases Option.some.inj hc₀
      rw [hpar] at hpar₀; cases Option.some.inj hpar₀
      obtain ⟨_, _, a, _, _, ha, _, hb, _⟩ := supersede_some hsup
      rw [hap] at ha; cases Option.some.inj ha
      have hp : cert.named par child ev.sn (env.eventDigest ev) = true := List.find?_some (p := fun x : Cert => x.named _ child ev.sn (env.eventDigest ev)) hfind
      have := hcert cert (List.mem_of_find?_eq_some hfind) hp
      rw [this] at hb
      exact Approval.before_irrefl _ hb

/-- **D17. A stale provisional certificate installs nothing.** If the
parent has superseded the approving event — its checkpoint is gone, or the
certificate's anchor has moved by evidence `m` on a well-formed parent
history — then no proof lets the certificate register, advance or
supersede the child: the token is dead (H12). Mutant: consumption that
skips `certStands`. -/
theorem D17_stale_provisional_certificate_refused (p : Params) (env : DEnv) (s : Sys) {child par : AID}
    {ev : ChildEvent} {cert : Cert}
    (hfind : s.certs.find? (fun x => x.named par child ev.sn (env.eventDigest ev)) = some cert)
    (hprov : cert.anchor.verdict = .provisional) (hcp : cert.parent = par)
    (hmoved : s.ckpt par = none ∨
      ∃ pc m, s.ckpt par = some pc ∧ WF pc ∧ cert.anchor.moved pc m = true)
    (proof : Option Seq) :
    stepFn p env s (.registerDelegated child par ev proof) = none ∧
      (∀ c, s.ckpt child = some c → c.parent = some par →
        stepFn p env s (.advanceDelegated child ev proof) = none ∧
        stepFn p env s (.supersedeDelegated child ev proof) = none) := by
  have hstands : s.certStands cert proof = false := by
    simp only [Sys.certStands, hprov, hcp]
    rcases hmoved with h | ⟨pc, m, hpc, hwf, hm⟩
    · rw [h]
    · rw [hpc]; exact H12_moved_refutes_stands hwf hm proof
  constructor
  · cases hs : stepFn p env s (.registerDelegated child par ev proof) with
    | none => rfl
    | some s' =>
      exfalso
      obtain ⟨_, hsn0, _, cert', hfind', hst, _⟩ := registerDelegated_some hs
      rw [hsn0] at hfind
      rw [hfind] at hfind'; cases Option.some.inj hfind'
      rw [hstands] at hst; simp at hst
  · intro c hc hpar
    constructor
    · cases hs : stepFn p env s (.advanceDelegated child ev proof) with
      | none => rfl
      | some s' =>
        exfalso
        obtain ⟨c₀, par₀, cert', _, hc₀, hpar₀, hfind', hst, _, _⟩ := advanceDelegated_some hs
        rw [hc] at hc₀; cases Option.some.inj hc₀
        rw [hpar] at hpar₀; cases Option.some.inj hpar₀
        rw [hfind] at hfind'; cases Option.some.inj hfind'
        rw [hstands] at hst; simp at hst
    · cases hs : stepFn p env s (.supersedeDelegated child ev proof) with
      | none => rfl
      | some s' =>
        exfalso
        obtain ⟨c₀, par₀, cert', _, hc₀, hpar₀, hfind', hst, _, _⟩ := supersedeDelegated_some hs
        rw [hc] at hc₀; cases Option.some.inj hc₀
        rw [hpar] at hpar₀; cases Option.some.inj hpar₀
        rw [hfind] at hfind'; cases Option.some.inj hfind'
        rw [hstands] at hst; simp at hst

/-- **D18. A rotation supersedes an interaction at the same sequence, and
never the reverse** (KERI rules B3 and A2). A leaf installed by an
approval in a parent interaction at sequence `n` is replaced by a standing
certificate approved in the parent's rotation at `n`, at any seal index;
a leaf installed by an approval in a rotation is never replaced by one in
an interaction at the same sequence. Mutant: `Approval.before` comparing
indices only. -/
theorem D18_rotation_supersedes_interaction (p : Params) (env : DEnv) (s : Sys) {child par : AID}
    {c : Checkpoint} (hc : s.ckpt child = some c) (hpar : c.parent = some par) {l : Leaf}
    (hl : c.hist c.latest = some l) {ev : ChildEvent} (hsn : ev.sn = c.latest) {cert : Cert}
    (hfind : s.certs.find? (fun x => x.named par child ev.sn (env.eventDigest ev)) = some cert)
    (proof : Option Seq) (hstands : s.certStands cert proof = true) (n : Seq) (i j : Nat) :
    (c.approval = some ⟨n, false, i⟩ → cert.approval = ⟨n, true, j⟩ →
      ∃ s', stepFn p env s (.supersedeDelegated child ev proof) = some s') ∧
    (c.approval = some ⟨n, true, i⟩ → cert.approval = ⟨n, false, j⟩ →
      stepFn p env s (.supersedeDelegated child ev proof) = none) := by
  constructor
  · intro ha hca
    have hsup : supersede c ev.sn ev.toad cert.approval = some (superseded c l ev.sn ev.toad cert.approval) := by
      simp only [supersede, hpar, hl, ha]
      rw [if_pos ⟨hsn, by rw [hca]; simp [Approval.before]⟩]
      simp [superseded, hpar]
    exact ⟨_, (D11_supersede_iff p env s child ev proof _).2
      ⟨c, par, cert, _, _, hc, hpar, takeCert_of hfind, hstands, hsup, rfl⟩⟩
  · intro ha hca
    simp only [stepFn, hc, hpar, Sys.takeCert, hfind]
    split
    · rfl
    · rw [H10_older_approval_cannot_supersede ha (by rw [hca]; simp [Approval.before])]; rfl

end CardanoKeri.Delegation
