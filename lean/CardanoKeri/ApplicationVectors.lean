import CardanoKeri.Application
import CardanoKeri.CheckpointDatumVectors
import CardanoKeri.RequestLifecycleVectors
import Lean

/-! Vectors of KERI's application on the application-held model, for the
on-chain registration approval and checkpoint creation.

The approval rows fix a deployment (state policy `state(A_keri)`, registry
seed), an AID, the holding address, the initial checkpoint datum and the
deposit, and give the bytes the Lean derives: the registry name, the key, the
initial datum and its hash, the serialised approval preimage and the approval
name, and the configuration record's preimage and token name. The codec, hash
and key are the concrete ones of `ConsumerBytes`; the initial datum is the
version 2 checkpoint datum of `CheckpointDatum` written for the initial state
of the request (born at its booking bound, refunding to its refund address);
the datum hash is BLAKE2b-256 of its serialisation, as
`singular_state/preimage.initial_datum_hash`. The checkpoint datum decoder is
`CheckpointDatum.decode`; a request's refund address, a Plutus `Address`
with no stake credential, is recorded in the checkpoint datum as its ledger
bytes on the test network (header `0x60` for a key, `0x70` for a script,
then the 28-byte hash).

The transaction rows run the actual `Application.accepted` on fixture
transactions: configuration creation, bookings, folds and returns of one
request, the spends of a pending termination, and the spend of a delivered
checkpoint by its own lifecycle. The request and configuration datums' own
byte layouts are not fixed here: the fixture decoders map a fixture number to
the decoded registration or configuration. The holding address is the
checkpoint validator's, a Plutus `Address` with a script payment credential and
no stake credential, another script than the application's. Evidence over the
listed inputs, not a proof over all inputs. -/
namespace CardanoKeri.Application.Vectors
open Lean (Json toJson)
open Singular SingularApplicationHeld
open CardanoKeri.ConsumerIdentity.Bytes (pack unpack ofBytes constr bstr blake2b256 aidOfCesr)
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (toHex ofHex policyHex txHex aidE aidE2)

/-! ## The deployment -/

def scriptHash (seed : Nat) : List Nat := (List.range 28).map fun i => (seed * 37 + i * 5 + 3) % 256

/-- `Address { payment_credential: Script(hash), stake_credential: None }`. -/
def scriptAddress (hash : List Nat) : List Nat :=
  constr 0 [constr 1 [bstr hash], constr 1 []]

/-- `Address { payment_credential: VerificationKey(hash), stake_credential: None }`. -/
def keyAddress (hash : List Nat) : List Nat :=
  constr 0 [constr 0 [bstr hash], constr 1 []]

def applicationScript : List Nat := scriptHash 1
def statePolicyBytes : List Nat := (ofHex policyHex).toOption.getD []
def seedTx : List Nat := (ofHex txHex).toOption.getD []

def release : PublishedRelease :=
  { applicationPolicy := ofBytes applicationScript,
    applicationCredential := ofBytes (scriptAddress applicationScript),
    stateProgram := ofBytes statePolicyBytes, statePolicy := ofBytes statePolicyBytes }

/-- The checkpoint validator, where a fold delivers the registry's checkpoints:
another script than the application's. -/
def checkpointScript : List Nat := scriptHash 5
def checkpointCredential : Nat := ofBytes (scriptAddress checkpointScript)

def seed : OutRef := ⟨ofBytes seedTx, 0⟩
def deployment : Deployment := ⟨release, seed⟩

def refundAddress : Nat := ofBytes (keyAddress (scriptHash 2))
def otherAddress : Nat := ofBytes (keyAddress (scriptHash 3))
def spenderAddress : Nat := ofBytes (keyAddress (scriptHash 4))

/-- The registry's configuration parameters, the scenario registry's. -/
def parameters : ApplicationParameters :=
  { registrationCost := 2, minimumTip := 1, processTime := 5, retractTime := 0, bookingWidth := 1 }

def rp : CardanoKeri.Registry.Params := CardanoKeri.Registry.Scenarios.p
def env : Env := ⟨fun _ => true⟩

/-- The checkpoint parameters: the registry's deposit 10 is the checkpoint
deposit 6 plus the freeze bond 4; one premium is 1. -/
def cp : CardanoKeri.Checkpoint.Params :=
  { D := 6, B := 4, P := 1, W := 10, hD := by decide, hB := by decide }

/-! ## The initial datum -/

/-- The network the vectors run on: the test network. -/
def network : Nat := 0

/-- The ledger bytes a checkpoint datum records for a request's refund
address: a Plutus `Address` with a key or script payment credential and no
stake credential, as the enterprise address on the test network. Any other
address has none here. -/
def refundTo (address : Nat) : Option Nat :=
  match CheckpointDatum.ofBytes? (unpack address) with
  | some (.constr 0 [.constr kind [.bytes hash], .constr 1 []]) =>
    if kind ≤ 1 ∧ hash.length = 28 then some (pack (((6 + kind) * 16 + network) :: hash)) else none
  | _ => none

/-- The refund address the initial datum records for the request's refund address. -/
def refundLedger : Nat := (refundTo refundAddress).getD 0

/-- The initial state's datum facts for an AID, with the fields a case changes. -/
def initialFacts (sn epoch : Nat := 0) (poisoned frozen toppedUp : Bool := false)
    (bornAt : Nat := 10) (refund : Nat := refundLedger) : CardanoKeri.Checkpoint.State :=
  .present ⟨sn, epoch, poisoned, frozen, bornAt, refund, 0, toppedUp⟩

