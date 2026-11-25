import CardanoKeri.ApplicationCustodyHistory

namespace CardanoKeri.Application.Custody
open Checkpoint SingularApplicationHeld

/-- An evidenced change of a live checkpoint. The two bond options on rotation
have the same attestation kind; freeze uses its own kind. -/
def advanceUse : Checkpoint.Action → Option (Attestation.Change × Seq)
  | .rotate next _ _ => some (.advance, next)
  | .freeze next _ => some (.freeze, next)
  | _ => none

/-- The actual accepted local step and the observation of its spent checkpoint
in a single transaction. -/
structure AdvanceAt (o : Observation) where
  params : Checkpoint.Params
  env : Checkpoint.Env
  old : ObservedOutput
  live : Live
  action : Checkpoint.Action
  time : Slot
  flow : Checkpoint.Flow
  successor : State
  input : namedInput o old.reference = some old
  step : Step params env action time (.present live) flow successor
  observed : AdvanceCorrespondence env action (.present live) old o

/-- Given the matching input, script and mint, when the decoded reading accepts,
then the actual ledger mint has quantity +1 for that claim. -/
private theorem observed_advance_quantity {r : Attestation.AdvanceReads} {kind epoch sn next}
    {old : ObservedOutput} {o : Observation}
    (actual : r.script = old.credential ∧ ∃ read, r.spend kind epoch sn next = some read ∧
      read.input = old.reference ∧ read.transaction.mint = o.assets.mint)
    (issued : r.attested kind epoch sn next = true) :
    Assets.mintQty o.assets (r.policy.asset (.spend kind old.credential old.reference)) = 1 := by
  obtain ⟨script, read, selected, input, mint⟩ := actual
  simp only [Attestation.AdvanceReads.attested, selected, Option.any_some, Bool.and_eq_true] at issued
  have one := (Attestation.minted_iff ..).mp issued.2
  simpa only [Assets.mintQty, script, input, mint] using one

/-- Given an executed spend and its ledger observation, when the action is a
rotation or freeze, then this transaction mints exactly one attestation for its
actual purpose, checkpoint script and consumed reference. -/
theorem advance_minted_at_use {o : Observation} (use : AdvanceAt o) {kind next}
    (purpose : advanceUse use.action = some (kind, next)) :
    Assets.mintQty o.assets (use.env.advanceReads.policy.asset
      (.spend kind use.old.credential use.old.reference)) = 1 := by
  obtain ⟨p, env, old, l, action, time, flow, successor, _, executed, observed⟩ := use
  dsimp at *
  cases executed <;> simp only [advanceUse, Option.some.injEq, Prod.mk.injEq, reduceCtorEq] at purpose
  all_goals
    obtain ⟨rfl, rfl⟩ := purpose
    apply observed_advance_quantity observed
    assumption

/-- Given an executed deposit, when the advance mint and the checkpoint spend
are inspected, then the mint contains the same advance-kind asset as keep and
the checkpoint separately accepted the successor keys' deposit authorization. -/
theorem depositing_rotation_needs_advance_and_intent {o : Observation} (use : AdvanceAt o)
    {target payee} (deposit : use.action = .rotate target .deposit payee) :
    Assets.mintQty o.assets (use.env.advanceReads.policy.asset
      (.spend .advance use.old.credential use.old.reference)) = 1 ∧
    use.env.depositAuthorized (use.live.epoch + 1) = true := by
  refine ⟨advance_minted_at_use use (next := target) (by rw [deposit]; rfl), ?_⟩
  have step := use.step
  rw [deposit] at step
  exact T6_deposit_requires_new_keys _ _ step

/-- Given two checkpoints spending distinct references in one transaction under
the same advance policy, when both spends are accepted, then the observed mint
contains the two distinct assets, one unit each. -/
theorem two_checkpoint_spends_need_two_attestations {o : Observation} (a b : AdvanceAt o)
    {ka kb na nb} (ha : advanceUse a.action = some (ka, na))
    (hb : advanceUse b.action = some (kb, nb)) (refs : a.old.reference ≠ b.old.reference)
    (policy : a.env.advanceReads.policy = b.env.advanceReads.policy)
    (names : Attestation.FaithfulNames b.env.advanceReads.policy
      (.spend ka a.old.credential a.old.reference) (.spend kb b.old.credential b.old.reference)) :
    let x := a.env.advanceReads.policy.asset (.spend ka a.old.credential a.old.reference)
    let y := b.env.advanceReads.policy.asset (.spend kb b.old.credential b.old.reference)
    Assets.mintQty o.assets x = 1 ∧ Assets.mintQty o.assets y = 1 ∧ x ≠ y := by
  refine ⟨advance_minted_at_use a ha, advance_minted_at_use b hb, ?_⟩
  dsimp only
  rw [policy]
  intro same
  have eq := names (congrArg Singular.TokenId.name same)
  exact refs (Attestation.Claim.spend.inj eq).2.2

