import CardanoKeri.ApplicationCustodyHistory
import CardanoKeri.CheckpointLifecycleExamples

/-! One complete observed booking, using the public registry's reachable worlds and
the checkpoint lifecycle examples. The finite name and datum tables represent the
public reads of this execution. The conviction is the modeled checkpoint step. -/
namespace CardanoKeri.Application.Custody.Examples

open SingularApplicationHeld
open Checkpoint Checkpoint.Examples
open Registry.Examples (registration termination)
set_option maxRecDepth 8192

private def release : PublishedRelease := ⟨7, 71, 8, 8⟩
private def seed : Singular.OutRef := ⟨90, 0⟩
private def rid : Singular.TokenId := ⟨8, 9⟩
private def target := Preimage.terminationApproval rid 11
private def code (preimage : Preimage) : List Nat :=
  if preimage = target then [5] else
  match preimage with
  | .state _ => [9]
  | .active .. => [11]
  | .applicationConfiguration _ => [3]
  | .registrationApproval .. => [4]
  | .terminationApproval .. => [0]

private def data : RegistrationData :=
  ⟨rid, 11, 42, 42, 111, 777, 14, 1, 6, 6⟩
private def i : Interpretation where
  hash := fun bytes => bytes.headD 0
  code := code
  keyOf := id
  decode := fun raw => if raw == 700 then some (.registration data) else none
  decodeConfiguration := fun raw => if raw == 701 then some ⟨⟨2, 1, 5, 0, 1⟩, 111⟩ else none
  decodeCheckpoint := fun raw => match raw with
    | 777 => some ⟨11, (State.present live).datumFacts⟩
    | 778 => some ⟨11, (State.present rotatedLive).datumFacts⟩
    | 779 => some ⟨11, .terminationPending rotatedLive.hash⟩
    | _ => none
  refundTo := some

private def active := activeAsset i.hash i.code rid 11
private def approval := registrationAsset i.hash i.code release data
private def terminationToken := terminationApproval i.hash i.code release rid 11
private def commit : TrieCommit := List.length
private def aenv : Application.Env := ⟨fun key => key == 11⟩
private abbrev rp := Registry.Examples.p

private def cash (tx ix owner amount : Nat) : ObservedOutput :=
  ⟨⟨tx, ix⟩, owner, amount, .empty, []⟩
private def record : ObservedOutput :=
  ⟨⟨99, 1⟩, 71, 1, .application 701, [(configurationAsset i release rid, 1)]⟩
private def genesisState : ObservedOutput := ⟨⟨99, 0⟩, 8, 2, .root 0, [(rid, 1)]⟩
private def registry0 : PublicRegistry := ⟨rid, seed, genesisState, []⟩
private def registry1 : PublicRegistry :=
  ⟨rid, seed, {genesisState with reference := ⟨102, 0⟩, datum := .root 1},
    Singular.trieSet [] 11 (.known .active)⟩
private def request : ObservedOutput :=
  ⟨registration.request.reference, 71, 17, .application 700, [(approval, 1)]⟩
private def carrier : ObservedOutput :=
  ⟨origin.carrierRef, 111, 14, .application 777, [(active, 1)]⟩
private def advanced : ObservedOutput := ⟨⟨103, 0⟩, 111, 13, .application 778, [(active, 1)]⟩
private def convicted : ObservedOutput := ⟨⟨105, 0⟩, 111, 4, .application 779, [(active, 1)]⟩
private def bookedRequest : ObservedOutput :=
  ⟨termination.request.reference, 71, 3, .empty, [(active, 1), (terminationToken, 1)]⟩

private def observation (ins outs : List ObservedOutput) (mint : List (Singular.TokenId × Int))
    (actions : List Application.Action := []) (references : List ObservedOutput := [])
    (invoked : List Nat := []) (interval : Singular.Interval := ⟨2, 3⟩) (donation := 0) :
    Observation :=
  { assets := ⟨ins.map (·.reference), outs.map (fun o => ⟨o.assets⟩), mint, invoked⟩,
    inputs := ins, outputs := outs, referenceInputs := references.map (·.reference),
    referenceOutputs := references, interval, donation, actions }

