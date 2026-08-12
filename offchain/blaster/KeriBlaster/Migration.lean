import PlutusCore.UPLC
import CardanoLedgerApi.V3
import KeriBlaster.S2Cek

/-!
# M8 compiled evidence for the #254 checkpoint migration family

This module executes the **exact changed compiled checkpoint program** — the
one the current `onchain/` source produces, extracted from the live
`plutus-blueprint` derivation, never the frozen M8 baseline — and requires it
to refuse a named authority mutant and a named replay mutant.

Two design rules make the result mean what it says.

**A rejection must be the validator's own.** The pinned CEK evaluator does not
implement every Plutus builtin, and a refused builtin dispatch also stops the
machine with `Error`. Reporting that as `REJECT` would map "the program refused
this transaction" and "we could not evaluate the program" onto one word. So a
mutant is only `REJECT` when `errorKind` is `term-error`, which is the shape a
validator's own `expect` failure compiles to. A `builtin-dispatch` failure is
reported as `COULD-NOT-EVALUATE` and fails the run.

**Neither mutant may need a builtin the evaluator lacks.** Both are therefore
built to be refused *before* any signature verification happens: the replay
mutant contradicts the named spent output, and the authority mutant carries an
empty controller signature set, which cannot satisfy a 2-of-3 threshold and
never calls `verify_ed25519_signature` at all.

The positive control is the instrument's own: the same program applied to its
parameters alone settles as `HALT`. A runner that can only ever print `ERROR`
would prove nothing by printing it twice.
-/

-- Decoding a whole applied validator exceeds the default elaboration
-- recursion depth, exactly as the S2 evidence module already found.
set_option maxRecDepth 100000

#import_uplc migrationObserverWithdraw PlutusV3 single_cbor_hex "nix-generated/checkpoint_observer.observer_migration.withdraw.hex"

namespace KeriBlaster.Migration

open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V1.Address (Address)
open CardanoLedgerApi.V1.Credential (Credential)
open CardanoLedgerApi.V2.Tx (OutputDatum TxOut)
open CardanoLedgerApi.V3.Contexts (ScriptContext ScriptInfo TxInInfo TxInfo)
open CardanoLedgerApi.V3.Tx (TxOutRef)

/-- A fixed-width byte string from a literal, so widths stay visible. -/
def label (s : String) : ByteString := { data := s }

/-- The applied source generation and its minting policy. The program's own
`own_hash` is read from the consumed input's address, so this one definition
drives both and they cannot drift apart. -/
def sourcePolicy : ByteString := label "s2-migration-source-policy-01"

def predecessorPolicy : ByteString := label "s2-migration-predecessor-pol"

def targetPolicy : ByteString := label "s2-migration-target-policy-01"
/-- The spent checkpoint output the redeemer names. -/
def ownRefId : ByteString := label "s2-migration-own-ref-txid-012345"

/-- A different transaction id, used only by the replay mutant. -/
def otherRefId : ByteString := label "s2-migration-other-ref-txid-0123"

def ownRef : TxOutRef where
  txOutRefId := ownRefId
  txOutRefIdx := 0

/-- `OutputReference` as the validator decodes it. -/
def outRefData (txid : ByteString) (index : Int) : Data :=
  Data.Constr 0 [Data.B txid, Data.I index]

/-- `Unweighted m` is constructor 0 of `Threshold`. -/
def unweighted (m : Int) : Data := Data.Constr 0 [Data.I m]

/-- A well-formed `CheckpointDatumV1`.

Well-formedness matters here: an ill-formed projection would make the
authority mutant fail as `MigrationDatumIllFormed` instead of
`MigrationQuorumUnsatisfied`, which is a rejection for the wrong reason and
would make the control vacuous. Widths are exact: a 32-byte AID, 32-byte
verkeys, three current keys with a 2-of-3 threshold, and no witnesses with
`toad = 0`.
-/
def checkpointDatumV1 : Data :=
  Data.Constr 0
    [ Data.B (label "s2-migration-cesr-aid-0123456789")
    , Data.List
        [ Data.B (label "s2-migration-ctrl-key-0-01234567")
        , Data.B (label "s2-migration-ctrl-key-1-01234567")
        , Data.B (label "s2-migration-ctrl-key-2-01234567") ]
    , unweighted 2
    , Data.List [ Data.B (label "s2-migration-next-key-0-01234567") ]
    , unweighted 1
    , Data.List []
    , Data.I 0
    , Data.I 7
    , Data.I 4
    ]

