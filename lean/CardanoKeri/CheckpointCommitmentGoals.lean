import CardanoKeri.CheckpointGoals

/-! A conviction pays only the payee of a commitment opened beforehand over this
identifier, key state, deployment and evidence (#534, #271, #508).

The release's commitment program is modelled as far as a conviction needs it:
opening (`OpenEvent`), revealing inside the window (`RevealEvent`, and the
conviction's own reveal), sweeping after expiry (`SweepEvent`); retiring the
marker is the burn every exit performs (`Sys.retire`). The conviction step
requires the commitment it reveals to name the convicted output's key state, the
evidence the conviction shows and the payee paid, and the conviction slot to lie
in the commitment's window. The system step requires that commitment to be open
and to name the convicted AID and the system's deployment, and burns it.

A commitment names no checkpoint output. Every step that keeps the key state (a
top-up, a freeze, a poison) therefore keeps it entitling, and a rotation, which
changes the key state, voids it for good. Only the holder of the next keys can
rotate.

A commitment is first eligible in the slot after its opening: its age is one
slot.

Left to the technical layer, and stated nowhere here: the hash that hides the
evidence and payee until the reveal, the nonce, the marker's derivation from the
opening seed, the deposit's amount and its payouts (to the payee at a reveal or
a conviction, to whoever signs a sweep), the payee's signatures, and the
lifetime the release applies (the model requires only that a commitment expires
no earlier than it is first eligible). -/
namespace CardanoKeri.Checkpoint

/-! ## The conviction step reads the commitment -/

/-- **A conviction pays only an entitled payee.**
Given any local step whose action is a conviction naming `payee` and revealing `c`.
When the step is read.
Then its source is a live output `l` with duplicity at its key state, and `c`
entitles `payee` to convict `l` at the step's slot: `c` names `l`'s key state, the evidence
the environment shows at `l`'s key state and `payee`, and the slot lies in its
window. -/
theorem convict_requires_entitlement (p : Params) (env : Env) {payee : Addr} {c : Commitment}
    {t : Slot} {s s' : State} {f : Flow} (h : Step p env (.convict payee c) t s f s') :
    ∃ l, s = .present l ∧ env.duplicityAt l.epoch l.sn = true ∧ c.entitles env l payee t := by
  cases h with
  | convict _ _ _ hdup hent => exact ⟨_, rfl, hdup, hent⟩

/-- **Without an entitling commitment the conviction is refused.**
Given a live output `l`, a payee, a slot and a commitment that does not entitle
that payee to convict `l` at that slot.
When a conviction naming that payee and revealing that commitment is attempted.
Then there is no step, and the executable step function refuses it. -/
theorem convict_refused_without_entitlement (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hnot : ¬ c.entitles env l payee t) :
    (∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s') ∧
      stepFn p env (.convict payee c) t (.present l) = none := by
  refine ⟨fun f s' h => ?_, ?_⟩
  · obtain ⟨_, hl, _, hent⟩ := convict_requires_entitlement p env h
    cases hl
    exact hnot hent
  · simp [stepFn, hnot]

/-- **A commitment for another payee pays nobody else.**
Given a commitment naming a payee other than the one the conviction pays.
When the conviction is attempted on any live output at any slot.
Then it is refused. -/
theorem convict_refused_for_other_payee (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hother : c.payee ≠ payee) :
    ∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s' :=
  (convict_refused_without_entitlement p env (fun h => hother h.2.2.1)).1

/-- **A commitment for one key state entitles no other.**
Given a commitment naming a key state other than that of the live output being
convicted (another key state of this identifier, before or after a rotation).
When the conviction is attempted with any payee at any slot.
Then it is refused. -/
theorem convict_refused_for_other_key_state (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hother : c.keyState ≠ l.hash) :
    ∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s' :=
  (convict_refused_without_entitlement p env (fun h => hother h.1)).1

/-- **A commitment for one evidence entitles no other.**
Given a commitment naming evidence other than the evidence the conviction shows at
the output's key state.
When the conviction is attempted with any payee at any slot.
Then it is refused. -/
theorem convict_refused_for_other_evidence (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hother : env.evidenceAt l.epoch l.sn ≠ some c.evidence) :
    ∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s' :=
  (convict_refused_without_entitlement p env (fun h => hother h.2.1)).1

/-- **An immature commitment is refused.**
Given a conviction slot before the commitment's first eligible slot.
When the conviction is attempted.
Then it is refused. -/
theorem convict_refused_before_eligible (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hearly : t < c.eligibleAfter) :
    ∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s' :=
  (convict_refused_without_entitlement p env (fun h => absurd h.2.2.2.1 (Nat.not_le.mpr hearly))).1

/-- **An expired commitment is refused.**
Given a conviction slot after the commitment's last slot.
When the conviction is attempted.
Then it is refused. -/
theorem convict_refused_after_expiry (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hlate : c.expiresAt < t) :
    ∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s' :=
  (convict_refused_without_entitlement p env (fun h => absurd h.2.2.2.2 (Nat.not_le.mpr hlate))).1

/-- **A commitment is first eligible in the slot after its opening.**
Given a commitment as the commitment program opens it.
When a slot is compared with the commitment's first eligible slot.
Then the slot is at or after it exactly when it is strictly after the upper end
of the opening transaction's validity range: the age is one slot. -/
theorem commitment_eligible_from_next_slot {c : Commitment} (hformed : c.wellFormed) (now : Slot) :
    c.eligibleAfter ≤ now ↔ c.openedAt < now := by
  rw [hformed.1]
  exact Nat.lt_iff_add_one_le.symm

/-- **A commitment opened in the slot of the conviction is refused.**
Given a commitment as the commitment program opens it (first eligible in the slot
after the upper end of its opening transaction's validity range), and a conviction
slot no later than that upper end — in particular the slot the opening transaction
lands in.
When the conviction is attempted.
Then it is refused. -/
theorem convict_refused_in_opening_slot (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hformed : c.wellFormed) (hsame : t ≤ c.openedAt) :
    ∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s' :=
  convict_refused_before_eligible p env
    (Nat.not_le.mp fun h => Nat.not_lt.mpr hsame ((commitment_eligible_from_next_slot hformed t).mp h))

/-- **The committed evidence is the duplicity proved.**
Given a conviction of a live output `l` revealing commitment `c`.
When the commitment's evidence is read.
Then that evidence, as a context and a rival, proves duplicity at `l`'s key state. -/
theorem convict_committed_evidence_is_duplicity (p : Params) (env : Env) {payee : Addr}
    {c : Commitment} {t : Slot} {l : Live} {f : Flow} {s' : State}
    (h : Step p env (.convict payee c) t (.present l) f s') :
    CardanoKeri.Duplicity.duplicityAt l.epoch l.sn c.evidence.1 c.evidence.2 = true := by
  obtain ⟨_, hl, hdup, hent⟩ := convict_requires_entitlement p env h
  cases hl
  have hev := hent.2.1
  unfold Env.duplicityAt at hdup
  unfold Env.evidenceAt at hev
  revert hdup hev
  cases env.convictionContext l.epoch l.sn <;> cases env.convictionRival l.epoch l.sn <;>
    simp
  intro hdup hev
  rw [← hev]
  exact hdup

/-! ## A commitment follows the key state, not the output -/

/-- **Every step keeps the key state or rotates it.**
Given any local step from a live output `l` to a live output `l'`.
When their key states are compared.
Then either the step is not a rotation (a poison, a freeze or a top-up) and the key
state is the same, or it is a rotation and the epoch is one higher. -/
theorem step_keeps_key_state_or_rotates (p : Params) (env : Env) {a : Action} {t : Slot}
    {l l' : Live} {f : Flow} (h : Step p env a t (.present l) f (.present l')) :
    (a.isRotation = false ∧ l'.hash = l.hash) ∨ (a.isRotation = true ∧ l'.epoch = l.epoch + 1) := by
  cases h <;> simp [Action.isRotation, Live.hash]

/-- **Entitlement reads only the key state of the output.**
Given two live outputs with the same key state.
When a commitment is read against either, for any payee at any slot.
Then it entitles at one exactly when it entitles at the other. -/
theorem Commitment.entitles_same_key_state (env : Env) (c : Commitment) {l l' : Live}
    (hkey : l'.hash = l.hash) (payee : Addr) (now : Slot) :
    c.entitles env l' payee now ↔ c.entitles env l payee now := by
  have he : l'.epoch = l.epoch := congrArg KeyState.epoch hkey
  have hs : l'.sn = l.sn := congrArg KeyState.sn hkey
  unfold Commitment.entitles
  rw [hkey, he, hs]

/-- **A conviction reads only the key state of the output.**
Given two live outputs with the same key state.
When a conviction naming a payee and revealing a commitment is attempted at either,
at the same slot.
Then the commitment entitles that payee at one exactly when at the other, and the
conviction is accepted at one exactly when at the other. -/
theorem conviction_same_key_state (p : Params) (env : Env) {l l' : Live} (hkey : l'.hash = l.hash)
    (c : Commitment) (payee : Addr) (now : Slot) :
    (c.entitles env l' payee now ↔ c.entitles env l payee now) ∧
      ((∃ f s, Step p env (.convict payee c) now (.present l') f s) ↔
        ∃ f s, Step p env (.convict payee c) now (.present l) f s) := by
  have he : l'.epoch = l.epoch := congrArg KeyState.epoch hkey
  have hs : l'.sn = l.sn := congrArg KeyState.sn hkey
  have hent := Commitment.entitles_same_key_state env c hkey payee now
  refine ⟨hent, ⟨?_, ?_⟩⟩
  · rintro ⟨f, s, h⟩
    obtain ⟨_, hl, hdup, held⟩ := convict_requires_entitlement p env h
    cases hl
    rw [he, hs] at hdup
    exact ⟨_, _, Step.convict now payee c hdup (hent.mp held)⟩
  · rintro ⟨f, s, h⟩
    obtain ⟨_, hl, hdup, held⟩ := convict_requires_entitlement p env h
    cases hl
    rw [← he, ← hs] at hdup
    exact ⟨_, _, Step.convict now payee c hdup (hent.mpr held)⟩

/-- **A top-up keeps every commitment.**
Given a top-up from a live output `l` to `l'`, by anyone.
When a conviction naming a payee and revealing a commitment is attempted at `l'`.
Then the commitment entitles that payee at `l'` exactly when it did at `l`, and
the conviction is accepted at `l'` exactly when it was at `l`. -/
theorem commitment_survives_topUp (p : Params) (env : Env) {x : Value} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env (.topUp x) t (.present l) f (.present l'))
    (c : Commitment) (payee : Addr) (now : Slot) :
    (c.entitles env l' payee now ↔ c.entitles env l payee now) ∧
      ((∃ f s, Step p env (.convict payee c) now (.present l') f s) ↔
        ∃ f s, Step p env (.convict payee c) now (.present l) f s) := by
  apply conviction_same_key_state
  cases h; rfl

/-- **A freeze keeps every commitment.**
Given a freeze from a live output `l` to `l'`.
When a conviction naming a payee and revealing a commitment is attempted at `l'`.
Then the commitment entitles that payee at `l'` exactly when it did at `l`, and
the conviction is accepted at `l'` exactly when it was at `l`. -/
theorem commitment_survives_freeze (p : Params) (env : Env) {sn' : Seq} {hunter : Addr} {t : Slot}
    {l l' : Live} {f : Flow} (h : Step p env (.freeze sn' hunter) t (.present l) f (.present l'))
    (c : Commitment) (payee : Addr) (now : Slot) :
    (c.entitles env l' payee now ↔ c.entitles env l payee now) ∧
      ((∃ f s, Step p env (.convict payee c) now (.present l') f s) ↔
        ∃ f s, Step p env (.convict payee c) now (.present l) f s) := by
  apply conviction_same_key_state
  cases h; rfl

/-- **A poison keeps every commitment.**
Given a poison from a live output `l` to `l'`.
When a conviction naming a payee and revealing a commitment is attempted at `l'`.
Then the commitment entitles that payee at `l'` exactly when it did at `l`, and
the conviction is accepted at `l'` exactly when it was at `l`. -/
theorem commitment_survives_poison (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env .poison t (.present l) f (.present l'))
    (c : Commitment) (payee : Addr) (now : Slot) :
    (c.entitles env l' payee now ↔ c.entitles env l payee now) ∧
      ((∃ f s, Step p env (.convict payee c) now (.present l') f s) ↔
        ∃ f s, Step p env (.convict payee c) now (.present l) f s) := by
  apply conviction_same_key_state
  cases h; rfl

/-- **A rotation voids every commitment over the key state it leaves.**
Given a rotation from a live output `l` to `l'`, and a commitment naming `l`'s key
state.
When a conviction naming any payee and revealing that commitment is attempted at
`l'` at any slot.
Then the commitment entitles nobody there, and the conviction is refused. Only the
holder of the next keys can rotate. -/
theorem rotation_voids_commitment (p : Params) (env : Env) {sn' : Seq} {op : BondOp}
    {hunter : Addr} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env (.rotate sn' op hunter) t (.present l) f (.present l'))
    {c : Commitment} (hc : c.keyState = l.hash) (payee : Addr) (now : Slot) :
    ¬ c.entitles env l' payee now ∧ ∀ f s, ¬ Step p env (.convict payee c) now (.present l') f s := by
  have hnot : ¬ c.entitles env l' payee now := by
    intro hent
    rcases step_keeps_key_state_or_rotates p env h with ⟨hr, _⟩ | ⟨_, he⟩
    · simp [Action.isRotation] at hr
    · have same : l.epoch = l'.epoch := congrArg KeyState.epoch (hc.symm.trans hent.1)
      rw [he] at same
      exact absurd same (Nat.ne_of_lt (Nat.lt_succ_self _))
  refine ⟨hnot, fun f s hs => ?_⟩
  obtain ⟨_, hl, _, hent⟩ := convict_requires_entitlement p env hs
  cases hl
  exact hnot hent

/-- **Along a trace the key state stays until a rotation, and then the epoch only grows.**
Given a trace from a live output `l` to a live output `l'`.
When their key states are compared.
Then if no action of the trace is a rotation the key state is the same, and if any
is, the epoch of `l'` is strictly higher. -/
theorem trace_key_state (p : Params) (env : Env) {t : Slot} {s s' : State}
    {es : List (Slot × Action)} (h : Trace p env t s es s') :
    ∀ {l l' : Live}, s = .present l → s' = .present l' →
      (es.any (fun e => e.2.isRotation) = false → l'.hash = l.hash) ∧
      (es.any (fun e => e.2.isRotation) = true → l.epoch < l'.epoch) := by
  induction h with
  | nil => intro l l' hl hl'; subst hl; cases hl'; simp
  | @cons t₀ t₁ s₀ s₁ s₂ a f rest _ hs htail ih =>
    intro l l' hl hl'
    subst hl
    cases s₁ with
    | present m =>
      obtain ⟨ih₁, ih₂⟩ := ih rfl hl'
      have rest_le : m.epoch ≤ l'.epoch := by
        cases hr : rest.any (fun e => e.2.isRotation)
        · exact Nat.le_of_eq (congrArg KeyState.epoch (ih₁ hr)).symm
        · exact Nat.le_of_lt (ih₂ hr)
      rcases step_keeps_key_state_or_rotates p env hs with ⟨ha, hh⟩ | ⟨ha, he⟩
      · have hme : m.epoch = l.epoch := congrArg KeyState.epoch hh
        simp only [List.any_cons, ha, Bool.false_or]
        exact ⟨fun hr => (ih₁ hr).trans hh, fun hr => hme ▸ ih₂ hr⟩
      · simp only [List.any_cons, ha, Bool.true_or]
        refine ⟨fun hr => Bool.noConfusion hr, fun _ => ?_⟩
        calc l.epoch < l.epoch + 1 := Nat.lt_succ_self _
          _ = m.epoch := he.symm
          _ ≤ l'.epoch := rest_le
    | terminationPending k =>
      have := trace_from_pending p env htail
      subst this
      cases hl'
    | absent => cases hs
    | convicted => cases hs

/-- **A commitment survives every trace without a rotation.**
Given a trace from a live output `l` to a live output `l'` in which no action is a
rotation (any number of top-ups, freezes and poisons).
When a conviction naming a payee and revealing a commitment is attempted at `l'`.
Then the commitment entitles that payee at `l'` exactly when it did at `l`, and
the conviction is accepted at `l'` exactly when it was at `l`. -/
theorem commitment_survives_without_rotation (p : Params) (env : Env) {t : Slot}
    {es : List (Slot × Action)} {l l' : Live} (h : Trace p env t (.present l) es (.present l'))
    (hnone : es.any (fun e => e.2.isRotation) = false) (c : Commitment) (payee : Addr) (now : Slot) :
    (c.entitles env l' payee now ↔ c.entitles env l payee now) ∧
      ((∃ f s, Step p env (.convict payee c) now (.present l') f s) ↔
        ∃ f s, Step p env (.convict payee c) now (.present l) f s) :=
  conviction_same_key_state p env ((trace_key_state p env h rfl rfl).1 hnone) c payee now

/-- **A commitment does not survive a rotation, whatever follows it.**
Given a commitment naming the key state of a live output `l`, and a trace from `l`
to a live output `l'` in which some action is a rotation.
When a conviction naming any payee and revealing that commitment is attempted at
`l'` at any slot.
Then the commitment entitles nobody there, and the conviction is refused. -/
theorem rotation_voids_commitment_along_trace (p : Params) (env : Env) {t : Slot}
    {es : List (Slot × Action)} {l l' : Live} (h : Trace p env t (.present l) es (.present l'))
    (hsome : es.any (fun e => e.2.isRotation) = true) {c : Commitment} (hc : c.keyState = l.hash)
    (payee : Addr) (now : Slot) :
    ¬ c.entitles env l' payee now ∧ ∀ f s, ¬ Step p env (.convict payee c) now (.present l') f s := by
  have later := (trace_key_state p env h rfl rfl).2 hsome
  have hnot : ¬ c.entitles env l' payee now := fun hent =>
    Nat.ne_of_lt later (congrArg KeyState.epoch (hc.symm.trans hent.1))
  refine ⟨hnot, fun f s hs => ?_⟩
  obtain ⟨_, hl, _, hent⟩ := convict_requires_entitlement p env hs
  cases hl
  exact hnot hent

/-! ## The system holds the commitments and burns the one a conviction reveals -/

/-- **What a revealed commitment must be.**
Given a system, an AID and an action.
When the system step's commitment premise is read.
Then it holds exactly when the commitment the action reveals, if any, is open under
its own marker and names that AID and the system's deployment. -/
theorem Sys.revealOpen_iff (s : Sys) (aid : AID) (a : Action) :
    s.revealOpen aid a ↔ ∀ c, a.revealed = some c →
      s.commitments c.marker = some c ∧ c.aid = aid ∧ c.deployment = s.deployment := by
  unfold Sys.revealOpen Sys.revealOpenB
  cases a.revealed with
  | none => simp
  | some c => simp

/-- **Every open commitment is well formed and kept under its own marker.**
Given a reachable system.
When an open commitment is read under marker `m`.
Then its marker is `m`, and it is first eligible in the slot after its opening and no later
than it expires. -/
theorem ledger_well_formed (p : Params) (env : SystemEnv) {s : Sys} (h : SysReach p env s) :
    ∀ m c, s.commitments m = some c → c.marker = m ∧ c.wellFormed := by
  induction h with
  | init d => intro m c found; cases found
  | step _ hs ih =>
    intro m c found
    cases hs with
    | register event =>
      obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, _, _, _, rfl⟩ := event
      exact ih m c found
    | «local» event =>
      obtain ⟨x, a, now, f, st, _, _, _, rfl⟩ := event
      unfold Sys.retireRevealed at found
      cases hr : a.revealed with
      | none => rw [hr] at found; exact ih m c found
      | some r =>
        rw [hr] at found
        simp only [Sys.retire, Sys.set] at found
        split at found
        · cases found
        · exact ih m c found
    | book event =>
      obtain ⟨x, k, origin, before, booked, booker, fee, b, f, entry,
        _, _, _, _, _, _, _, _, _, rfl⟩ := event
      exact ih m c found
    | complete event =>
      obtain ⟨x, assoc, receipt, _, rfl⟩ := event
      exact ih m c found
    | openCommitment event =>
      obtain ⟨d, _, formed, rfl⟩ := event
      simp only at found
      split at found
      · rename_i same
        cases found
        exact ⟨same.symm, formed⟩
      · exact ih m c found
    | reveal event =>
      obtain ⟨d, now, _, _, _, rfl⟩ := event
      simp only [Sys.retire] at found
      split at found
      · cases found
      · exact ih m c found
    | sweep event =>
      obtain ⟨d, now, _, _, rfl⟩ := event
      simp only [Sys.retire] at found
      split at found
      · cases found
      · exact ih m c found

/-- **A system conviction consumes an open, entitling commitment.**
Given any system step after which an AID's live output `l` is a pending
termination.
When the step is read.
Then it is a conviction paying some `payee` at some slot that revealed a
commitment `c`: before the step `c` was open under its marker and named that AID
and the system's deployment,
`c` entitles `payee` to convict `l` at that slot, and after the step `c` is no
longer open (its marker is burnt, so it entitles no second conviction). -/
theorem sys_conviction_consumes_commitment (p : Params) (env : SystemEnv) {s s' : Sys}
    (h : SysStep p env s s') {aid : AID} {l : Live} {k : Hash}
    (hlive : s.states aid = .present l) (hpending : s'.states aid = .terminationPending k) :
    ∃ (payee : Addr) (c : Commitment) (now : Slot),
      s.commitments c.marker = some c ∧ c.aid = aid ∧ c.deployment = s.deployment ∧
      c.entitles (env aid) l payee now ∧ s'.commitments c.marker = none := by
  cases h with
  | register event =>
    obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, step, _, _, rfl⟩ := event
    by_cases same : aid = x
    · subst same
      rw [hlive] at step
      cases step
    · simp [Sys.installOrigin, Sys.set, same, hlive] at hpending
  | «local» event =>
    obtain ⟨x, a, now, f, st, _, step, opened, rfl⟩ := event
    by_cases same : aid = x
    · subst same
      simp [Sys.set] at hpending
      subst hpending
      rw [hlive] at step
      obtain ⟨l', payee, c, hl, rfl, _, hent, _⟩ := pending_only_by_conviction p _ step
      cases hl
      obtain ⟨hopen, haid, hdep⟩ := (Sys.revealOpen_iff _ _ _).mp opened.1 c rfl
      refine ⟨payee, c, now, hopen, haid, hdep, hent, ?_⟩
      simp [Sys.retireRevealed, Action.revealed, Sys.retire]
    · simp [Sys.set, same, hlive] at hpending
  | book event =>
    obtain ⟨x, k', origin, before, booked, booker, fee, b, f, entry,
      _, _, _, _, _, _, _, _, _, rfl⟩ := event
    simp [Sys.associate, hlive] at hpending
  | complete event =>
    obtain ⟨x, assoc, receipt, _, rfl⟩ := event
    by_cases same : aid = x
    · subst same
      simp [Sys.finish, Sys.set] at hpending
    · simp [Sys.finish, Sys.set, same, hlive] at hpending
  | openCommitment event =>
    obtain ⟨d, _, _, rfl⟩ := event
    simp [hlive] at hpending
  | reveal event =>
    obtain ⟨d, now, _, _, _, rfl⟩ := event
    simp [Sys.retire, hlive] at hpending
  | sweep event =>
    obtain ⟨d, now, _, _, rfl⟩ := event
    simp [Sys.retire, hlive] at hpending

/-- **A reachable system never convicts in a commitment's opening slot.**
Given a reachable system and a step after which an AID's live output `l` is a
pending termination.
When the commitment that step reveals is read.
Then the conviction's slot is strictly after the upper end of the commitment's
opening transaction's validity range, so the opening transaction cannot share the
conviction's slot. -/
theorem sys_conviction_after_opening_slot (p : Params) (env : SystemEnv) {s s' : Sys}
    (reach : SysReach p env s) (h : SysStep p env s s') {aid : AID} {l : Live} {k : Hash}
    (hlive : s.states aid = .present l) (hpending : s'.states aid = .terminationPending k) :
    ∃ (payee : Addr) (c : Commitment) (now : Slot),
      s.commitments c.marker = some c ∧ c.entitles (env aid) l payee now ∧ c.openedAt < now := by
  obtain ⟨payee, c, now, hopen, _, _, hent, _⟩ :=
    sys_conviction_consumes_commitment p env h hlive hpending
  have formed := (ledger_well_formed p env reach c.marker c hopen).2
  exact ⟨payee, c, now, hopen, hent, (commitment_eligible_from_next_slot formed now).mp hent.2.2.2.1⟩

/-- **A commitment closes only inside or after its window.**
Given a reachable system with a commitment `c` open under marker `m`, and a step
after which nothing is open under `m`.
When the step is read.
Then it happened at a slot inside `c`'s window (a reveal, or the conviction that
revealed `c`) or strictly after it (a sweep); never before `c` was eligible. -/
theorem commitment_closes_in_or_after_window (p : Params) (env : SystemEnv) {s s' : Sys}
    (reach : SysReach p env s) (h : SysStep p env s s') {m : Marker} {c : Commitment}
    (hopen : s.commitments m = some c) (hclosed : s'.commitments m = none) :
    ∃ now : Slot, (c.eligibleAfter ≤ now ∧ now ≤ c.expiresAt) ∨ c.expiresAt < now := by
  have named := (ledger_well_formed p env reach m c hopen).1
  cases h with
  | register event =>
    obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, _, _, _, rfl⟩ := event
    simp [Sys.installOrigin, Sys.set, hopen] at hclosed
  | «local» event =>
    obtain ⟨x, a, now, f, st, _, step, opened, rfl⟩ := event
    cases hr : a.revealed with
    | none => simp [Sys.retireRevealed, hr, Sys.set, hopen] at hclosed
    | some r =>
      simp only [Sys.retireRevealed, hr, Sys.retire, Sys.set] at hclosed
      by_cases same : m = r.marker
      · cases a with
        | convict payee r' =>
          cases hr
          obtain ⟨ropen, _⟩ := (Sys.revealOpen_iff _ _ _).mp opened.1 r rfl
          rw [← same, hopen] at ropen
          cases ropen
          obtain ⟨_, _, _, hent⟩ := convict_requires_entitlement p _ step
          exact ⟨now, Or.inl ⟨hent.2.2.2.1, hent.2.2.2.2⟩⟩
        | register | rotate | poison | freeze | topUp => cases hr
      · simp [same, hopen] at hclosed
  | book event =>
    obtain ⟨x, k, origin, before, booked, booker, fee, b, f, entry,
      _, _, _, _, _, _, _, _, _, rfl⟩ := event
    simp [Sys.associate, hopen] at hclosed
  | complete event =>
    obtain ⟨x, assoc, receipt, _, rfl⟩ := event
    simp [Sys.finish, Sys.set, hopen] at hclosed
  | openCommitment event =>
    obtain ⟨d, free, _, rfl⟩ := event
    simp only at hclosed
    split at hclosed
    · cases hclosed
    · rw [hopen] at hclosed; cases hclosed
  | reveal event =>
    obtain ⟨d, now, dopen, early, late, rfl⟩ := event
    simp only [Sys.retire] at hclosed
    by_cases same : m = d.marker
    · rw [← same, hopen] at dopen
      cases dopen
      exact ⟨now, Or.inl ⟨early, late⟩⟩
    · simp [same, hopen] at hclosed
  | sweep event =>
    obtain ⟨d, now, dopen, expired, rfl⟩ := event
    simp only [Sys.retire] at hclosed
    by_cases same : m = d.marker
    · rw [← same, hopen] at dopen
      cases dopen
      exact ⟨now, Or.inr expired⟩
    · simp [same, hopen] at hclosed


/-! ## The system keeps a commitment while the key state stays, and at one deployment -/

/-- **A system keeps its deployment.**
Given any system step.
When the deployment is read before and after it.
Then it is the same. -/
theorem sys_step_keeps_deployment (p : Params) (env : SystemEnv) {s s' : Sys} (h : SysStep p env s s') :
    s'.deployment = s.deployment := by
  cases h with
  | register event =>
    obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, _, _, _, rfl⟩ := event
    rfl
  | «local» event =>
    obtain ⟨x, a, now, f, st, _, _, _, rfl⟩ := event
    unfold Sys.retireRevealed
    cases a.revealed <;> rfl
  | book event =>
    obtain ⟨x, k, origin, before, booked, booker, fee, b, f, entry,
      _, _, _, _, _, _, _, _, _, rfl⟩ := event
    rfl
  | complete event =>
    obtain ⟨x, assoc, receipt, _, rfl⟩ := event
    rfl
  | openCommitment event =>
    obtain ⟨d, _, _, rfl⟩ := event
    rfl
  | reveal event =>
    obtain ⟨d, now, _, _, _, rfl⟩ := event
    rfl
  | sweep event =>
    obtain ⟨d, now, _, _, rfl⟩ := event
    rfl

/-- **A top-up, a freeze or a poison leaves every commitment open and entitling.**
Given a system whose AID holds the live output `l`, and a system step after which
that AID holds a different live output `l'` with the same key state (a top-up by
anyone, a freeze or a poison of that checkpoint).
When the commitments are read after the step and a conviction of the AID revealing
a commitment `c` is considered.
Then the step opened and burnt no commitment, the system's premise on `c` holds
after the step exactly when it held before, and `c` entitles a payee at `l'`
exactly when it did at `l`. -/
theorem sys_commitment_survives_key_state_step (p : Params) (env : SystemEnv) {s s' : Sys}
    (h : SysStep p env s s') {aid : AID} {l l' : Live}
    (hlive : s.states aid = .present l) (hlive' : s'.states aid = .present l')
    (hspent : l' ≠ l) (hkey : l'.hash = l.hash) (c : Commitment) (payee : Addr) (now : Slot) :
    s'.commitments = s.commitments ∧
      (s'.revealOpen aid (.convict payee c) ↔ s.revealOpen aid (.convict payee c)) ∧
      (c.entitles (env aid) l' payee now ↔ c.entitles (env aid) l payee now) := by
  have hdep := sys_step_keeps_deployment p env h
  have hcomm : s'.commitments = s.commitments := by
    cases h with
    | register event =>
      obtain ⟨x, t, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, _, _, _, rfl⟩ := event
      rfl
    | «local» event =>
      obtain ⟨x, a, t, f, st, _, step, _, rfl⟩ := event
      by_cases same : aid = x
      · subst same
        simp [Sys.set] at hlive'
        subst hlive'
        rw [hlive] at step
        cases a with
        | convict payee' c' => cases step
        | register | rotate | poison | freeze | topUp => rfl
      · simp [Sys.set, same, hlive] at hlive'
        exact absurd hlive'.symm hspent
    | book event =>
      obtain ⟨x, k, origin, before, booked, booker, fee, b, f, entry,
        _, _, _, _, _, _, _, _, _, rfl⟩ := event
      rfl
    | complete event =>
      obtain ⟨x, assoc, receipt, _, rfl⟩ := event
      rfl
    | openCommitment event =>
      obtain ⟨d, _, _, rfl⟩ := event
      simp [hlive] at hlive'
      exact absurd hlive'.symm hspent
    | reveal event =>
      obtain ⟨d, t, _, _, _, rfl⟩ := event
      simp [Sys.retire, hlive] at hlive'
      exact absurd hlive'.symm hspent
    | sweep event =>
      obtain ⟨d, t, _, _, rfl⟩ := event
      simp [Sys.retire, hlive] at hlive'
      exact absurd hlive'.symm hspent
  refine ⟨hcomm, ?_, Commitment.entitles_same_key_state (env aid) c hkey payee now⟩
  simp [Sys.revealOpen, Sys.revealOpenB, Action.revealed, hcomm, hdep]

/-- **A commitment naming another deployment is refused.**
Given a system and a commitment naming a deployment other than the system's.
When a conviction of any AID naming any payee reveals that commitment.
Then the system's premise on the commitment fails: the conviction is refused,
whether or not the commitment is open and whatever else it names. -/
theorem sys_conviction_refused_for_other_deployment (s : Sys) (aid : AID) (payee : Addr)
    {c : Commitment} (hother : c.deployment ≠ s.deployment) :
    ¬ s.revealOpen aid (.convict payee c) :=
  fun h => hother ((Sys.revealOpen_iff _ _ _).mp h c rfl).2.2

/-- **A commitment convicts at its own deployment and at no other.**
Given a conviction that one system accepts for an AID (its checkpoint step convicts
and the revealed commitment is open there, naming that AID and that system's
deployment), and a second system in which the same commitment is open and the same
AID holds a live output carrying the key state the commitment names.
When the same conviction is attempted in the second system.
Then its checkpoint step convicts there too, and the second system accepts the
conviction exactly when it is the same deployment as the first: at a checkpoint of
another deployment with the same identifier and key state it is refused. -/
theorem sys_conviction_only_at_commitment_deployment (p : Params) (env : Env) {s₁ s₂ : Sys}
    {aid : AID} {payee : Addr} {c : Commitment} {now : Slot} {f : Flow} {st : State} {l₂ : Live}
    (hstep : Step p env (.convict payee c) now (s₁.states aid) f st)
    (hopen₁ : s₁.revealOpen aid (.convict payee c))
    (hlive₂ : s₂.states aid = .present l₂) (hkey : c.keyState = l₂.hash)
    (hopen₂ : s₂.commitments c.marker = some c) :
    (∃ f' st', Step p env (.convict payee c) now (s₂.states aid) f' st') ∧
      (s₂.revealOpen aid (.convict payee c) ↔ s₂.deployment = s₁.deployment) := by
  obtain ⟨l₁, _, hdup, hent⟩ := convict_requires_entitlement p env hstep
  obtain ⟨_, haid, hdep₁⟩ := (Sys.revealOpen_iff _ _ _).mp hopen₁ c rfl
  have hh : l₂.hash = l₁.hash := hkey.symm.trans hent.1
  have he : l₂.epoch = l₁.epoch := congrArg KeyState.epoch hh
  have hs : l₂.sn = l₁.sn := congrArg KeyState.sn hh
  rw [← he, ← hs] at hdup
  refine ⟨?_, fun h₂ => ?_, fun same => ?_⟩
  · rw [hlive₂]
    exact ⟨_, _, Step.convict now payee c hdup
      ((Commitment.entitles_same_key_state env c hh payee now).mpr hent)⟩
  · exact ((Sys.revealOpen_iff _ _ _).mp h₂ c rfl).2.2.symm.trans hdep₁
  · refine (Sys.revealOpen_iff _ _ _).mpr fun c' revealed => ?_
    cases revealed
    exact ⟨hopen₂, haid, hdep₁.trans same.symm⟩

end CardanoKeri.Checkpoint