private def seedOut := cash 90 0 42 3
private def funds := cash 91 0 42 17
private def pledgeFunds := cash 92 0 7 1
private def bookingFeeFunds := cash 93 0 7 1
private def openObs := observation [seedOut] [genesisState, record]
  [(rid, 1), (configurationAsset i release rid, 1)] [.createConfiguration rid seed 1] [] [8]
private def regObs := observation [funds] [request] [(approval, 1)] [.bookRegistration 0]
  [record] [] ⟨0, 1⟩
private def foldObs : FoldObservation :=
  let ins := [request, genesisState]
  let outs := [registry1.state, carrier, cash 102 2 6 1]
  let view := (observation ins outs [(approval, -1), (active, 1)]).assets
  ⟨registry0, registry1, view, ins, outs, [.register request.reference 11 1 14], [], ⟨2, 3⟩, 0, 2⟩
private def advanceObs := observation [carrier] [advanced, cash 103 1 6 1] []
private def pledgeOut := cash 104 0 7 1
private def pledgeObs := observation [pledgeFunds] [pledgeOut] [] (interval := ⟨3, 4⟩)
private def convictionObs := observation [advanced, pledgeOut]
  [convicted, cash 105 1 42 6, cash 105 2 7 4] [] (interval := ⟨5, 6⟩)
private def bookObs := observation [convicted, bookingFeeFunds] [bookedRequest, cash 200 1 7 1]
  [(terminationToken, 1)] [.bookTermination convicted.reference 0 rid 11] [record] [] ⟨6, 7⟩

private def advanceWorld (w : CandidateWorld) (o : Observation) : CandidateWorld :=
  {w with unspent := w.unspent.filter (fun x => !o.assets.spent.contains x.reference) ++ o.outputs,
          spentReferences := w.spentReferences ++ o.assets.spent}
private def initWorld : CandidateWorld := ⟨[], [seedOut, funds, pledgeFunds, bookingFeeFunds], [], []⟩
private def genesisWorld := {advanceWorld initWorld openObs with
  registries := [registry0]
  domain := [.state seed]}
private def requestWorld := advanceWorld genesisWorld regObs
private def foldedObs := adapted foldObs record 2
private def foldWorld := {advanceWorld requestWorld foldedObs with
  registries := [registry1]
  domain := genesisWorld.domain ++ foldObs.changes.flatMap (changePreimages foldObs)}
private def advancedWorld := advanceWorld foldWorld advanceObs
private def pledgeWorld := advanceWorld advancedWorld pledgeObs
private def convictionWorld := advanceWorld pledgeWorld convictionObs
private def bookingWorld := advanceWorld convictionWorld bookObs

private abbrev ValidLedger (before after : CandidateWorld) (o : Observation) :=
  LedgerObservationCorrespondence before after o.assets o.inputs o.outputs 0 o.donation

local instance (o : ObservedOutput) (xs : List ObservedOutput) : Decidable (o ∈ xs) :=
  letI : BEq ObservedOutput := instBEqOfDecidableEq
  inferInstance

/-- Given the seed and its value, when genesis creates the state and configuration, then the ledger accounts for both outputs. -/
private theorem genesisLedger : ValidLedger initWorld genesisWorld openObs := by
  constructor <;> first | rfl | decide
/-- Given the funded controller, when registration is booked, then its input value and minted approval reach the request. -/
private theorem regLedger : ValidLedger genesisWorld requestWorld regObs := by
  constructor <;> first | rfl | decide
private def foldTx : Transaction requestWorld foldWorld :=
  ⟨102, foldedObs, 0, by constructor <;> first | rfl | decide⟩
private def advanceTx : Transaction foldWorld advancedWorld :=
  ⟨103, advanceObs, 0, by constructor <;> first | rfl | decide⟩
private def pledgeTx : Transaction advancedWorld pledgeWorld :=
  ⟨104, pledgeObs, 0, by constructor <;> first | rfl | decide⟩
private def convictionTx : Transaction pledgeWorld convictionWorld :=
  ⟨105, convictionObs, 0, by constructor <;> first | rfl | decide⟩