def checkpointData (aid : String) (s : CardanoKeri.Checkpoint.State) : CheckpointDatum.Data :=
  (CheckpointDatum.datum (aidOfCesr aid) CheckpointDatum.Vectors.simpleKeys s).getD (.int 0)

def initialData (aid : String) : CheckpointDatum.Data := checkpointData aid initialFacts

def initialRaw (aid : String) : Nat := CheckpointDatum.raw (initialData aid)

/-- Checkpoint datums of the request's AID in another state than the initial one. -/
def otherRaw (s : CardanoKeri.Checkpoint.State) : Nat := CheckpointDatum.raw (checkpointData aidE s)

def advancedRaw : Nat := otherRaw (initialFacts (sn := 7))
def epochRaw : Nat := otherRaw (initialFacts (epoch := 3))
def poisonedRaw : Nat := otherRaw (initialFacts (poisoned := true))
def frozenRaw : Nat := otherRaw (initialFacts (frozen := true))
def toppedUpRaw : Nat := otherRaw (initialFacts (toppedUp := true))
def bornLaterRaw : Nat := otherRaw (initialFacts (bornAt := 11))
def otherRefundRaw : Nat := otherRaw (initialFacts (refund := (refundTo otherAddress).getD 0))
def pendingRaw : Nat := otherRaw (.terminationPending ⟨0, 0⟩)

/-- The initial state of the request's AID with other key material than the committed datum. -/
def otherKeysRaw : Nat :=
  CheckpointDatum.raw ((CheckpointDatum.datum (aidOfCesr aidE) CheckpointDatum.Vectors.richKeys
    initialFacts).getD (.int 0))

/-- BLAKE2b-256 of an initial datum's serialisation. -/
def datumHash (raw : Nat) : Nat := pack (blake2b256 (unpack raw))

/-! ## Requests and the fixture decoder -/

def registry : TokenId := deployment.registry ⟨CardanoKeri.ConsumerIdentity.Bytes.hash,
  CardanoKeri.ConsumerIdentity.Bytes.code, CardanoKeri.ConsumerIdentity.Bytes.keyOf, fun _ => none, datumHash,
  fun _ => none, fun _ => none, fun _ => none⟩

/-- A registry whose state policy is not `state(A_keri)`. -/
def foreignRegistry : TokenId := ⟨ofBytes (scriptHash 9), registry.name⟩

def requestData (deposit : Nat) : RegistrationData :=
  { registry, key := aidOfCesr aidE, controller := 0, refundAddress,
    holdingAddress := checkpointCredential, initialDatum := datumHash (initialRaw aidE),
    deposit, bookedAt := 10, processDeadline := 15, reclaimEnd := 15 }

/-- A request committing the hash of another checkpoint datum. -/
def committing (raw : Nat) : RegistrationData := { requestData 15 with initialDatum := datumHash raw }

/-- Fixture request datums: the number a request output carries, decoded. -/
def requests : List (Nat × RegistrationData) := [
  (9001, requestData 15),
  (9002, { requestData 15 with registry := foreignRegistry }),
  (9003, requestData 13),
  (9004, { requestData 15 with holdingAddress := otherAddress }),
  (9005, { requestData 15 with processDeadline := 16, reclaimEnd := 16 }),
  (9006, { requestData 15 with holdingAddress := release.applicationCredential }),
  (9007, requestData 14),
  (9008, { requestData 15 with refundAddress := 7 }),
  (9011, committing advancedRaw),
  (9012, committing epochRaw),
  (9013, committing poisonedRaw),
  (9014, committing frozenRaw),
  (9015, committing toppedUpRaw),
  (9016, committing bornLaterRaw),
  (9017, committing otherRefundRaw),
  (9018, committing pendingRaw),
  (9019, committing (initialRaw aidE2))]

def decode : DecodeApplication := fun raw =>
  (requests.find? (·.1 == raw)).map fun entry => .registration entry.2

/-- The registry's configuration: the scenario parameters and the checkpoint
validator's credential. -/
def scenarioConfiguration : Configuration := ⟨parameters, checkpointCredential⟩

/-- Fixture configuration datums: the number a configuration record carries, decoded. -/
def configurations : List (Nat × Configuration) := [
  (8001, scenarioConfiguration),
  (8002, { scenarioConfiguration with parameters.retractTime := 1 }),
  (8003, { scenarioConfiguration with checkpointCredential := release.applicationCredential })]

def decodeConfiguration (raw : Nat) : Option Configuration :=
  (configurations.find? (·.1 == raw)).map (·.2)

def interpretation : Interpretation :=
  ⟨CardanoKeri.ConsumerIdentity.Bytes.hash, CardanoKeri.ConsumerIdentity.Bytes.code,
   CardanoKeri.ConsumerIdentity.Bytes.keyOf, decode, datumHash, decodeConfiguration,
   CheckpointDatum.decode release, refundTo⟩

def i : Interpretation := interpretation

def dataOf (raw : Nat) : RegistrationData := ((requests.find? (·.1 == raw)).map (·.2)).getD (requestData 0)

def approvalOf (raw : Nat) : TokenId := registrationAsset i.hash i.code release (dataOf raw)

def active : TokenId := activeAsset i.hash i.code registry (aidOfCesr aidE)

def configuration (r : TokenId) (raw : Nat := 8001) : ObservedOutput :=
  ⟨⟨50, 0⟩, release.applicationCredential, 2, .application raw, [(configurationAsset i release r, 1)]⟩

