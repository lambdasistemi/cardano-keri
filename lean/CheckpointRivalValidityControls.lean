import CardanoKeri.AttestationFixtures
import CardanoKeri.ApplicationCustodyExample

/-! Reachable inputs and executed edges for the #573 checks. The richer
registration commits two next keys and establishes witness 10. Its first
rotation uses one key; sibling rotations can expose the other or change the
witness set. The second advance lets checks distinguish consecutive priors. -/
namespace CardanoKeri.Checkpoint.RivalControls
set_option maxRecDepth 8192
open Duplicity CheckpointConviction Examples

def inceptionEvent : SignedEvent :=
  let e := { baseContext.accepted.event with
    eventDigest := "registration", aid := 11, sn := 0, kind := .inception, priorDigest := 0,
    nextKeys := [1, 2], nextThreshold := .count 1 }
  signed e [1] [10]

private def opensInception (event : Content) : Bool :=
  inceptionWrites 11 (signed event [1] [10]) [10]

#guard opensInception inceptionEvent.event
#guard !opensInception { inceptionEvent.event with priorDigest := 7 }
#guard !opensInception { inceptionEvent.event with cuts := [20] }
#guard !opensInception { inceptionEvent.event with adds := [21] }

def first := signed {baseContext.accepted.event with aid := 11, eventDigest := "first"} [1] [10]
def second : SignedEvent :=
  let e := {first.event with eventDigest := "second", sn := 2, keys := [4], nextKeys := [5], cuts := [10], adds := [12]}
  signed e [4] [12]
def bookingOrigin := {origin with inception := EventHistory.inception inceptionEvent [10]}
private def acceptsNext (threshold : Threshold) (atInception : Bool) : Bool :=
  if atInception then opensInception { inceptionEvent.event with nextThreshold := threshold }
  else rotationValid bookingOrigin.inception.predecessor
    (signed { first.event with nextKeys := [4,5], nextThreshold := threshold } [1] [10])

private def nextDenominatorCases (atInception : Bool) : Bool :=
  acceptsNext (.weighted [[.key ⟨2, 4⟩, .key ⟨1, 2⟩]]) atInception &&
  acceptsNext (.weighted [[.key ⟨1, 4294967297⟩, .key ⟨4294967296, 4294967297⟩]]) atInception &&
  !acceptsNext (.weighted [[.key ⟨1, 0⟩]]) atInception &&
  !acceptsNext (.weighted [[.group ⟨1, 0⟩ [⟨1, 1⟩]]]) atInception &&
  !acceptsNext (.weighted [[.group ⟨1, 1⟩ [⟨1, 0⟩]]]) atInception

#guard nextDenominatorCases true
#guard nextDenominatorCases false

-- The same signed rule is checked at installation, advance, and rival grading.
private def admittedWeight (rule : Threshold) (expected : Bool) : Bool :=
  let prior := bookingOrigin.inception.predecessor
  let genesis := inceptionEvent.event
  let rotation := first.event
  let genesisWith := fun current next => opensInception { genesis with threshold := current, nextThreshold := next }
  let rotateWith := fun current next => rotationValid prior
    (signed { rotation with threshold := current, nextThreshold := next } [1] [10])
  [genesisWith rule (.count 1), genesisWith (.count 1) rule,
   rotateWith rule (.count 1), rotateWith (.count 1) rule].all (· == expected)

#guard admittedWeight (.weighted [[.key ⟨2,1⟩]]) false
#guard admittedWeight (.weighted [[.group ⟨2,1⟩ [⟨1,1⟩]]]) false
#guard admittedWeight (.weighted [[.group ⟨1,1⟩ [⟨2,1⟩]]]) false
#guard admittedWeight (.weighted [[.group ⟨2,2⟩ [⟨3,3⟩]]]) true
#guard !rotationValid { bookingOrigin.inception.predecessor with
  nextThreshold := .weighted [[.key ⟨2,1⟩, .key ⟨0,1⟩]] } first

