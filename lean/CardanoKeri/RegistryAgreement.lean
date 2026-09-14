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

end CardanoKeri.Registry.Agreement