def request (raw lovelace : Nat) : ObservedOutput :=
  ⟨⟨60, 0⟩, release.applicationCredential, lovelace, .application raw, [(approvalOf raw, 1)]⟩

def holding (lovelace datum : Nat) (address : Nat := checkpointCredential) : ObservedOutput :=
  ⟨⟨70, 0⟩, address, lovelace, .application datum, [(active, 1)]⟩

def pay (address lovelace : Nat) : ObservedOutput := ⟨⟨70, 1⟩, address, lovelace, .empty, []⟩

def view (spent : List OutRef) (mint : List (TokenId × Int)) (invoked : List Nat) :
    SingularApplicationHeld.Assets.TxView :=
  ⟨spent, [], mint, invoked⟩

/-! ## Cases -/

structure Case where
  id : String
  note : String
  kind : String
  observation : Observation

def booking (raw lovelace : Nat) (mint : Int := 1) (references : Bool := true)
    (interval : Interval := ⟨9, 10⟩) (record : Nat := 8001) : Observation :=
  { assets := view [] [(approvalOf raw, mint)] [release.applicationPolicy],
    inputs := [], outputs := [request raw lovelace],
    referenceInputs := if references then [⟨50, 0⟩] else [],
    referenceOutputs := [configuration registry record, configuration foreignRegistry],
    interval, donation := 0, actions := [.bookRegistration 0] }

def fold (holdingLovelace : Nat) (interval : Interval := ⟨12, 15⟩) (donation : Nat := 2)
    (datum : Nat := initialRaw aidE) (burn : Int := -1) (raw : Nat := 9001)
    (address : Nat := checkpointCredential) : Observation :=
  { assets := view [⟨60, 0⟩] [(approvalOf raw, burn), (active, 1)] [release.statePolicy],
    inputs := [request raw (requestLovelace parameters (dataOf raw))],
    outputs := [holding holdingLovelace datum address],
    referenceInputs := [⟨50, 0⟩], referenceOutputs := [configuration registry],
    interval, donation, actions := [.foldRegistration ⟨60, 0⟩ 0] }

/-- A transaction of the checkpoint's own lifecycle (an advance, say) spending
the delivered checkpoint at `address`, with no application action. The
application's verdict only: the checkpoint validator's rules are the
checkpoint model's. -/
def checkpointSpend (address : Nat) : Observation :=
  { assets := view [⟨70, 0⟩] [] [], inputs := [holding 15 (initialRaw aidE) address],
    outputs := [holding 15 (initialRaw aidE) address], referenceInputs := [], referenceOutputs := [],
    interval := ⟨16, 17⟩, donation := 0, actions := [] }

def return_ (refund : Nat) (interval : Interval := ⟨15, 20⟩) (address : Nat := refundAddress) :
    Observation :=
  { assets := view [⟨60, 0⟩] [(approvalOf 9001, -1)] [],
    inputs := [request 9001 18], outputs := [pay address refund, pay spenderAddress (18 - refund)],
    referenceInputs := [⟨50, 0⟩], referenceOutputs := [configuration registry],
    interval, donation := 0, actions := [.returnRegistration ⟨60, 0⟩] }

def terminationApprovalAsset : TokenId :=
  terminationApproval i.hash i.code release registry (aidOfCesr aidE)

/-- The termination request a booking places: the application address, an
empty datum, exactly the active token and the termination approval, holding
`Mr` 2 plus the minimum tip 1. -/
def pending (lovelace : Nat := 3) (datum : OutputDatum := .empty) : ObservedOutput :=
  ⟨⟨80, 0⟩, release.applicationCredential, lovelace, datum, [(active, 1), (terminationApprovalAsset, 1)]⟩

/-- A terminating fold reading the configuration record and donating the
request less the tip. -/
def terminationFold (donation : Nat := 2) (references : Bool := true) : Observation :=
  { assets := view [⟨80, 0⟩] [(terminationApprovalAsset, -1), (active, -1)] [release.statePolicy],
    inputs := [pending], outputs := [], referenceInputs := if references then [⟨50, 0⟩] else [],
    referenceOutputs := [configuration registry],
    interval := ⟨12, 15⟩, donation,
    actions := [.foldTermination ⟨80, 0⟩ registry (aidOfCesr aidE)] }

def terminationReturn : Observation :=
  { assets := view [⟨80, 0⟩] [(terminationApprovalAsset, -1)] [],
    inputs := [pending], outputs := [], referenceInputs := [⟨50, 0⟩],
    referenceOutputs := [configuration registry],
    interval := ⟨12, 15⟩, donation := 0, actions := [.returnRegistration ⟨80, 0⟩] }

/-- The pending-termination datum of an AID at sequence number and epoch 0. -/
def pendingDatumOf (aid : String) : Nat :=
  CheckpointDatum.raw (checkpointData aid (.terminationPending ⟨0, 0⟩))

/-- The output a conviction leaves: at the checkpoint validator, the
pending-termination datum of the AID, exactly the minimum ADA 4 and the active
token. -/
def convicted (datum : Nat := pendingDatumOf aidE) (lovelace : Nat := 4)
    (address : Nat := checkpointCredential) (assets : List (TokenId × Nat) := [(active, 1)]) :
    ObservedOutput :=
  ⟨⟨90, 0⟩, address, lovelace, .application datum, assets⟩

