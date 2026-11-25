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

end CardanoKeri.Attestation.Checks
