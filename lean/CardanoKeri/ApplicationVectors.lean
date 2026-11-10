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
version 2 checkpoint datum of `CheckpointDatum`; the datum hash is BLAKE2b-256
of its serialisation, as `singular_state/preimage.initial_datum_hash`.

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

/-! ## The initial datum -/

def initialData (aid : String) : CheckpointDatum.Data :=
  (CheckpointDatum.datum (aidOfCesr aid) CheckpointDatum.Vectors.simpleKeys
    (CheckpointDatum.Vectors.registered 0)).getD (.int 0)

def initialRaw (aid : String) : Nat := CheckpointDatum.raw (initialData aid)

/-- BLAKE2b-256 of an initial datum's serialisation. -/
def datumHash (raw : Nat) : Nat := pack (blake2b256 (unpack raw))

/-! ## Requests and the fixture decoder -/

def registry : TokenId := deployment.registry ⟨CardanoKeri.ConsumerIdentity.Bytes.hash,
  CardanoKeri.ConsumerIdentity.Bytes.code, CardanoKeri.ConsumerIdentity.Bytes.keyOf, fun _ => none, datumHash,
  fun _ => none⟩

/-- A registry whose state policy is not `state(A_keri)`. -/
def foreignRegistry : TokenId := ⟨ofBytes (scriptHash 9), registry.name⟩

def requestData (deposit : Nat) : RegistrationData :=
  { registry, key := aidOfCesr aidE, controller := 0, refundAddress,
    holdingAddress := checkpointCredential, initialDatum := datumHash (initialRaw aidE),
    deposit, bookedAt := 10, processDeadline := 15, reclaimEnd := 15 }

/-- Fixture request datums: the number a request output carries, decoded. -/
def requests : List (Nat × RegistrationData) := [
  (9001, requestData 14),
  (9002, { requestData 14 with registry := foreignRegistry }),
  (9003, requestData 13),
  (9004, { requestData 14 with holdingAddress := otherAddress }),
  (9005, { requestData 14 with processDeadline := 16, reclaimEnd := 16 }),
  (9006, { requestData 14 with holdingAddress := release.applicationCredential })]

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
   CardanoKeri.ConsumerIdentity.Bytes.keyOf, decode, datumHash, decodeConfiguration⟩

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
    inputs := [request raw 17], outputs := [holding holdingLovelace datum address],
    referenceInputs := [⟨50, 0⟩], referenceOutputs := [configuration registry],
    interval, donation, actions := [.foldRegistration ⟨60, 0⟩ 0] }

/-- A transaction of the checkpoint's own lifecycle (an advance, say) spending
the delivered checkpoint at `address`, with no application action. The
application's verdict only: the checkpoint validator's rules are the
checkpoint model's. -/
def checkpointSpend (address : Nat) : Observation :=
  { assets := view [⟨70, 0⟩] [] [], inputs := [holding 14 (initialRaw aidE) address],
    outputs := [holding 14 (initialRaw aidE) address], referenceInputs := [], referenceOutputs := [],
    interval := ⟨16, 17⟩, donation := 0, actions := [] }

def return_ (refund : Nat) (interval : Interval := ⟨15, 20⟩) (address : Nat := refundAddress) :
    Observation :=
  { assets := view [⟨60, 0⟩] [(approvalOf 9001, -1)] [],
    inputs := [request 9001 17], outputs := [pay address refund, pay spenderAddress (17 - refund)],
    referenceInputs := [⟨50, 0⟩], referenceOutputs := [configuration registry],
    interval, donation := 0, actions := [.returnRegistration ⟨60, 0⟩] }

def terminationApprovalAsset : TokenId :=
  terminationApproval i.hash i.code release registry (aidOfCesr aidE)

def pending : ObservedOutput :=
  ⟨⟨80, 0⟩, release.applicationCredential, 4, .empty, [(active, 1), (terminationApprovalAsset, 1)]⟩

def terminationFold : Observation :=
  { assets := view [⟨80, 0⟩] [(terminationApprovalAsset, -1), (active, -1)] [release.statePolicy],
    inputs := [pending], outputs := [], referenceInputs := [], referenceOutputs := [],
    interval := ⟨12, 15⟩, donation := 0,
    actions := [.foldTermination ⟨80, 0⟩ registry (aidOfCesr aidE)] }

