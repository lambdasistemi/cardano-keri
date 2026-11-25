import CardanoKeri.ApplicationCustodyExample

/-! Reachable inputs and executed edges for the #573 checks. The richer
registration commits two next keys and establishes witness 10. Its first
rotation uses one key; sibling rotations can expose the other or change the
witness set. The second advance lets checks distinguish consecutive priors. -/
namespace CardanoKeri.Checkpoint.RivalControls
open Duplicity CheckpointConviction Examples

def inceptionEvent : SignedEvent :=
  let e := { baseContext.accepted.event with
    aid := 11, sn := 0, kind := .inception,
    nextKeys := [1, 2], nextThreshold := .count 1 }
  signed e [1] [10]

def first := signed {baseContext.accepted.event with aid := 11} [1] [10]
def second : SignedEvent :=
  let e := {first.event with sn := 2, keys := [4], nextKeys := [5], cuts := [10], adds := [12]}
  signed e [4] [12]
def bookingOrigin := {origin with inception := EventHistory.inception inceptionEvent [10]}
def setup : SystemEnv := fun aid => {env aid with
  inceptionWriter := fun _ _ => some (inceptionEvent, [10])
  rotationWriter := fun _ _ _ sn => some (if sn = 1 then first else second)}
def atRegistration := (Sys.init deployment).installOrigin 11 (.present live) bookingOrigin
def h1 := EventHistory.rotation bookingOrigin.inception first
def atFirst := atRegistration.set 11 (.present rotatedLive) (some h1)
def nextLive := rotatedLive.rotated p 2
def h2 := EventHistory.rotation h1 second
def atSecond := atFirst.set 11 (.present nextLive) (some h2)

theorem registrationReach : SysReach p setup atRegistration := by
  apply SysReach.step (.init deployment) (.register ?_)
  exact ⟨11, 1, 42, 5, {dregIn := 3, bIn := 2, poolIn := 5}, .present live,
    Registry.Examples.p, Registry.Examples.env, Registry.Examples.cfg, registrationReceipt,
    Registry.Examples.registration, bookingOrigin, rfl, rfl, Step.register 1 42 5 (by decide),
    delivered_origin, ⟨by decide, by decide⟩, rfl⟩

theorem firstReach : SysReach p setup atFirst := by
  apply SysReach.step registrationReach (.local ?_)
  refine ⟨11, .rotate 1 .keep 6, 3, {hunter := some {addr := 6, pool := 1}},
    .present rotatedLive, ?_, Step.rotateKeepPaid 3 1 6 (by decide) (by decide) (by decide),
    ⟨rfl, by decide⟩, rfl⟩
  intro _ _ h
  cases h

theorem secondReach : SysReach p setup atSecond := by
  apply SysReach.step firstReach (.local ?_)
  refine ⟨11, .rotate 2 .keep 6, 4, {hunter := some {addr := 6, pool := 1}},
    .present nextLive, ?_, Step.rotateKeepPaid 4 2 6 (by decide) (by decide) (by decide),
    ⟨rfl, by decide⟩, rfl⟩
  intro _ _ h
  cases h

def tip := h1.datum.tip KeyEncoding.symbolic 1
def alternative := signed {first.event with keys := [2], extension := [99]} [2] [10]
def seals := signed {first.event with extension := [99]} [1] [10]
def obs : Registry.Conviction := ⟨⟨105,0⟩, ⟨tip, alternative⟩⟩

example := inception_carries_no_previous inceptionEvent [10]
example := rotation_replaces_previous h1 second
example := advance_forgets_older h1.datum none second.event
example := h2.datum_commitments
example := h1.datum_writer
example := reachable_writer_datum secondReach 11
example := stored_rotation_valid (aid := 11) (previous := bookingOrigin.inception) (event := first) (by decide)
example := EventHistory.authenticated_aid (aid := 11) (history := h2) (by decide)
example := h1.datum.matches_tip KeyEncoding.symbolic 1
example := KeyReads.symbolic.matches_history (aid := 11) (history := h1) (tip := tip) (by decide)
example := accepts_iff tip alternative
example := rotated_tip_accepts_iff_duplicity (aid := 11) (previous := bookingOrigin.inception)
  (writer := first) firstReach rfl (reads := KeyReads.symbolic) (tip := tip) (by decide) alternative
example := reachable_conflict_has_accepted_comparison (aid := 11) (live := rotatedLive)
  (previous := bookingOrigin.inception) (writer := first) (rival := alternative)
  firstReach rfl rfl (by decide) rfl (by decide)
example := rotated_writer_accepts_with_encoding (aid := 11) (live := rotatedLive)
  (previous := bookingOrigin.inception) (writer := first) (rival := alternative)
  firstReach rfl rfl (by decide) rfl (by decide) KeyEncoding.symbolic
example := NestedWriter.reachable_nested_writer_accepts_sibling
example := inception_conviction_refused (aid := 11) (key := live.hash) (after := atFirst)
  (event := inceptionEvent) (witnesses := [10]) registrationReach rfl

private theorem reachedCommit : SysReach p env committed :=
  .step (.step (.step (.init deployment) registered_step) rotated_step) committed_step