/-- Given an attestation already held in a consumed input or present in an
output, when the transaction's mint field has zero net units of its asset,
then the relying script's mint check refuses that claim. -/
theorem held_without_fresh_mint_refused (o : Observation) (policy : Attestation.Policy)
    (claim : Attestation.Claim)
    (_held : ∃ out ∈ o.inputs ++ o.outputs, quantity out (policy.asset claim) > 0)
    (absent : Assets.mintQty o.assets (policy.asset claim) = 0) :
    policy.minted o.assets claim = false := by
  simp [Attestation.Policy.minted, absent]

/-- Given the same checkpoint, amount and time, when a top-up is submitted,
then every choice of evidence reads gives the same refusal or successor. -/
theorem top_up_independent_of_evidence (p : Checkpoint.Params) (a b : Checkpoint.Env)
    (amount now : Nat) (s : State) :
    stepFn p a (.topUp amount) now s = stepFn p b (.topUp amount) now s := by
  cases s <;> rfl

/-- Given a pending checkpoint, when unrelated tokens are burned alongside its
release, then its verdict still depends on its own termination approval. -/
theorem pending_release_with_unrelated_burns (i : Interpretation) (release : PublishedRelease)
    (registry : Singular.TokenId) (input : ObservedOutput) (o : Observation)
    (burns : List (Singular.TokenId × Int))
    (unrelated : ∀ entry ∈ burns, entry.2 < 0 ∧ entry.1.policy ≠ release.applicationPolicy) :
    pendingReleased i release registry input {o with assets.mint := o.assets.mint ++ burns} =
      pendingReleased i release registry input o := by
  unfold pendingReleased
  cases checkpointDatum i input with
  | none => rfl
  | some d =>
    have empty : burns.filter (fun e => e.1 == terminationApproval i.hash i.code release registry
        (i.keyOf d.aid)) = [] := by
      apply List.filter_eq_nil_iff.mpr
      intro e he
      simp only [beq_iff_eq]
      intro eq
      exact (unrelated e he).2 (congrArg Singular.TokenId.policy eq)
    simp [Assets.mintQty, List.filter_append, empty]

/-- Given a cleanup transaction spending the submitter's change, with only
negative mint entries for the attestation policy and no checkpoint input or
output, when its ledger step settles, then every checkpoint holding is preserved
and the burn policy succeeds with an empty evidence list. -/
theorem cleanup_preserves_untouched_checkpoints {before after : CandidateWorld} (tx : Transaction before after)
    (policy : Attestation.Policy) (emptyName script : Nat) (verified : Assets.TxView → Attestation.Claim → Bool)
    (burn : ∀ entry ∈ tx.observation.assets.mint, entry.1.policy = policy.id → entry.2 < 0)
    (noInput : ∀ o ∈ before.unspent, o.credential = script → o.reference ∉ tx.observation.assets.spent)
    (noOutput : ∀ o ∈ tx.observation.outputs, o.credential ≠ script) :
    policy.authorizes tx.observation.assets emptyName verified [] = true ∧
    ∀ o : ObservedOutput, o.credential = script → (o ∈ after.unspent ↔ o ∈ before.unspent) := by
  refine ⟨(Attestation.pure_burn_needs_no_evidence ..).2 burn, ?_⟩
  intro o credential
  rw [tx.ledger.nextUnspent, List.mem_append, List.mem_filter]
  constructor
  · rintro (⟨mem, _⟩ | fresh)
    · exact mem
    · exact False.elim (noOutput o fresh credential)
  · intro mem
    exact Or.inl ⟨mem, by simpa using noInput o mem credential⟩

end CardanoKeri.Application.Custody
