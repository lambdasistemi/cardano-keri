import CardanoKeri.AttestationGoals
import CardanoKeri.CheckpointDepositVectors
import CardanoKeri.ApplicationCustodyExample

/-! Finite observations for the mint of a depositing rotation at one spent
reference and for the two independent policies of a conviction. -/
namespace CardanoKeri.Attestation.Checks
open Singular SingularApplicationHeld.Assets
open CardanoKeri.Checkpoint
open CardanoKeri.CheckpointDeposit.Vectors

private def signedDeposit : Authorization :=
  ⟨"signed", "", frozenCase, twoOfThree,
    [⟨0, "new-0", "frozen-required"⟩, ⟨1, "new-1", "frozen-required"⟩]⟩
private def unsignedDeposit : Authorization := {signedDeposit with signatures := []}
private def wronglySigned : Authorization := {signedDeposit with signatures :=
  [⟨0, "old-0", "frozen-required"⟩, ⟨1, "old-1", "frozen-required"⟩]}

private def advanceClaim : Claim := .spend .advance observed.checkpointPolicy observed.spentRef
private def token := Fixtures.advancePolicy.asset advanceClaim
private def original : TxView := ⟨[observed.spentRef], [⟨[(token, 1)]⟩], [(token, 1)], [token.policy]⟩
private def withMint (a : Authorization) (tx : TxView) : Env :=
  {a.env with advanceReads := ⟨observed.checkpointPolicy, Fixtures.advancePolicy,
    fun _ _ _ _ => some ⟨observed.spentRef, tx⟩⟩}
private def moves (a : Authorization) (op : BondOp) (tx : TxView) :=
  (stepFn params (withMint a tx) (.rotate frozenCase.newSn op 0) 200 (.present frozenState)).isSome

-- Both operations read the same single +1. The spending script alone checks the
-- deposit signatures, including when the signers are from the wrong key set.
#guard moves signedDeposit .keep original && moves signedDeposit .deposit original
#guard moves unsignedDeposit .keep original && !moves unsignedDeposit .deposit original
#guard moves wronglySigned .keep original && !moves wronglySigned .deposit original

private def mintedInstead (claim : Claim) (q : Int := 1) : TxView :=
  {original with mint := [(Fixtures.advancePolicy.asset claim, q)]}

#guard !moves signedDeposit .deposit {original with mint := []}
#guard !moves signedDeposit .deposit (mintedInstead advanceClaim 2)
#guard !moves signedDeposit .deposit (mintedInstead advanceClaim (-1))
#guard !moves signedDeposit .deposit (mintedInstead (.spend .freeze observed.checkpointPolicy observed.spentRef))
#guard !moves signedDeposit .deposit (mintedInstead (.spend .advance (observed.checkpointPolicy + 1) observed.spentRef))
#guard !moves signedDeposit .deposit (mintedInstead (.spend .advance observed.checkpointPolicy
  {observed.spentRef with index := observed.spentRef.index + 1}))
#guard !moves signedDeposit .deposit {original with mint := [(token, 1), (token, -1)]}

-- Both spending scripts inspect the same transaction with two different inputs.
private def otherRef : OutRef := {observed.spentRef with index := observed.spentRef.index + 1}
private def otherToken := Fixtures.advancePolicy.asset (.spend .advance observed.checkpointPolicy otherRef)
private def batch : TxView :=
  { original with
    spent := [observed.spentRef, otherRef]
    mint := [(token, 1), (otherToken, 1)]}
private def inBatch (ref : OutRef) (tx : TxView) : Bool :=
  let env := {signedDeposit.env with advanceReads := ⟨observed.checkpointPolicy,
    Fixtures.advancePolicy, fun _ _ _ _ => some ⟨ref, tx⟩⟩}
  (stepFn params env (.rotate frozenCase.newSn .keep 0) 200 (.present frozenState)).isSome
#guard token != otherToken && inBatch observed.spentRef batch && inBatch otherRef batch
#guard inBatch observed.spentRef {batch with mint := [(token, 1)]} &&
  !inBatch otherRef {batch with mint := [(token, 1)]}
#guard !inBatch observed.spentRef {batch with mint := [(otherToken, 1)]} &&
  inBatch otherRef {batch with mint := [(otherToken, 1)]}

private def cp := Fixtures.policies
private def input : OutRef := ⟨103, 0⟩
private def tx := (Fixtures.convictionSpend input).transaction
#guard cp.requiresBoth tx input
#guard !cp.requiresBoth {tx with mint := tx.mint.take 1} input
#guard !cp.requiresBoth {tx with mint := tx.mint.drop 1} input
#guard !cp.requiresBoth {tx with mint := [], outputs := [⟨tx.mint.map fun e => (e.1, 1)⟩]} input

private def verified (_ : TxView) (c : Claim) := decide (c = advanceClaim)
#guard Fixtures.advancePolicy.authorizes original 0 verified [advanceClaim]
#guard !Fixtures.advancePolicy.authorizes original 0 (fun _ _ => false) [advanceClaim]
#guard !Fixtures.advancePolicy.authorizes original 0 verified []
#guard Fixtures.advancePolicy.authorizes (mintedInstead advanceClaim (-1)) 0 (fun _ _ => false) []
#guard !Fixtures.advancePolicy.authorizes {original with mint := [(⟨token.policy, 0⟩, 1)]} 0 verified []

-- Distinct scripts may read one transaction at the local boundary.
private def mixed : TxView :=
  {batch with
    spent := observed.spentRef :: tx.spent
    mint := (token, 1) :: tx.mint
    invoked := token.policy :: tx.invoked}