/-- A termination booking: spends the convicted output, places the request,
mints one termination approval, reads the configuration record. -/
def terminationBooking (input : ObservedOutput := convicted) (request : ObservedOutput := pending)
    (mint : Int := 1) (references : Bool := true) (key : Nat := aidOfCesr aidE)
    (r : TokenId := registry) : Observation :=
  { assets := view [input.reference] [(terminationApprovalAsset, mint)] [release.applicationPolicy],
    inputs := [input], outputs := [request, pay spenderAddress 1],
    referenceInputs := if references then [⟨50, 0⟩] else [],
    referenceOutputs := [configuration registry, configuration foreignRegistry],
    interval := ⟨12, 15⟩, donation := 0, actions := [.bookTermination input.reference 0 r key] }

/-- A booking under a registry whose state policy is not `state(A_keri)`,
consistent in every other respect: the pending output holds that registry's
active token and the request its termination approval. -/
def foreignTerminationBooking : Observation :=
  let foreignActive := activeAsset i.hash i.code foreignRegistry (aidOfCesr aidE)
  let foreignApproval := terminationApproval i.hash i.code release foreignRegistry (aidOfCesr aidE)
  let request : ObservedOutput := { pending 3 with assets := [(foreignActive, 1), (foreignApproval, 1)] }
  let o := terminationBooking (input := convicted (assets := [(foreignActive, 1)])) (request := request)
    (r := foreignRegistry)
  { o with assets := view [⟨90, 0⟩] [(foreignApproval, 1)] [release.applicationPolicy] }

/-- Two bookings of the same key, two requests, two approvals minted. -/
def terminationBookedTwice : Observation :=
  { terminationBooking (mint := 2) with
    outputs := [pending, pending],
    actions := [.bookTermination ⟨90, 0⟩ 0 registry (aidOfCesr aidE),
      .bookTermination ⟨90, 0⟩ 1 registry (aidOfCesr aidE)] }

/-- The termination approval of a key other than the request's. -/
def otherTerminationApproval : TokenId :=
  terminationApproval i.hash i.code release registry (aidOfCesr aidE2)

/-- A termination approval minted onto a pending termination with no action. -/
def terminationApprovalMinted : Observation :=
  { assets := view [] [(terminationApprovalAsset, 1)] [], inputs := [], outputs := [pending],
    referenceInputs := [], referenceOutputs := [], interval := ⟨12, 15⟩, donation := 0, actions := [] }

def terminationActiveKept : Observation :=
  { terminationFold with assets := (view [⟨80, 0⟩] [(terminationApprovalAsset, -1)] [release.statePolicy]) }

/-- A fold that also spends a second booked request no action names. -/
def foldWithUnnamed : Observation :=
  { assets := view [⟨60, 0⟩, ⟨61, 0⟩] [(approvalOf 9001, -1), (active, 1)] [release.statePolicy],
    inputs := [request 9001 18, ⟨⟨61, 0⟩, release.applicationCredential, 18, .application 9001,
      [(approvalOf 9001, 1)]⟩],
    outputs := [holding 15 (initialRaw aidE)],
    referenceInputs := [⟨50, 0⟩], referenceOutputs := [configuration registry],
    interval := ⟨12, 15⟩, donation := 2, actions := [.foldRegistration ⟨60, 0⟩ 0] }

/-- An approval minted onto a request output with no booking. -/
def approvalWithoutBooking : Observation :=
  { (booking 9001 18) with actions := [] }

/-- The same output booked twice, one approval minted. -/
def bookingTwice : Observation :=
  { (booking 9001 18) with actions := [.bookRegistration 0, .bookRegistration 0] }

/-- Two request outputs of one payload, both booked, two approvals minted. -/
def bookingOnePayloadTwice : Observation :=
  { (booking 9001 18 (mint := 2)) with
    outputs := [request 9001 18, request 9001 18],
    actions := [.bookRegistration 0, .bookRegistration 1] }

/-- Two requests of one payload folded into one holding, both approvals burned. -/
def foldOnePayloadTwice : Observation :=
  { (fold 15) with
    assets := view [⟨60, 0⟩, ⟨61, 0⟩] [(approvalOf 9001, -2), (active, 1)] [release.statePolicy],
    inputs := [request 9001 18, ⟨⟨61, 0⟩, release.applicationCredential, 18, .application 9001,
      [(approvalOf 9001, 1)]⟩],
    donation := 4, actions := [.foldRegistration ⟨60, 0⟩ 0, .foldRegistration ⟨61, 0⟩ 0] }

def genesis (raw : Nat) (r : TokenId) : Observation :=
  { assets := view [seed] [(r, 1), (configurationAsset i release r, 1)]
      [release.statePolicy, release.applicationPolicy],
    inputs := [], outputs := [configuration r raw], referenceInputs := [], referenceOutputs := [],
    interval := ⟨0, 1⟩, donation := 0, actions := [.createConfiguration r seed 0] }