/-- `CheckpointDatum.V1` wraps the inner record; this is what the
authorization carries verbatim. -/
def carriedState : Data := Data.Constr 0 [checkpointDatumV1]

/-- The consumed row's datum is the frozen `CheckpointDatum` version sum: the
lean design carries no generation integer and no origin back-pointer, because
the applied hash is release identity and the migration transaction is the
lineage edge. -/
def versionedDatum : Data := Data.Constr 0 [checkpointDatumV1]

/-- `MigrationPredecessor`: the policy holding the spent output, and the
output itself. -/
def predecessorData (txid : ByteString) : Data :=
  Data.Constr 0 [Data.B sourcePolicy, outRefData txid 0]

/-- A script address with no delegation part, matching Aiken `from_script`. -/
def fromScript (scriptHash : ByteString) : Address where
  addressCredential := .ScriptCredential scriptHash
  addressStakingCredential := none

/-- `MigrationTarget`: the target policy, ACTIVE, no legacy refund. -/
def targetData : Data :=
  Data.Constr 0
    [ Data.B targetPolicy
    , Data.Constr 0 []
    , IsData.toData (fromScript targetPolicy)
    , Data.Constr 1 []
    ]

/-- `MigrationAuthorization`, parameterised by the two things the mutants
vary: which output it claims to spend, and its controller signature set. -/
def authorizationData (txid : ByteString) (signatures : List Data) : Data :=
  Data.Constr 0
    [ Data.B (label "cardano-keri/migration/v1")
    , Data.I 0
    , predecessorData txid
    , Data.Constr 0 []
    , carriedState
    , targetData
    , Data.List signatures
    ]

/-- The consumed source: an ACTIVE row holding its own token. -/
def sourceInput : TxInInfo where
  txInInfoOutRef := ownRef
  txInInfoResolved :=
    { txOutAddress := fromScript sourcePolicy
    , txOutValue := []
    , txOutDatum := .OutputDatum versionedDatum
    , txOutReferenceScript := none }

/-- `MigrationProof.MigrateOutProof` is constructor 0: the source generation
leaving under its own controller quorum. -/
def migrateOutProof (authorization : Data) : Data :=
  Data.Constr 0 [authorization]

/-- The stake credential the zero-lovelace observer withdrawal is made under. -/
def observerCredential : Credential :=
  .ScriptCredential (label "s2-migration-observer-cred")

/-- `ObserverClaim`: the migration action tag, the checkpoint policy, and the
exact source output. The checkpoint program independently requires this same
claim, so neither side trusts the other's reading of the transaction. -/
def observerClaim (txid : ByteString) : Data :=
  Data.Constr 0
    [ Data.I 5
    , Data.B sourcePolicy
    , Data.Constr 0 [outRefData txid 0]
    ]

/-- `ObserverEnvelope`: the claim plus its proof payload. -/
def observerEnvelope (claimTxid : ByteString) (authorization : Data) : Data :=
  Data.Constr 0 [observerClaim claimTxid, migrateOutProof authorization]

/-- A rewarding context: the promoted observer runs as a zero-lovelace
withdrawal, so its purpose is `RewardingScript`, never a spend. -/
def migrateOutContext (claimTxid : ByteString) (authorization : Data) :
    ScriptContext where
  scriptContextTxInfo :=
    { txInfoInputs := [sourceInput]
    , txInfoReferenceInputs := []
    , txInfoOutputs := []
    , txInfoFee := 0
    , txInfoMint := []
    , txInfoTxCerts := []
    , txInfoWdrl := [(observerCredential, 0)]
    , txInfoValidRange := Data.Constr 0 []
    , txInfoSignatories := []
    , txInfoRedeemers := []
    , txInfoData := []
    , txInfoId := label "s2-migration-tx-id"
    , txInfoVotes := []
    , txInfoProposalProcedures := []
    , txInfoCurrentTreasuryAmount := Data.Constr 0 []
    , txInfoTreasuryDonation := Data.Constr 0 [] }
  scriptContextRedeemer := observerEnvelope claimTxid authorization
  scriptContextScriptInfo := .RewardingScript observerCredential

