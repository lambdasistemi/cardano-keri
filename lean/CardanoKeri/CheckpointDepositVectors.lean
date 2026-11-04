import CardanoKeri.CheckpointDepositGoals
import CardanoKeri.CheckpointDatumVectors

/-! Vectors of the deposit intent (#517).

Intent rows fix a spent checkpoint state, what the validator observes (network,
policy, spent output, AID) and the new sequence number, and give the intent the
validator requires and its signed bytes. Requirement rows pair a state with a
candidate intent: accepted only when the candidate is the required intent,
refused for every named change of one field. Authorization rows give the new
keys, the threshold and signatures, and whether the deposit rotation step is
taken under the concrete reading of `Env.depositAuthorized`.

Signatures are symbolic: each names its position, the key that made it and the
intent whose bytes it signs. The Lean checks them with an ideal verifier (a
signature is the key followed by the message); an implementation reproduces a
row with real Ed25519 signatures by its own test keys over the committed bytes.
Checks run the actual Lean functions; they are evidence over the listed
inputs, not a proof over all inputs. -/
namespace CardanoKeri.CheckpointDeposit.Vectors
open Lean (Json toJson)
open CardanoKeri.Checkpoint
open CardanoKeri.CheckpointDatum
open CardanoKeri.CheckpointDeposit
open CardanoKeri.ConsumerIdentity.Bytes (pack unpack utf8)
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (ofHex field str policyHex txHex aidE aidE2 aidB)
open CardanoKeri.CheckpointDatum.Vectors (natJson hexJson stateJson rows fieldControls key refundBytes)

/-! ## Cases -/

/-- Lovelace amounts of mainnet magnitude, so the amount needs a four-byte head. -/
def params : Params :=
  { D := 3000000, B := 2000000, P := 1000000, W := 10, hD := by decide, hB := by decide }

def bytesOf (s : String) : List Nat :=
  match ofHex s with
  | .ok bs => bs
  | .error _ => []

def observed : Observed :=
  { networkId := 0, checkpointPolicy := pack (bytesOf policyHex),
    spentRef := ⟨pack (bytesOf txHex), 1⟩, aid := pack (utf8 aidE) }

def frozenState : Live := ⟨4, 2, false, true, 100, pack (refundBytes 57), 0⟩
def unfrozenState : Live := ⟨4, 2, false, false, 100, pack (refundBytes 57), 5000000⟩
def poisonedFrozenState : Live := ⟨4, 2, true, true, 100, pack (refundBytes 57), 0⟩
def largeState : Live :=
  ⟨18446744073709551621, 1180591620717411303424, false, true, 100, pack (refundBytes 57), 0⟩

structure IntentCase where
  id : String
  note : String
  state : Live
  observed : Observed
  newSn : Seq

def frozenCase : IntentCase :=
  ⟨"frozen", "a frozen checkpoint: the intent names the freeze bond", frozenState, observed, 7⟩

def unfrozenCase : IntentCase :=
  ⟨"unfrozen", "an unfrozen checkpoint: the intent names 0", unfrozenState, observed, 7⟩

def poisonedCase : IntentCase :=
  ⟨"frozen-poisoned", "a frozen checkpoint its current keys poisoned: the rotation clears the poison, the intent names the freeze bond",
    poisonedFrozenState, observed, 7⟩

def intentCases : List IntentCase := [
  frozenCase, unfrozenCase, poisonedCase,
  ⟨"mainnet", "the same frozen checkpoint on network 1", frozenState, { observed with networkId := 1 }, 7⟩,
  ⟨"large-numbers", "sequence number and epoch beyond 2^64 (tagged big numbers), output index 300 and a basic AID",
    largeState, { observed with spentRef := ⟨pack (bytesOf txHex), 300⟩, aid := pack (utf8 aidB) },
    18446744073709551630⟩]

def IntentCase.required (c : IntentCase) : DepositIntent := intentFor params c.observed c.state c.newSn

/-- A candidate intent paired with the state it is presented for. -/
structure Requirement where
  id : String
  note : String
  base : IntentCase
  candidate : DepositIntent

def lastByte (n : Nat) : Nat :=
  let bs := unpack n
  pack (bs.dropLast ++ [(bs.getLastD 0 + 1) % 256])

def requirementCases : List Requirement :=
  let f := frozenCase.required
  let u := unfrozenCase.required
  [⟨"frozen-required", "the required intent for a frozen checkpoint: accepted", frozenCase, f⟩,
   ⟨"unfrozen-required", "the required intent for an unfrozen checkpoint, naming 0: accepted", unfrozenCase, u⟩,
   ⟨"poisoned-required", "the required intent for a frozen, poisoned checkpoint: accepted",
     poisonedCase, poisonedCase.required⟩,
   ⟨"domain-v2", "another version of the domain tag", frozenCase,
     { f with domain := utf8 "cardano-keri/checkpoint/deposit/v2" }⟩,
   ⟨"domain-other-protocol", "another protocol's domain tag", frozenCase,
     { f with domain := utf8 "cardano-keri/value-write/v1" }⟩,
   ⟨"other-network", "the intent for network 1 presented on network 0", frozenCase, { f with networkId := 1 }⟩,
   ⟨"other-policy", "another checkpoint policy", frozenCase,
     { f with checkpointPolicy := lastByte f.checkpointPolicy }⟩,
   ⟨"other-transaction", "an output of another transaction", frozenCase,
     { f with spentRef := { f.spentRef with tx := lastByte f.spentRef.tx } }⟩,
   ⟨"other-output-index", "another output of the same transaction", frozenCase,
     { f with spentRef := { f.spentRef with index := 0 } }⟩,
   ⟨"other-aid", "another AID", frozenCase, { f with aid := pack (utf8 aidE2) }⟩,
   ⟨"other-sequence-number", "another rotation of the same lineage", frozenCase, { f with newSn := f.newSn + 1 }⟩,
   ⟨"old-epoch", "the epoch of the spent state instead of the one the rotation opens", frozenCase,
     { f with newEpoch := frozenState.epoch }⟩,
   ⟨"frozen-names-zero", "a frozen checkpoint with an intent naming 0", frozenCase, { f with deposit := 0 }⟩,
   ⟨"frozen-names-less", "a frozen checkpoint with an intent naming one lovelace less than the bond", frozenCase,
     { f with deposit := params.B - 1 }⟩,
   ⟨"frozen-names-more", "a frozen checkpoint with an intent naming one lovelace more than the bond", frozenCase,
     { f with deposit := params.B + 1 }⟩,
   ⟨"unfrozen-names-bond", "an unfrozen checkpoint with an intent naming the freeze bond", unfrozenCase,
     { u with deposit := params.B }⟩]

def Requirement.accepted (r : Requirement) : Bool := r.candidate.preimage == r.base.required.preimage

/-! ## Signatures -/

/-- The ideal verifier of the vectors: a signature is the key followed by the message. -/
def idealVerify : Verify := fun k m s => s == k ++ m

def newKey (i : Nat) : List Nat := key (40 + i)
def oldKey (i : Nat) : List Nat := key (60 + i)

def keyOf : String → List Nat
  | "new-0" => newKey 0 | "new-1" => newKey 1 | "new-2" => newKey 2
  | "old-0" => oldKey 0 | "old-1" => oldKey 1 | "old-2" => oldKey 2
  | _ => []

/-- A signature: its position in the new keys, the key that made it and the
requirement case whose candidate bytes it signs. -/
structure Sig where
  position : Nat
  signer : String
  over : String

def overBytes (over : String) : List Nat :=
  ((requirementCases.find? (·.id == over)).map (·.candidate.preimage)).getD []

def Sig.wire (s : Sig) : Nat × List Nat := (s.position, keyOf s.signer ++ overBytes s.over)

def newKeys : List Nat := [pack (newKey 0), pack (newKey 1), pack (newKey 2)]

def twoOfThree : Duplicity.Threshold := .count 2

def halves : Duplicity.Threshold := .weighted [[.key ⟨1, 2⟩, .key ⟨1, 2⟩, .key ⟨1, 2⟩]]

structure Authorization where
  id : String
  note : String
  base : IntentCase
  threshold : Duplicity.Threshold
  signatures : List Sig

def authorizationCases : List Authorization := [
  ⟨"two-of-three", "two of three new keys sign the required intent: the deposit is taken", frozenCase, twoOfThree,
    [⟨0, "new-0", "frozen-required"⟩, ⟨1, "new-1", "frozen-required"⟩]⟩,
  ⟨"three-of-three", "all three new keys sign: the deposit is taken", frozenCase, twoOfThree,
    [⟨0, "new-0", "frozen-required"⟩, ⟨1, "new-1", "frozen-required"⟩, ⟨2, "new-2", "frozen-required"⟩]⟩,
  ⟨"one-of-three", "one new key signs, below the threshold: refused", frozenCase, twoOfThree,
    [⟨0, "new-0", "frozen-required"⟩]⟩,
  ⟨"repeated-position", "the same position twice counts once: refused", frozenCase, twoOfThree,
    [⟨0, "new-0", "frozen-required"⟩, ⟨0, "new-0", "frozen-required"⟩]⟩,
  ⟨"position-out-of-range", "a signature at a position with no key never counts: refused", frozenCase, twoOfThree,
    [⟨0, "new-0", "frozen-required"⟩, ⟨3, "new-1", "frozen-required"⟩]⟩,
  ⟨"positions-swapped", "each signature at the other key's position does not verify: refused", frozenCase, twoOfThree,
    [⟨0, "new-1", "frozen-required"⟩, ⟨1, "new-0", "frozen-required"⟩]⟩,
  ⟨"old-keys", "the keys of the spent epoch sign: refused", frozenCase, twoOfThree,
    [⟨0, "old-0", "frozen-required"⟩, ⟨1, "old-1", "frozen-required"⟩]⟩,
  ⟨"signed-other-output", "the new keys signed the intent for another output of the same transaction: refused",
    frozenCase, twoOfThree, [⟨0, "new-0", "other-output-index"⟩, ⟨1, "new-1", "other-output-index"⟩]⟩,
  ⟨"signed-other-network", "the new keys signed the intent for another network: refused", frozenCase, twoOfThree,
    [⟨0, "new-0", "other-network"⟩, ⟨1, "new-1", "other-network"⟩]⟩,
  ⟨"signed-zero-on-frozen", "the new keys signed an intent naming 0 for a frozen checkpoint: refused", frozenCase,
    twoOfThree, [⟨0, "new-0", "frozen-names-zero"⟩, ⟨1, "new-1", "frozen-names-zero"⟩]⟩,
  ⟨"one-stale-two-current", "one signature over another output, two over the required intent: the deposit is taken",
    frozenCase, twoOfThree,
    [⟨0, "new-0", "other-output-index"⟩, ⟨1, "new-1", "frozen-required"⟩, ⟨2, "new-2", "frozen-required"⟩]⟩,
  ⟨"weighted-two-halves", "a weighted threshold of three halves, two keys sign: the deposit is taken", frozenCase,
    halves, [⟨0, "new-0", "frozen-required"⟩, ⟨2, "new-2", "frozen-required"⟩]⟩,
  ⟨"weighted-one-half", "a weighted threshold of three halves, one key signs: refused", frozenCase, halves,
    [⟨1, "new-1", "frozen-required"⟩]⟩,
  ⟨"unfrozen-zero", "an unfrozen checkpoint, the new keys sign the intent naming 0: the deposit is taken and brings nothing",
    unfrozenCase, twoOfThree, [⟨0, "new-0", "unfrozen-required"⟩, ⟨1, "new-1", "unfrozen-required"⟩]⟩,
  ⟨"unfrozen-signed-bond", "an unfrozen checkpoint, the new keys sign an intent naming the freeze bond: refused",
    unfrozenCase, twoOfThree, [⟨0, "new-0", "unfrozen-names-bond"⟩, ⟨1, "new-1", "unfrozen-names-bond"⟩]⟩]

def Authorization.evidence (a : Authorization) : Evidence :=
  { observed := a.base.observed, newKeys := newKeys, newThreshold := a.threshold,
    signatures := a.signatures.map Sig.wire }

/-- The environment of one deposit rotation: the witnessed rotation from the
spent state to the new sequence number, and the concrete reading of the
deposit authorization. -/
def Authorization.env (a : Authorization) : Env :=
  { rotationTo := fun e sn sn' => e == a.base.state.epoch && sn == a.base.state.sn && sn' == a.base.newSn,
    depositAuthorized := fun e =>
      e == a.base.state.epoch + 1 && a.evidence.authorizes idealVerify params a.base.state a.base.newSn,
    quorum := fun _ => false, convictionContext := fun _ _ => none, convictionRival := fun _ _ => none }

def Authorization.step (a : Authorization) : Option (Flow × State) :=
  stepFn params a.env (.rotate a.base.newSn .deposit 0) 200 (.present a.base.state)

/-! ## Rendering -/

def observedJson (o : Observed) : Json := Json.mkObj [
  ("networkId", natJson o.networkId), ("checkpointPolicy", hexJson (unpack o.checkpointPolicy)),
  ("spentRef", Json.mkObj [("transactionId", hexJson (unpack o.spentRef.tx)),
    ("outputIndex", natJson o.spentRef.index)]),
  ("aid", hexJson (unpack o.aid))]

def intentJson (i : DepositIntent) : Json := Json.mkObj [
  ("domain", hexJson i.domain), ("networkId", natJson i.networkId),
  ("checkpointPolicy", hexJson (unpack i.checkpointPolicy)),
  ("spentRef", Json.mkObj [("transactionId", hexJson (unpack i.spentRef.tx)),
    ("outputIndex", natJson i.spentRef.index)]),
  ("aid", hexJson (unpack i.aid)), ("newSn", natJson i.newSn), ("newEpoch", natJson i.newEpoch),
  ("deposit", natJson i.deposit)]

def inputJson (c : IntentCase) : Json := Json.mkObj [
  ("spent", stateJson (.present c.state)), ("observed", observedJson c.observed), ("newSn", natJson c.newSn)]

def intentRow (c : IntentCase) : Json := Json.mkObj [
  ("id", toJson c.id), ("note", toJson c.note), ("input", inputJson c),
  ("intent", intentJson c.required), ("preimage", hexJson c.required.preimage)]

def requirementRow (r : Requirement) : Json := Json.mkObj [
  ("id", toJson r.id), ("note", toJson r.note), ("input", inputJson r.base),
  ("candidate", intentJson r.candidate), ("candidatePreimage", hexJson r.candidate.preimage),
  ("requiredPreimage", hexJson r.base.required.preimage), ("accepted", toJson r.accepted)]

def stepJson : Option (Flow × State) → Json
  | none => Json.mkObj [("taken", toJson false)]
  | some (f, s) => Json.mkObj [("taken", toJson true), ("bIn", natJson f.bIn), ("successor", stateJson s)]

def authorizationRow (a : Authorization) : Json :=
  let ev := a.evidence
  Json.mkObj [
    ("id", toJson a.id), ("note", toJson a.note), ("input", inputJson a.base),
    ("newKeys", toJson ["new-0", "new-1", "new-2"]), ("threshold", toJson a.threshold),
    ("signatures", Json.arr (a.signatures.map fun s => Json.mkObj [
      ("position", natJson s.position), ("signer", toJson s.signer),
      ("over", toJson s.over)]).toArray),
    ("signedBytes", hexJson a.base.required.preimage),
    ("countedPositions", toJson (verifiedPositions idealVerify (ev.newKeys.map unpack)
      a.base.required.preimage ev.signatures).eraseDups),
    ("authorized", toJson (ev.authorizes idealVerify params a.base.state a.base.newSn)),
    ("step", stepJson a.step)]

def table : Json := Json.mkObj [
  ("description", toJson ("Vectors of the deposit intent: for each spent checkpoint state and observed " ++
    "network, policy, output and AID, the intent the validator requires and its signed bytes; candidate " ++
    "intents accepted or refused for a state; and signature sets, with whether the deposit rotation is taken.")),
  ("model", toJson "lean/CardanoKeri/CheckpointDeposit.lean"),
  ("params", Json.mkObj [("B", natJson params.B)]),
  ("layout", Json.mkObj [
    ("DepositIntent", toJson ("constructor 0 [domain: bytes, network_id: int, checkpoint_policy: bytes, " ++
      "spent_ref: OutputReference, aid: bytes, new_sn: int, new_epoch: int, deposit: int]")),
    ("OutputReference", toJson "constructor 0 [transaction_id: bytes, output_index: int]"),
    ("domain", toJson s!"the UTF-8 bytes of {domainTag}, frozen"),
    ("aid", toJson "the AID's qualified CESR text bytes (UTF-8), as the datum carries it"),
    ("new_epoch", toJson "the spent state's epoch plus one"),
    ("deposit", toJson "B - bHeld: B when the spent state is frozen, 0 when it is not"),
    ("preimage", toJson "the Plutus Data serialisation of the intent; each signature is Ed25519 over it"),
    ("signatures", toJson ("pairs (position in the rotation event's current keys, signature); a position " ++
      "outside the keys never counts, a repeated position counts once, the counted positions must " ++
      "satisfy the rotation event's current threshold")),
    ("signature rows", toJson ("symbolic: signer names a test key, over names the requirement row whose " ++
      "candidate bytes are signed"))]),
  ("intents", Json.arr (intentCases.map intentRow).toArray),
  ("requirements", Json.arr (requirementCases.map requirementRow).toArray),
  ("authorizations", Json.arr (authorizationCases.map authorizationRow).toArray)]

/-! ## Checking a committed table -/

/-- A committed intent row equals the Lean's row, and its committed bytes
read back as exactly the committed intent. -/
def verifyIntent (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some c := intentCases.find? (·.id == id) | throw s!"{id}: no such intent case"
  unless row == intentRow c do throw s!"{id}: differs from the Lean's row"
  let bytes ← ofHex (← str row ["preimage"])
  unless (ofBytes? bytes).map (fun d => cbor d) == some c.required.preimage do
    throw s!"{id}: the committed bytes do not read back as the required intent"

/-- A committed requirement row equals the Lean's row, and its committed
candidate bytes are accepted exactly when they equal the required bytes. -/
def verifyRequirement (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some r := requirementCases.find? (·.id == id) | throw s!"{id}: no such requirement case"
  unless row == requirementRow r do throw s!"{id}: differs from the Lean's row"
  let candidate ← ofHex (← str row ["candidatePreimage"])
  unless toJson (candidate == r.base.required.preimage) == (← field row ["accepted"]) do
    throw s!"{id}: the committed candidate bytes do not get the committed verdict"

def verifyAuthorization (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some a := authorizationCases.find? (·.id == id) | throw s!"{id}: no such authorization case"
  unless row == authorizationRow a do throw s!"{id}: differs from the Lean's row"

/-- Both verdicts occur among the requirement rows and both outcomes among the
authorization rows, and every authorization row's step is taken exactly when
its evidence authorizes the intent. -/
def verdictCounts : Except String (Nat × Nat) := do
  let accepted := (requirementCases.filter (·.accepted)).length
  let refused := (requirementCases.filter (!·.accepted)).length
  if accepted == 0 || refused == 0 then throw "requirement rows need both verdicts"
  let taken := (authorizationCases.filter (·.step.isSome)).length
  if taken == 0 || taken == authorizationCases.length then throw "authorization rows need both outcomes"
  for a in authorizationCases do
    unless a.step.isSome == a.evidence.authorizes idealVerify params a.base.state a.base.newSn do
      throw s!"{a.id}: the step and the authorization disagree"
  pure (accepted, refused)

def checkTable (j : Json) : Except String (Nat × Nat × Nat × Nat × Nat) := do
  let intents ← rows j "intents"
  let requirements ← rows j "requirements"
  let authorizations ← rows j "authorizations"
  unless intents.size == intentCases.length do throw "intent count differs from the Lean cases"
  unless requirements.size == requirementCases.length do throw "requirement count differs from the Lean cases"
  unless authorizations.size == authorizationCases.length do
    throw "authorization count differs from the Lean cases"
  for row in intents do verifyIntent row
  for row in requirements do verifyRequirement row
  for row in authorizations do verifyAuthorization row
  let _ ← verdictCounts
  let fields := (← fieldControls intents verifyIntent) + (← fieldControls requirements verifyRequirement) +
    (← fieldControls authorizations verifyAuthorization)
  pure (intents.size, requirements.size, authorizations.size, fields, (requirementCases.filter (!·.accepted)).length)

end CardanoKeri.CheckpointDeposit.Vectors
