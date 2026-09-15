import CardanoKeri.RegistryGoals

/-!
# The registry–checkpoint lifecycle agreement (INV408-04)

The per-AID lifecycle view of a registry state, in `CardanoKeri.Checkpoint`'s
D-040 vocabulary (`absent`, `present`, `parked`, `convicted`), plus the two
*transit* views the two-stage transport forces on any observer: a pending
go-request carrying the already-retained key state, and the immediately
reapable tombstone's pending conviction.

This is a projection, not an equality: a raw registry step is *not* an atomic
checkpoint step. A close (present → parked in D-040 terms) is two raw steps —
the authorized reap, then the fold that lands the go-request — and the
projection names the transit state `closing` between them. `Checkpoint.lean`
is read-only; nothing here rewrites ticket 324's machine. Custody of the
closing key state across the pending request rests on the preserved R9
theorems (a go-request is never retractable, never rejectable); the
parked-leaf statement below is INV408-05.
-/

namespace CardanoKeri.Registry.Agreement

/-- The pending go-request for `aid`, if any: the first inbox entry for `aid`
whose op is not user-postable. At most one exists in a reachable system
(`Inv.goUnique`). -/
def pendingGo (s : Sys) (aid : AID) : Option Op :=
  match s.requests.filter fun x => x.2.aid = aid ∧ x.2.op.userPostable = false with
  | [] => none
  | x :: _ => some x.2.op

/-- The per-AID lifecycle view. `dangling` classifies an active leaf with no
checkpoint and no pending go-request — exactly what `Inv.activeCkpt` forbids;
reachable systems therefore never project there (an owner-audited claim). -/
inductive RegLife where
  /-- Never registered. -/
  | absent
  /-- The checkpoint UTxO is on chain (live or tombstone transport state). -/
  | present
  /-- A live bond has been closed; the closing rotation's reached key state
  `k` rides in the pending go-request. -/
  | closing (k : KeyState)
  /-- A tombstone has been reaped; conviction rides in the pending request. -/
  | closingTomb
  /-- The retained parked registry hash: leaf `dormant k`, no on-chain
  checkpoint (INV408-01: not an on-chain parked checkpoint). -/
  | parked (k : KeyState)
  /-- Terminal conviction. -/
  | convicted
  /-- Active leaf, no checkpoint, no pending go-request: unreachable. -/
  | dangling
  deriving Repr, DecidableEq

/-- The projection (INV408-04), nested so each layer computes against
unchanged interfaces. -/
def project (s : Sys) (aid : AID) : RegLife :=
  match lookup s.ckpts aid with
  | some _ => .present
  | none =>
    match lookup s.leaves aid with
    | some (.dormant k) => .parked k
    | some .convicted => .convicted
    | some (.active _) =>
      match pendingGo s aid with
      | some (.goDormant k) => .closing k
      | some .goConvicted => .closingTomb
      | _ => .dangling
    | none => .absent

/-- INV408-05: an actual parked leaf (the retained registry hash `k`) implies
no checkpoint, and the projection reads the reached key state off the leaf. -/
theorem parked_leaf_no_ckpt {p : Params} {s : Sys} (h : ReachFar p env s) (aid : AID)
    {k : KeyState} (hl : lookup s.leaves aid = some (.dormant k)) :
    lookup s.ckpts aid = none ∧ project s aid = .parked k :=
  by
  have hc : lookup s.ckpts aid = none :=
    R1_not_active_no_ckpt p env h aid hl (fun tok => by simp)
  exact ⟨hc, by simp [project, hc, hl]⟩

/-- **Refused-revival leaf custody (INV408-05, A-002(b)).** A posted revival
of `aid` is refused by a fold that tries to process it; the refusal consumes
nothing — there is no successor state — and the retained dormant leaf still
carries `k` while no checkpoint exists (the retained-registry-hash form of
dormant: no checkpoint UTxO). General over every reachable system, evidence
environment, slot, folder, generation, plugin and batch; `Registry.stepFn` is
unchanged. The refusal boundary is the actual `stepFn … = none` result; the
key-state retention clause is the retained-leaf hypothesis, the no-checkpoint
disentanglement is R1c. -/
theorem refused_revival_keeps_leaf
    {p : Params} {env : Env} {now : Slot} {s : Sys} (hreach : ReachFar p env s)
    {folder : Addr} {g : Gen} {pl : Script} {batch : List (ReqId × FoldAction)}
    {aid : AID} {k : KeyState} {id : ReqId} {owner : Addr} {t : Slot}
    (hl : lookup s.leaves aid = some (.dormant k))
    (hpost : (id, ⟨aid, owner, t, Op.revive⟩) ∈ s.requests)
    (hb : (id, FoldAction.process) ∈ batch)
    (href : stepFn p env (Action.fold folder g pl batch) now s = none) :
    lookup s.leaves aid = some (.dormant k) ∧ lookup s.ckpts aid = none :=
  ⟨hl, R1_not_active_no_ckpt p env hreach aid hl (fun _ => by simp)⟩

