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
Then The guard is false regardless of supplied context or rival; this is the independent KERI reader. The enforcement decision uses acceptsRival. -/
theorem Env.inception_duplicity_refused (env : Env) (epoch : Epoch) :
    env.duplicityAt epoch 0 = false := by
  cases hc : env.convictionContext epoch 0 <;>
    cases hr : env.convictionRival epoch 0 <;>
      simp [Env.duplicityAt, hc, hr, CardanoKeri.Duplicity.sequence_zero_refused]

/-- Given any step entering pending termination, when its spent input and
rival are read, then the one-rival comparison succeeded for its native
epoch and sequence. The permitted conclusion is the enforcement decision. -/
theorem conviction_has_spent_tip_comparison (p : Params) (env : Env)
    {a : Action} {t : Slot} {l : Live} {f : Flow} {key : KeyState}
    (h : Step p env a t (.present l) f (.terminationPending key)) :
    ∃ comparison, env.comparison l.epoch l.sn = some comparison ∧
      comparison.tip.epoch = l.epoch ∧ comparison.tip.sn = l.sn ∧
      CheckpointConviction.accepts comparison.tip comparison.rival = true := by
  have accepted := (T12_convict_exact p env h).2.2
  cases found : env.comparison l.epoch l.sn with
  | none => simp [Env.acceptsRival, found] at accepted
  | some comparison =>
    simp only [Env.acceptsRival, found, Option.map_some, Option.getD_some,
      CheckpointConviction.Comparison.acceptsAt, Bool.and_eq_true, beq_iff_eq] at accepted
    exact ⟨comparison, rfl, accepted.1.1, accepted.1.2, accepted.2⟩

/-- Given A concrete context/rival pair satisfies Duplicity.duplicityAt epoch sn; next is strictly larger than sn.
When Evaluate that same pair at epoch,next.
Then The target-bound predicate is false. The old declaration contains no Step or convicted successor, so its exact type survives; separately bind this false guard to refusal of actual live booking into pending. -/
theorem old_pair_cannot_convict_new_target (epoch sn next : Nat)
    (context : Duplicity.Context) (rival : Duplicity.SignedEvent)
    (old : Duplicity.duplicityAt epoch sn context rival = true) (later : sn < next) :
    Duplicity.duplicityAt epoch next context rival = false := by
  have target := ((Duplicity.duplicityAt_iff _ _ _ _).mp old).2.1
  simp [Duplicity.duplicityAt, target, Nat.ne_of_lt later]

end CardanoKeri.Checkpoint