/-- The single applied parameter of `observer_migration`: the one predecessor
policy it accepts. It is an applied parameter, never a redeemer field, and the
resulting program hash is this release's identity -- there is no generation
integer to apply. -/
def appliedParameters : List Data :=
  [Data.B predecessorPolicy]

/-- A `Data` argument as a UPLC term. -/
def dataTerm (value : Data) : PlutusCore.UPLC.Term.Term := .Const (.Data value)

/-- Step budget for one bounded run. -/
def budget : Nat := 10000000

/-- Run the imported program against one context. -/
def runAgainst (context : ScriptContext) : KeriBlaster.S2.Cek.Trace :=
  KeriBlaster.S2.Cek.runProgram
    migrationObserverWithdraw.script
    (appliedParameters.map dataTerm ++ [dataTerm (IsData.toData context)])
    budget

/-- The replay mutant: a real package whose named source output is not the one
being spent. Refused by the outref equality, before any signature work. -/
def replayMutant : ScriptContext :=
  migrateOutContext otherRefId (authorizationData otherRefId [])

/-- The authority mutant: the correct source output, and no controller
signature at all. A 2-of-3 threshold cannot be met by the empty set, and
`verify_ed25519_signature` is never reached. -/
def authorityMutant : ScriptContext :=
  migrateOutContext ownRefId (authorizationData ownRefId [])

/-- How a mutant run is classified.

`REJECT` is reserved for the validator's own refusal. Anything the pinned
evaluator could not carry out is `COULD-NOT-EVALUATE` and is never reported as
a rejection.
-/
def classify (trace : KeriBlaster.S2.Cek.Trace) : String :=
  if trace.exhausted then "COULD-NOT-EVALUATE"
  else if KeriBlaster.S2.Cek.errored trace then
    if KeriBlaster.S2.Cek.errorKind trace == "term-error" then "REJECT"
    else "COULD-NOT-EVALUATE"
  else "ACCEPT"

/-- Emit one mutant row, failing the run if it is not a genuine rejection. -/
def reportMutant (className : String) (context : ScriptContext) : IO Bool := do
  let trace := runAgainst context
  let outcome := classify trace
  IO.println s!"M8.migration-mutant class={className} outcome={outcome}"
  if outcome != "REJECT" then
    IO.eprintln s!"M8: {className} mutant was not refused by the program itself (outcome={outcome}, error_kind={KeriBlaster.S2.Cek.errorKind trace}, steps={trace.steps}); this is not evidence of enforcement"
    pure false
  else
    pure true

/-- The instrument's own positive control.

The same program applied to its parameters alone must settle as `HALT`. This
is what distinguishes "the machine refuses this transaction" from "this runner
prints ERROR whatever it is given", and it is checked before any mutant row is
believed.
-/
def parameterControl : IO Bool := do
  let trace :=
    KeriBlaster.S2.Cek.runProgram
      migrationObserverWithdraw.script
      (appliedParameters.map dataTerm)
      budget
  let outcome := KeriBlaster.S2.Cek.outcome trace
  IO.println s!"M8.migration-control case=applied-parameters outcome={outcome} steps={trace.steps}"
  if outcome != "HALT" then
    IO.eprintln s!"M8: the runner could not settle the program on its parameters alone (outcome={outcome}); a REJECT from it would not be distinguishable from a runner that always errors"
    pure false
  else
    pure true

/-- The migration evidence entry point.

It is reached from `KeriBlaster.main` when `MIGRATION_EVIDENCE` is set, so the
migration rows and the S2 rows come from one binary built over one pinned
module graph, and neither can be produced by a copy of the checking path.
-/
def run : IO UInt32 := do
  let controlOk ← parameterControl
  if !controlOk then
    return 1
  let authorityOk ← reportMutant "authority" authorityMutant
  let replayOk ← reportMutant "replay" replayMutant
  if authorityOk && replayOk then
    IO.println "PASS: the exact changed compiled checkpoint family refused the named authority and replay mutants"
    return 0
  else
    return 1

end KeriBlaster.Migration
