import CardanoKeri.Statements.Delegation

/-!
# Delegation statements D1 … D18 — unproven

STATEMENTS mode: every theorem ends in `sorry`. Rulings: #292,
`docs/design/credential-verification.md` ("Delegation: recursion becomes
induction", "Delegation does not touch the TEL"), the feasibility report
under `specs/134-delegated-aids/` (§4.2). Mutants named per theorem; the
ledger is `STATEMENTS-ATOMS.md`.

Repair 3 (invariant review, 2026-09-10): the approval position carries
the parent event's kind (B3: D18), certificates carry their anchor and a
provisional one is re-validated at consumption (D17), installation is
bound to the exact event (D15), a re-minted approval cannot re-install
(D16).
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
the parent's checkpoint at that time, naming that sequence, and the leaf
carries that event's toad. Mutant: `advanceDelegated` without
`takeCert`. -/
theorem D4_delegated_leaf_needs_approval (p : Params) (env : DEnv) {s : Sys} (h : Reach p env s)
    {child par : AID} {c : Checkpoint} (hc : s.ckpt child = some c) (hpar : c.parent = some par)
    {sn : Seq} {l : Leaf} (hl : c.hist sn = some l) :
    ∃ s₀ s₁ ev w pc v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.mint par child ev w) = some s₁ ∧
      ReachFrom p env s₁ s ∧ ev.sn = sn ∧ l.toad = ev.toad ∧ s₀.ckpt par = some pc ∧
      walkOn p env.toEnv pc (approvalSeal env child ev) w = some v := by
  sorry

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
  sorry

/-- **D12. A non-delegated history is insert-only at the system level**
(H8 lifted): in a reachable system no action changes an existing leaf of a
checkpoint with no parent. Mutant: `supersedeDelegated` accepting
`parent = none`. -/
theorem D12_plain_insert_only (p : Params) (env : DEnv) {s s' : Sys} (h : Reach p env s) {a : Action}
    (hs : stepFn p env s a = some s') {aid : AID} {c c' : Checkpoint}
    (hc : s.ckpt aid = some c) (hnd : c.parent = none) (hc' : s'.ckpt aid = some c')
    {sn : Seq} {l : Leaf} (hl : c.hist sn = some l) :
    c'.hist sn = some l := by
  sorry

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
  sorry

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
  sorry

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
  sorry

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
  sorry

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
  sorry

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
  sorry

end CardanoKeri.Delegation
