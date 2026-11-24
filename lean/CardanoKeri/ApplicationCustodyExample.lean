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

private theorem genesisLedger : ValidLedger initWorld genesisWorld openObs := by
  constructor <;> first | rfl | decide
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

private theorem neutral {before after : CandidateWorld} (past : Reach before)
    (tx : Transaction before after)
    (mint : policyDelta tx.observation.assets release.statePolicy [] = true)
    (untouched : ∀ r ∈ before.registries, r.state.reference ∉ tx.observation.assets.spent)
    (registries : after.registries = before.registries) (domain : after.domain = before.domain) :
    Reach after :=
  .neutral past _ _ _ _ _ tx.ledger mint untouched registries domain

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

private theorem registeredPath : CarrierHistory p env i active 11 startEdges registered foldWorld carrier := by
  have installed : RegistrationEvent p env (Sys.init deployment) registered :=
    ⟨11, 1, 42, 5, { dregIn := 3, bIn := 2, poolIn := 5 }, .present live,
      rp, Registry.Examples.env, Registry.Examples.cfg, registrationReceipt, registration, origin,
      rfl, rfl, Step.register 1 42 5 (by decide), delivered_origin, ⟨by decide, by decide⟩, rfl⟩
  exact .register (.init deployment) installed rfl (origin := origin) rfl (live := live) rfl
    foldTx rfl ⟨rfl,rfl⟩ ⟨rfl,rfl⟩

private theorem rotatedPath : CarrierHistory p env i active 11 rotationEdges rotated advancedWorld advanced := by
  exact .spend registeredPath advanceTx (action := .rotate 1 .keep 6) (now := 3)
    (state := .present rotatedLive) rfl ⟨rfl,rfl⟩ ⟨rfl,rfl⟩
    (by intro refund pool equal; cases equal)
    (Step.rotateKeepPaid 3 1 6 (by decide) (by decide) (by decide)) rfl (by decide) rfl

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

end CardanoKeri.Application.Custody.Examples