def cases : List Case := [
  ⟨"configuration-created", "the registry's genesis creates its configuration record with retractTime = 0",
    "configuration", genesis 8001 registry⟩,
  ⟨"configuration-with-retraction", "a configuration record with retractTime = 1: refused",
    "configuration", genesis 8002 registry⟩,
  ⟨"configuration-foreign-registry", "a configuration record for a registry whose state policy is not state(A_keri): refused",
    "configuration", genesis 8001 foreignRegistry⟩,
  ⟨"booking", "a request holding exactly deposit 15, registration cost 2 and tip 1, reading the configuration record: accepted",
    "booking", booking 9001 18⟩,
  ⟨"booking-foreign-registry", "the same request naming a registry whose state policy is not state(A_keri): refused",
    "booking", booking 9002 18⟩,
  ⟨"booking-short-deposit", "a deposit of 13, one below the minimum ADA 4 plus the deposit 10: refused",
    "booking", booking 9003 16⟩,
  ⟨"booking-one-lovelace-more", "the request holds 19, one more than its exact contents: refused",
    "booking", booking 9001 19⟩,
  ⟨"booking-one-lovelace-less", "the request holds 17, one less than its exact contents: refused",
    "booking", booking 9001 17⟩,
  ⟨"booking-other-holding-address", "the approval commits a holding address other than the checkpoint validator's: refused",
    "booking", booking 9004 18⟩,
  ⟨"booking-application-holding", "the approval commits the application address as the holding address: refused",
    "booking", booking 9006 18⟩,
  ⟨"booking-checkpoint-is-application", "the configuration record names the application address as the checkpoint validator and the approval commits it: refused",
    "booking", booking 9006 18 (record := 8003)⟩,
  ⟨"booking-wrong-deadline", "the request records a deadline one after the booking bound plus the processing time: refused",
    "booking", booking 9005 18⟩,
  ⟨"booking-without-configuration", "the configuration record is not a reference input: refused",
    "booking", booking 9001 18 (references := false)⟩,
  ⟨"booking-two-approvals", "two approvals of the payload minted for one booking: refused",
    "booking", booking 9001 18 (mint := 2)⟩,
  ⟨"booking-one-payload-twice", "two request outputs of one payload, both booked, two approvals minted: refused",
    "booking", bookingOnePayloadTwice⟩,
  ⟨"booking-twice", "the same output booked twice, one approval minted: refused",
    "booking", bookingTwice⟩,
  ⟨"approval-without-booking", "an approval minted onto a request output with no booking: refused",
    "booking", approvalWithoutBooking⟩,
  ⟨"fold-at-deadline", "a fold ending at the deadline, delivering exactly the deposit 15 in the initial state, a pool of one premium, donating the registration cost: accepted",
    "fold", fold 15⟩,
  ⟨"fold-donating-more", "the same fold donating 3: accepted",
    "fold", fold 15 (donation := 3)⟩,
  ⟨"fold-after-deadline", "a fold whose validity interval ends one slot after the deadline: refused",
    "fold", fold 15 (interval := ⟨12, 16⟩)⟩,
  ⟨"fold-holding-one-more", "the holding holds the deposit plus one lovelace: refused",
    "fold", fold 16⟩,
  ⟨"fold-holding-one-less", "the holding holds the deposit less one lovelace: refused",
    "fold", fold 14⟩,
  ⟨"fold-donation-short", "the treasury donation is one less than the registration cost: refused",
    "fold", fold 15 (donation := 1)⟩,
  ⟨"fold-other-datum", "the holding carries the initial state of the AID with other key material than the committed datum: refused",
    "fold", fold 15 (datum := otherKeysRaw)⟩,
  ⟨"fold-approval-kept", "the approval is not burned: refused",
    "fold", fold 15 (burn := 0)⟩,
  ⟨"fold-one-payload-twice", "two requests of one payload folded into one holding, both approvals burned: refused",
    "fold", foldOnePayloadTwice⟩,
  ⟨"fold-at-application-address", "the holding is delivered to the application address instead of the checkpoint validator: refused",
    "fold", fold 15 (address := release.applicationCredential)⟩,
  ⟨"fold-at-committed-other-address", "a request committing another address than the checkpoint validator's, folded to that address: refused",
    "fold", fold 15 (raw := 9004) (address := otherAddress)⟩,
  ⟨"fold-other-commitment-to-checkpoint", "a request committing another address than the checkpoint validator's, folded to the checkpoint validator: refused",
    "fold", fold 15 (raw := 9004)⟩,
  ⟨"fold-advanced-sequence", "the request committed, and the holding carries, a checkpoint datum at sequence number 7: refused",
    "fold", fold 15 (raw := 9011) (datum := advancedRaw)⟩,
  ⟨"fold-advanced-epoch", "the committed datum is at epoch 3: refused",
    "fold", fold 15 (raw := 9012) (datum := epochRaw)⟩,
  ⟨"fold-poisoned", "the committed datum is poisoned: refused",
    "fold", fold 15 (raw := 9013) (datum := poisonedRaw)⟩,
  ⟨"fold-frozen", "the committed datum is frozen: refused",
    "fold", fold 15 (raw := 9014) (datum := frozenRaw)⟩,
  ⟨"fold-topped-up", "the committed datum is topped up: refused",
    "fold", fold 15 (raw := 9015) (datum := toppedUpRaw)⟩,
  ⟨"fold-born-later", "the committed datum is born one slot after the booking bound: refused",
    "fold", fold 15 (raw := 9016) (datum := bornLaterRaw)⟩,
  ⟨"fold-other-refund", "the committed datum refunds to another address than the request names: refused",
    "fold", fold 15 (raw := 9017) (datum := otherRefundRaw)⟩,
  ⟨"fold-pending-termination", "the committed datum is a pending termination: refused",
    "fold", fold 15 (raw := 9018) (datum := pendingRaw)⟩,
  ⟨"fold-other-aid", "the committed datum is the initial datum of another AID: refused",
    "fold", fold 15 (raw := 9019) (datum := initialRaw aidE2)⟩,
  ⟨"fold-pool-below-premium", "a request of deposit 14, the minimum ADA 4, the deposit 6 and the freeze bond 4, leaving a pool below one premium: refused",
    "fold", fold 14 (raw := 9007)⟩,
  ⟨"fold-unrecorded-refund", "a request whose refund address is not an address a checkpoint datum can record: refused",
    "fold", fold 15 (raw := 9008)⟩,
  ⟨"checkpoint-spent-at-checkpoint-validator", "the delivered checkpoint spent by its own lifecycle at the checkpoint validator, no application action: the application does not refuse it",
    "checkpoint", checkpointSpend checkpointCredential⟩,
  ⟨"checkpoint-spent-at-application-address", "the same spend of a checkpoint sitting at the application address: no action names it, refused",
    "checkpoint", checkpointSpend release.applicationCredential⟩,
  ⟨"return-at-deadline", "a return starting at the deadline paying the refund address 17, the request less the tip: accepted",
    "return", return_ 17⟩,
  ⟨"return-straddling-deadline", "a return whose validity interval starts one slot before the deadline: refused",
    "return", return_ 17 (interval := ⟨14, 20⟩)⟩,
  ⟨"return-refund-reduced", "the refund address is paid one lovelace less than the request less the tip: refused",
    "return", return_ 16⟩,
  ⟨"return-refund-redirected", "the refund is paid to another address: refused",
    "return", return_ 17 (address := otherAddress)⟩,
  ⟨"termination-booking", "anyone books the termination of a convicted checkpoint: the pending output (4 lovelace, the active token, a pending-termination datum) is spent, one termination approval is minted, the request holds 3 (Mr 2 plus the tip 1) at the application address, the booker keeps 1: accepted",
    "termination-booking", terminationBooking⟩,
  ⟨"termination-booking-live-checkpoint", "the spent output carries the live datum of the AID: no conviction, refused",
    "termination-booking", terminationBooking (input := convicted (datum := initialRaw aidE))⟩,
  ⟨"termination-booking-other-aid", "the pending datum is of another AID than the key booked: refused",
    "termination-booking", terminationBooking (input := convicted (datum := pendingDatumOf aidE2))⟩,
  ⟨"termination-booking-other-key", "the booking names another key than the pending output's, with the approval of that key: refused",
    "termination-booking", { terminationBooking (key := aidOfCesr aidE2) with
      assets := view [⟨90, 0⟩] [(otherTerminationApproval, 1)] [release.applicationPolicy] }⟩,
  ⟨"termination-booking-at-other-address", "the pending output sits at another address than the checkpoint validator's: refused",
    "termination-booking", terminationBooking (input := convicted (address := otherAddress))⟩,
  ⟨"termination-booking-pending-one-more", "the pending output holds the minimum ADA plus one: refused",
    "termination-booking", terminationBooking (input := convicted (lovelace := 5))⟩,
  ⟨"termination-booking-without-active-token", "the pending output does not hold the active token: refused",
    "termination-booking", terminationBooking (input := convicted (assets := []))⟩,
  ⟨"termination-booking-request-one-more", "the request holds 4, one more than Mr plus the tip: refused",
    "termination-booking", terminationBooking (request := pending 4)⟩,
  ⟨"termination-booking-request-one-less", "the request holds 2, one less than Mr plus the tip: refused",
    "termination-booking", terminationBooking (request := pending 2)⟩,
  ⟨"termination-booking-request-datum", "the request carries a datum: refused",
    "termination-booking", terminationBooking (request := pending (datum := .application 1))⟩,
  ⟨"termination-booking-without-configuration", "the configuration record is not a reference input: refused",
    "termination-booking", terminationBooking (references := false)⟩,
  ⟨"termination-booking-foreign-registry", "the booking names a registry whose state policy is not state(A_keri): refused",
    "termination-booking", foreignTerminationBooking⟩,
  ⟨"termination-booking-two-approvals", "two termination approvals minted for one booking: refused",
    "termination-booking", terminationBooking (mint := 2)⟩,
  ⟨"termination-booked-twice", "the same key booked twice into two requests, two approvals minted: refused",
    "termination-booking", terminationBookedTwice⟩,
  ⟨"termination-fold", "a termination request spent by its terminating fold, reading the configuration record, burning its approval and active token, donating 2 (the request less the tip): accepted",
    "termination", terminationFold⟩,
  ⟨"termination-fold-donation-short", "the terminating fold donates 1, one less than the request less the tip: refused",
    "termination", terminationFold (donation := 1)⟩,
  ⟨"termination-fold-without-configuration", "the configuration record is not a reference input of the terminating fold: refused",
    "termination", terminationFold (references := false)⟩,
  ⟨"termination-approval-minted", "a termination approval minted onto a pending termination with no action: refused",
    "termination", terminationApprovalMinted⟩,
  ⟨"termination-fold-active-kept", "a terminating fold that does not burn the active token: refused",
    "termination", terminationActiveKept⟩,
  ⟨"fold-with-unnamed-request", "a fold that also spends a second booked request no action names: refused",
    "fold", foldWithUnnamed⟩,
  ⟨"termination-return", "a return naming a pending termination: refused",
    "termination", terminationReturn⟩]