private def bookingTx : Transaction convictionWorld bookingWorld :=
  ⟨200, bookObs, 1, by constructor <;> first | rfl | decide⟩

#guard accepted i aenv rp p release openObs
#guard accepted i aenv rp p release regObs
#guard accepted i aenv rp p release foldedObs
#guard accepted i aenv rp p release bookObs

private abbrev Reach := CandidateReachable i.hash i.code commit release

/-- Given a reachable public world, when a valid ledger step preserves the registry state and mints no state-policy asset, then the successor is reachable. -/
private theorem neutral {before after : CandidateWorld} (past : Reach before)
    (tx : Transaction before after)
    (mint : policyDelta tx.observation.assets release.statePolicy [] = true)
    (untouched : ∀ r ∈ before.registries, r.state.reference ∉ tx.observation.assets.spent)
    (registries : after.registries = before.registries) (domain : after.domain = before.domain) :
    Reach after :=
  .neutral past _ _ _ _ _ tx.ledger mint untouched registries domain

/-- Given the funded initial world, when genesis, booking, fold and checkpoint spends run, then the pre-booking world is reachable under the public registry model. -/
private theorem publicHistory : Reach convictionWorld := by
  have initial : Reach initWorld := .initial _ (by decide) (by
    simp [seedOut, funds, pledgeFunds, bookingFeeFunds, cash, assetSupport])
  have deployed : Reach genesisWorld := .genesis initial seed _ _ _ registry0 0 0 genesisLedger
    (by decide) rfl rfl (List.mem_cons_self) (by decide) rfl (by decide) rfl rfl
  have requested := neutral deployed (⟨100, regObs, 0, regLedger⟩ : Transaction _ requestWorld)
    (by decide) (by decide) rfl rfl
  have folded : Reach foldWorld := .fold requested foldObs foldTx.ledger (List.mem_cons_self)
    (by decide) rfl rfl
  have advancedReach := neutral folded advanceTx (by decide) (by decide) rfl rfl
  have pledgeReach := neutral advancedReach pledgeTx (by decide) (by decide) rfl rfl
  exact neutral pledgeReach convictionTx (by decide) (by decide) rfl rfl

/-- Given that execution and its finite naming table, when identifier 11 is queried, then the registry has the required history and unambiguous names. -/
private theorem history : HistoryPremises i.hash i.code commit release convictionWorld registry1 11 := by
  refine ⟨publicHistory, ?_, ?_, ?_⟩
  · change registry1 ∈ [registry1]
    simp
  all_goals
    change ∀ a ∈ [Preimage.state seed, .active rid 11, .registrationApproval rid 11 111 777 14,
      .active rid 11], ∀ b ∈ [Preimage.state seed, .active rid 11, .registrationApproval rid 11 111 777 14,
      .active rid 11], _
    simp only [List.forall_mem_cons, List.not_mem_nil, false_implies, implies_true, and_true]
    decide

/-- Given the example naming table, when a preimage has the name of the termination approval, then it is the exact termination preimage. -/
private theorem namedApproval (preimage : Preimage)
    (same : i.hash (i.code preimage) = i.hash (i.code target)) : preimage = target := by
  by_cases different : preimage = target
  · exact different
  change (code preimage).headD 0 = 5 at same
  unfold code at same
  rw [if_neg different] at same
  cases preimage <;> cases same

private abbrev startEdges := [(Sys.init deployment, registered, carrier)]
private abbrev rotationEdges := (registered, rotated, advanced) :: startEdges
private abbrev convictionEdges := (committed, pending, convicted) :: rotationEdges

/-- Given the accepted registration, when its fold delivers the new holding, then the carrier history starts at that indexed output. -/
private theorem registeredPath : CarrierHistory p env i active 11 startEdges registered foldWorld carrier := by
  have installed : RegistrationEvent p env (Sys.init deployment) registered :=
    ⟨11, 1, 42, 5, { dregIn := 3, bIn := 2, poolIn := 5 }, .present live,
      rp, Registry.Examples.env, Registry.Examples.cfg, registrationReceipt, registration, origin,
      rfl, rfl, Step.register 1 42 5 (by decide), delivered_origin, ⟨by decide, by decide⟩, rfl⟩
  exact .register (.init deployment) installed rfl (origin := origin) rfl (live := live) rfl
    foldTx rfl ⟨rfl,rfl⟩ ⟨rfl,rfl⟩

