import CardanoKeri.CheckpointGoals

/-! A conviction pays only the payee of a commitment opened beforehand over this
checkpoint output and this evidence (#534, #271).

The release's commitment program is modelled as far as a conviction needs it:
opening (`OpenEvent`), revealing inside the window (`RevealEvent`, and the
conviction's own reveal), sweeping after expiry (`SweepEvent`); retiring the
marker is the burn every exit performs (`Sys.retire`). The conviction step
requires the commitment it reveals to name the convicted output, the evidence
the conviction shows and the payee paid, and the conviction slot to lie in the
commitment's window. The system step requires that commitment to be open and to
name the convicted AID, and burns it.

Left to the technical layer, and stated nowhere here: the hash that hides the
evidence and payee until the reveal, the nonce, the marker's derivation from the
opening seed, the deposit's amount and its payouts (to the payee at a reveal or
a conviction, to whoever signs a sweep), the payee's signatures, and the exact
age and lifetime the release applies (the model requires only that a commitment
is eligible strictly after its opening and no later than it expires). -/
namespace CardanoKeri.Checkpoint

/-! ## The conviction step reads the commitment -/

/-- The number of the three marks (poison, freeze, top-up) set on a live output. -/
def Live.marks (l : Live) : Nat := l.poisoned.toNat + l.frozen.toNat + l.toppedUp.toNat

/-- `l'` is a later output than `l`: a higher sequence number, or the same one with
more marks set. -/
def Live.before (l l' : Live) : Prop := l.sn < l'.sn ∨ (l.sn = l'.sn ∧ l.marks < l'.marks)

/-- Given two live outputs in the `Live.before` order.
When they are compared.
Then they differ: no output is later than itself. -/
theorem Live.before_irrefl (l : Live) : ¬ l.before l := by
  rintro (h | ⟨_, h⟩) <;> exact Nat.lt_irrefl _ h

/-- Given three live outputs, each later than the one before.
When the first and the last are compared.
Then the last is later than the first. -/
theorem Live.before_trans {l₁ l₂ l₃ : Live} (h₁ : l₁.before l₂) (h₂ : l₂.before l₃) :
    l₁.before l₃ := by
  rcases h₁ with h₁ | ⟨e₁, h₁⟩ <;> rcases h₂ with h₂ | ⟨e₂, h₂⟩
  · exact Or.inl (Nat.lt_trans h₁ h₂)
  · exact Or.inl (e₂ ▸ h₁)
  · exact Or.inl (e₁ ▸ h₂)
  · exact Or.inr ⟨e₁.trans e₂, Nat.lt_trans h₁ h₂⟩

/-- **Every step that spends a live output leaves a later one.**
Given any local step from a live output `l` to a live output `l'` (a rotation, a
poison, a freeze or a top-up, by whoever may submit it).
When the two outputs are compared.
Then `l'` is later than `l`: a rotation raises the sequence number, and a poison,
a freeze or a top-up sets a mark that was clear. -/
theorem step_output_later (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) : l.before l' := by
  cases h with
  | rotateKeepPaid _ _ _ _ hsn _ => exact Or.inl hsn
  | rotateKeepUnpaid _ _ _ _ hsn _ => exact Or.inl hsn
  | rotateDepositPaid _ _ _ _ hsn _ _ => exact Or.inl hsn
  | rotateDepositUnpaid _ _ _ _ hsn _ _ => exact Or.inl hsn
  | poison _ _ hclean =>
    refine Or.inr ⟨rfl, ?_⟩
    simp [Live.marks, hclean]
  | freeze _ _ _ _ _ _ hb _ =>
    refine Or.inr ⟨rfl, ?_⟩
    simp [Live.marks, hb]
  | topUp _ _ hfresh _ =>
    refine Or.inr ⟨rfl, ?_⟩
    simp [Live.marks, hfresh]

/-- **No output recurs.**
Given a nonempty trace from a live output `l` to a live output `l'`.
When the two outputs are compared.
Then `l'` is later than `l`, so it is a different output. -/
theorem trace_output_later (p : Params) (env : Env) {t : Slot} {s s' : State}
    {es : List (Slot × Action)} (h : Trace p env t s es s') :
    ∀ {l l' : Live}, s = .present l → s' = .present l' → es ≠ [] → l.before l' := by
  induction h with
  | nil => intro l l' _ _ hne; exact absurd rfl hne
  | @cons t₀ t₁ s₀ s₁ s₂ a f rest _ hs htail ih =>
    intro l l' hl hl' _
    subst hl
    cases s₁ with
    | present m =>
      have hm := step_output_later p env hs
      cases rest with
      | nil =>
        cases htail
        cases hl'
        exact hm
      | cons e rest' => exact Live.before_trans hm (ih rfl hl' (List.cons_ne_nil _ _))
    | terminationPending k =>
      have := trace_from_pending p env htail
      subst this
      cases hl'
    | absent => cases hs
    | convicted => cases hs

/-- **A commitment over a spent output entitles nothing afterwards.**
Given a commitment opened over the live output `l`, and a nonempty trace from `l`
to a live output `l'` (any rotation, poison, freeze or top-up in between).
When a conviction of `l'` reveals that commitment.
Then the commitment entitles no payee at any slot. -/
theorem spent_output_commitment_entitles_nothing (p : Params) (env : Env) {t : Slot}
    {es : List (Slot × Action)} {l l' : Live} (c : Commitment)
    (h : Trace p env t (.present l) es (.present l')) (hne : es ≠ []) (hc : c.output = l)
    (payee : Addr) (now : Slot) : ¬ c.entitles env l' payee now := by
  rintro ⟨hout, -⟩
  have later := trace_output_later p env h rfl rfl hne
  rw [← hc, hout] at later
  exact Live.before_irrefl _ later

/-- **A conviction pays only an entitled payee.**
Given any local step whose action is a conviction naming `payee` and revealing `c`.
When the step is read.
Then its source is a live output `l` with duplicity at its key state, and `c`
entitles `payee` to convict `l` at the step's slot: `c` names `l`, the evidence
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

/-- **A commitment for one checkpoint output entitles no other.**
Given a commitment naming a live output other than the one being convicted (another
checkpoint, or this checkpoint before a rotation, poison, freeze or top-up).
When the conviction is attempted with any payee at any slot.
Then it is refused. -/
theorem convict_refused_for_other_output (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hother : c.output ≠ l) :
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

/-- **A commitment opened in the slot of the conviction is refused.**
Given a commitment as the commitment program opens it (eligible strictly after the
upper end of its opening transaction's validity range), and a conviction slot no
later than that upper end — in particular the slot the opening transaction lands in.
When the conviction is attempted.
Then it is refused. -/
theorem convict_refused_in_opening_slot (p : Params) (env : Env) {l : Live} {payee : Addr}
    {c : Commitment} {t : Slot} (hformed : c.wellFormed) (hsame : t ≤ c.openedAt) :
    ∀ f s', ¬ Step p env (.convict payee c) t (.present l) f s' :=
  convict_refused_before_eligible p env (Nat.lt_of_le_of_lt hsame hformed.1)

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

/-! ## The system holds the commitments and burns the one a conviction reveals -/

/-- **What a revealed commitment must be.**
Given a system, an AID and an action.
When the system step's commitment premise is read.
Then it holds exactly when the commitment the action reveals, if any, is open under
its own marker and names that AID. -/
theorem Sys.revealOpen_iff (s : Sys) (aid : AID) (a : Action) :
    s.revealOpen aid a ↔ ∀ c, a.revealed = some c → s.commitments c.marker = some c ∧ c.aid = aid := by
  unfold Sys.revealOpen Sys.revealOpenB
  cases a.revealed with
  | none => simp
  | some c => simp

/-- **Every open commitment is well formed and kept under its own marker.**
Given a reachable system.
When an open commitment is read under marker `m`.
Then its marker is `m`, and it is eligible strictly after its opening and no later
than it expires. -/
theorem ledger_well_formed (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) :
    ∀ m c, s.commitments m = some c → c.marker = m ∧ c.wellFormed := by
  induction h with
  | init => intro m c found; cases found
  | step _ hs ih =>
    intro m c found
    cases hs with
    | register event =>
      obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, _, _, rfl⟩ := event
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
commitment `c`: before the step `c` was open under its marker and named that AID,
`c` entitles `payee` to convict `l` at that slot, and after the step `c` is no
longer open (its marker is burnt, so it entitles no second conviction). -/
theorem sys_conviction_consumes_commitment (p : Params) (env : Env) {s s' : Sys}
    (h : SysStep p env s s') {aid : AID} {l : Live} {k : Hash}
    (hlive : s.states aid = .present l) (hpending : s'.states aid = .terminationPending k) :
    ∃ (payee : Addr) (c : Commitment) (now : Slot),
      s.commitments c.marker = some c ∧ c.aid = aid ∧ c.entitles env l payee now ∧
      s'.commitments c.marker = none := by
  cases h with
  | register event =>
    obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, step, _, rfl⟩ := event
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
      obtain ⟨l', payee, c, hl, rfl, _, hent, _⟩ := pending_only_by_conviction p env step
      cases hl
      obtain ⟨hopen, haid⟩ := (Sys.revealOpen_iff _ _ _).mp opened c rfl
      refine ⟨payee, c, now, hopen, haid, hent, ?_⟩
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
theorem sys_conviction_after_opening_slot (p : Params) (env : Env) {s s' : Sys}
    (reach : SysReach p env s) (h : SysStep p env s s') {aid : AID} {l : Live} {k : Hash}
    (hlive : s.states aid = .present l) (hpending : s'.states aid = .terminationPending k) :
    ∃ (payee : Addr) (c : Commitment) (now : Slot),
      s.commitments c.marker = some c ∧ c.entitles env l payee now ∧ c.openedAt < now := by
  obtain ⟨payee, c, now, hopen, _, hent, _⟩ :=
    sys_conviction_consumes_commitment p env h hlive hpending
  have formed := (ledger_well_formed p env reach c.marker c hopen).2
  exact ⟨payee, c, now, hopen, hent, Nat.lt_of_lt_of_le formed.1 hent.2.2.2.1⟩

/-- **A commitment closes only inside or after its window.**
Given a reachable system with a commitment `c` open under marker `m`, and a step
after which nothing is open under `m`.
When the step is read.
Then it happened at a slot inside `c`'s window (a reveal, or the conviction that
revealed `c`) or strictly after it (a sweep); never before `c` was eligible. -/
theorem commitment_closes_in_or_after_window (p : Params) (env : Env) {s s' : Sys}
    (reach : SysReach p env s) (h : SysStep p env s s') {m : Marker} {c : Commitment}
    (hopen : s.commitments m = some c) (hclosed : s'.commitments m = none) :
    ∃ now : Slot, (c.eligibleAfter ≤ now ∧ now ≤ c.expiresAt) ∨ c.expiresAt < now := by
  have named := (ledger_well_formed p env reach m c hopen).1
  cases h with
  | register event =>
    obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, _, _, rfl⟩ := event
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
          obtain ⟨ropen, _⟩ := (Sys.revealOpen_iff _ _ _).mp opened r rfl
          rw [← same, hopen] at ropen
          cases ropen
          obtain ⟨_, _, _, hent⟩ := convict_requires_entitlement p env step
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

end CardanoKeri.Checkpoint
