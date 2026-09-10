import CardanoKeri.Statements.Delegation

/-!
# Delegation statements D1 … D14 — unproven

STATEMENTS mode: every theorem ends in `sorry`. Rulings: #292,
`docs/design/credential-verification.md` ("Delegation: recursion becomes
induction", "Delegation does not touch the TEL"), the feasibility report
under `specs/134-delegated-aids/`. Mutants named per theorem; the ledger
is `STATEMENTS-ATOMS.md`.
-/

namespace CardanoKeri.Delegation

open CardanoKeri.History

/-- **D1. No cycles.** In a reachable system no identity is its own
ancestor at any depth: a certificate needs the parent's checkpoint before
the child's, and the parent of an AID is fixed at its inception. Mutant:
`registerDelegated` that ignores `known`. -/
theorem D1_no_cycles (p : Params) (env : DEnv) {s : Sys} (h : Reach p env s) (n : Nat) (a : AID) :
    ancestorWithin s n a a = false := by
  sorry

/-- **D2. Mint, exactly** (public inversion). A certificate is minted iff
the parent's checkpoint is present as a reference input, the approval seal
walks against the parent's history with some verdict, and no token of that
name exists. No actor, no child check: fail on the seal, never on the
chain. Mutant: `mint` requiring the child's checkpoint. -/
theorem D2_mint_iff (p : Params) (env : DEnv) (s : Sys) (parent child : AID) (ev : ChildEvent)
    (w : WalkCore) (s' : Sys) :
    stepFn p env s (.mint parent child ev w) = some s' ↔
      ∃ pc v, s.ckpt parent = some pc ∧ walkOn p env.toEnv pc (approvalSeal env child ev) w = some v ∧
        (∀ c ∈ s.certs, c.named parent child ev.sn (env.eventDigest ev) = false) ∧
        s' = { s with certs := ⟨parent, child, ev.sn, env.eventDigest ev, w.kel.sn, w.idx, v⟩ :: s.certs } := by
  sorry

/-- **D3. Minting spends nothing.** A mint changes no checkpoint and no
delegation record: the parent is read, never spent, so any number of
children record in one block. Mutant: `mint` that advances the parent. -/
theorem D3_mint_spends_nothing (p : Params) (env : DEnv) {s s' : Sys} {parent child : AID}
    {ev : ChildEvent} {w : WalkCore} (hs : stepFn p env s (.mint parent child ev w) = some s') :
    s'.ckpt = s.ckpt ∧ s'.known = s.known := by
  sorry

/-- **D4. A delegated leaf exists only because the parent's approval
walked** (recursion becomes induction). Every leaf of a reachable
delegated checkpoint consumed a certificate minted by a seal walk against
the parent's checkpoint at that time, naming that sequence. Mutant:
`advanceDelegated` without `takeCert`. -/
theorem D4_delegated_leaf_needs_approval (p : Params) (env : DEnv) {s : Sys} (h : Reach p env s)
    {child par : AID} {c : Checkpoint} (hc : s.ckpt child = some c) (hpar : c.parent = some par)
    {sn : Seq} {l : Leaf} (hl : c.hist sn = some l) :
    ∃ s₀ s₁ ev w pc v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint par child ev w) = some s₁ ∧
      ReachFrom p env s₁ s ∧ ev.sn = sn ∧ s₀.ckpt par = some pc ∧
      walkOn p env.toEnv pc (approvalSeal env child ev) w = some v := by
  sorry

/-- **D5. A certificate is consumed once.** After a delegated registration
or rotation, no token of the consumed name remains; the same approval
cannot land twice. Mutant: `takeCert` that leaves the token in place. -/
theorem D5_certificate_consumed_once (p : Params) (env : DEnv) {s s' : Sys} (h : Reach p env s) {child : AID} {ev : ChildEvent}
    {a : Action}
    (ha : a = .advanceDelegated child ev ∨ a = .supersedeDelegated child ev ∨
      ∃ par, a = .registerDelegated child par ev)
    (hs : stepFn p env s a = some s') {c' : Checkpoint} (hc : s'.ckpt child = some c')
    {par : AID} (hpar : c'.parent = some par) :
    ∀ c ∈ s'.certs, c.named par child ev.sn (env.eventDigest ev) = false := by
  sorry

/-- **D6. The ancestry walk reads parent fields only.** Two systems with
the same parent fields answer every ancestry question alike: no signature,
no history, no certificate is consulted. Mutant: `ancestorWithin` that
consults `certs`. -/
theorem D6_ancestry_reads_parents_only (s s' : Sys) (h : s.parents = s'.parents) (n : Nat) (a r : AID) :
    ancestorWithin s n a r = ancestorWithin s' n a r := by
  sorry

/-- **D7. Depth is the consumer's.** More generations never lose an
ancestor: a consumer picks its bound, and unbounded depth cannot stall it
because the walk is structural in the bound. Mutant: `ancestorWithin`
that refuses at exactly `n`. -/
theorem D7_depth_is_the_consumers (s : Sys) (n : Nat) (a r : AID) (h : ancestorWithin s n a r = true) :
    ancestorWithin s (n + 1) a r = true := by
  sorry

/-- **D8. The seal's position binds** (KERI rule B2). A minted certificate
records the exact position at which the approval seal sits in the exact
parent event; a seal for the same child elsewhere does not mint at that
position. Mutant: `walkOn` searching the seal list. -/
theorem D8_seal_position_binds (p : Params) (env : DEnv) {s s' : Sys} {parent child : AID}
    {ev : ChildEvent} {w : WalkCore} (hs : stepFn p env s (.mint parent child ev w) = some s') :
    w.kel.seals[w.idx]? = some (approvalSeal env child ev) ∧
      ∃ c ∈ s'.certs, c.named parent child ev.sn (env.eventDigest ev) = true ∧
        c.parentSn = w.kel.sn ∧ c.sealIdx = w.idx := by
  sorry

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
  sorry

/-- **D10. Delegation does not touch the TEL.** A delegated issuer's seal
walk is the same whether or not its parent is on chain: it runs against
the issuer's own checkpoint, whose leaf already embodies the approval.
Mutant: `issuerWalk` that requires the parent's checkpoint. -/
theorem D10_delegation_does_not_touch_the_tel (p : Params) (env : DEnv) (tenv : TelEnv) {s s' : Sys}
    {par child : AID} (hne : child ≠ par) (hs : stepFn p env s (.leave par) = some s')
    (rid : RegistryId) (w : Walk) :
    issuerWalk p tenv s' child rid w = issuerWalk p tenv s child rid w := by
  sorry

/-- **D11. Superseding, exactly** (public inversion). A delegated rotation
at the latest sequence replaces the latest leaf iff the child is
delegated, a certificate of that name is present, and the history's
`supersede` accepts it. Mutant: `supersedeDelegated` on a non-delegated
child. -/
theorem D11_supersede_iff (p : Params) (env : DEnv) (s : Sys) (child : AID) (ev : ChildEvent) (s' : Sys) :
    stepFn p env s (.supersedeDelegated child ev) = some s' ↔
      ∃ c par cert s₁ c', s.ckpt child = some c ∧ c.parent = some par ∧
        s.takeCert par child ev.sn (env.eventDigest ev) = some (cert, s₁) ∧
        supersede c ev.sn ev.toad (cert.parentSn, cert.sealIdx) = some c' ∧
        s' = s₁.setCkpt child (some c') := by
  sorry

/-- **D14. Superseding needs a strictly later approval** (KERI rule B2, the
feasibility report §3: the position of the seal decides). The installed
leaf remembers the position of the approval that installed it; a delegated
rotation at the same sequence replaces it only with a certificate whose
approval sits later in the parent's log, and installs that position. A
certificate approved earlier — at parent sequence 2 against a leaf
installed at 3 — is refused. Mutant: `supersedeDelegated` passing a fixed
position instead of the certificate's. -/
theorem D14_supersede_needs_later_approval (p : Params) (env : DEnv) (s : Sys) (child : AID)
    (ev : ChildEvent) :
    (∀ s', stepFn p env s (.supersedeDelegated child ev) = some s' →
      ∃ c par cert a c', s.ckpt child = some c ∧ c.parent = some par ∧ c.approval = some a ∧
        cert ∈ s.certs ∧ cert.named par child ev.sn (env.eventDigest ev) = true ∧
        a.before (cert.parentSn, cert.sealIdx) ∧
        s'.ckpt child = some c' ∧ c'.approval = some (cert.parentSn, cert.sealIdx)) ∧
    (∀ c par cert a, s.ckpt child = some c → c.parent = some par → c.approval = some a →
      s.certs.find? (fun x => x.named par child ev.sn (env.eventDigest ev)) = some cert →
      ¬ a.before (cert.parentSn, cert.sealIdx) →
      stepFn p env s (.supersedeDelegated child ev) = none) := by
  sorry

/-- **D12. A non-delegated history is insert-only at the system level**
(H8 lifted): in a reachable system no action changes an existing leaf of a checkpoint with no
parent. Mutant: `advancePlain` without the `parent = none` guard would
not falsify this; `supersedeDelegated` accepting `parent = none` does. -/
theorem D12_plain_insert_only (p : Params) (env : DEnv) {s s' : Sys} (h : Reach p env s) {a : Action}
    (hs : stepFn p env s a = some s') {aid : AID} {c c' : Checkpoint}
    (hc : s.ckpt aid = some c) (hnd : c.parent = none) (hc' : s'.ckpt aid = some c')
    {sn : Seq} {l : Leaf} (hl : c.hist sn = some l) :
    c'.hist sn = some l := by
  sorry

/-- **D13. An overturned approval leaves the child standing** (a witness
of the explicit omission of #292, not a guarantee). There is a reachable
system in which a child's leaf consumed a certificate minted under a
provisional walk, the parent has since inserted a leaf at or below the
approving event's sequence — the approval sits on the disputed branch —
and the child's leaf is still there. A bonded challenge for this third
divergence is a later ruling. -/
theorem D13_overturned_approval_witness :
    ∃ (p : Params) (env : DEnv) (s₀ s₁ s : Sys) (par child : AID) (ev : ChildEvent) (w : WalkCore)
      (pc pc' c : Checkpoint),
      ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint par child ev w) = some s₁ ∧
      s₀.ckpt par = some pc ∧ walkOn p env.toEnv pc (approvalSeal env child ev) w = some .provisional ∧
      ReachFrom p env s₁ s ∧ s.ckpt child = some c ∧ c.parent = some par ∧ (c.hist ev.sn).isSome ∧
      s.ckpt par = some pc' ∧ ∃ m, w.e < m ∧ m ≤ w.kel.sn ∧ (pc'.hist m).isSome := by
  sorry

end CardanoKeri.Delegation