/-! ## Rows -/

def hexOf (n : Nat) : String := toHex (unpack n)

def verdict (o : Observation) : String :=
  if accepted i env rp cp release o then "accepted" else "refused"

def intervalJson (x : Interval) : Json :=
  Json.mkObj [("lower", toJson x.lower), ("upper", toJson x.upper)]

def outputJson (x : ObservedOutput) : Json :=
  Json.mkObj [("address", toJson (hexOf x.credential)), ("lovelace", toJson x.lovelace)]

def row (c : Case) : Json :=
  let o := c.observation
  Json.mkObj [("id", toJson c.id), ("note", toJson c.note), ("kind", toJson c.kind),
    ("validity", intervalJson o.interval), ("donation", toJson o.donation),
    ("inputs", Json.arr (o.inputs.map outputJson).toArray),
    ("outputs", Json.arr (o.outputs.map outputJson).toArray),
    ("referenced", toJson (o.referenceInputs.length)),
    ("verdict", toJson (verdict o))]

/-- The approval of an AID, with every byte it is derived from. -/
def approvalRow (id note aid : String) (deposit : Nat) : Json :=
  let raw := initialRaw aid
  let key := aidOfCesr aid
  let preimage := i.code (.registrationApproval registry key checkpointCredential (datumHash raw) deposit)
  Json.mkObj [("id", toJson id), ("note", toJson note),
    ("input", Json.mkObj [("statePolicy", toJson policyHex),
      ("seed", Json.mkObj [("transactionId", toJson txHex), ("outputIndex", toJson seed.index)]),
      ("aid", toJson aid), ("holdingAddress", toJson (hexOf checkpointCredential)),
      ("initialDatum", toJson (hexOf raw)), ("deposit", toJson deposit)]),
    ("registryName", toJson (hexOf registry.name)), ("key", toJson (hexOf key)),
    ("initialDatumHash", toJson (hexOf (datumHash raw))),
    ("approvalPreimage", toJson (toHex preimage)),
    ("approval", Json.mkObj [("policy", toJson (toHex applicationScript)),
      ("name", toJson (hexOf (approval i deployment key checkpointCredential (datumHash raw) deposit).name))])]

