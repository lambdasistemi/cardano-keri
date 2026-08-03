import CardanoLedgerApi.V3

/-!
# V3 script context fixtures for the S2 purpose and preparation proofs

Three of the observer pairs are byte-identical: an observer's `withdraw` and
`publish` programs are the same bytes, so nothing about their purpose
behaviour can be established from the programs themselves. The only input
that may differ between a reward run and a certify run is the `ScriptContext`
applied after the declared parameters.

These fixtures therefore exist to make the context the sole variable. Each
one is built from the same empty transaction body and differs only in its
`ScriptInfo` and the one field the ledger requires to be consistent with it:
a rewarding context carries the matching withdrawal, a certifying context
carries the matching certificate.
-/

namespace KeriBlaster.S2.Fixtures

open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V1.Address (Address)
open CardanoLedgerApi.V1.Credential (Credential)
open CardanoLedgerApi.V2.Tx (OutputDatum TxOut)
open CardanoLedgerApi.V3.Contexts (ScriptContext ScriptInfo TxInInfo TxInfo)
open CardanoLedgerApi.V3.TxCert (TxCert)
open CardanoLedgerApi.V3.Tx (TxOutRef)

/-- A byte string built from an ASCII test label.

Fixture identifiers are arbitrary but must be stable, so that two contexts
differ only where a fixture deliberately makes them differ.
-/
def label (s : String) : ByteString := { data := s }

/-- The staking credential every observer fixture is anchored on. -/
def observerCredential : Credential :=
  .PubKeyCredential (label "s2-observer-credential")

/-- A second, different credential.

Kept only to show it is *not* what the certify control varies: the publish
branch of every observer matches on the certificate constructor alone and
ignores the credential, so a control that varied the credential would be a
control that cannot fail.
-/
def otherCredential : Credential :=
  .PubKeyCredential (label "s2-other-credential")

/-- The registration certificate the certifying fixtures carry. -/
def observerCertificate : TxCert :=
  .TxCertRegStaking observerCredential none

/-- An empty transaction body.

Every fixture starts here, so any behavioural difference observed between
two fixtures is attributable to the fields the fixture overrides and to
nothing else.
-/
def emptyTxInfo : TxInfo where
  txInfoInputs := []
  txInfoReferenceInputs := []
  txInfoOutputs := []
  txInfoFee := 0
  txInfoMint := []
  txInfoTxCerts := []
  txInfoWdrl := []
  txInfoValidRange := Data.Constr 0 []
  txInfoSignatories := []
  txInfoRedeemers := []
  txInfoData := []
  txInfoId := label "s2-tx-id"
  txInfoVotes := []
  txInfoProposalProcedures := []
  txInfoCurrentTreasuryAmount := Data.Constr 0 []
  txInfoTreasuryDonation := Data.Constr 0 []

/-- A rewarding context for the given credential.

The withdrawal list is kept consistent with the `ScriptInfo`, so this is a
well-formed reward invocation rather than a context that a validator could
reject for an unrelated structural reason.
-/
def rewardContext (credential : Credential) : ScriptContext where
  scriptContextTxInfo :=
    { emptyTxInfo with txInfoWdrl := [(credential, 0)] }
  scriptContextRedeemer := Data.Constr 0 []
  scriptContextScriptInfo := .RewardingScript credential

/-- A certifying context for the given credential, at certificate index 0. -/
def certifyContext (credential : Credential) : ScriptContext where
  scriptContextTxInfo :=
    { emptyTxInfo with
        txInfoTxCerts := [.TxCertRegStaking credential none] }
  scriptContextRedeemer := Data.Constr 0 []
  scriptContextScriptInfo :=
    .CertifyingScript 0 (.TxCertRegStaking credential none)

/-- A spending context, used by the checkpoint preparation proof. -/
def spendContext : ScriptContext where
  scriptContextTxInfo := emptyTxInfo
  scriptContextRedeemer := Data.Constr 0 []
  scriptContextScriptInfo :=
    .SpendingScript { txOutRefId := label "s2-tx-id", txOutRefIdx := 0 } none

/-- A minting context, used by the hash-proof preparation proof. -/
def mintContext : ScriptContext where
  scriptContextTxInfo := emptyTxInfo
  scriptContextRedeemer := Data.Constr 0 []
  scriptContextScriptInfo := .MintingScript (label "s2-policy")

/-- The `Data` encoding a program actually receives. -/
def contextData (context : ScriptContext) : Data := IsData.toData context

/-- A certifying context whose certificate is *not* a registration.