def terminationReturn : Observation :=
  { assets := view [⟨80, 0⟩] [(terminationApprovalAsset, -1)] [],
    inputs := [pending], outputs := [], referenceInputs := [], referenceOutputs := [],
    interval := ⟨12, 15⟩, donation := 0, actions := [.returnRegistration ⟨80, 0⟩] }

def terminationActiveKept : Observation :=
  { terminationFold with assets := (view [⟨80, 0⟩] [(terminationApprovalAsset, -1)] [release.statePolicy]) }

/-- A fold that also spends a second booked request no action names. -/
def foldWithUnnamed : Observation :=
  { assets := view [⟨60, 0⟩, ⟨61, 0⟩] [(approvalOf 9001, -1), (active, 1)] [release.statePolicy],
    inputs := [request 9001 17, ⟨⟨61, 0⟩, release.applicationCredential, 17, .application 9001,
      [(approvalOf 9001, 1)]⟩],
    outputs := [holding 14 (initialRaw aidE)],
    referenceInputs := [⟨50, 0⟩], referenceOutputs := [configuration registry],
    interval := ⟨12, 15⟩, donation := 2, actions := [.foldRegistration ⟨60, 0⟩ 0] }

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
  ⟨"booking", "a request holding exactly deposit 14, registration cost 2 and tip 1, reading the configuration record: accepted",
    "booking", booking 9001 17⟩,
  ⟨"booking-foreign-registry", "the same request naming a registry whose state policy is not state(A_keri): refused",
    "booking", booking 9002 17⟩,
  ⟨"booking-short-deposit", "a deposit of 13, one below the minimum ADA 4 plus the deposit 10: refused",
    "booking", booking 9003 16⟩,
  ⟨"booking-one-lovelace-more", "the request holds 18, one more than its exact contents: refused",
    "booking", booking 9001 18⟩,
  ⟨"booking-one-lovelace-less", "the request holds 16, one less than its exact contents: refused",
    "booking", booking 9001 16⟩,
  ⟨"booking-other-holding-address", "the approval commits a holding address other than the checkpoint validator's: refused",
    "booking", booking 9004 17⟩,
  ⟨"booking-application-holding", "the approval commits the application address as the holding address: refused",
    "booking", booking 9006 17⟩,
  ⟨"booking-checkpoint-is-application", "the configuration record names the application address as the checkpoint validator and the approval commits it: refused",
    "booking", booking 9006 17 (record := 8003)⟩,
  ⟨"booking-wrong-deadline", "the request records a deadline one after the booking bound plus the processing time: refused",
    "booking", booking 9005 17⟩,
  ⟨"booking-without-configuration", "the configuration record is not a reference input: refused",
    "booking", booking 9001 17 (references := false)⟩,
  ⟨"booking-two-approvals", "two approvals of the payload minted: refused",
    "booking", booking 9001 17 (mint := 2)⟩,
  ⟨"fold-at-deadline", "a fold ending at the deadline, delivering exactly the deposit, donating the registration cost: accepted",
    "fold", fold 14⟩,
  ⟨"fold-donating-more", "the same fold donating 3: accepted",
    "fold", fold 14 (donation := 3)⟩,
  ⟨"fold-after-deadline", "a fold whose validity interval ends one slot after the deadline: refused",
    "fold", fold 14 (interval := ⟨12, 16⟩)⟩,
  ⟨"fold-holding-one-more", "the holding holds the deposit plus one lovelace: refused",
    "fold", fold 15⟩,
  ⟨"fold-holding-one-less", "the holding holds the deposit less one lovelace: refused",
    "fold", fold 13⟩,
  ⟨"fold-donation-short", "the treasury donation is one less than the registration cost: refused",
    "fold", fold 14 (donation := 1)⟩,
  ⟨"fold-other-datum", "the holding carries another initial datum than the committed one: refused",
    "fold", fold 14 (datum := initialRaw aidE2)⟩,
  ⟨"fold-approval-kept", "the approval is not burned: refused",
    "fold", fold 14 (burn := 0)⟩,
  ⟨"fold-at-application-address", "the holding is delivered to the application address instead of the checkpoint validator: refused",
    "fold", fold 14 (address := release.applicationCredential)⟩,
  ⟨"fold-at-committed-other-address", "a request committing another address than the checkpoint validator's, folded to that address: refused",
    "fold", fold 14 (raw := 9004) (address := otherAddress)⟩,
  ⟨"fold-other-commitment-to-checkpoint", "a request committing another address than the checkpoint validator's, folded to the checkpoint validator: refused",
    "fold", fold 14 (raw := 9004)⟩,
  ⟨"checkpoint-spent-at-checkpoint-validator", "the delivered checkpoint spent by its own lifecycle at the checkpoint validator, no application action: the application does not refuse it",
    "checkpoint", checkpointSpend checkpointCredential⟩,
  ⟨"checkpoint-spent-at-application-address", "the same spend of a checkpoint sitting at the application address: no action names it, refused",
    "checkpoint", checkpointSpend release.applicationCredential⟩,
  ⟨"return-at-deadline", "a return starting at the deadline paying the refund address 16, the request less the tip: accepted",
    "return", return_ 16⟩,
  ⟨"return-straddling-deadline", "a return whose validity interval starts one slot before the deadline: refused",
    "return", return_ 16 (interval := ⟨14, 20⟩)⟩,
  ⟨"return-refund-reduced", "the refund address is paid one lovelace less than the request less the tip: refused",
    "return", return_ 15⟩,
  ⟨"return-refund-redirected", "the refund is paid to another address: refused",
    "return", return_ 16 (address := otherAddress)⟩,
  ⟨"termination-fold", "a pending termination spent by its terminating fold, burning its approval and active token: accepted",
    "termination", terminationFold⟩,
  ⟨"termination-fold-active-kept", "a terminating fold that does not burn the active token: refused",
    "termination", terminationActiveKept⟩,
  ⟨"fold-with-unnamed-request", "a fold that also spends a second booked request no action names: refused",
    "fold", foldWithUnnamed⟩,
  ⟨"termination-return", "a return naming a pending termination: refused",
    "termination", terminationReturn⟩]

