import PlutusCore.UPLC
import CardanoLedgerApi.V3
import KeriBlaster.S2Cek

/-!
# M8 compiled evidence for the #254 S254-E entitlement family

This module executes the **exact compiled programs the current `onchain/`
source produces** — extracted from the live `plutus-blueprint` derivation,
never the frozen M8 baseline — and requires the reservation half of the
entitlement family to refuse four named mutants.

## The three design rules inherited from the migration evidence

**A rejection must be the validator's own.** The pinned CEK evaluator does not
implement every Plutus builtin, and a refused builtin dispatch also stops the
machine with `Error`. Reporting that as `REJECT` would map "the program refused
this transaction" and "we could not evaluate the program" onto one word. So a
mutant is only `REJECT` when `errorKind` is `term-error`, which is the shape a
validator's own `expect` failure compiles to. A `builtin-dispatch` failure is
reported as `COULD-NOT-EVALUATE` and fails the run.

**No mutant may need a builtin the evaluator lacks.** Every mutant below is
refused by a structural, interval, or value comparison. None reaches
`verify_ed25519_signature`, and none reaches the commitment hash: the reveal
path deliberately does not recompute it, so no mutant here depends on
`serialiseData` or `blake2b_256` being available.

**The instrument's own positive control.** Each imported program applied to its
parameters alone must settle as `HALT`. A runner that could only ever print
`ERROR` would prove nothing by printing it four times.

## The fourth rule this module adds

**An accepted honest neighbour.** The four mutants differ from one honest
transaction in exactly one field each, and that honest transaction is run
first and required to `ACCEPT`. Without it, a fixture broken in some unrelated
way would produce four rejections that look exactly like enforcement and
establish nothing. This is the compiled form of the discipline the Aiken and
Haskell suites already follow.

## What this module does and does not indict — stated, not implied

The four mutant rows run against the **commitment program**, which is the half
of the entitled family that owns the reservation: its authenticity by value,
its scope, its maturity window, and its refund. That is where all four named
classes are decidable without crypto.

The **checkpoint program** is identified and arity-asserted by the flake's
extraction — its seventh applied `CommitmentFamily` argument is required there,
from the live blueprint — but it is NOT executed here, and this module emits an
explicit non-claim saying so rather than letting its identity row be read as a
behavioural result. Two independent reasons, both recorded because either alone
would be enough:

* its entitlement leg sits behind `bind_enforcement_evidence` and
  `freeze_predicate`, which verify Ed25519 signatures — a builtin the pinned
  evaluator refuses — so a mutant aimed at it would settle as
  `COULD-NOT-EVALUATE`, which is not a rejection and must never be reported as
  one;
* elaborating the entitled checkpoint program alongside the commitment program
  in one module overflows the Lean elaborator's stack (observed, exit 134),
  so this instrument cannot hold both.

Its entitlement legs are proved instead by the Aiken applied-program rows in
`checkpoint_tests.ak` and `checkpoint_register_tests.ak`, by the Haskell mirror
in `EntitlementSpec`, and by the cross-language verdict vectors. This run
claims exactly what it observed and no more.
-/

-- Decoding a whole applied validator exceeds the default elaboration
-- recursion depth, exactly as the S2 and migration evidence modules found.
set_option maxRecDepth 100000

#import_uplc commitmentSpend PlutusV3 single_cbor_hex "nix-generated/bounty_commitment.bounty_commitment.spend.hex"

namespace KeriBlaster.Entitlement

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

-- ---------------------------------------------------------------
-- Applied release identity
-- ---------------------------------------------------------------

/-- 28 bytes. The applied commitment policy: one script hash is both the
marker's policy id and the reservation output's payment credential, so this
single definition drives both sides of every fixture. -/
def commitmentPolicy : ByteString := label "s254e-commitment-policy-01ab"

/-- 28 bytes. -/
def checkpointPolicy : ByteString := label "s254e-checkpoint-policy-01ab"

/-- 28 bytes. -/
def hashProofPolicy : ByteString := label "s254e-hash-proof-policy-01ab"

/-- 28 bytes: the beneficiary the reservation named. -/
def payee : ByteString := label "s254e-committed-payee-01abcd"

/-- 28 bytes: a key the reservation never named. -/
def attacker : ByteString := label "s254e-substituted-payee-0abc"

/-- 32 bytes. The marker is protocol-opaque on the reveal path: the program
checks its width and its binding to the scope, not its seed derivation, which
belongs to the opening. -/
def marker : ByteString := label "s254e-commitment-marker-01234567"