def approvals : List Json := [
  approvalRow "approval" "the registration approval of a funded registration of 15 lovelace" aidE 15,
  approvalRow "approval-other-deposit" "the same registration committing 16: another approval" aidE 16,
  approvalRow "approval-other-aid" "another AID in the same registry: another key, datum and approval" aidE2 15]

/-! ## The checkpoint validator's release of a pending output -/

structure ReleaseCase where
  id : String
  note : String
  input : ObservedOutput
  observation : Observation

def releaseCases : List ReleaseCase := [
  ⟨"release-into-booking", "the transaction mints one termination approval of the registry and of the key of the pending datum's AID: released",
    convicted, terminationBooking⟩,
  ⟨"release-without-approval", "no termination approval minted: kept",
    convicted, { terminationBooking with assets := view [⟨90, 0⟩] [] [] }⟩,
  ⟨"release-two-approvals", "two termination approvals of the key minted: kept",
    convicted, terminationBooking (mint := 2)⟩,
  ⟨"release-other-key-approval", "the termination approval of another key minted: kept",
    convicted, { terminationBooking with
      assets := view [⟨90, 0⟩] [(otherTerminationApproval, 1)] [release.applicationPolicy] }⟩,
  ⟨"release-live-checkpoint", "a live checkpoint, with the termination approval of its key minted: kept",
    convicted (datum := initialRaw aidE), terminationBooking⟩]

def mintJson (o : Observation) : Json :=
  Json.arr (o.assets.mint.map fun (t, q) => Json.mkObj [("policy", toJson (hexOf t.policy)),
    ("name", toJson (hexOf t.name)), ("quantity", toJson q)]).toArray

def releaseRow (c : ReleaseCase) : Json :=
  let datum := match c.input.datum with | .application raw => hexOf raw | _ => ""
  Json.mkObj [("id", toJson c.id), ("note", toJson c.note), ("datum", toJson datum),
    ("mint", mintJson c.observation),
    ("verdict", toJson (if pendingReleased i release registry c.input c.observation then "released" else "kept"))]

/-- The termination approval of an AID, with every byte it is derived from. -/
def terminationApprovalRow (id note aid : String) : Json :=
  let key := aidOfCesr aid
  Json.mkObj [("id", toJson id), ("note", toJson note), ("aid", toJson aid),
    ("registryName", toJson (hexOf registry.name)), ("key", toJson (hexOf key)),
    ("preimage", toJson (toHex (i.code (.terminationApproval registry key)))),
    ("approval", Json.mkObj [("policy", toJson (toHex applicationScript)),
      ("name", toJson (hexOf (terminationApproval i.hash i.code release registry key).name))])]

def terminationApprovals : List Json := [
  terminationApprovalRow "termination-approval" "the termination approval of the AID in the registry" aidE,
  terminationApprovalRow "termination-approval-other-aid" "another AID in the same registry: another approval" aidE2]

def configurationRow : Json :=
  Json.mkObj [("registryName", toJson (hexOf registry.name)),
    ("preimage", toJson (toHex (i.code (.applicationConfiguration registry)))),
    ("checkpointCredential", toJson (hexOf scenarioConfiguration.checkpointCredential)),
    ("token", Json.mkObj [("policy", toJson (toHex applicationScript)),
      ("name", toJson (hexOf (configurationAsset i release registry).name))]),
    ("parameters", Json.mkObj [("registrationCost", toJson parameters.registrationCost),
      ("minimumTip", toJson parameters.minimumTip), ("processTime", toJson parameters.processTime),
      ("retractTime", toJson parameters.retractTime), ("bookingWidth", toJson parameters.bookingWidth)])]