Every observer's publish branch is `expect RegisterCredential {..} =
certificate`, so an un-registration certificate must make that `expect`
fail. This is the wrong-certify control, and it is the constructor that
varies — not the credential, which that branch ignores.
-/
def wrongCertifyContext : ScriptContext where
  scriptContextTxInfo :=
    { emptyTxInfo with
        txInfoTxCerts := [.TxCertUnRegStaking observerCredential none] }
  scriptContextRedeemer := Data.Constr 0 []
  scriptContextScriptInfo :=
    .CertifyingScript 0 (.TxCertUnRegStaking observerCredential none)

/-- A rewarding context whose redeemer cannot be an `ObserverEnvelope`.

Every observer's withdraw branch begins `expect envelope: ObserverEnvelope =
redeemer`, so an integer redeemer must make that `expect` fail. This is the
wrong-reward control.
-/
def wrongRewardContext : ScriptContext where
  scriptContextTxInfo :=
    { emptyTxInfo with txInfoWdrl := [(observerCredential, 0)] }
  scriptContextRedeemer := Data.I 0
  scriptContextScriptInfo := .RewardingScript observerCredential

/-- The reward context for the observer credential. -/
def rewardData : Data := contextData (rewardContext observerCredential)

/-- The certify context for the observer credential. -/
def certifyData : Data := contextData (certifyContext observerCredential)

/-- The wrong-reward control input. -/
def wrongRewardData : Data := contextData wrongRewardContext

/-- The wrong-certify control input. -/
def wrongCertifyData : Data := contextData wrongCertifyContext

/-- The spend context, encoded. -/
def spendData : Data := contextData spendContext

/-- The mint context, encoded. -/
def mintData : Data := contextData mintContext

/-! ## The withdraw-path fixture for `observer_advance`

Every reward run so far has stopped at `TailList` while the validator was
still taking its redeemer apart: `expect envelope: ObserverEnvelope =
redeemer` cannot succeed against `Constr 0 []`, so no reward run has ever
reached the logic under test. Reaching it needs the shape
`observer_advance.withdraw` actually reads.

From `onchain/lib/cardano_keri/checkpoint/observer.ak`, `validate_advance`
requires, in order: a well-formed `ObserverEnvelope`; `claim.own_ref =
Some ref`; a payload castable to `AdvanceEvidence`; an input at exactly that
`own_ref`; an `InlineDatum` on it holding `CheckpointDatum.V1`; an output at
`from_script(claim.checkpoint_policy)`; an `InlineDatum` on that holding
`CheckpointDatum.V1`. Only then does it build `SpentCheckpoint`, whose
`aid_asset_name` field is `deriveAidAssetName(old.cesr_aid)`.

These values are the *shape* the validator demands, not a semantically valid
rotation. Reaching the logic is the point; what the machine then does there
is an observation to be reported, never a fixture choice to be tuned until
it looks like a pass.
-/

/-- The script hash the checkpoint state output is locked by, and the value
`claim.checkpoint_policy` carries. One definition serves both, so the claim
and the output address cannot drift apart. -/
def checkpointPolicy : ByteString := label "s2-checkpoint-policy-0123456"

/-- `from_script(hash)`: a script payment credential and no delegation part.

`validate_advance` selects the state output with `output.address ==
from_script(claim.checkpoint_policy)`, which is data equality, so this must
agree constructor for constructor with Aiken's `from_script`.
-/
def fromScript (scriptHash : ByteString) : Address where
  addressCredential := .ScriptCredential scriptHash
  addressStakingCredential := none

/-- An empty `Value`.

`validate_advance` never reads the value of the resolved input or of the
state output, so an empty one keeps the fixture from asserting anything it
does not need to.
-/
def emptyValue : List (Data × Data) := []

/-- The output reference the envelope names and the fixture input carries.

Both uses read this one definition, so `find_input` is being given a genuine
match rather than two literals that happen to agree today.
-/
def advanceOwnRef : TxOutRef where
  txOutRefId := label "s2-advance-own-ref-txid-01234567"
  txOutRefIdx := 0

/-- The AID the spent checkpoint is bound to.

This is the exact byte string `deriveAidAssetName` would hash, so its width
is protocol-relevant even though nothing about the digest is claimed here.
-/
def advanceCesrAid : ByteString := label "s2-advance-cesr-aid-0123456789ab"

/-- A KERI threshold in its unweighted `m`-of-`n` form: `Unweighted` is
constructor 0 of `Threshold`. -/
def unweightedThreshold (m : Int) : Data := Data.Constr 0 [Data.I m]

/-- The frozen `CheckpointDatumV1` record, in its exact positional field
order: `cesr_aid`, `cur_keys`, `cur_threshold`, `next_keys`,
`next_threshold`, `witnesses`, `toad`, `seq`, `native_sn`. The order is
protocol surface; reordering changes the bytes. -/
def checkpointDatumV1 (cesrAid : ByteString) (seq nativeSn : Int) : Data :=
  Data.Constr 0
    [ Data.B cesrAid
    , Data.List [Data.B (label "s2-advance-cur-key-0123456789abc")]
    , unweightedThreshold 1
    , Data.List [Data.B (label "s2-advance-next-key-0123456789ab")]
    , unweightedThreshold 1
    , Data.List []
    , Data.I 0
    , Data.I seq
    , Data.I nativeSn
    ]

/-- `CheckpointDatum.V1` is constructor 0 wrapping the inner record. -/
def checkpointDatum (inner : Data) : Data := Data.Constr 0 [inner]

/-- An `AdvanceEvidence` with the right arity and field kinds and no
content.

The list-typed fields are empty, which keeps the fixture clear of Aiken's
tuple encoding for `ctrl_sigs`/`wit_receipts` while still satisfying the
structural cast: an empty list is a valid `List<(Int, ByteArray)>`. This
evidence is deliberately not a valid rotation — it only has to get the
machine past `expect evidence: AdvanceEvidence = payload`.
-/
def advanceEvidence : Data :=
  Data.Constr 0
    [ Data.B (label "")   -- event_bytes
    , Data.I 0            -- off_t
    , Data.I 0            -- off_i
    , Data.I 0            -- off_s
    , Data.List []        -- off_k
    , Data.I 0            -- off_kt
    , Data.List []        -- off_n
    , Data.I 0            -- off_nt
    , Data.List []        -- off_br
    , Data.List []        -- off_ba
    , Data.I 0            -- off_bt
    , Data.List []        -- wit_cut
    , Data.List []        -- wit_add
    , Data.List []        -- ctrl_sigs
    , Data.List []        -- wit_receipts
    ]

/-- The stable action tag for Advance (`observe_advance` in `observer.ak`).

`validate_advance` compares `claim.action` against it to decide whether the
spent datum is a plain `CheckpointDatum` or the Armed response form.
-/
def observeAdvance : Int := 1

/-- `ObserverClaim { action, checkpoint_policy, own_ref }`. Aiken's `Option`
is `Some` at constructor 0 and `None` at constructor 1. -/
def observerClaim (action : Int) (policy : ByteString)
    (ownRef : Option TxOutRef) : Data :=
  Data.Constr 0
    [ Data.I action
    , Data.B policy
    , match ownRef with
      | some reference => Data.Constr 0 [IsData.toData reference]
      | none => Data.Constr 1 []
    ]

/-- `ObserverEnvelope { claim, payload }`. -/
def observerEnvelope (claim payload : Data) : Data :=
  Data.Constr 0 [claim, payload]

/-- The input `validate_advance` resolves `own_ref` to, carrying the spent
checkpoint state as an inline datum. -/
def advanceOwnInput : TxInInfo where
  txInInfoOutRef := advanceOwnRef
  txInInfoResolved :=
    { txOutAddress := fromScript checkpointPolicy
    , txOutValue := emptyValue
    , txOutDatum :=
        .OutputDatum (checkpointDatum (checkpointDatumV1 advanceCesrAid 0 0))
    , txOutReferenceScript := none }

/-- The created state output, at the address the claim's policy derives, with
its own inline successor datum. -/
def advanceStateOutput : TxOut where
  txOutAddress := fromScript checkpointPolicy
  txOutValue := emptyValue
  txOutDatum :=
    .OutputDatum (checkpointDatum (checkpointDatumV1 advanceCesrAid 1 1))
  txOutReferenceScript := none

/-- The reward context that reaches `observer_advance`'s rotation logic.

It is still a rewarding invocation on the observer credential — the purpose
is unchanged and the withdrawal stays consistent with the `ScriptInfo`. What
changes is that the redeemer is now a real `ObserverEnvelope` and the
transaction actually carries the input and output the validator goes looking
for.
-/
def advanceRewardContext : ScriptContext where
  scriptContextTxInfo :=
    { emptyTxInfo with
        txInfoInputs := [advanceOwnInput]
        txInfoOutputs := [advanceStateOutput]
        txInfoWdrl := [(observerCredential, 0)] }
  scriptContextRedeemer :=
    observerEnvelope
      (observerClaim observeAdvance checkpointPolicy (some advanceOwnRef))
      advanceEvidence
  scriptContextScriptInfo := .RewardingScript observerCredential

/-- The advance withdraw-path reward context, encoded. -/
def advanceRewardData : Data := contextData advanceRewardContext

/-- Byte widths this fixture asserts rather than trusts.

`cesr_aid` is 32 bytes, a script hash is 28, a transaction id is 32. These
are hand-written literals, and a miscounted one would silently change the
preimage `deriveAidAssetName` hashes, so each is checked against the width
the protocol fixes instead of against my counting.
-/
def advanceFixtureWidths : List (String × Nat × Nat) :=
  [ ("cesr_aid", advanceCesrAid.data.length, 32)
  , ("checkpoint_policy", checkpointPolicy.data.length, 28)
  , ("own_ref.transaction_id", advanceOwnRef.txOutRefId.data.length, 32)
  , ("cur_key_digest", (label "s2-advance-cur-key-0123456789abc").data.length, 32)
  , ("next_key_digest", (label "s2-advance-next-key-0123456789ab").data.length, 32)
  ]

/-- The fixtures a purpose block applies, in the order it applies them.

Declaring them as one list keeps a block from silently testing fewer
contexts than it claims, and lets the emitted evidence report how many
genuinely distinct contexts were applied.
-/
def purposeFixtures : List (String × Data) :=
  [ ("reward", rewardData)
  , ("certify", certifyData)
  , ("wrong_reward", wrongRewardData)
  , ("wrong_certify", wrongCertifyData)
  ]

end KeriBlaster.S2.Fixtures
