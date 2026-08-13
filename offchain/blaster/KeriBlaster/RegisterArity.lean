import PlutusCore.UPLC
import CardanoLedgerApi.V3
import KeriBlaster.S2Cek

/-!
# M8 compiled evidence for the corrected #254 register arity

This module executes the **exact compiled combined register** the current
`onchain/` source produces, extracted from the live `plutus-blueprint`
derivation, never the frozen M8 baseline. It establishes where that program's
parameter surface actually ends.

`checkpoint_register` declares eight applied parameters. Before #254 A-007 the
deployment applied nine, so the ninth argument -- a leftover version integer
from the cut version feature -- occupied the slot the ledger fills with the
script context, and every identity derived from it belonged to a program that
could not settle a transaction. Two runs of the real compiled program pin the
boundary:

**At eight, the program settles.** Applied to its eight parameters and nothing
else, the machine reaches a value: what remains is a script still waiting for
its context. That is `HALT`, and it is also this instrument's positive control
-- a runner that could only ever print `ERROR` would prove nothing by printing
it twice.

**At nine, the program adjudicates.** A ninth argument is not absorbed as
configuration; it is consumed as the script context and judged. The mutant
supplies a well-formed `ScriptContext` whose purpose the register does not
serve, which reaches the validator's own `else(_) { fail }` arm. So the ninth
argument is script input, never a parameter, which is exactly why applying the
version integer there was a defect rather than a cosmetic surplus.

**A rejection must be the validator's own.** The pinned CEK evaluator does not
implement every Plutus builtin, and a refused builtin dispatch also stops the
machine with `Error`. Reporting that as `REJECT` would map "the program refused
this input" and "we could not evaluate the program" onto one word. A mutant is
therefore `REJECT` only when `errorKind` is `term-error`, the shape a
validator's own failure compiles to; a `builtin-dispatch` failure is reported
as `COULD-NOT-EVALUATE` and fails the run. The mutant is deliberately built to
be refused at the purpose dispatch, before any deposit, bond or signature work,
so it cannot reach a builtin the evaluator lacks.

__What this does not establish.__ The four policy-hash parameters applied here
are placeholders of the correct width, not the four sibling hashes the
deployment derives, so these runs say nothing about which observers the
register trusts. The applied identity in the recipe's target row comes from the
production derivation, not from this module; the recipe binds the two by
requiring the SHA-256 of the program extracted here to equal the SHA-256 of the
program the derivation read.
-/

-- Decoding a whole applied validator exceeds the default elaboration
-- recursion depth, exactly as the S2 and migration evidence modules found.
set_option maxRecDepth 100000

#import_uplc checkpointRegisterMint PlutusV3 single_cbor_hex "nix-generated/checkpoint_register.checkpoint_register.mint.hex"

namespace KeriBlaster.RegisterArity

open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V1.Credential (Credential)
open CardanoLedgerApi.V3.Contexts (ScriptContext ScriptInfo TxInfo)

/-- A fixed-width byte string from a literal, so widths stay visible. -/
def label (s : String) : ByteString := { data := s }

/-- The four policy hashes the register is applied to, at the exact 28-byte
width a `PolicyId` has. They are placeholders: this module is evidence about
arity, not about which observers the register trusts. -/
def migrationHash : ByteString := label "s254r-migration-policy-01234"

def lifecycleHash : ByteString := label "s254r-lifecycle-policy-01234"

def advanceHash : ByteString := label "s254r-advance-policy-0123456"

def enforcementHash : ByteString := label "s254r-enforcement-policy-012"

/-- The four deployment integers, at their real released values. -/
def networkId : Int := 0

def registrationDeposit : Int := 1000000000

def freezeBond : Int := 5000000

def freezeWindow : Int := 10000

/-- The exact eight applied parameters of the corrected register, in the order
`checkpoint_register` declares them.

There is no version argument. The register declares no version parameter, so
this list is what the corrected deployment applies and its length is the whole
point of this module.
-/
def appliedParameters : List Data :=
  [ Data.B migrationHash
  , Data.B lifecycleHash
  , Data.B advanceHash
  , Data.B enforcementHash
  , Data.I networkId
  , Data.I registrationDeposit
  , Data.I freezeBond
  , Data.I freezeWindow
  ]

