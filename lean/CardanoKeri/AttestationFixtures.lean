import CardanoKeri.Attestation

/-! Small decoded transactions for the checkpoint and registry examples. -/
namespace CardanoKeri.Attestation.Fixtures
open Singular SingularApplicationHeld.Assets

def name : Claim → Nat
  | .spend kind script input =>
    let tag := match kind with | .advance => 1 | .freeze => 2 | .convict => 4
    ((input.tx * 256 + input.index) * 256 + script) * 8 + tag
  | .book app ix datum deposit => ((datum * 256 + deposit) * 256 + app) * 256 + ix

def bookingPolicy : Policy := ⟨51, name⟩

def bookingTx (claims : List Claim) : TxView :=
  ⟨[], [], claims.map (fun c => (bookingPolicy.asset c, 1)), [bookingPolicy.id]⟩

/-- Explicit ledger observations used by the economic scenario fixtures.
Each row names the producing transaction and the claim it actually minted. -/
structure BookingRow where
  tx : Nat
  index : Nat
  datum : Nat
  deposit : Nat
  deriving Lean.ToJson, Lean.FromJson

def readBooking (rows : List BookingRow) (tx : Nat) : Option TxView :=
  let claims := (rows.filter (·.tx == tx)).map fun r => Claim.book 7 r.index r.datum r.deposit
  if claims.isEmpty then none else some (bookingTx claims)

def bookingTransactions (rows : List BookingRow) : List MintObservation :=
  (rows.map (·.tx)).eraseDups.filterMap fun tx =>
    (readBooking rows tx).map fun view => ⟨tx, view⟩

def policies : ConvictionPolicies := ⟨111, ⟨52, name⟩, ⟨53, name⟩, by decide⟩

def advancePolicy : Policy := ⟨54, name⟩

def advanceSpend (kind : Change) (input : OutRef) (script := 111) : Spend :=
  let asset := advancePolicy.asset (.spend kind script input)
  ⟨input, ⟨[input], [], [(asset, 1)], [advancePolicy.id]⟩⟩

def advances (positions : Nat → Nat → Nat → Bool)
    (spent : Nat → OutRef := fun e => if e == 0 then ⟨102, 1⟩ else ⟨102 + e, 0⟩) (script := 111) :
    AdvanceReads :=
  ⟨script, advancePolicy, fun kind epoch sn next =>
    if positions epoch sn next then some (advanceSpend kind (spent epoch) script) else none⟩

def convictionMint (input : OutRef) : List (TokenId × Int) :=
  let claim := Claim.spend .convict policies.script input
  [(policies.enforcement.asset claim, 1), (policies.entitlement.asset claim, 1)]

def convictionSpend (input : OutRef) : Spend :=
  ⟨input, ⟨[input], [], convictionMint input, [52, 53]⟩⟩

def convictionReads (out : OutRef) (input : OutRef := ⟨103, 0⟩) : ConvictionReads :=
  ⟨policies, fun ref => if ref == out then some (convictionSpend input) else none⟩

end CardanoKeri.Attestation.Fixtures
