import CardanoKeri.CheckpointGoals

namespace CardanoKeri.Checkpoint

/-- Given a checkpoint target, when its concrete evidence guard succeeds,
then an authenticated context and a rival exist and satisfy the concrete
target-bound predicate. Conversely that evidence enables the guard. -/
theorem Env.duplicityAt_iff (env : Env) (epoch : Epoch) (sn : Seq) :
    env.duplicityAt epoch sn = true ↔
      ∃ context rival, env.convictionContext epoch sn = some context ∧
        env.convictionRival epoch sn = some rival ∧
        CardanoKeri.Duplicity.duplicityAt epoch sn context rival = true := by
  cases hc : env.convictionContext epoch sn <;>
    cases hr : env.convictionRival epoch sn <;> simp [Env.duplicityAt, hc, hr]

/-- Given any environment, when conviction is requested against inception,
then the concrete evidence guard refuses, regardless of alleged rival data. -/
theorem Env.inception_duplicity_refused (env : Env) (epoch : Epoch) :
    env.duplicityAt epoch 0 = false := by
  cases hc : env.convictionContext epoch 0 <;>
    cases hr : env.convictionRival epoch 0 <;>
      simp [Env.duplicityAt, hc, hr, CardanoKeri.Duplicity.sequence_zero_refused]

/-- Given an active checkpoint, when a step convicts it, then concrete
evidence validates two different ordinary rotations at its own target. -/
theorem convict_requires_concrete_pair (p : Params) (env : Env)
    {a : Action} {t : Slot} {l : Live} {f : Flow}
    (h : Step p env a t (.present l) f .convicted) :
    ∃ context rival, env.convictionContext l.epoch l.sn = some context ∧
      env.convictionRival l.epoch l.sn = some rival ∧
      context.epoch = l.epoch ∧ context.accepted.event.sn = l.sn ∧
      Duplicity.rotationValid context.prior context.accepted = true ∧
      Duplicity.rotationValid context.prior rival = true ∧
      context.accepted.event.sn = rival.event.sn ∧
      context.accepted.event ≠ rival.event := by
  obtain ⟨context, rival, hc, hr, hd⟩ :=
    (Env.duplicityAt_iff env l.epoch l.sn).mp (T12_convict_exact p env h).2
  exact ⟨context, rival, hc, hr, (Duplicity.duplicityAt_iff _ _ _ _).mp hd⟩

/-- Given a parked checkpoint, when a step convicts it, then a concrete
pair validates against the parked target, and the step transfers no value. -/
theorem parked_convict_requires_concrete_pair (p : Params) (env : Env)
    {a : Action} {t : Slot} {hs : Hash} {f : Flow}
    (h : Step p env a t (.parked hs) f .convicted) :
    f = {} ∧ ∃ context rival, env.convictionContext hs.epoch hs.sn = some context ∧
      env.convictionRival hs.epoch hs.sn = some rival ∧
      Duplicity.duplicityAt hs.epoch hs.sn context rival = true := by
  exact ⟨(T12_convict_parked_exact p env h).2.1,
    (Env.duplicityAt_iff env hs.epoch hs.sn).mp (T12_convict_parked_exact p env h).2.2⟩

/-- Given a valid rivalry at a target, when the checkpoint has advanced to
another sequence, then that old pair cannot convict the new target. -/
theorem old_pair_cannot_convict_new_target (epoch sn next : Nat)
    (context : Duplicity.Context) (rival : Duplicity.SignedEvent)
    (old : Duplicity.duplicityAt epoch sn context rival = true) (later : sn < next) :
    Duplicity.duplicityAt epoch next context rival = false := by
  have target := ((Duplicity.duplicityAt_iff _ _ _ _).mp old).2.1
  simp [Duplicity.duplicityAt, target, Nat.ne_of_lt later]

end CardanoKeri.Checkpoint