def setup : SystemEnv := fun aid => {env aid with
  inceptionOpening := {
    prefixCode := fun subject => if subject == 11 then some "E" else none
    decodeEvidence := fun bytes => if bytes == [1] then some ⟨inceptionEvent, [10]⟩ else none
    deriveIdentifier := fun bytes => if bytes == [1] then some 11 else none }
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
def alternative := signed {first.event with eventDigest := "alternative", keys := [2], extension := [99]} [2] [10]
def seals := signed {first.event with eventDigest := "seals", extension := [99]} [1] [10]
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
def grouped := signed {first.event with eventDigest := "grouped", threshold := nestedRule, nextThreshold := nestedRule} [1] [10]
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
  convictionReads := CardanoKeri.Attestation.Fixtures.convictionReads (claim r).output}
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
      .present rotatedLive, ?_, Step.rotateKeepPaid (env := spendEnv r 11) (l := live) 3 1 6 (show (env 11).rotationTo live.epoch live.sn 1 = true from by decide) (by decide) (by decide),
      ⟨rfl, rfl⟩, rfl⟩
    intro _ _ h
    cases h
  apply SysReach.step rotated (.openCommitment ?_)
  exact ⟨pledge r, rfl, (show commitment.wellFormed from by decide), rfl⟩

def spendReady (r : SignedEvent) : Bool :=
  (opened r).revealOpenB 11 (.convict 7 (pledge r)) &&
    (opened r).comparisonMatchesWriter (spendEnv r 11) 11 &&
    decide ((pledge r).entitles (spendEnv r 11) rotatedLive 7 5)

def underSigned := signed {first.event with eventDigest := "undersigned", threshold := .count 2, extension := [2]} [1] [10]
#guard spendReady alternative && spendReady underSigned
#guard (stepFn p (spendEnv alternative 11) (.convict 7 (pledge alternative)) 5 (.present rotatedLive)).isSome
#guard (stepFn p (spendEnv underSigned 11) (.convict 7 (pledge underSigned)) 5 (.present rotatedLive)).isNone
example := presented_conflict_passes_system_comparison (aid := 11) (live := rotatedLive)
  (previous := bookingOrigin.inception) (writer := first) (rival := alternative)
  (openedReach alternative) rfl rfl (by decide) rfl (by decide) KeyEncoding.symbolic ⟨105,0⟩ rfl rfl

-- Prepare a conviction at the registered, never-rotated writer. The claim,
-- commitment, signatures and receipt all name the presented event at sequence 0.
def incRival := signed {first.event with eventDigest := "inc-rival", sn := 0, extension := [99]} [1] [10]
def incClaim : Registry.Conviction :=
  ⟨⟨105, 0⟩, ⟨bookingOrigin.inception.datum.tip KeyEncoding.symbolic 0, incRival⟩⟩
def incEnv (aid : Nat) : Env := {setup aid with
  presentedSpend := fun _ _ => some incClaim
  convictionReads := CardanoKeri.Attestation.Fixtures.convictionReads incClaim.output ⟨102, 1⟩}
def incPledge := {pledge incRival with keyState := live.hash}
def incOpened : Sys :=
  {atRegistration with commitments := fun k => if k = incPledge.marker then some incPledge else atRegistration.commitments k}
def incAction := Action.convict 7 incPledge
def incPending :=
  (incOpened.set 11 (.terminationPending live.hash) none (some incClaim)).retireRevealed incAction

example : SysReach p incEnv incOpened ∧ ¬ConvictionEdge p incEnv 11 live.hash incOpened incPending := by
  have registered : SysReach p incEnv atRegistration := by
    apply SysReach.step (.init deployment) (.register ?_)
    exact ⟨11, 1, 42, 5, {dregIn := 3, bIn := 2, poolIn := 5}, .present live,
      Registry.Examples.p, Registry.Examples.env, Registry.Examples.cfg, registrationReceipt,
      Registry.Examples.registration, bookingOrigin, rfl, rfl, Step.register 1 42 5 (by decide),
      delivered_origin, ⟨by decide, rfl⟩, rfl⟩
  have reached : SysReach p incEnv incOpened :=
    .step registered (.openCommitment ⟨incPledge, rfl, (show commitment.wellFormed from by decide), rfl⟩)
  exact ⟨reached, inception_conviction_refused reached (event := inceptionEvent) (witnesses := [10]) rfl⟩

#guard incOpened.revealOpenB 11 incAction && incOpened.comparisonMatchesWriter (incEnv 11) 11
example : incPledge.entitles (incEnv 11) live 7 5 := by decide
#guard (incEnv 11).convictionSpend 0 0 == some incClaim
#guard incClaim.comparison.tip.previous.isNone && incClaim.comparison.rival.event.sn == 0
#guard (stepFn p (incEnv 11) incAction 5 (.present live)).isNone
#guard incPending.states 11 == .terminationPending live.hash && incPending.convictions 11 == some incClaim
#guard (incPending.commitments incPledge.marker).isNone

end CardanoKeri.Checkpoint.RivalControls
