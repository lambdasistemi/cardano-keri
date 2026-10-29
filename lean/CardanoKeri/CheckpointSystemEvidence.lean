import CardanoKeri.CheckpointCompletionGoals
import CardanoKeri.CheckpointReceiptCheck

/-! Reachability evidence retained by a finite certificate interpreter. These
predicates describe the existing system events; they add no admission rule. -/
namespace CardanoKeri.Checkpoint

def OriginsReachable (s : Sys) : Prop :=
  ∀ aid origin, s.origins aid = some origin →
    CardanoKeri.Registry.Reach origin.parameters origin.environment
      origin.configuration origin.registered

def PendingReachable (s : Sys) : Prop :=
  ∀ aid association, s.pending aid = some association →
    CardanoKeri.Registry.Reach association.origin.parameters association.origin.environment
      association.origin.configuration association.booked

/-- Given an actual registration receipt and a delivered origin, when the
origin is installed, then its registered snapshot is reachable in precisely
the origin's stored Registry context. -/
theorem delivered_origin_reachable {rp : CardanoKeri.Registry.Params}
    {re : CardanoKeri.Registry.Env} {cfg : Singular.Config}
    {receipt : CardanoKeri.Registry.FoldReceipt rp re cfg}
    {b : Singular.RegistrationBooking} {aid : AID} {origin : Origin}
    (delivered : DeliveredOrigin receipt b aid origin) :
    CardanoKeri.Registry.Reach origin.parameters origin.environment
      origin.configuration origin.registered := by
  rcases delivered with ⟨_, _, hp, he, hc, hs, _⟩
  rw [hp, he, hc, hs]
  exact CardanoKeri.Registry.Reach.next receipt.reachable
    (action := .fold receipt.before.gen receipt.before.config.applicationPolicy receipt.unspent receipt.transaction)
    receipt.executed

/-- Given reachable stored origins and pending booking snapshots, when any
actual Checkpoint system event occurs, then both sets of stored snapshots
remain reachable under their own unchanged Registry contexts. -/
theorem sysstep_snapshot_reachability (p : Params) (env : Env) {s next : Sys}
    (origins : OriginsReachable s) (pending : PendingReachable s)
    (step : SysStep p env s next) : OriginsReachable next ∧ PendingReachable next := by
  cases step with
  | register event =>
    obtain ⟨aid, now, refund, pool, flow, state, rp, re, cfg, receipt, booking, origin,
      _, _, _, delivered, rfl⟩ := event
    constructor
    · intro other stored found
      by_cases same : other = aid
      · subst other
        simp only [Sys.installOrigin, ↓reduceIte, Option.some.injEq] at found
        subst stored
        exact delivered_origin_reachable delivered
      · exact origins other stored (by simpa [Sys.installOrigin, same] using found)
    · intro other association found
      by_cases same : other = aid
      · simp [Sys.installOrigin, same] at found
      · exact pending other association (by simpa [Sys.installOrigin, same] using found)
  | «local» event =>
    obtain ⟨aid, action, now, flow, state, _, _, _, rfl⟩ := event
    exact ⟨origins, pending⟩
  | book event =>
    obtain ⟨aid, key, origin, before, booked, booker, fee, booking, flow, entry,
      _, storedOrigin, _, history, executed, _, _, _, _, rfl⟩ := event
    refine ⟨origins, ?_⟩
    intro other association found
    by_cases same : other = aid
    · subst other
      simp only [Sys.associate, ↓reduceIte, Option.some.injEq] at found
      subst association
      exact CardanoKeri.Registry.Reach.next
        (history.reachable (origins aid origin storedOrigin))
        (action := .bookTermination aid booker fee booking) executed
    · exact pending other association (by simpa [Sys.associate, same] using found)
  | complete event =>
    obtain ⟨aid, association, receipt, _, rfl⟩ := event
    refine ⟨origins, ?_⟩
    intro other stored found
    by_cases same : other = aid
    · simp [Sys.finish, same] at found
    · exact pending other stored (by simpa [Sys.finish, same] using found)

def PendingOrigins (s : Sys) : Prop :=
  ∀ aid association, s.pending aid = some association →
    s.origins aid = some association.origin

/-- Given pending associations that name their stored origins, when an actual
system event occurs, then every remaining or newly booked association still
names the origin stored at that same AID. -/
theorem sysstep_pending_origins (p : Params) (env : Env) {s next : Sys}
    (bound : PendingOrigins s) (step : SysStep p env s next) : PendingOrigins next := by
  cases step with
  | register event =>
    obtain ⟨aid, now, refund, pool, flow, state, rp, re, cfg, receipt, booking, origin,
      _, _, _, _, rfl⟩ := event
    intro other association found
    by_cases same : other = aid
    · simp [Sys.installOrigin, same] at found
    · simpa [Sys.installOrigin, same] using bound other association
        (by simpa [Sys.installOrigin, same] using found)
  | «local» event =>
    obtain ⟨aid, action, now, flow, state, _, _, _, rfl⟩ := event
    exact bound
  | book event =>
    obtain ⟨aid, key, origin, before, booked, booker, fee, booking, flow, entry,
      _, storedOrigin, _, _, _, _, _, _, _, rfl⟩ := event
    intro other association found
    by_cases same : other = aid
    · subst other
      simp only [Sys.associate, ↓reduceIte, Option.some.injEq] at found
      subst association
      exact storedOrigin
    · exact bound other association (by simpa [Sys.associate, same] using found)
  | complete event =>
    obtain ⟨aid, association, receipt, _, rfl⟩ := event
    intro other stored found
    by_cases same : other = aid
    · simp [Sys.finish, same] at found
    · exact bound other stored (by simpa [Sys.finish, same] using found)

structure CertifiedSys where
  state : Sys
  origins : OriginsReachable state
  pending : PendingReachable state
  bound : PendingOrigins state

def CertifiedSys.init : CertifiedSys := {
  state := Sys.init
  origins := by intro aid origin found; cases found
  pending := by intro aid association found; cases found
  bound := by intro aid association found; cases found }

def CertifiedSys.advance (current : CertifiedSys) {p : Params} {env : Env} {next : Sys}
    (step : SysStep p env current.state next) : CertifiedSys := {
  state := next
  origins := (sysstep_snapshot_reachability p env current.origins current.pending step).1
  pending := (sysstep_snapshot_reachability p env current.origins current.pending step).2
  bound := sysstep_pending_origins p env current.bound step }

end CardanoKeri.Checkpoint