/-! ## Rows -/

def hexOf (n : Nat) : String := toHex (unpack n)

def verdict (o : Observation) : String :=
  if accepted i env rp release o then "accepted" else "refused"

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
  approvalRow "approval" "the registration approval of a funded registration of 14 lovelace" aidE 14,
  approvalRow "approval-other-deposit" "the same registration committing 15: another approval" aidE 15,
  approvalRow "approval-other-aid" "another AID in the same registry: another key, datum and approval" aidE2 14]

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
      "folds, returns and termination spends, and the spend of a delivered checkpoint.")),
    ("model", toJson "lean/CardanoKeri/Application.lean"),
    ("deposit", toJson "the approval commits the whole carrier; the holding holds exactly it"),
    ("holding", toJson "the approval commits the checkpoint validator's credential, which the configuration record names and which is not the application's; the fold delivers there"),
    ("request", toJson "deposit + registrationCost + minimumTip"),
    ("treasury", toJson "a fold's treasury_donation is at least the registration costs it folds"),
    ("deadline", toJson "bookedAt (the booking's validity upper bound) plus processTime; retractTime = 0"),
    ("intervals", toJson "lower bound included, upper bound excluded, as the ledger hands them to scripts"),
    ("configuration", configurationRow),
    ("approvals", Json.arr approvals.toArray),
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
  for changed in CardanoKeri.Registry.LifecycleVectors.perturbations configuration do
    if (verifyConfiguration changed).toOption.isSome then throw s!"a changed field survived: {changed.compress}"
    fields := fields + 1
  let accepted := committed.filter (fun r => (r.getObjValAs? String "verdict").toOption == some "accepted")
  if accepted.size == 0 || accepted.size == committed.size then throw "rows need both verdicts"
  pure (committed.size, accepted.size, fields)

end CardanoKeri.Application.Vectors