/-- Reached-key custody in the pending request (INV408-05): a closing key
state `k` rides in an actual inbox entry — which the preserved R9 theorems
keep pending (never retractable, never rejectable) until its fold lands. -/
theorem custody_of_pending {s : Sys} {aid : AID} {k : KeyState}
    (hp : pendingGo s aid = some (.goDormant k)) :
    ∃ x, x ∈ s.requests ∧ x.2.aid = aid ∧ x.2.op = .goDormant k :=
    by
  unfold pendingGo at hp
  split at hp
  · simp at hp
  · rename_i x xs hf
    have hx : x ∈ s.requests.filter
        (fun x => decide (x.2.aid = aid ∧ x.2.op.userPostable = false)) := by
      rw [hf]; exact List.mem_cons_self
    have hmem := List.mem_filter.mp hx
    refine ⟨x, hmem.1, ?_, ?_⟩
    · exact (of_decide_eq_true hmem.2).1
    · simpa using hp
/-! ## A-002(a) as ruled by A-003: universal pending custody -/

/-- `pendingGo` reads the head of the filtered inbox. The filter predicate is
inlined verbatim (exactly the one inside `pendingGo`), so rewriting stays
syntactic. -/
def pendingGoIn (rs : List (ReqId × Request)) (aid : AID) : Option Op :=
  match rs.filter (fun x => decide (x.2.aid = aid ∧ x.2.op.userPostable = false)) with
  | [] => none
  | x :: _ => some x.2.op

theorem pendingGo_eq_pendingGoIn (s : Sys) (aid : AID) :
    pendingGo s aid = pendingGoIn s.requests aid := rfl

/-- **The consuming-fold exception** (A-002(a) as ruled by A-003): a fold
whose batch processes the actual pending go-request of `aid` — identified
from the prestate by the request the prestate inbox holds (`aid`, key state
`k`), not by whether the postcondition happens to fail, not exempting every
fold, and carrying no hidden premise. -/
def consumesPending (s : Sys) (aid : AID) (k : KeyState) (a : Action) : Prop :=
  ∃ folder g pl batch id owner t, a = Action.fold folder g pl batch ∧
    (id, FoldAction.process) ∈ batch ∧
    lookup s.requests id = some ⟨aid, owner, t, Op.goDormant k⟩

/-- A non-pending head is dropped by the filter. -/
theorem pendingPred_cons_neg {rs : List (ReqId × Request)} {aid : AID} {x : ReqId × Request}
    (hp : ¬ (x.2.aid = aid ∧ x.2.op.userPostable = false)) :
    (x :: rs).filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
      = rs.filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) := by
  simp [List.filter, hp]

/-- A pending head is kept by the filter. -/
theorem pendingPred_cons_pos {rs : List (ReqId × Request)} {aid : AID} {x : ReqId × Request}
    (hp : x.2.aid = aid ∧ x.2.op.userPostable = false) :
    (x :: rs).filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
      = x :: rs.filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) := by
  simp [List.filter, hp]

