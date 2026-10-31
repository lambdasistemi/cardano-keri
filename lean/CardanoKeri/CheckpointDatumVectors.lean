import CardanoKeri.CheckpointDatumGoals
import CardanoKeri.ConsumerBytesVectors

/-! Vectors of the version 2 checkpoint datum and its decoder (#498).

Accepted rows fix a checkpoint state, the AID and the key material, and give
the serialised datum, what the decoder returns and the consumer's verdict on a
genuine holding carrying it, under the concrete interpretation of #489.
Refused rows give a serialised datum the decoder refuses, each a named change
of a written datum. The Aiken consumer (#343) reproduces both. Checks run the
actual decoder and consumer predicate; they are evidence over the listed
inputs, not a proof over all inputs. -/
namespace CardanoKeri.CheckpointDatum.Vectors
open Lean (Json toJson)
open CardanoKeri.Checkpoint
open CardanoKeri.ConsumerIdentity
open CardanoKeri.ConsumerIdentity.Bytes
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (toHex ofHex field str policyHex txHex aidE aidE2 aidB)

/-! ## Cases -/

def params : Params := { D := 3, B := 2, P := 1, W := 10, hD := by decide, hB := by decide }

/-- A 32-byte key digest. -/
def key (seed : Nat) : List Nat := (List.range 32).map fun i => (seed * 31 + i * 7) % 256

/-- A refund address of `n` bytes. -/
def refundBytes (n : Nat) : List Nat := (List.range n).map fun i => (i * 3 + 1) % 256

def simpleKeys : KeyMaterial := ⟨[key 1], .unweighted 1, [key 2], .unweighted 1, [], 0⟩

def richKeys : KeyMaterial :=
  ⟨[key 3, key 4, key 5], .weighted [[(1, 2), (1, 2)], [(1, 1)]], [key 6, key 7], .unweighted 2,
   [key 8, key 9, key 10], 2⟩

structure Accepted where
  id : String
  note : String
  aid : String
  state : State
  keys : KeyMaterial
  now : Slot

def registered (pool : Nat) : State := .present ⟨0, 0, false, false, 100, pack (refundBytes 57), pool⟩

def acceptedCases : List Accepted := [
  ⟨"registered-funded", "just registered with a funded premium pool, read after its juvenility window: accepted; the pool is held in the value, not the datum",
    aidE, registered 5000000, simpleKeys, 110⟩,
  ⟨"registered-juvenile", "the same checkpoint read one slot before its juvenility window ends: decoded, refused by the consumer",
    aidE, registered 5000000, simpleKeys, 109⟩,
  ⟨"rotated", "a live checkpoint after rotations, with weighted thresholds and witnesses: accepted",
    aidE2, .present ⟨7, 3, false, false, 100, pack (refundBytes 57), 0⟩, richKeys, 200⟩,
  ⟨"poisoned", "a live checkpoint its current keys have poisoned: decoded, refused by the consumer",
    aidE, .present ⟨4, 2, true, false, 100, pack (refundBytes 57), 3⟩, simpleKeys, 200⟩,
  ⟨"frozen", "a live checkpoint whose bond is frozen: decoded, refused by the consumer",
    aidE, .present ⟨4, 2, false, true, 100, pack (refundBytes 57), 3⟩, simpleKeys, 200⟩,
  ⟨"pending-termination", "a convicted checkpoint awaiting its terminating fold: decoded, refused by the consumer",
    aidE, .terminationPending ⟨2, 4⟩, simpleKeys, 200⟩,
  ⟨"large-numbers", "sequence number and epoch beyond 2^64 (tagged big numbers) and a 70-byte refund address (chunked): accepted",
    aidB, .present ⟨18446744073709551621, 1180591620717411303424, false, false, 100, pack (refundBytes 70), 0⟩,
    simpleKeys, 200⟩]

/-- The eight fields of the first accepted case's live datum. -/
def liveFields : List Data :=
  [.bytes (utf8 aidE), .int 4, .int 2, boolData false, boolData false, .int 100,
   .bytes (refundBytes 57), keyMaterialData simpleKeys]

def keyFields : List Data :=
  [bytesListData simpleKeys.curKeys, thresholdData simpleKeys.curThreshold,
   bytesListData simpleKeys.nextKeys, thresholdData simpleKeys.nextThreshold,
   bytesListData simpleKeys.witnesses, .int simpleKeys.toad]

def live (fs : List Data) : Data := .constr 1 [.constr 0 fs]

def withField (i : Nat) (d : Data) : Data := live (liveFields.set i d)

def withKeys (fs : List Data) : Data := withField 7 (.constr 0 fs)

/-- The version 1 layout of `datum.ak`: a 32-byte AID, keys, thresholds,
witnesses, `toad`, `seq` and `native_sn`. -/
def versionOne : Data :=
  .constr 0 [.constr 0 [.bytes (key 0), bytesListData [key 1], thresholdData (.unweighted 1),
    bytesListData [key 2], thresholdData (.unweighted 1), bytesListData [], .int 0, .int 3, .int 4]]

structure Refused where
  id : String
  note : String
  bytes : List Nat

def refusedData : List (String × String × Data) := [
  ("version-1", "the version 1 layout the checkpoint validator writes today", versionOne),
  ("version-3", "an unknown version constructor", .constr 2 [.constr 0 liveFields]),
  ("version-no-field", "version 2 without its field", .constr 1 []),
  ("version-two-fields", "version 2 with two fields", .constr 1 [.constr 0 liveFields, .constr 0 liveFields]),
  ("unknown-form", "a version 2 form that is neither live nor pending termination", .constr 1 [.constr 2 liveFields]),
  ("live-seven-fields", "a live datum without its key material", live (liveFields.take 7)),
  ("live-nine-fields", "a live datum with an extra field", live (liveFields ++ [.int 0])),
  ("pending-five-fields", "a pending-termination datum with an extra field",
    .constr 1 [.constr 1 [.bytes (utf8 aidE), .int 4, .int 2, keyMaterialData simpleKeys, .int 0]]),
  ("pending-negative-epoch", "a pending-termination datum with a negative epoch",
    .constr 1 [.constr 1 [.bytes (utf8 aidE), .int 4, .int (-2), keyMaterialData simpleKeys]]),
  ("aid-integer", "the AID as an integer", withField 0 (.int 5)),
  ("sn-negative", "a negative sequence number", withField 1 (.int (-1))),
  ("epoch-bytes", "the epoch as a byte string", withField 2 (.bytes [])),
  ("poisoned-not-boolean", "poison as constructor 2", withField 3 (.constr 2 [])),
  ("poisoned-boolean-with-field", "poison as a Boolean constructor carrying a field", withField 3 (.constr 1 [.int 0])),
  ("frozen-integer", "freeze as an integer", withField 4 (.int 1)),
  ("born-at-negative", "a negative birth slot", withField 5 (.int (-100))),
  ("refund-integer", "the refund address as an integer", withField 6 (.int 7)),
  ("keys-list", "the key material as a list", withField 7 (.list keyFields)),
  ("keys-five-fields", "key material without `toad`", withKeys (keyFields.take 5)),
  ("key-integer", "a current key as an integer", withKeys (keyFields.set 0 (.list [.int 1]))),
  ("threshold-unknown-form", "a threshold constructor that is neither unweighted nor weighted", withKeys (keyFields.set 1 (.constr 2 [.int 1]))),
  ("weight-one-field", "a weight without its denominator",
    withKeys (keyFields.set 3 (.constr 1 [.list [.list [.constr 0 [.int 1]]]]))),
  ("witnesses-map", "the witnesses as a map", withKeys (keyFields.set 4 (.map []))),
  ("toad-bytes", "`toad` as a byte string", withKeys (keyFields.set 5 (.bytes []))),
  ("not-a-constructor", "the live fields as a bare list", .list liveFields)]

def refusedCases : List Refused :=
  refusedData.map (fun (id, note, d) => ⟨id, note, cbor d⟩) ++ [
    ⟨"trailing-byte", "a written datum followed by one more byte", cbor (live liveFields) ++ [0]⟩,
    ⟨"truncated", "a written datum missing its last byte", (cbor (live liveFields)).dropLast⟩,
    ⟨"empty", "no bytes", []⟩,
    ⟨"break-byte", "a lone break byte", [0xff]⟩]

/-! ## The consumer reading a vector -/

def contextFor (aid : String) : Except String Context :=
  ConsumerIdentity.Bytes.Vectors.context ⟨policyHex, txHex, 0, aid⟩

def environment (c : Context) : Environment := { network := c.network, release := some c.release }

def holding (c : Context) (bytes : List Nat) : AH.ObservedOutput :=
  { reference := ⟨0, 0⟩, credential := c.release.applicationCredential, lovelace := 2000000,
    datum := .application (pack bytes), assets := [(representativeAsset interpretation c, 1)] }

/-- The consumer predicate on a genuine holding carrying these datum bytes. -/
def accepts (c : Context) (bytes : List Nat) (now : Slot) : Bool :=
  consumableHoldingB interpretation c (environment c) params now (holding c bytes)

/-! ## Rendering -/

/-- Naturals beyond the safe JSON number range are decimal strings. -/
def natJson (n : Nat) : Json := if n < 9007199254740992 then toJson n else toJson (toString n)

def intJson (n : Int) : Json := if n.natAbs < 9007199254740992 then toJson n else toJson (toString n)

def hexJson (bs : List Nat) : Json := toJson (toHex bs)

def stateJson : State → Json
  | .present l => Json.mkObj [("form", "live"), ("sn", natJson l.sn), ("epoch", natJson l.epoch),
      ("poisoned", toJson l.poisoned), ("frozen", toJson l.frozen), ("bornAt", natJson l.bornAt),
      ("refundTo", hexJson (unpack l.refundTo)), ("pool", natJson l.pool)]
  | .terminationPending h => Json.mkObj [("form", "terminationPending"), ("sn", natJson h.sn),
      ("epoch", natJson h.epoch)]
  | .absent => Json.mkObj [("form", "absent")]
  | .convicted => Json.mkObj [("form", "convicted")]

def thresholdJson : Threshold → Json
  | .unweighted m => Json.mkObj [("unweighted", intJson m)]
  | .weighted cs => Json.mkObj [("weighted", Json.arr (cs.map fun c =>
      Json.arr (c.map fun w => Json.arr #[intJson w.1, intJson w.2]).toArray).toArray)]

def keysJson (k : KeyMaterial) : Json := Json.mkObj [
  ("curKeys", Json.arr (k.curKeys.map hexJson).toArray), ("curThreshold", thresholdJson k.curThreshold),
  ("nextKeys", Json.arr (k.nextKeys.map hexJson).toArray), ("nextThreshold", thresholdJson k.nextThreshold),
  ("witnesses", Json.arr (k.witnesses.map hexJson).toArray), ("toad", intJson k.toad)]

def decodedJson : Option DecodedDatum → Json
  | none => Json.null
  | some r => Json.mkObj [("aid", hexJson (unpack r.aid)), ("state", stateJson r.state)]

def acceptedRow (a : Accepted) : Except String Json := do
  let c ← contextFor a.aid
  let some d := datum c.aid a.keys a.state | throw s!"{a.id}: no datum for this state"
  pure (Json.mkObj [
    ("id", toJson a.id), ("note", toJson a.note),
    ("input", Json.mkObj [("aid", toJson a.aid), ("state", stateJson a.state), ("keys", keysJson a.keys)]),
    ("datum", hexJson (cbor d)),
    ("decoded", decodedJson (decode c.release (raw d))),
    ("consumer", Json.mkObj [("now", natJson a.now), ("accepted", toJson (accepts c (cbor d) a.now))])])

def refusedRow (r : Refused) : Except String Json := do
  let c ← contextFor aidE
  pure (Json.mkObj [
    ("id", toJson r.id), ("note", toJson r.note), ("datum", hexJson r.bytes),
    ("decoded", decodedJson (decode c.release (pack r.bytes))),
    ("consumer", Json.mkObj [("now", natJson 200), ("accepted", toJson (accepts c r.bytes 200))])])

def table : Except String Json := do
  let accepted ← acceptedCases.mapM acceptedRow
  let refused ← refusedCases.mapM refusedRow
  pure (Json.mkObj [
    ("description", toJson ("Vectors of the version 2 checkpoint datum: for each checkpoint state, AID " ++
      "and key material, the serialised inline datum, what the consumer's decoder returns and the " ++
      "consumer's verdict on a genuine holding carrying it; and serialised datums the decoder refuses.")),
    ("model", toJson "lean/CardanoKeri/CheckpointDatum.lean"),
    ("identity", toJson "lean/consumer-identity-vectors.json: state policy, seed and the representative asset of the AID"),
    ("params", Json.mkObj [("W", natJson params.W)]),
    ("layout", Json.mkObj [
      ("CheckpointDatum", toJson "V1 = constructor 0 (refused); V2 = constructor 1 [CheckpointDatumV2]"),
      ("CheckpointDatumV2.Live", toJson "constructor 0 [aid: bytes, sn: int, epoch: int, poisoned: Bool, frozen: Bool, born_at: int, refund_to: bytes, keys: KeyMaterial]"),
      ("CheckpointDatumV2.TerminationPending", toJson "constructor 1 [aid: bytes, sn: int, epoch: int, keys: KeyMaterial]"),
      ("KeyMaterial", toJson "constructor 0 [cur_keys: List<bytes>, cur_threshold: Threshold, next_keys: List<bytes>, next_threshold: Threshold, witnesses: List<bytes>, toad: int]"),
      ("Threshold", toJson "Unweighted = constructor 0 [int]; Weighted = constructor 1 [List<List<Weight>>]; Weight = constructor 0 [num: int, den: int]"),
      ("Bool", toJson "False = constructor 0 []; True = constructor 1 []"),
      ("aid", toJson "the AID's qualified CESR text bytes (UTF-8), as the registry key"),
      ("pool", toJson "not in the datum: decoded as 0; the amount is held in the output's value")]),
    ("accepted", Json.arr accepted.toArray),
    ("refused", Json.arr refused.toArray)])

/-! ## Checking a committed table -/

def rows (j : Json) (k : String) : Except String (Array Json) := do
  match ← field j [k] with
  | .arr a => pure a
  | _ => throw s!"no {k} rows"

/-- A committed accepted row equals the Lean's row for its id, and its own
committed datum bytes decode to its committed result and get its verdict. -/
def verifyAccepted (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some a := acceptedCases.find? (·.id == id) | throw s!"{id}: no such accepted case"
  unless row == (← acceptedRow a) do throw s!"{id}: differs from the Lean's row"
  let c ← contextFor a.aid
  let bytes ← ofHex (← str row ["datum"])
  unless decodedJson (decode c.release (pack bytes)) == (← field row ["decoded"]) do
    throw s!"{id}: the committed datum does not decode to the committed result"
  unless toJson (accepts c bytes a.now) == (← field row ["consumer", "accepted"]) do
    throw s!"{id}: the committed datum does not get the committed verdict"

/-- A committed refused row carries the Lean's bytes for its id, which the
decoder refuses and the consumer refuses. -/
def verifyRefused (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some r := refusedCases.find? (·.id == id) | throw s!"{id}: no such refused case"
  unless row == (← refusedRow r) do throw s!"{id}: differs from the Lean's row"
  let c ← contextFor aidE
  let bytes ← ofHex (← str row ["datum"])
  unless (decode c.release (pack bytes)).isNone do throw s!"{id}: the committed datum decodes"
  if accepts c bytes 200 then throw s!"{id}: the consumer accepts the committed datum"

/-- Every leaf: strings, numbers, Booleans and nulls, inside objects and arrays. -/
partial def leaves (j : Json) (path : List String) : List (List String) :=
  match j with
  | .obj kvs => kvs.toList.flatMap fun (k, v) => leaves v (path ++ [k])
  | .arr xs => (xs.toList.zipIdx).flatMap fun (v, i) => leaves v (path ++ [toString i])
  | _ => [path]

def mutateLeaf : Json → Json
  | .str s => match s.toList.reverse with
    | [] => .str "00"
    | c :: rest => .str (String.ofList (rest.reverse ++ [if c == '0' then '1' else '0']))
  | .num n => .num { n with mantissa := n.mantissa + 1 }
  | .bool b => .bool (!b)
  | .null => .num 0
  | other => other

partial def mutateAt (j : Json) : List String → Json
  | [] => mutateLeaf j
  | k :: rest => match j with
    | .obj _ => match j.getObjVal? k with
      | .ok v => j.setObjVal! k (mutateAt v rest)
      | .error _ => j
    | .arr xs => match k.toNat? with
      | some i => if h : i < xs.size then .arr (xs.set i (mutateAt xs[i] rest)) else j
      | none => j
    | other => other

/-- Every leaf of every committed row except the free-text `id` and `note`,
changed in turn, must fail its row's verification. -/
def fieldControls (rs : Array Json) (verify : Json → Except String Unit) : Except String Nat := do
  let mut count := 0
  for row in rs do
    for path in leaves row [] do
      if path == ["id"] || path == ["note"] then continue
      match verify (mutateAt row path) with
      | .ok () => throw s!"changing {path} of {← str row ["id"]} still verifies"
      | .error _ => count := count + 1
  pure count

/-- Every node of a `Data`, as the path of field and item positions to it. -/
partial def paths : Data → List (List Nat)
  | .constr _ fs => [] :: (fs.zipIdx.flatMap fun (f, i) => (paths f).map (i :: ·))
  | .list xs => [] :: (xs.zipIdx.flatMap fun (x, i) => (paths x).map (i :: ·))
  | _ => [[]]

def otherKind : Data → Data
  | .int _ => .bytes []
  | _ => .int 0

partial def replaceAt (d : Data) : List Nat → Data
  | [] => otherKind d
  | i :: rest => match d with
    | .constr n fs => .constr n (fs.modify i fun f => replaceAt f rest)
    | .list xs => .list (xs.modify i fun x => replaceAt x rest)
    | other => other

/-- Every node of every accepted datum, replaced by a node of another kind,
must be refused by the decoder. -/
def kindControls : Except String Nat := do
  let mut count := 0
  for a in acceptedCases do
    let c ← contextFor a.aid
    let some d := datum c.aid a.keys a.state | throw s!"{a.id}: no datum"
    for p in paths d do
      if (decodeData (replaceAt d p)).isSome then throw s!"{a.id}: changing the kind at {p} still decodes"
      count := count + 1
  pure count

def checkTable (j : Json) : Except String (Nat × Nat × Nat × Nat) := do
  let accepted ← rows j "accepted"
  let refused ← rows j "refused"
  unless accepted.size == acceptedCases.length do throw "accepted count differs from the Lean cases"
  unless refused.size == refusedCases.length do throw "refused count differs from the Lean cases"
  for row in accepted do verifyAccepted row
  for row in refused do verifyRefused row
  let fields := (← fieldControls accepted verifyAccepted) + (← fieldControls refused verifyRefused)
  pure (accepted.size, refused.size, fields, ← kindControls)

end CardanoKeri.CheckpointDatum.Vectors
