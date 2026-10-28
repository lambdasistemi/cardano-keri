import CardanoKeri.RegistryCompleteness

/-! Construction facts for the Registry simulator's imported fold adapter.
These facts explain why synthetic structural approvals are not user inputs.
They do not establish application authorization or economic acceptance. -/
namespace CardanoKeri.Registry

deriving instance ReflBEq, LawfulBEq for Singular.Approval
deriving instance ReflBEq, LawfulBEq for Singular.Interval
deriving instance ReflBEq, LawfulBEq for Singular.BookingContents
deriving instance ReflBEq, LawfulBEq for Singular.RegistrationRequest
deriving instance ReflBEq, LawfulBEq for Singular.RegistrationBooking

/-- Given any configuration and actual economic fold member, when the imported
adapter constructs its structural request, then its edge is supported and its
complete approval tuple is admitted under that same configuration. -/
theorem projected_request_admitted (cfg : Singular.Config) (member : Singular.FoldMember) :
    Singular.allowed (Singular.foldLegacyRequest cfg member).edge = true ∧
    Singular.admitsFor cfg (Singular.foldLegacyRequest cfg member)
      (Singular.foldLegacyRequest cfg member).approval = true := by
  cases member <;>
    simp [Singular.foldLegacyRequest, Singular.allowed, Singular.admitsFor,
      Singular.requestDestination]

/-- Given any configuration and actual economic fold member, when the imported
adapter constructs its structural request, then the claimed keyed mint is the
edge's actual keyed delta. This is not the transaction's mint observation. -/
theorem projected_request_claim (cfg : Singular.Config) (member : Singular.FoldMember) :
    Singular.requestClaim (Singular.foldLegacyRequest cfg member) =
      Singular.assetDelta (Singular.foldLegacyRequest cfg member) := by
  cases member <;> rfl

/-- Given any list of actual economic members, when the imported adapter
constructs the structural batch, then its aggregate claimed mint equals its
aggregate actual mint; the economic transaction still owes its separate mint
checks. -/
theorem projected_batch_claim (cfg : Singular.Config) (members : List Singular.FoldMember) :
    Singular.claimedMint (members.map (Singular.foldLegacyRequest cfg)) =
      Singular.actualMint (members.map (Singular.foldLegacyRequest cfg)) := by
  unfold Singular.claimedMint Singular.actualMint
  simp only [List.foldl_map]
  congr 1

/-- Given any state and booking accepted by the imported registration judgment,
when the KERI registration pool prepends that booking, then its whole World
projection equals the accepted World. No reachability assumption is needed. -/
theorem registration_reconstruction {s : Sys} {b : Singular.RegistrationBooking}
    {world : Singular.World} (accepted : Singular.book s.toWorld b = .ok world) :
    ({ s with registrations := b :: s.registrations } : Sys).toWorld = world := by
  unfold Singular.book at accepted
  split at accepted
  · contradiction
  · split at accepted
    · contradiction
    · cases accepted
      rfl

/-- Given any state, including a malformed uploaded state, when an economic
fold selects a member from that state's actual pools, then the same metadata
lookup supplies that exact member. This does not assert World reachability. -/
theorem selected_member_available (s : Sys) (tx : Singular.EconomicTransaction)
    (member : Singular.FoldMember) (selected : member ∈ Singular.foldMembers s.toWorld tx) :
    MemberAvailable s member := by
  cases member with
  | registration b => exact (Singular.foldMembers_registration selected).1
  | termination b =>
    obtain ⟨input, _, chosen⟩ := List.mem_filterMap.mp selected
    cases reference : input.ref with
    | none => simp [reference] at chosen
    | some ref =>
      simp only [reference, Option.bind_some] at chosen
      unfold Singular.foldMemberAt at chosen
      cases registration : s.toWorld.pending.find? (fun b => b.request.reference == ref) with
      | some r => simp [registration] at chosen
      | none =>
        change s.registrations.find? (fun b => b.request.reference == ref) = none at registration
        simp only [Sys.toWorld, registration, List.find?_map] at chosen
        cases found : s.terminations.find? (fun e => e.booking.request.reference == ref) with
        | none => simp [Function.comp_def, found] at chosen
        | some e =>
          simp only [Function.comp_def, found, Option.map_some, Option.some.injEq,
            Singular.FoldMember.termination.injEq] at chosen
          have same : e.booking.request.reference = ref := by simpa using List.find?_some found
          exact ⟨e, by simpa [pendingAt, ← chosen, same] using found, chosen⟩

/-- Given any registration pool and a Boolean recovery selector, when recovery
keeps the selected bookings, then selecting the original pool by membership in
the result reproduces exactly that result, including ordering and duplicates. -/
theorem recovery_pool_membership (pool : List Singular.RegistrationBooking)
    (keep : Singular.RegistrationBooking → Bool) :
    pool.filter (fun b => (pool.filter keep).contains b) = pool.filter keep := by
  apply List.filter_congr
  intro b member
  apply Bool.eq_iff_iff.mpr
  simp [List.mem_filter, member]

/-- Given any state and a recovery selector, when only its registration pool
is filtered, then the KERI reconstruction recovers that whole World exactly.
This covers both imported recovery effects, without a Reach premise. -/
theorem recovery_reconstruction (s : Sys) (keep : Singular.RegistrationBooking → Bool) :
    recoverRegistrations s { s.toWorld with pending := s.registrations.filter keep } =
      .ok { s with registrations := s.registrations.filter keep } := by
  unfold recoverRegistrations
  dsimp only
  rw [recovery_pool_membership]
  simp [Sys.toWorld, pure, Except.pure, bind, Except.bind]

end CardanoKeri.Registry