/-- 32 bytes: the protocol's minimum nonce width, exactly. -/
def nonce : ByteString := label "s254e-commitment-nonce-012345678"

/-- 32 bytes. The reveal path never recomputes the commitment hash, so this is
opaque here — which is exactly why no mutant below needs a hash builtin. -/
def commitmentHash : ByteString := label "s254e-commitment-hash-0123456789"

/-- 32 bytes. -/
def commitmentTxId : ByteString := label "s254e-commitment-txid-0123456789"

/-- 32 bytes: a different reservation, used only by the entitlement mutant. -/
def otherTxId : ByteString := label "s254e-other-commitment-txid-0123"

/-- 32 bytes. -/
def checkpointTxId : ByteString := label "s254e-checkpoint-txid-0123456789"

def network : Int := 0

def commitMinAge : Int := 1

/-- An explicit finite release lifetime. There is no protocol default for this
magnitude and none is recreated here. -/
def commitmentLifetime : Int := 7200

/-- The demonstrated 5 ADA floor, retained. -/
def commitDeposit : Int := 5000000

def commitUpper : Int := 1000

def eligibleAfter : Int := commitUpper + commitMinAge

def expiresAt : Int := commitUpper + commitmentLifetime

def refundIndex : Int := 0

-- ---------------------------------------------------------------
-- Wire shapes, exactly as the validator decodes them
-- ---------------------------------------------------------------

/-- `OutputReference`. -/
def outRefData (txid : ByteString) (index : Int) : Data :=
  Data.Constr 0 [Data.B txid, Data.I index]

def commitmentRef : TxOutRef where
  txOutRefId := commitmentTxId
  txOutRefIdx := 0

/-- `CommitmentParameters`: the four applied magnitudes. -/
def parametersData : Data :=
  Data.Constr 0
    [ Data.I network
    , Data.I commitMinAge
    , Data.I commitmentLifetime
    , Data.I commitDeposit ]

/-- `CommitmentFamily`: the pinned policy plus those magnitudes. -/
def familyData : Data :=
  Data.Constr 0 [Data.B commitmentPolicy, parametersData]

/-- `BountyScope`, parameterised by the one field the scope mutant varies. -/
def scopeData (scopeNetwork : Int) : Data :=
  Data.Constr 0
    [ Data.B (label "cardano-keri/bounty-commitment")
    , Data.I 1
    , Data.I scopeNetwork
    , Data.B checkpointPolicy
    , outRefData checkpointTxId 3
    , Data.Constr 0 []
    , Data.B marker
    , Data.I commitUpper
    , Data.I eligibleAfter
    , Data.I expiresAt ]

/-- `BountyCommitmentV1`. -/
def commitmentData (scopeNetwork : Int) : Data :=
  Data.Constr 0
    [ scopeData scopeNetwork
    , Data.B payee
    , Data.B commitmentHash
    , Data.B marker ]

/-- `BountyRevealV1`, parameterised by the reservation it names. -/
def revealData (namedTxId : ByteString) : Data :=
  Data.Constr 0
    [ outRefData namedTxId 0, Data.B nonce, Data.I refundIndex ]

/-- `BountySpend.Reveal` is constructor 0. -/
def revealRedeemer (namedTxId : ByteString) : Data :=
  Data.Constr 0 [revealData namedTxId]

/-- A script address with no delegation part, matching Aiken `from_script`. -/
def fromScript (scriptHash : ByteString) : Address where
  addressCredential := .ScriptCredential scriptHash
  addressStakingCredential := none

/-- An enterprise key address, matching Aiken `from_verification_key`. -/
def fromVerificationKey (pkh : ByteString) : Address where
  addressCredential := .PubKeyCredential pkh
  addressStakingCredential := none

/-- Exactly `deposit` lovelace plus the quantity-one marker, in the flattened
order Aiken's `exact_commitment_value` compares against. -/
def commitmentValue : CardanoLedgerApi.V1.Value.Value :=
  [ (Data.B (label ""), Data.Map [(Data.B (label ""), Data.I commitDeposit)])
  , (Data.B commitmentPolicy, Data.Map [(Data.B marker, Data.I 1)]) ]

/-- A lovelace-only value. -/
def lovelaceOnly (amount : Int) : CardanoLedgerApi.V1.Value.Value :=
  [(Data.B (label ""), Data.Map [(Data.B (label ""), Data.I amount)])]

