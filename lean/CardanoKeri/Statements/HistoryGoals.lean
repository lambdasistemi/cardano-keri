import CardanoKeri.Statements.History

/-!
# History and seal-walk statements H1 … H10, S1 … S7 — unproven

STATEMENTS mode. Every theorem ends in `sorry`; the intended guarantee is
stated, not the easiest provable variant. Each carries, in its docstring,
the ruling it answers to and the single-atom mutant expected to falsify it
(the semantic-atom ledger `STATEMENTS-ATOMS.md` lists them by row). Nothing
below is proved; `#print axioms` on any of them reports `sorryAx`.

Every statement is a property of this model. Whether the model is the right
model is settled against `docs/design/credential-verification.md`, #391 and
the KERI superseding rules, not by `lake build`.
-/

namespace CardanoKeri.History

/-! ## The history accumulator -/

/-- **H1.** Well-formedness is what registration creates and every history
step preserves. Mutant: `advance` that forgets the back-pointer
(`prev := none`), or `supersede` that moves the back-pointer. -/
theorem H1_wf_reachable {c : Checkpoint} (h : HReach c) : WF c := by
  sorry

/-- **H2. The range proof is sound.** On a well-formed history, whatever
`cover` accepts is the greatest establishment at or below `k`: nothing
rotated between `e` and `k`. This is the whole point of the back-pointer
(#391: "two exact lookups and two integer comparisons"). Mutant: drop
`k < e'` from `cover`. -/
theorem H2_cover_sound {c : Checkpoint} (hwf : WF c) {e k : Seq} {succ : Option Seq} {v : Verdict}
    (h : cover c e k succ = some v) : Governs c e k := by
  sorry

/-- **H3. The range proof is complete.** Every governing leaf has a range
proof: the successor leaf when one exists, nothing when `e` is the latest.
Mutant: `cover` that refuses `succ = none`. -/
theorem H3_cover_complete {c : Checkpoint} (hwf : WF c) {e k : Seq} (hg : Governs c e k) :
    ∃ succ v, cover c e k succ = some v := by
  sorry

/-- **H4. Provisional means exactly "the latest leaf".** A walk is
provisional iff it rests on the latest establishment event with no
successor, and final iff a successor leaf closes the range. Mutant:
`cover` returning `final` on `succ = none`. -/
theorem H4_provisional_iff_latest {c : Checkpoint} (hwf : WF c) {e k : Seq} {succ : Option Seq} :
    cover c e k succ = some .provisional ↔
      succ = none ∧ e = c.latest ∧ e ≤ k ∧ ∃ l, c.hist e = some l := by
  sorry

/-- **H5. A final verdict is stable under every later history step.** An
interaction event before a later rotation can no longer be superseded
(design: "its admission is final"). Mutant: `supersede` that touches a
non-latest leaf. -/
theorem H5_final_is_stable {c c' : Checkpoint} (hwf : WF c) {a : HAction} (hs : hstep c a = some c')
    {e k : Seq} {succ : Option Seq} (h : cover c e k succ = some .final) :
    cover c' e k succ = some .final := by
  sorry

/-- **H6. A superseding rotation at or below `k` shunts the event.** A
provisional verdict for `k` is withdrawn, under every range proof, by an
advance to `e'` with `e' ≤ k` (KERI rule A0: the superseded interaction
and its successors sit on the disputed branch). Mutant: `cover` with
`k ≤ e'` instead of `k < e'`. -/
theorem H6_superseding_excludes {c c' : Checkpoint} (hwf : WF c) {e k e' : Seq} {t : Nat}
    {appr : Option Approval} (h : cover c e k none = some .provisional)
    (hs : advance c e' t appr = some c') (hle : e' ≤ k) :
    ∀ succ, cover c' e k succ = none := by
  sorry

/-- **H7. A later rotation makes the provisional verdict final.** An advance
to `e' > k` closes the range and the same leaf now governs `k` finally,
with the new leaf as the successor proof. Mutant: `advance` that inserts
the new leaf with the wrong back-pointer. -/
theorem H7_provisional_becomes_final {c c' : Checkpoint} (hwf : WF c) {e k e' : Seq} {t : Nat}
    {appr : Option Approval} (h : cover c e k none = some .provisional)
    (hs : advance c e' t appr = some c') (hlt : k < e') :
    cover c' e k (some e') = some .final := by
  sorry

/-- **H8. A non-delegated history is insert-only** (KERI rule A1): no step
of a well-formed non-delegated checkpoint changes or removes an existing
leaf. Well-formedness is needed: with `latest = 0` and a stray leaf at 1,
`advance 1` would overwrite it. Mutant: `supersede` without the `parent`
guard. -/
theorem H8_non_delegated_insert_only {c c' : Checkpoint} (hwf : WF c) (hnd : c.parent = none)
    {a : HAction} (hs : hstep c a = some c') {sn : Seq} {l : Leaf} (h : c.hist sn = some l) :
    c'.hist sn = some l := by
  sorry

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
  sorry

/-- **H10. An older approval cannot supersede** (KERI rule B2: the position
of the seal decides which of two competing delegated rotations wins). A
rotation whose approval sits at or before the one that installed the
latest leaf is refused, whatever else it presents. Mutant: drop
`a.before appr` from `supersede`. -/
theorem H10_older_approval_cannot_supersede {c : Checkpoint} {a : Approval} (ha : c.approval = some a)
    {appr : Approval} (hnot : ¬ a.before appr) (sn' : Seq) (t : Nat) :
    supersede c sn' t appr = none := by
  sorry

/-! ## The seal walk -/

/-- **S1. The walk needs the historical keys and witnesses.** A successful
walk rests on an existing leaf, at or above the toad floor, whose keys
signed and whose witnesses receipted the sealing event. Mutant: drop the
`receipted` conjunct (the hash-chain-free branch binding of #391). -/
theorem S1_walk_needs_leaf_signature_and_receipts (p : Params) (env : Env) {c : Checkpoint} {sl : Seal}
    {w : WalkCore} {v : Verdict} (h : walkOn p env c sl w = some v) :
    ∃ l, c.hist w.e = some l ∧ p.toadFloor ≤ l.toad ∧
      env.signed l.epoch w.kel = true ∧ env.receipted l.epoch w.kel = true := by
  sorry

/-- **S2. The walk binds the sealed thing at its position.** The seal at the
named index is exactly the seal of the sealed thing; for a TEL event, the
event also names the registry. A genuine event of the issuer cannot be
presented for a thing it never sealed (#391's "without every link").
Mutant: compare `seal.i` only. -/
theorem S2_walk_binds_seal_at_index (p : Params) (env : TelEnv) {c : Checkpoint} {rid : RegistryId}
    {w : Walk} {v : Verdict} (h : sealWalk p env c rid w = some v) :
    w.core.kel.seals[w.core.idx]? = some (w.tel.sealOf env.digest) ∧ w.tel.ri = rid := by
  sorry

/-- **S3. The walk never reads the current keys.** Historical issuance and
current control are answered by the same reference input but the walk is
invariant under the current key state (design: "the current keys in a
checkpoint say nothing about history"). Mutant: `walkOn` that checks
`env.signed c.cur` instead of the leaf's epoch. -/
theorem S3_walk_ignores_current_keys (p : Params) (env : Env) (c : Checkpoint) (x : Epoch) (sl : Seal)
    (w : WalkCore) :
    walkOn p env { c with cur := x } sl w = walkOn p env c sl w := by
  sorry

/-- **S4. A thief of the current keys gets at most a provisional verdict.**
If signatures verify only under the current key state, every successful
walk is provisional, and H6 says the owner's next rotation withdraws it
(design: "stolen-current-key `ixn` issuing fake creds is killed by owner
rotation"). Mutant: `cover` returning `final` for the latest leaf. -/
theorem S4_current_key_thief_only_provisional (p : Params) (env : Env) {c : Checkpoint} (hwf : WF c)
    (hthief : ∀ ep ev, env.signed ep ev = true → ep = c.cur)
    {sl : Seal} {w : WalkCore} {v : Verdict} (h : walkOn p env c sl w = some v) :
    v = .provisional := by
  sorry

/-- **S5. The walk's verdict is the range proof's verdict.** Final iff a
successor leaf closed the range; provisional iff the covering leaf is the
latest. Mutant: `walkOn` returning a constant verdict. -/
theorem S5_walk_verdict_is_cover_verdict (p : Params) (env : Env) {c : Checkpoint} {sl : Seal}
    {w : WalkCore} {v : Verdict} (h : walkOn p env c sl w = some v) :
    cover c w.e w.kel.sn w.succ = some v := by
  sorry

/-- **S6. One seal, one TEL event.** With a collision-resistant digest, two
successful walks through the same seal position of the same sealing event
name the same TEL event. Stated with injectivity as a hypothesis, not a
fact of the model. Mutant: `sealOf` that omits the digest. -/
theorem S6_seal_names_one_event (p : Params) (env : TelEnv) (hinj : Function.Injective env.digest)
    {c c' : Checkpoint} {rid rid' : RegistryId} {w w' : Walk} {v v' : Verdict}
    (h : sealWalk p env c rid w = some v) (h' : sealWalk p env c' rid' w' = some v')
    (hkel : w.core.kel = w'.core.kel) (hidx : w.core.idx = w'.core.idx) :
    w.tel = w'.tel := by
  sorry

/-- **S7. An establishment event is its own leaf.** When the sealing event
is a `rot` (an establishment-only registry), the covering leaf is the event
itself. Mutant: drop the `w.e = w.kel.sn` guard. -/
theorem S7_establishment_seal_is_own_leaf (p : Params) (env : Env) {c : Checkpoint} {sl : Seal}
    {w : WalkCore} {v : Verdict} (hest : w.kel.establishment = true)
    (h : walkOn p env c sl w = some v) :
    w.e = w.kel.sn := by
  sorry

end CardanoKeri.History