private def convicts (view : TxView) : Bool :=
  let env := Examples.env 11
  let reads : ConvictionReads := {env.convictionReads with
    producingSpend := fun out => if out = (⟨105, 0⟩ : OutRef) then some ⟨input, view⟩ else none}
  (stepFn Examples.p {env with convictionReads := reads} (.convict 7 Examples.commitment)
    5 (.present Examples.rotatedLive)).isSome
#guard observed.spentRef != input && inBatch observed.spentRef mixed && convicts mixed
#guard inBatch observed.spentRef {mixed with mint := [(token, 1)]} &&
  !convicts {mixed with mint := [(token, 1)]}
#guard !inBatch observed.spentRef {mixed with mint := tx.mint} && convicts {mixed with mint := tx.mint}

private def freezeToken := Fixtures.advancePolicy.asset (.spend .freeze observed.checkpointPolicy otherRef)
private def freezeSecond (view : TxView) : Bool :=
  let env := {signedDeposit.env with advanceReads := ⟨observed.checkpointPolicy,
    Fixtures.advancePolicy, fun _ _ _ _ => some ⟨otherRef, view⟩⟩}
  (stepFn params env (.freeze frozenCase.newSn 0) 200 (.present {frozenState with frozen := false})).isSome
private def rotationAndFreeze := {batch with mint := [(token, 1), (freezeToken, 1)]}
#guard inBatch observed.spentRef rotationAndFreeze && freezeSecond rotationAndFreeze
#guard !freezeSecond batch

-- Two local steps read distinct live datums and their held lovelace.
open SingularApplicationHeld
open CardanoKeri.Application (Interpretation Observation namedInput checkpointDatum)
open CardanoKeri.Application.Custody (AdvanceAt CheckpointSpendAt Carries)

private def liveFor (ref : OutRef) := {frozenState with refundTo := ref.index}
private def aidFor (ref : OutRef) := 20 + ref.index
private def registryId : TokenId := ⟨8, 9⟩
private def reading : Interpretation where
  hash := fun xs => xs.headD 0
  code := fun | .active _ key => [key] | _ => []
  keyOf := id
  decode := fun _ => none
  decodeConfiguration := fun _ => none
  decodeCheckpoint := fun raw =>
    [observed.spentRef, otherRef].findSome? fun ref =>
      if raw = ref.index then some ⟨aidFor ref, (State.present (liveFor ref)).datumFacts⟩ else none
  refundTo := some

private def actualInput (ref : OutRef) : ObservedOutput :=
  ⟨ref, observed.checkpointPolicy, (State.present (liveFor ref)).heldValue params Registry.Examples.p,
    .application ref.index, [(activeAsset reading.hash reading.code registryId (aidFor ref), 1)]⟩
private def pairObservation : Observation :=
  ⟨batch, [actualInput observed.spentRef, actualInput otherRef], [], [], [], ⟨0, 1⟩, 0, []⟩

private def useInput (ref : OutRef)
    (input : namedInput pairObservation ref = some (actualInput ref))
    (mint : Fixtures.advancePolicy.minted batch (.spend .advance observed.checkpointPolicy ref) = true)
    (spent : batch.spent.contains ref = true)
    (decoded : checkpointDatum reading (actualInput ref) =
      some ⟨aidFor ref, (State.present (liveFor ref)).datumFacts⟩) : CheckpointSpendAt reading pairObservation where
  params := params
  env := {signedDeposit.env with advanceReads := ⟨observed.checkpointPolicy,
    Fixtures.advancePolicy, fun _ _ _ _ => some ⟨ref, batch⟩⟩}
  old := actualInput ref
  live := liveFor ref
  action := .rotate frozenCase.newSn .keep 0
  time := 200
  flow := {}
  successor := .present {liveFor ref with
    sn := frozenCase.newSn, epoch := frozenState.epoch + 1, poisoned := false, toppedUp := false}
  input := input
  step := Step.rotateKeepUnpaid 200 _ 0 (by
    change (batch.spent.contains ref && Fixtures.advancePolicy.minted batch
      (.spend .advance observed.checkpointPolicy ref)) = true
    rw [spent, mint]; rfl) (by change frozenState.sn < frozenCase.newSn; decide)
    (by change frozenState.pool < params.P; decide)
  observed := ⟨rfl, _, rfl, rfl, rfl⟩
  registry := registryId
  registryParams := Registry.Examples.p
  aid := aidFor ref
  carries := ⟨by
    change quantity (actualInput ref) (activeAsset reading.hash reading.code registryId (aidFor ref)) = 1
    simp [actualInput, quantity], decoded⟩
  value := rfl

private def firstUse := useInput observed.spentRef (by decide) (by decide) (by decide) (by decide)
private def secondUse := useInput otherRef (by decide) (by decide) (by decide) (by decide)

example : mintQty batch token = 1 ∧ mintQty batch otherToken = 1 ∧ token ≠ otherToken :=
  CardanoKeri.Application.Custody.two_checkpoint_spends_need_two_attestations
    firstUse secondUse rfl rfl (by decide) rfl
    (by intro eq; exact False.elim ((by decide : token.name ≠ otherToken.name) eq))

-- Keeping A's reference, active token, AID and mint cannot make B's state
-- decode from A. The pool is read independently from the input lovelace.
example : ¬ Carries reading (activeAsset reading.hash reading.code registryId firstUse.aid)
    firstUse.aid firstUse.old (.present secondUse.live) := by
  intro h
  exact (by decide : checkpointDatum reading firstUse.old ≠
    some ⟨firstUse.aid, (State.present secondUse.live).datumFacts⟩) h.2
#guard firstUse.old.lovelace != (State.present {firstUse.live with pool := firstUse.live.pool + 1}).heldValue
  firstUse.params firstUse.registryParams
end CardanoKeri.Attestation.Checks