/-- Removing an absent identifier leaves the list unchanged. -/
theorem remove_absent {α : Type} {rs : List (Nat × α)} {id : Nat}
    (h : id ∉ rs.map (·.1)) : remove rs id = rs := by
  induction rs with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨j, r'⟩ := x
    have hj : j ≠ id := fun e => h (List.mem_map.2 ⟨(j, r'), List.mem_cons.2 (Or.inl rfl), e⟩)
    simp only [remove, if_neg hj]
    rw [ih (fun hm => h (List.mem_cons.2 (Or.inr hm)))]

/-- Removing a request that fails the pending predicate cannot change the
filtered inbox: identifier uniqueness means removal touches nothing else, and
the removed entry was filtered out anyway. -/
theorem pendingPred_remove {rs : List (ReqId × Request)} {aid : AID} {id : ReqId} {r : Request}
    (hnd : (rs.map (·.1)).Nodup) (hl : lookup rs id = some r)
    (hnp : ¬ (r.aid = aid ∧ r.op.userPostable = false)) :
    (remove rs id).filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
      = rs.filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) := by
  induction rs with
  | nil => simp [lookup] at hl
  | cons x rs ih =>
    obtain ⟨i, r'⟩ := x
    by_cases hii : i = id
    · subst hii
      simp [lookup] at hl
      subst hl
      have hnm : i ∉ rs.map (·.1) := by
        intro hc
        have hpair : List.Pairwise (fun a b : ReqId => a ≠ b)
            ((fun x => x.1) (i, r') :: rs.map (·.1)) := hnd
        rw [List.mem_map] at hc
        obtain ⟨z, hz, he⟩ := hc
        have hz' : z.1 ∈ rs.map (·.1) := List.mem_map.2 ⟨z, hz, rfl⟩
        have hp1 := (List.pairwise_cons.1 hpair).1
        exact absurd he.symm (hp1 z.1 hz')
      simp only [remove, if_pos rfl]
      rw [remove_absent hnm]
      simp [hnp]
    · have hnd' : (rs.map (·.1)).Nodup := (List.nodup_cons.1 hnd).2
      have hl' : lookup rs id = some r := by
        simp only [lookup, if_neg hii] at hl
        exact hl
      have ih' := ih hnd' hl'
      simp only [remove, if_neg hii]
      by_cases hp' : (r'.aid = aid ∧ r'.op.userPostable = false)
      · rw [pendingPred_cons_pos hp', pendingPred_cons_pos hp']
        rw [ih']
      · rw [pendingPred_cons_neg hp', pendingPred_cons_neg hp']
        rw [ih']

/-- The filtered inbox is invariant through an applied batch, as long as no
batch element processes the pending request itself (`hxc`). The batch
invariant is threaded with the existing post-operation boundary lemmas
(`processOne_inv`, `rejectOne_inv` — a successful competing fold may process
a foreign go-request, which these preserve), NOT by any claim that removing
an arbitrary request preserves `AccInv`: `activeCkpt` is existential and
removing its very witness would destroy it. `y` is the pending entry;
reachability and uniqueness come from the batch invariant. -/
theorem pendingPred_applyBatch {p : Params} {env : Env} {now : Slot} {aid : AID} {k : KeyState}
    {n : ReqId} {s : Sys} {y : ReqId × Request} (inv : Inv p s)
    (hya : y.2.aid = aid) (hyk : y.2.op = .goDormant k) (hynp : y.2.op.userPostable = false)
    (hys : y ∈ s.requests)
    : ∀ (batch : List (ReqId × FoldAction)),
      (∀ id, (id, .process) ∈ batch →
         ∀ owner t, lookup s.requests id = some ⟨aid, owner, t, .goDormant k⟩ → False) →
      ∀ {acc acc' : Acc}, AccInv p n acc → y ∈ acc.requests →
        (∀ x, x ∈ acc.requests → x ∈ s.requests) →
        (acc.requests.filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
            = s.requests.filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))) →
        applyBatch p env now acc batch = some acc' →
        acc'.requests.filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
          = s.requests.filter (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) := by
  intro batch
  induction batch with
  | nil =>
    intro hxc acc acc' hi hmem hsub hwinv h
    simp only [applyBatch, Option.some.injEq] at h
    subst h
    exact hwinv
  | cons x rest ih =>
    obtain ⟨i, fa⟩ := x
    intro hxc acc acc' hi hmem hsub hwinv h
    rcases hl : lookup acc.requests i with _ | r
    · simp [applyBatch, hl] at h
    · have hxc₁ : ∀ id, (id, .process) ∈ rest →
          ∀ owner t, lookup s.requests id = some ⟨aid, owner, t, .goDormant k⟩ → False :=
        fun id hm => hxc id (List.mem_cons_of_mem _ hm)
      have hsub₁ : ∀ x, x ∈ remove acc.requests i → x ∈ s.requests :=
        fun x hx => hsub x (mem_remove hx)
      cases fa with
      | process =>
        rcases hres : processOne p env now { acc with requests := remove acc.requests i } r
          with _ | acc₁
        · simp [applyBatch, hl, hres] at h
        · simp only [applyBatch, hl, hres] at h
          have hi₁ : AccInv p n acc₁ := processOne_inv p env now hi hl hres
          have hreq : acc₁.requests = remove acc.requests i := by
            rw [processOne_requests p env now hres]
          by_cases hP : (r.aid = aid ∧ r.op.userPostable = false)
          · -- the consumer: r is the pending entry itself — excluded
            exfalso
            have hyeq : y = (i, r) :=
              hi.goUnique y (i, r) hmem (lookup_some_mem hl) hynp hP.2 (hya.trans hP.1.symm)
            have h1 : y.1 = i := by rw [hyeq]
            have hlook : lookup s.requests i = some y.2 :=
              lookup_some_of_mem inv.reqNodup (by rw [← h1]; exact hys)
            have hyreq : y.2 = ⟨aid, y.2.owner, y.2.submittedAt, .goDormant k⟩ := by
              rw [← hya, ← hyk]
            exact hxc i (List.mem_cons.2 (Or.inl rfl)) y.2.owner y.2.submittedAt
              (by rw [hlook, hyreq])
          · have hfil : (remove acc.requests i).filter
                (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
              = acc.requests.filter
                (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) :=
              pendingPred_remove hi.reqNodup hl hP
            have hyi : y.1 ≠ i := by
              intro e
              subst e
              have hyeq : y = (y.1, r) := eq_of_mem_of_fst_eq hi.reqNodup hl hmem rfl
              rw [hyeq] at hya hynp
              exact absurd (⟨hya, hynp⟩ : r.aid = aid ∧ r.op.userPostable = false) hP
            have hmem₂ : y ∈ acc₁.requests := by rw [hreq]; exact mem_remove_of_mem hmem hyi
            have hsub₂ : ∀ x, x ∈ acc₁.requests → x ∈ s.requests := by
              intro x hx
              rw [hreq] at hx
              exact hsub₁ x hx
            have hwinv₂ : acc₁.requests.filter
                  (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
                = s.requests.filter
                  (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) := by
              rw [hreq]
              exact hfil.trans hwinv
            have hind := ih hxc₁ hi₁ hmem₂ hsub₂ hwinv₂ h
            exact hind
      | reject =>
        rcases hres : rejectOne p now { acc with requests := remove acc.requests i } r
          with _ | acc₁
        · simp [applyBatch, hl, hres] at h
        · simp only [applyBatch, hl, hres] at h
          have hi₁ : AccInv p n acc₁ := rejectOne_inv p now hi hl hres
          have hupreq : r.op.userPostable = true ∧ acc₁.requests = remove acc.requests i := by
            simp only [rejectOne, Option.some.injEq] at hres
            split at hres
            · rename_i hc
              obtain ⟨rfl⟩ := hres
              exact ⟨hc.2, rfl⟩
            · cases hres
          obtain ⟨hup, hreq⟩ := hupreq
          have hfil : (remove acc.requests i).filter
                (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
              = acc.requests.filter
                (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) :=
              pendingPred_remove hi.reqNodup hl (by simp [hup])
          have hyi : y.1 ≠ i := by
            intro e
            subst e
            have hyeq : y = (y.1, r) := eq_of_mem_of_fst_eq hi.reqNodup hl hmem rfl
            rw [hyeq] at hya hynp
            exact absurd (⟨hya, hynp⟩ : r.aid = aid ∧ r.op.userPostable = false) (by simp [hup])
          have hmem₂ : y ∈ acc₁.requests := by rw [hreq]; exact mem_remove_of_mem hmem hyi
          have hsub₂ : ∀ x, x ∈ acc₁.requests → x ∈ s.requests := by
            intro x hx
            rw [hreq] at hx
            exact hsub₁ x hx
          have hwinv₂ : acc₁.requests.filter
                (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false))
              = s.requests.filter
                (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) := by
            rw [hreq]
            exact hfil.trans hwinv
          have hind := ih hxc₁ hi₁ hmem₂ hsub₂ hwinv₂ h
          exact hind

/-- **Universal pending custody (A-002(a) as ruled by A-003).** Before the
end of time, in a reachable system, a pending go-request carrying key state
`k` stays pending across EVERY successful action except the fold that
legitimately consumes it: posting, retracting, rejecting, and folds of
competing requests are all instances of the quantifier. The refused /
no-successor boundary is stated honestly: `stepFn` returning `none` produces
no successor state at all, and no preservation claim is made about one.
`Registry.stepFn` is unchanged; the hypotheses are exactly the ruled
`ReachFar p env s` and `now < p.far` plus the custody antecedent. -/
theorem pending_go_preserved {p : Params} {env : Env} {a : Action} {now : Slot}
    {s : Sys} {f : Flow} {s' : Sys}
    (hreach : ReachFar p env s) (hnow : now < p.far)
    {aid : AID} {k : KeyState} (hp : pendingGo s aid = some (.goDormant k))
    (hs : stepFn p env a now s = some (f, s'))
    (hxc : ¬ consumesPending s aid k a) :
    pendingGo s' aid = some (.goDormant k) := by
  have inv := reach_inv p env hreach
  rw [pendingGo_eq_pendingGoIn]
  simp only [pendingGoIn]
  unfold pendingGo at hp
  cases hfil : s.requests.filter
      (fun v => decide (v.2.aid = aid ∧ v.2.op.userPostable = false)) with
  | nil =>
    rw [hfil] at hp
    exact absurd hp (by simp)
  | cons y ys =>
    obtain ⟨yid, yreq⟩ := y
    obtain ⟨yaid, yowner, ysub, yop⟩ := yreq
    obtain ⟨hys, hydec⟩ :=
      List.mem_filter.mp (by rw [hfil]; exact List.mem_cons_self)
    obtain ⟨hya, hynp⟩ := of_decide_eq_true hydec
    have hyk : yop = .goDormant k := by
      rw [hfil] at hp
      simpa using hp
    cases a with
    | contribute a' o' t' op' =>
      simp only [stepFn] at hs
      split at hs
      · rename_i hup
        simp only [Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨_, rfl⟩ := hs
        have hnp0 : ¬ ((s.nextReq, Request.mk a' o' t' op').2.aid = aid ∧
            (s.nextReq, Request.mk a' o' t' op').2.op.userPostable = false) := by
          simp [hup]
        rw [pendingPred_cons_neg hnp0, hfil]
        simp [hyk]
      · cases hs
    | retract id =>
      simp only [stepFn] at hs
      split at hs
      · cases hs
      · rename_i r hl
        split at hs
        · rename_i h2
          simp only [Option.some.injEq, Prod.mk.injEq] at hs
          obtain ⟨_, rfl⟩ := hs
          have hup := go_not_phase2 inv hnow hl h2
          have hnp0 : ¬ (r.aid = aid ∧ r.op.userPostable = false) := by simp [hup]
          rw [pendingPred_remove inv.reqNodup hl hnp0, hfil]
          simp [hyk]
        · cases hs
    | reap reaper a' rec =>
      simp only [stepFn] at hs
      split at hs
      · cases hs
      · rename_i c hc
        split at hs
        · rename_i hr
          simp only [Option.some.injEq, Prod.mk.injEq] at hs
          obtain ⟨_, rfl⟩ := hs
          have hna : a' ≠ aid := by
            intro e
            rw [e] at hc
            rw [inv.goNoCkpt aid
              ⟨(yid, Request.mk yaid yowner ysub yop), hys, hya, hynp⟩] at hc
            simp at hc
          have hnp0 : ¬ ((s.nextReq, Request.mk a' reaper p.far (goOp c)).2.aid = aid ∧
              (s.nextReq, Request.mk a' reaper p.far (goOp c)).2.op.userPostable = false) := by
            simp [hna, goOp_not_postable]
          rw [pendingPred_cons_neg hnp0, hfil]
          simp [hyk]
        · cases hs
    | convictCkpt a' =>
      simp only [stepFn] at hs
      split at hs
      · rename_i hc
        split at hs
        · simp only [Option.some.injEq, Prod.mk.injEq] at hs
          obtain ⟨_, rfl⟩ := hs
          rw [hfil]
          simp [hyk]
        · cases hs
      · cases hs
    | fold folder g pl batch =>
      simp only [stepFn] at hs
      split at hs
      · split at hs
        · cases hs
        · rename_i acc hab
          simp only [Option.some.injEq, Prod.mk.injEq] at hs
          obtain ⟨_, rfl⟩ := hs
          have hxc' : ∀ id, (id, .process) ∈ batch →
              ∀ owner t, lookup s.requests id = some ⟨aid, owner, t, .goDormant k⟩ → False := by
            intro id hm owner t hlook
            exact hxc ⟨folder, g, pl, batch, id, owner, t, rfl, hm, hlook⟩
          have hres := pendingPred_applyBatch inv hya hyk hynp hys batch hxc'
            (accInv_of_inv inv) hys (fun x hx => hx) (by rfl) hab
          rw [hres, hfil]
          simp [hyk]
      · cases hs

end CardanoKeri.Registry.Agreement