private theorem paidEdge : ConvictionEdge p env 11 rotatedLive.hash committed pending :=
  Application.Custody.Examples.witnessed_termination_booking.2.2.2
example := conviction_establishes_duplicity reachedCommit paidEdge
example := rotated_conviction_is_duplicity (previous := origin.inception)
  (writer := writerFixture 11 1 .rotation) (comparison := Fixtures.comparison 11 1 1)
  reachedCommit paidEdge rfl rfl
example := Env.convictionSpend_attested (env := env 11) (epoch := 1) (sn := 1)
  (observation := ⟨⟨105,0⟩, Fixtures.comparison 11 1 1⟩) rfl
example := conviction_mint_bound_to_output
example := Application.Custody.Examples.rotated_journey_establishes_duplicity


-- The same registration reaches a sibling writer with both grouped fields.
def nestedRule : Threshold := .weighted [[.group ⟨1,1⟩ [⟨1,1⟩]]]
def grouped := signed {first.event with threshold := nestedRule, nextThreshold := nestedRule} [1] [10]
def hg := EventHistory.rotation bookingOrigin.inception grouped
def nestedState := atRegistration.set 11 (.present rotatedLive) (some hg)
def nestedEnv (aid : Nat) : Env := {setup aid with rotationWriter := fun _ _ _ _ => some grouped}

theorem nestedReach : SysReach p nestedEnv nestedState := by
  have start : SysReach p nestedEnv atRegistration := by
    apply SysReach.step (.init deployment) (.register ?_)
    exact ⟨11, 1, 42, 5, {dregIn := 3, bIn := 2, poolIn := 5}, .present live,
      Registry.Examples.p, Registry.Examples.env, Registry.Examples.cfg, registrationReceipt,
      Registry.Examples.registration, bookingOrigin, rfl, rfl, Step.register 1 42 5 (by decide),
      delivered_origin, ⟨by decide, by decide⟩, rfl⟩
  apply SysReach.step start (.local ?_)
  refine ⟨11, .rotate 1 .keep 6, 3, {hunter := some {addr := 6, pool := 1}},
    .present rotatedLive, ?_, Step.rotateKeepPaid 3 1 6 (by decide) (by decide) (by decide),
    ⟨rfl, by decide⟩, rfl⟩
  intro _ _ h
  cases h

def claim (r : SignedEvent) : Registry.Conviction := {obs with comparison.rival := r}
def spendEnv (r : SignedEvent) (aid : Nat) : Env := {setup aid with
  presentedSpend := fun _ _ => some (claim r)
  attestationMinted := fun seen => decide (seen = claim r)}
def pledge (r : SignedEvent) := {commitment with evidence := r}
def opened (r : SignedEvent) : Sys :=
  let c := pledge r
  {atFirst with commitments := fun k => if k = c.marker then some c else atFirst.commitments k}

-- For each actual candidate rival, reach the live writer with its own matching
-- open commitment under the environment which will present that very rival.
theorem openedReach (r : SignedEvent) : SysReach p (spendEnv r) (opened r) := by
  have reg : SysReach p (spendEnv r) atRegistration := by
    apply SysReach.step (.init deployment) (.register ?_)
    exact ⟨11, 1, 42, 5, {dregIn := 3, bIn := 2, poolIn := 5}, .present live,
      Registry.Examples.p, Registry.Examples.env, Registry.Examples.cfg, registrationReceipt,
      Registry.Examples.registration, bookingOrigin, rfl, rfl, Step.register 1 42 5 (by decide),
      delivered_origin, ⟨by decide, rfl⟩, rfl⟩
  have rotated : SysReach p (spendEnv r) atFirst := by
    apply SysReach.step reg (.local ?_)
    refine ⟨11, .rotate 1 .keep 6, 3, {hunter := some {addr := 6, pool := 1}},
      .present rotatedLive, ?_, Step.rotateKeepPaid 3 1 6 rfl (by decide) (by decide),
      ⟨rfl, rfl⟩, rfl⟩
    intro _ _ h
    cases h
  apply SysReach.step rotated (.openCommitment ?_)
  exact ⟨pledge r, rfl, (show commitment.wellFormed from by decide), rfl⟩

def spendReady (r : SignedEvent) : Bool :=
  (opened r).revealOpenB 11 (.convict 7 (pledge r)) &&
    (opened r).comparisonMatchesWriter (spendEnv r 11) 11 &&
    decide ((pledge r).entitles (spendEnv r 11) rotatedLive 7 5)

def underSigned := signed {first.event with threshold := .count 2, extension := [2]} [1] [10]
#guard spendReady alternative && spendReady underSigned
#guard (stepFn p (spendEnv alternative 11) (.convict 7 (pledge alternative)) 5 (.present rotatedLive)).isSome
#guard (stepFn p (spendEnv underSigned 11) (.convict 7 (pledge underSigned)) 5 (.present rotatedLive)).isNone
example := presented_conflict_passes_system_comparison (aid := 11) (live := rotatedLive)
  (previous := bookingOrigin.inception) (writer := first) (rival := alternative)
  (openedReach alternative) rfl rfl (by decide) rfl (by decide) KeyEncoding.symbolic ⟨105,0⟩ rfl rfl

end CardanoKeri.Checkpoint.RivalControls