/-- The whole mint map: this marker, burned exactly once. -/
def burnOne : CardanoLedgerApi.V1.Value.Value :=
  [(Data.B commitmentPolicy, Data.Map [(Data.B marker, Data.I (-1))])]

/-- `Interval<Int>` as the validator decodes it: two bounds, each a bound type
plus an inclusivity flag. `Finite` is constructor 1; `True` is constructor 1. -/
def finiteRange (lower upper : Int) : Data :=
  Data.Constr 0
    [ Data.Constr 0 [Data.Constr 1 [Data.I lower], Data.Constr 1 []]
    , Data.Constr 0 [Data.Constr 1 [Data.I upper], Data.Constr 1 []] ]

/-- The reservation being spent: a script output holding exactly its own
marker plus the applied deposit, carrying an inline commitment datum. -/
def commitmentInput (scopeNetwork : Int) : TxInInfo where
  txInInfoOutRef := commitmentRef
  txInInfoResolved :=
    { txOutAddress := fromScript commitmentPolicy
    , txOutValue := commitmentValue
    , txOutDatum := .OutputDatum (commitmentData scopeNetwork)
    , txOutReferenceScript := none }

/-- The deposit refund. Parameterised by its recipient, which is the one field
the payout mutant varies. -/
def refundOutput (recipient : ByteString) : TxOut where
  txOutAddress := fromVerificationKey recipient
  txOutValue := lovelaceOnly commitDeposit
  txOutDatum := .NoOutputDatum
  txOutReferenceScript := none

/-- One reveal context. Every field a mutant varies is an argument, so the
four mutants below differ from the honest case in exactly one place and the
difference is visible at the call site. -/
def revealContext
    (scopeNetwork : Int) (namedTxId : ByteString)
    (lower upper : Int) (recipient : ByteString) : ScriptContext where
  scriptContextTxInfo :=
    { txInfoInputs := [commitmentInput scopeNetwork]
    , txInfoReferenceInputs := []
    , txInfoOutputs := [refundOutput recipient]
    , txInfoFee := 0
    , txInfoMint := burnOne
    , txInfoTxCerts := []
    , txInfoWdrl := []
    , txInfoValidRange := finiteRange lower upper
    , txInfoSignatories := [payee]
    , txInfoRedeemers := []
    , txInfoData := []
    , txInfoId := label "s254e-entitlement-tx-id"
    , txInfoVotes := []
    , txInfoProposalProcedures := []
    , txInfoCurrentTreasuryAmount := Data.Constr 0 []
    , txInfoTreasuryDonation := Data.Constr 0 [] }
  scriptContextRedeemer := revealRedeemer namedTxId
  scriptContextScriptInfo := .SpendingScript commitmentRef none

/-- The honest matured reveal. Everything below differs from this in one
field. -/
def honestReveal : ScriptContext :=
  revealContext network commitmentTxId eligibleAfter (eligibleAfter + 1) payee

/-- `entitlement`: the reveal names a DIFFERENT reservation than the input it
is spending. The redeemer no longer binds to this commitment, so nothing
entitles this settlement — refused by the reveal's own redeemer binding,
before any timing or value leg. -/
def entitlementMutant : ScriptContext :=
  revealContext network otherTxId eligibleAfter (eligibleAfter + 1) payee

/-- `age`: revealed in the very slot the reservation was opened in. One slot
short of maturity, so the commit-reveal gap the whole scheme rests on never
elapsed. -/
def ageMutant : ScriptContext :=
  revealContext network commitmentTxId commitUpper commitUpper payee

/-- `scope`: a reservation whose stored network is not the applied one. Its
scope was never well formed for this release, so it cannot be revealed under
it however well the rest of the transaction is built. -/
def scopeMutant : ScriptContext :=
  revealContext (network + 1) commitmentTxId eligibleAfter (eligibleAfter + 1)
    payee

/-- `payout`: the exact deposit, at the exact index, to the wrong key. This is
the substitution the whole entitlement design exists to refuse: the attacker
signs as itself and names itself, and the committed payee is the only thing
that says no. -/
def payoutMutant : ScriptContext :=
  revealContext network commitmentTxId eligibleAfter (eligibleAfter + 1)
    attacker

-- ---------------------------------------------------------------
-- The pinned machine
-- ---------------------------------------------------------------

/-- A `Data` argument as a UPLC term. -/
def dataTerm (value : Data) : PlutusCore.UPLC.Term.Term := .Const (.Data value)

/-- Step budget for one bounded run. -/
def budget : Nat := 10000000