/-- Given the registered holding, when the signed advance is paid, then its successor output is the next carrier in the history. -/
private theorem rotatedPath : CarrierHistory p env i active 11 rotationEdges rotated advancedWorld advanced := by
  exact .spend registeredPath advanceTx (action := .rotate 1 .keep 6) (now := 3)
    (state := .present rotatedLive) rfl ⟨rfl,rfl⟩ ⟨rfl,rfl⟩
    (by intro refund pool equal; cases equal)
    (Step.rotateKeepPaid 3 1 6 (by decide) (by decide) (by decide)) rfl (by decide) rfl

/-- Given the rotated holding, when the commitment opens and its conviction spends the holding, then the carrier history ends at the pending output. -/
private theorem pendingPath : CarrierHistory p env i active 11 convictionEdges pending convictionWorld convicted := by
  have pledged := CarrierHistory.retain rotatedPath pledgeTx (by decide) committed_step (by rfl)
  exact .spend pledged convictionTx (action := .convict 7 commitment) (now := 5)
    (state := .terminationPending rotatedLive.hash) rfl ⟨rfl,rfl⟩ ⟨rfl,rfl⟩
    (by intro refund pool equal; cases equal)
    (Step.convict 5 7 commitment (by decide) (by decide)) (by rfl) rfl rfl

/-- Given the public genesis, registration, rotation, commitment and conviction
above, when the application mints the termination approval, then it spends
the output created by that conviction at the rotated position. -/
theorem witnessed_termination_booking :
    namedInput bookObs convicted.reference = some convicted ∧
    checkpointDatum i convicted = some ⟨11, .terminationPending rotatedLive.hash⟩ ∧
    (committed, pending, convicted) ∈ convictionEdges ∧
    ConvictionEdge p env 11 rotatedLive.hash committed pending := by
  obtain ⟨_, key, before, after, _, spent, datum, member, edge⟩ :=
    approval_spends_conviction_output registry1 release commit history pendingPath bookingTx aenv rp
      (by decide) namedApproval (by decide)
  have position : key = rotatedLive.hash := by
    change some _ = some _ at datum
    exact (State.terminationPending.inj (congrArg ConsumerIdentity.DecodedDatum.state (Option.some.inj datum))).symm
  subst key
  simp only [convictionEdges, rotationEdges, startEdges, List.mem_cons, List.not_mem_nil,
    or_false] at member
  rcases member with same | same | same
  · cases same
    exact ⟨spent, datum, List.mem_cons_self, edge⟩
  · have ref := congrArg (fun (e : Sys × Sys × ObservedOutput) => e.2.2.reference.tx) same
    exact False.elim ((by decide : convicted.reference.tx ≠ advanced.reference.tx) ref)
  · have ref := congrArg (fun (e : Sys × Sys × ObservedOutput) => e.2.2.reference.tx) same
    exact False.elim ((by decide : convicted.reference.tx ≠ carrier.reference.tx) ref)

-- A booking cannot reuse the registration carrier or the last live output.
#guard !accepted i aenv rp p release
  {bookObs with actions := [.bookTermination carrier.reference 0 rid 11]}
#guard !accepted i aenv rp p release
  {bookObs with actions := [.bookTermination advanced.reference 0 rid 11]}

private def nativeReceipt : PendingSpend := ⟨convicted.reference, 11, rotatedLive.hash⟩