/-- A `Data` argument as a UPLC term. -/
def dataTerm (value : Data) : PlutusCore.UPLC.Term.Term := .Const (.Data value)

/-- Step budget for one bounded run. -/
def budget : Nat := 10000000

/-- The stake credential the mutant's withdrawal is made under. -/
def rewardCredential : Credential :=
  .ScriptCredential (label "s254r-unserved-purpose-cred")

/-- An empty transaction. The mutant is refused at the purpose dispatch, so
nothing in here is ever read; it exists only so the context is well formed and
the refusal cannot be a malformed-input error from a builtin. -/
def emptyTxInfo : TxInfo where
  txInfoInputs := []
  txInfoReferenceInputs := []
  txInfoOutputs := []
  txInfoFee := 0
  txInfoMint := []
  txInfoTxCerts := []
  txInfoWdrl := [(rewardCredential, 0)]
  txInfoValidRange := Data.Constr 0 []
  txInfoSignatories := []
  txInfoRedeemers := []
  txInfoData := []
  txInfoId := label "s254r-tx-id"
  txInfoVotes := []
  txInfoProposalProcedures := []
  txInfoCurrentTreasuryAmount := Data.Constr 0 []
  txInfoTreasuryDonation := Data.Constr 0 []

/-- A well-formed rewarding context. `checkpoint_register` handles `mint` and
`spend` only and closes with `else(_) { fail }`, so a rewarding purpose reaches
that arm and the refusal is the validator's own. -/
def unservedPurposeContext : ScriptContext where
  scriptContextTxInfo := emptyTxInfo
  scriptContextRedeemer := Data.Constr 0 []
  scriptContextScriptInfo := .RewardingScript rewardCredential

/-- Run the imported program against a list of arguments. -/
def runWith (arguments : List Data) : KeriBlaster.S2.Cek.Trace :=
  KeriBlaster.S2.Cek.runProgram
    checkpointRegisterMint.script
    (arguments.map dataTerm)
    budget

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

/-- The parameter control: the program applied to its eight declared parameters
and nothing else must settle on a value. -/
def parameterControl : IO Bool := do
  let trace := runWith appliedParameters
  let outcome := KeriBlaster.S2.Cek.outcome trace
  IO.println s!"M8.register-control case=applied-parameters outcome={outcome}"
  if outcome != "HALT" then
    IO.eprintln s!"M8: the register did not settle on its {appliedParameters.length} declared parameters (outcome={outcome}, steps={trace.steps}); a REJECT from this runner would not be distinguishable from a runner that always errors"
    pure false
  else
    pure true

/-- The overapplication mutant: one argument past the declared parameters.

The extra argument is a well-formed script context, which is what the ledger
puts in that slot. The program judges it and refuses, establishing that the
parameter surface ended at the previous argument.
-/
def overapplicationMutant : IO Bool := do
  let trace :=
    runWith (appliedParameters ++ [IsData.toData unservedPurposeContext])
  let outcome := classify trace
  IO.println s!"M8.register-mutant class=overapplication outcome={outcome}"
  if outcome != "REJECT" then
    IO.eprintln s!"M8: the ninth argument was not refused by the program itself (outcome={outcome}, error_kind={KeriBlaster.S2.Cek.errorKind trace}, steps={trace.steps}); this is not evidence that the parameter surface ends at {appliedParameters.length}"
    pure false
  else
    pure true

/-- The register-arity evidence entry point.

Reached from `KeriBlaster.main` when `REGISTER_EVIDENCE` is set, so these rows
and the S2 and migration rows come from one binary over one pinned module
graph, and none can be produced by a copy of the checking path.
-/
def run : IO UInt32 := do
  let controlOk ← parameterControl
  if !controlOk then
    return 1
  let mutantOk ← overapplicationMutant
  if mutantOk then
    IO.println s!"PASS: the exact compiled register settles at {appliedParameters.length} applied parameters and refuses a further argument"
    return 0
  else
    return 1

end KeriBlaster.RegisterArity