def table : Json :=
  Json.mkObj [
    ("description", toJson ("KERI's application on the application-held Singular model: the registration " ++
      "approval bytes, the configuration record, and accepted and refused configuration creations, bookings, " ++
      "folds, returns and termination spends, and the spend of a delivered checkpoint; a fold delivers exactly " ++
      "the initial checkpoint state.")),
    ("model", toJson "lean/CardanoKeri/Application.lean"),
    ("deposit", toJson "the approval commits the whole carrier; the holding holds exactly it"),
    ("checkpoint", Json.mkObj [("D", toJson cp.D), ("B", toJson cp.B), ("P", toJson cp.P),
      ("Mc", toJson rp.Mc)]),
    ("initialState", toJson ("the holding's datum is the version 2 Live datum of the request's AID at sn 0, epoch 0, " ++
      "not poisoned, frozen or topped up, born_at = bookedAt, refund_to = the ledger bytes of the request's refund " ++
      "address; the pool is the deposit less Mc + D + B and is at least P")),
    ("holding", toJson "the approval commits the checkpoint validator's credential, which the configuration record names and which is not the application's; the fold delivers there"),
    ("request", toJson "deposit + registrationCost + minimumTip"),
    ("treasury", toJson "a fold's treasury_donation is at least the registration costs it folds and, for each termination request it folds, the request's lovelace less the minimum tip"),
    ("termination", toJson ("a conviction leaves at the checkpoint validator a pending-termination datum, exactly Mc and the active token; " ++
      "anyone books it: one termination approval of the registry and the key of the datum's AID is minted, and the request is placed " ++
      "at the application address with an empty datum, exactly the active token and the approval, holding Mr plus the minimum tip; " ++
      "the booker keeps Mc less the request; the checkpoint validator releases a pending output only when exactly one termination " ++
      "approval of its key is minted; the request has no deadline and only the terminating fold spends it")),
    ("Mr", toJson rp.Mr),
    ("mint", toJson ("the mint under the application policy is exactly what the actions justify: configuration +1 per " ++
      "created record, approval +1 per booked output, termination approval +1 per termination booking, approval -1 per " ++
      "fold or return, termination approval -1 per terminating fold; each booked output is booked once and each key's " ++
      "termination once")),
    ("deadline", toJson "bookedAt (the booking's validity upper bound) plus processTime; retractTime = 0"),
    ("intervals", toJson "lower bound included, upper bound excluded, as the ledger hands them to scripts"),
    ("configuration", configurationRow),
    ("approvals", Json.arr approvals.toArray),
    ("terminationApprovals", Json.arr terminationApprovals.toArray),
    ("releases", Json.arr (releaseCases.map releaseRow).toArray),
    ("rows", Json.arr (cases.map row).toArray)]

/-! ## Checking a committed table -/

def arrayOf (j : Json) (key : String) : Except String (Array Json) := do
  match j.getObjVal? key with
  | .ok (.arr rows) => pure rows
  | _ => throw s!"missing {key}"

/-- A committed transaction row equals the Lean's row of the same id. -/
def verifyRow (r : Json) : Except String Unit := do
  let id ← r.getObjValAs? String "id"
  let some c := cases.find? (·.id == id) | throw s!"{id}: no such case"
  unless r == row c do throw s!"{id}: differs from the Lean's row"

/-- A committed approval row equals the Lean's row of the same id. -/
def verifyApproval (r : Json) : Except String Unit := do
  let id ← r.getObjValAs? String "id"
  let some a := approvals.find? (fun a => (a.getObjValAs? String "id").toOption == some id)
    | throw s!"{id}: no such approval"
  unless r == a do throw s!"{id}: differs from the Lean's approval"

/-- A committed release row equals the Lean's row of the same id. -/
def verifyRelease (r : Json) : Except String Unit := do
  let id ← r.getObjValAs? String "id"
  let some c := releaseCases.find? (·.id == id) | throw s!"{id}: no such release"
  unless r == releaseRow c do throw s!"{id}: differs from the Lean's release"

def verifyConfiguration (r : Json) : Except String Unit := do
  unless r == configurationRow do throw "configuration differs from the Lean's"

def checkTable (j : Json) : Except String (Nat × Nat × Nat) := do
  unless j == table do throw "committed table differs from the Lean's table"
  let committed ← arrayOf j "rows"
  let committedApprovals ← arrayOf j "approvals"
  let some configuration := (j.getObjVal? "configuration").toOption | throw "missing configuration"
  unless committed.size == cases.length do throw "row count differs from the Lean cases"
  let mut fields := 0
  for r in committed do
    verifyRow r
    for changed in CardanoKeri.Registry.LifecycleVectors.perturbations r do
      if (verifyRow changed).toOption.isSome then throw s!"a changed field survived: {changed.compress}"
      fields := fields + 1
  for r in committedApprovals do
    verifyApproval r
    for changed in CardanoKeri.Registry.LifecycleVectors.perturbations r do
      if (verifyApproval changed).toOption.isSome then throw s!"a changed field survived: {changed.compress}"
      fields := fields + 1
  verifyConfiguration configuration
  for r in ← arrayOf j "releases" do
    verifyRelease r
    for changed in CardanoKeri.Registry.LifecycleVectors.perturbations r do
      if (verifyRelease changed).toOption.isSome then throw s!"a changed field survived: {changed.compress}"
      fields := fields + 1
  for changed in CardanoKeri.Registry.LifecycleVectors.perturbations configuration do
    if (verifyConfiguration changed).toOption.isSome then throw s!"a changed field survived: {changed.compress}"
    fields := fields + 1
  let accepted := committed.filter (fun r => (r.getObjValAs? String "verdict").toOption == some "accepted")
  if accepted.size == 0 || accepted.size == committed.size then throw "rows need both verdicts"
  pure (committed.size, accepted.size, fields)

end CardanoKeri.Application.Vectors
