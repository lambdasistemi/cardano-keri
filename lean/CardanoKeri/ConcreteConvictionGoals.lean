import CardanoKeri.CheckpointGoals

namespace CardanoKeri.Checkpoint

/-- Given Any environment and target epoch/sequence.
When Evaluate its concrete duplicity guard.
Then True iff there exist context and rival returned by the respective exact target lookups and their concrete target-bound predicate is true, both directions. -/
theorem Env.duplicityAt_iff (env : Env) (epoch : Epoch) (sn : Seq) :
    env.duplicityAt epoch sn = true ↔
      ∃ context rival, env.convictionContext epoch sn = some context ∧
        env.convictionRival epoch sn = some rival ∧
        CardanoKeri.Duplicity.duplicityAt epoch sn context rival = true := by
  cases hc : env.convictionContext epoch sn <;>
    cases hr : env.convictionRival epoch sn <;> simp [Env.duplicityAt, hc, hr]

/-- Given Any environment and epoch, with sequence zero.
When Evaluate duplicity at inception.
Then The guard is false regardless of supplied context or rival; neither live nor parked booking may bypass it. -/
theorem Env.inception_duplicity_refused (env : Env) (epoch : Epoch) :
    env.duplicityAt epoch 0 = false := by
  cases hc : env.convictionContext epoch 0 <;>
    cases hr : env.convictionRival epoch 0 <;>
      simp [Env.duplicityAt, hc, hr, CardanoKeri.Duplicity.sequence_zero_refused]

/-- Given All arguments and the exact successful local Checkpoint conviction premise in the statement, against the actual source live or parked key state.
When Invert that local conviction into explicit terminationPending at the unchanged source key state.
Then For T12 inversions the pending target is arbitrary and must equal the actual source hash; a wrong pending-key successor is excluded by this owning equality. Every original action, addressed D/B/pool payment, concrete-context, event-validity, same-sequence and distinct-event clause in the full conclusion is preserved verbatim. The representative and generic key remain active at the combined booking boundary; no local burn or retirement is asserted. -/
theorem convict_requires_concrete_pair (p : Params) (env : Env)
    {a : Action} {t : Slot} {l : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.terminationPending l.hash)) :
    ∃ context rival, env.convictionContext l.epoch l.sn = some context ∧
      env.convictionRival l.epoch l.sn = some rival ∧
      context.epoch = l.epoch ∧ context.accepted.event.sn = l.sn ∧
      Duplicity.rotationValid context.prior context.accepted = true ∧
      Duplicity.rotationValid context.prior rival = true ∧
      context.accepted.event.sn = rival.event.sn ∧
      context.accepted.event ≠ rival.event := by
  obtain ⟨context, rival, hc, hr, hd⟩ :=
    (Env.duplicityAt_iff env l.epoch l.sn).mp (T12_convict_exact p env h).2.2
  exact ⟨context, rival, hc, hr, (Duplicity.duplicityAt_iff _ _ _ _).mp hd⟩

/-- Given All arguments and the exact successful local Checkpoint conviction premise in the statement, against the actual source live or parked key state.
When Invert that local conviction into explicit terminationPending at the unchanged source key state.
Then For T12 inversions the pending target is arbitrary and must equal the actual source hash; a wrong pending-key successor is excluded by this owning equality. Every original action, addressed D/B/pool payment, concrete-context, event-validity, same-sequence and distinct-event clause in the full conclusion is preserved verbatim. The representative and generic key remain active at the combined booking boundary; no local burn or retirement is asserted. -/
theorem parked_convict_requires_concrete_pair (p : Params) (env : Env)
    {a : Action} {t : Slot} {hs : Hash} {f : Flow}
    (h : Step p env a t (.parked hs) f (.terminationPending hs)) :
    f = {} ∧ ∃ context rival, env.convictionContext hs.epoch hs.sn = some context ∧
      env.convictionRival hs.epoch hs.sn = some rival ∧
      Duplicity.duplicityAt hs.epoch hs.sn context rival = true := by
  exact ⟨(T12_convict_parked_exact p env h).2.2.1,
    (Env.duplicityAt_iff env hs.epoch hs.sn).mp (T12_convict_parked_exact p env h).2.2.2⟩

/-- Given A concrete context/rival pair satisfies Duplicity.duplicityAt epoch sn; next is strictly larger than sn.
When Evaluate that same pair at epoch,next.
Then The target-bound predicate is false. The old declaration contains no Step or convicted successor, so its exact type survives; separately bind this false guard to refusal of actual live and parked booking into pending. -/
theorem old_pair_cannot_convict_new_target (epoch sn next : Nat)
    (context : Duplicity.Context) (rival : Duplicity.SignedEvent)
    (old : Duplicity.duplicityAt epoch sn context rival = true) (later : sn < next) :
    Duplicity.duplicityAt epoch next context rival = false := by
  have target := ((Duplicity.duplicityAt_iff _ _ _ _).mp old).2.1
  simp [Duplicity.duplicityAt, target, Nat.ne_of_lt later]

end CardanoKeri.Checkpoint