/-- Given the registered carrier has rotated and entered pending termination,
when the booker pays the fee and places the economic request, then the
application receipt reads the rotated position from the spent output. Both
the economic booking and the mint succeed for this request reference. -/
theorem economic_booking_reads_rotated_position :
    Registry.bookTermination rp registryPending 11 7 bookingTx.fee termination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, registryBooked) ∧
    bookingTx.bookingSpend i release rp rid termination convicted.reference = some nativeReceipt ∧
    ∃ request before after, bookingTx.creates request ∧ request.reference = termination.request.reference ∧
      namedInput bookObs nativeReceipt.reference = some convicted ∧
      nativeReceipt.reference = convicted.reference ∧ nativeReceipt.aid = termination.request.key ∧
      checkpointDatum i convicted = some ⟨nativeReceipt.aid, .terminationPending nativeReceipt.position⟩ ∧
      (before, after, convicted) ∈ convictionEdges ∧
      ConvictionEdge p env nativeReceipt.aid nativeReceipt.position before after ∧
      ∃ writer, before.writers nativeReceipt.aid = some writer ∧ writer.authenticated nativeReceipt.aid = true ∧
        writer.epoch = nativeReceipt.position.epoch ∧ writer.writer.event.sn = nativeReceipt.position.sn := by
  refine ⟨registry_booked, rfl, ?_⟩
  exact booking_receipt_provenance registry1 release commit termination history pendingPath bookingTx
    aenv rp (by decide) (ref := convicted.reference) (receipt := nativeReceipt) rfl

-- Changing the creating transaction while keeping the output index, or
-- selecting a different output of the actual transaction, loses the receipt.
private def readdress (ref : Singular.OutRef) : Singular.TerminationBooking :=
  {termination with request := {termination.request with reference := ref}}
#guard (bookingTx.bookingSpend i release rp rid (readdress ⟨201, 0⟩) convicted.reference).isNone
#guard (bookingTx.bookingSpend i release rp rid (readdress ⟨200, 1⟩) convicted.reference).isNone
#guard (bookingTx.bookingSpend i release rp rid termination advanced.reference).isNone

example : ({bookingTx with identity := 201} : Transaction convictionWorld bookingWorld).bookingSpend
    i release rp rid termination convicted.reference = none := by decide

/-- Given the public registration, rotation and conviction, when the observed
mint books the economic request, its stored receipt is for the pending output
at 105#0 and the authenticated writer at epoch one and sequence one. -/
theorem economic_entry_for_rotated_checkpoint :
    bookingTx.economicBooking i release rp rid termination convicted.reference = some termination ∧
    ∃ entry source target, Registry.pendingAt registryBooked termination.request.reference = some entry ∧
      entry.booking = termination.toTerminationBooking ∧ entry.payload.spend.reference = convicted.reference ∧
      entry.payload.spend.aid = 11 ∧
      checkpointDatum i convicted = some ⟨entry.payload.spend.aid, .terminationPending entry.payload.spend.position⟩ ∧
      (source, target, convicted) ∈ convictionEdges ∧
      ConvictionEdge p env entry.payload.spend.aid entry.payload.spend.position source target := by
  refine ⟨rfl, ?_⟩
  exact economic_entry_traces_to_conviction registry1 release commit termination.toTerminationBooking history
    pendingPath bookingTx aenv rp (by decide) (ref := convicted.reference) (localBooking := termination)
    rfl registry_booked

/-- Given the public history ending at the rotated checkpoint, when its
conviction spends that state, then its accepted comparison uses the
authenticated writer and native position of the produced pending carrier. -/
theorem rotated_booking_compares_its_writer :
    ∃ writer comparison, committed.writers 11 = some writer ∧ writer.authenticated 11 = true ∧
      (env 11).comparison 1 1 = some comparison ∧
      (env 11).keyReads.matches 11 writer comparison.tip = true ∧
      comparison.tip.epoch = 1 ∧ comparison.tip.sn = 1 ∧
      CheckpointConviction.accepts (env 11).verifyRival comparison.tip comparison.rival = true := by
  have reach : SysReach p env committed := .step (.step (.step (.init deployment) registered_step) rotated_step) committed_step
  exact conviction_compares_authenticated_writer reach witnessed_termination_booking.2.2.2

-- The comparison still has its signatures. A next-key commitment which
-- cannot be read as the writer's established identity loses the system spend.
example :
    let bad := {env 11 with keyReads.nextCommitment := fun _ => none}
    bad.acceptsRival 1 1 = true ∧ committed.comparisonMatchesWriter bad 11 = false ∧
      (committed.localWriter bad 11 (.convict 7 commitment)).isNone = true := by decide
end CardanoKeri.Application.Custody.Examples