/-- The commitment program's single applied argument. -/
def commitmentParameters : List Data := [parametersData]

/-- The checkpoint program's seven applied arguments, ending in the
`CommitmentFamily` this slice added.

Kept as a definition even though this instrument does not execute that program:
it is the exact argument list the deployment applies, and writing it here is
what makes the non-claim below specific — the row names a program whose shape
this module knows, not one it merely heard about.
-/
def checkpointParameters : List Data :=
  [ Data.I 0
  , Data.B hashProofPolicy
  , Data.I network
  , Data.I 1000000000
  , Data.I 5000000
  , Data.I 10000
  , familyData ]

/-- Run the imported commitment program against one context. -/
def runCommitment (context : ScriptContext) : KeriBlaster.S2.Cek.Trace :=
  KeriBlaster.S2.Cek.runProgram
    commitmentSpend.script
    (commitmentParameters.map dataTerm ++ [dataTerm (IsData.toData context)])
    budget

/-- How a run is classified.

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
  let trace := runCommitment context
  let outcome := classify trace
  IO.println s!"M8.entitlement-mutant class={className} outcome={outcome}"
  if outcome != "REJECT" then
    IO.eprintln s!"M8: {className} mutant was not refused by the program itself (outcome={outcome}, error_kind={KeriBlaster.S2.Cek.errorKind trace}, steps={trace.steps}); this is not evidence of enforcement"
    pure false
  else
    pure true

/-- The accepted honest neighbour.

The four mutants each differ from this transaction in exactly one field. If
this one did not settle, four rejections would establish nothing about the
fields they vary — they would only establish that the fixture was broken.
-/
def honestControl : IO Bool := do
  let trace := runCommitment honestReveal
  let outcome := classify trace
  IO.println s!"M8.entitlement-control case=honest-reveal outcome={outcome} steps={trace.steps}"
  if outcome != "ACCEPT" then
    IO.eprintln s!"M8: the honest matured reveal was not accepted (outcome={outcome}, error_kind={KeriBlaster.S2.Cek.errorKind trace}); the mutant rows below would have no accepted neighbour and would prove nothing"
    pure false
  else
    pure true

/-- An instrument positive control over one imported program.

The program applied to its parameters alone must settle as `HALT`. This is what
distinguishes "the machine refuses this transaction" from "this runner prints
ERROR whatever it is given".
-/
def parameterControl
    (name : String) (program : PlutusCore.UPLC.Term.Program)
    (parameters : List Data) : IO Bool := do
  let trace :=
    KeriBlaster.S2.Cek.runProgram program (parameters.map dataTerm) budget
  let outcome := KeriBlaster.S2.Cek.outcome trace
  IO.println s!"M8.entitlement-control case=applied-parameters role={name} outcome={outcome} steps={trace.steps}"
  if outcome != "HALT" then
    IO.eprintln s!"M8: the runner could not settle the {name} program on its parameters alone (outcome={outcome}); a REJECT from it would not be distinguishable from a runner that always errors"
    pure false
  else
    pure true

/-- The entitlement evidence entry point.

Reached from `KeriBlaster.main` when `ENTITLEMENT_EVIDENCE` is set, so these
rows and the S2 rows come from one binary built over one pinned module graph,
and neither can be produced by a copy of the checking path.
-/
def run : IO UInt32 := do
  let commitmentOk ←
    parameterControl "commitment" commitmentSpend.script commitmentParameters
  if !commitmentOk then
    return 1
  -- The explicit non-claim about the second target. It is emitted
  -- unconditionally beside the identity row precisely so that row cannot be
  -- read as a behavioural result, and it names the applied argument count this
  -- module knows the program takes.
  IO.println s!"M8.entitlement-not-established subject=checkpoint-target applied_arguments={checkpointParameters.length} required_basis=executed-under-pinned-cek reason=entitlement-leg-behind-refused-ed25519-builtin"
  let honestOk ← honestControl
  if !honestOk then
    return 1
  let entitlementOk ← reportMutant "entitlement" entitlementMutant
  let ageOk ← reportMutant "age" ageMutant
  let scopeOk ← reportMutant "scope" scopeMutant
  let payoutOk ← reportMutant "payout" payoutMutant
  if entitlementOk && ageOk && scopeOk && payoutOk then
    IO.println "PASS: the exact compiled entitlement family accepted the honest matured reveal and refused the named entitlement, age, scope and payout mutants"
    return 0
  else
    return 1

end KeriBlaster.Entitlement
