import CardanoKeri.ConsumerBytesGoals

/-! Byte vectors of the concrete consumer identity (#489).

Each vector fixes the inputs a relying contract holds (state policy, seed and
AID) and the bytes the Lean derives from them: the registry key, both
serialised preimages, both names and the representative asset. The Aiken
consumer predicate (#343) reproduces them. Checks run the actual consumer
predicate with the concrete interpretation; they are evidence over the listed
inputs, not a proof over all inputs. -/
namespace CardanoKeri.ConsumerIdentity.Bytes.Vectors
open Lean (Json toJson)
open CardanoKeri.Checkpoint

def hexDigits : List Char := "0123456789abcdef".toList

def toHex (bs : List Nat) : String :=
  String.join (bs.map fun b => String.ofList [hexDigits[b / 16 % 16]!, hexDigits[b % 16]!])

def hexValue (c : Char) : Option Nat := hexDigits.idxOf? c

def ofHex (s : String) : Except String (List Nat) := do
  let cs := s.toList
  unless cs.length % 2 == 0 do throw s!"odd-hex-length {s}"
  (List.range (cs.length / 2)).mapM fun i =>
    match hexValue cs[2 * i]!, hexValue cs[2 * i + 1]! with
    | some h, some l => pure (h * 16 + l)
    | _, _ => throw s!"bad-hex {s}"

/-- A qualified CESR AID of 44 characters: a one-character code (`B`, `D`
or `E`) and a base64url body. Other codes are outside these vectors. -/
def qualifiedAid (text : String) : Bool :=
  let cs := text.toList
  cs.length == 44 && ['B', 'D', 'E'].contains cs[0]! &&
    cs.all fun c => c.isAlphanum || c == '-' || c == '_'

structure Input where
  statePolicy : String
  transactionId : String
  outputIndex : Nat
  aid : String

structure Case where
  id : String
  note : String
  input : Input

def release (statePolicy : Nat) : AH.PublishedRelease :=
  { applicationPolicy := 1, applicationCredential := 2, stateProgram := 3, statePolicy := statePolicy }

def context (i : Input) : Except String Context := do
  unless qualifiedAid i.aid do throw s!"not-a-qualified-aid {i.aid}"
  let policy ← ofHex i.statePolicy
  let tx ← ofHex i.transactionId
  unless policy.length == 28 do throw s!"state-policy-not-28-bytes {i.statePolicy}"
  unless tx.length == 32 do throw s!"transaction-id-not-32-bytes {i.transactionId}"
  pure { network := 0, release := release (ofBytes policy), seed := ⟨ofBytes tx, i.outputIndex⟩,
         aid := aidOfCesr i.aid }

/-- The fixture decoder: the application datum `711` decodes to `aid` with a
consumable live state. It never reads the asset, so a refusal below comes
from the asset clause alone. -/
def live : State := .present ⟨0, 0, false, false, 2, 42, 5⟩
def params : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def now : Slot := 8
def decoderFor (aid : AID) : AH.PublishedRelease → Nat → Option DecodedDatum :=
  fun _ raw => if raw == 711 then some ⟨aid, live⟩ else none

def concrete (c : Context) : Interpretation := interpretation (decoderFor c.aid)

def environment (c : Context) : Environment := { network := c.network, release := some c.release }

def holding (c : Context) (asset : Singular.TokenId) : AH.ObservedOutput :=
  { reference := ⟨0, 0⟩, credential := c.release.applicationCredential, lovelace := 2000000,
    datum := .application 711, assets := [(asset, 1)] }

/-- The consumer predicate on a holding carrying `asset`, under `c`. -/
def accepts (c : Context) (asset : Singular.TokenId) : Bool :=
  consumableHoldingB (concrete c) c (environment c) params now (holding c asset)

structure Derived where
  key : List Nat
  statePreimage : List Nat
  stateName : List Nat
  activePreimage : List Nat
  activeName : List Nat
  asset : Singular.TokenId

def derive (c : Context) : Derived :=
  let i := concrete c
  let registryId := registryAsset i c
  let stateP := code (.state c.seed)
  let activeP := code (.active registryId (keyOf c.aid))
  { key := unpack (keyOf c.aid), statePreimage := stateP, stateName := unpack registryId.name,
    activePreimage := activeP, activeName := unpack (representativeAsset i c).name,
    asset := representativeAsset i c }

def policyHex : String := "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
def txHex : String := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
def aidE : String := "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
def aidE2 : String := "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"
def aidB : String := "BPbeCTEUzPz5UEX4J9Mk8JST2bZV3phvCQ8hWs0diM14"

def cases : List Case := [
  ⟨"transferable-aid", "a transferable AID (code E) in the base registry",
    ⟨policyHex, txHex, 0, aidE⟩⟩,
  ⟨"other-aid-same-registry", "another AID in the same registry: the same state name, another active name",
    ⟨policyHex, txHex, 0, aidE2⟩⟩,
  ⟨"non-transferable-aid", "a non-transferable AID (code B) in the base registry",
    ⟨policyHex, txHex, 0, aidB⟩⟩,
  ⟨"rival-seed-output-index", "the same AID in a registry created from another output of the same transaction",
    ⟨policyHex, txHex, 1, aidE⟩⟩,
  ⟨"rival-seed-transaction", "the same AID in a registry created from another transaction",
    ⟨policyHex, "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1e", 0, aidE⟩⟩,
  ⟨"other-state-policy", "the same AID and seed under another state policy (another release)",
    ⟨"70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f6", txHex, 0, aidE⟩⟩,
  ⟨"seed-output-index-24", "an output index needing one following byte",
    ⟨policyHex, txHex, 24, aidE⟩⟩,
  ⟨"seed-output-index-256", "an output index needing two following bytes",
    ⟨policyHex, txHex, 256, aidE⟩⟩]

def renderInput (i : Input) : Json := Json.mkObj [
  ("statePolicy", toJson i.statePolicy),
  ("seed", Json.mkObj [("transactionId", toJson i.transactionId), ("outputIndex", toJson i.outputIndex)]),
  ("aid", toJson i.aid)]

def renderDerived (d : Derived) : List (String × Json) := [
  ("key", toJson (toHex d.key)),
  ("statePreimage", toJson (toHex d.statePreimage)),
  ("stateName", toJson (toHex d.stateName)),
  ("activePreimage", toJson (toHex d.activePreimage)),
  ("activeName", toJson (toHex d.activeName)),
  ("asset", Json.mkObj [("policy", toJson (toHex (unpack d.asset.policy))),
    ("name", toJson (toHex (unpack d.asset.name)))])]

def table : Except String Json := do
  let rows ← cases.mapM fun k => do
    let c ← context k.input
    pure (Json.mkObj ([("id", toJson k.id), ("note", toJson k.note), ("input", renderInput k.input)] ++
      renderDerived (derive c)))
  pure (Json.mkObj [
    ("description", toJson ("Byte vectors of the concrete consumer identity: for each relying-contract " ++
      "input (state policy, seed, AID) the registry key, the serialised State and Active preimages, " ++
      "their names and the representative asset a genuine holding carries.")),
    ("model", toJson "lean/CardanoKeri/ConsumerBytes.lean"),
    ("singular", toJson "d69ab005c3b710aeebf033d3c5cd08c56feb5643"),
    ("layout", Json.mkObj [
      ("key", toJson "the AID's qualified CESR text bytes (UTF-8)"),
      ("statePreimage", toJson "Plutus Data serialisation of State { seed: OutputReference { transaction_id, output_index } }"),
      ("activePreimage", toJson "Plutus Data serialisation of Active { registry: RegistryIdentity { policy: state policy, name: stateName }, key }"),
      ("name", toJson "BLAKE2b-256 of the preimage"),
      ("asset", toJson "policy: the state policy; name: activeName")]),
    ("vectors", Json.arr rows.toArray)])

/-! ## Checking a committed table -/

def field (j : Json) (path : List String) : Except String Json :=
  path.foldlM (fun j k => j.getObjVal? k) j

def str (j : Json) (path : List String) : Except String String := do
  match ← field j path with
  | .str s => pure s
  | _ => throw s!"not-a-string {path}"

def inputOf (row : Json) : Except String Input := do
  let n ← field row ["input", "seed", "outputIndex"]
  let index : Nat ← Lean.fromJson? n
  pure ⟨← str row ["input", "statePolicy"], ← str row ["input", "seed", "transactionId"], index,
        ← str row ["input", "aid"]⟩

/-- Recompute every derived field of a committed row from its inputs, and run
the consumer predicate: the committed asset is accepted under the row's
inputs, and refused once any input names another registry or AID. -/
def verifyRow (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let c ← context (← inputOf row)
  let d := derive c
  for (k, v) in renderDerived d do
    unless (← field row [k]) == v do throw s!"{id}: {k} differs from the Lean derivation"
  let policy ← ofHex (← str row ["asset", "policy"])
  let name ← ofHex (← str row ["asset", "name"])
  let committed : Singular.TokenId := ⟨ofBytes policy, ofBytes name⟩
  unless accepts c committed do throw s!"{id}: the genuine holding is refused"

/-- Change the last element. -/
def editLast (f : Nat → Nat) (l : List Nat) : List Nat :=
  match l.reverse with
  | [] => []
  | x :: r => (f x :: r).reverse

/-- Every input field changed in turn, each with its own context, environment
and decoder: only the asset clause can refuse. -/
def inputMutations (c : Context) : List (String × Context) :=
  let flip (n : Nat) : Nat := ofBytes (editLast (fun b => (b + 1) % 256) (unpack n))
  let txt := unpack c.aid
  let otherAid := pack (editLast (fun b => if b == 65 then 66 else 65) txt)
  [("statePolicy", { c with release := { c.release with statePolicy := flip c.release.statePolicy } }),
   ("seed.transactionId", { c with seed := { c.seed with tx := flip c.seed.tx } }),
   ("seed.outputIndex", { c with seed := { c.seed with index := c.seed.index + 1 } }),
   ("aid", { c with aid := otherAid })]

def refusalControls : Except String (List String) := do
  let mut log := []
  for k in cases do
    let c ← context k.input
    let d := derive c
    unless accepts c d.asset do throw s!"{k.id}: genuine holding refused"
    let wrongName : Singular.TokenId :=
      ⟨d.asset.policy, ofBytes (editLast (fun b => (b + 1) % 256) (unpack d.asset.name))⟩
    if accepts c wrongName then throw s!"{k.id}: holding with a changed name accepted"
    for (f, c') in inputMutations c do
      if accepts c' d.asset then throw s!"{k.id}: changed {f} still accepts the committed asset"
      log := log ++ [s!"REFUSED {k.id} {f}"]
    log := log ++ [s!"REFUSED {k.id} asset.name"]
  let names := (← cases.mapM fun k => do pure (derive (← context k.input)).asset)
  unless names.eraseDups.length == names.length do throw "two vectors share a representative asset"
  pure log

/-- Change one leaf: a hex digit or AID character, or an integer by one. -/
def mutateString (s : String) : String :=
  match s.toList.reverse with
  | [] => "00"
  | c :: rest => String.ofList (rest.reverse ++ [if c == '0' then '1' else '0'])

partial def leaves (j : Json) (path : List String) : List (List String) :=
  match j with
  | .obj kvs => kvs.toList.flatMap fun (k, v) => leaves v (path ++ [k])
  | .str _ | .num _ => [path]
  | _ => []

partial def mutateAt (j : Json) : List String → Json
  | [] => match j with
    | .str s => .str (mutateString s)
    | .num n => .num { n with mantissa := n.mantissa + 1 }
    | other => other
  | k :: rest => match j with
    | .obj _ => match j.getObjVal? k with
      | .ok v => j.setObjVal! k (mutateAt v rest)
      | .error _ => j
    | other => other

/-- Every derived or input leaf of every committed row, changed in turn, must
fail `verifyRow`. The free-text `id` and `note` are excluded. -/
def fieldControls (rows : Array Json) : Except String Nat := do
  let mut count := 0
  for row in rows do
    for path in leaves row [] do
      if path == ["id"] || path == ["note"] then continue
      match verifyRow (mutateAt row path) with
      | .ok () => throw s!"changing {path} of {← str row ["id"]} still verifies"
      | .error _ => count := count + 1
  pure count

def checkTable (j : Json) : Except String (Nat × Nat) := do
  let rows ← match ← field j ["vectors"] with
    | .arr rows => pure rows
    | _ => throw "no vectors"
  unless rows.size == cases.length do throw "vector count differs from the Lean cases"
  for row in rows do verifyRow row
  pure (rows.size, ← fieldControls rows)

/-! ## Singular's independent preimage table -/

def credentialData (c : Json) : Except String (List Nat) := do
  match c with
  | .arr #[.str kind, .str digest] =>
    let index := if kind == "key" then 0 else 1
    pure (constr index [bstr (← ofHex digest)])
  | _ => throw "bad credential"

/-- `Address { payment_credential, stake_credential }`, stake inline or none. -/
def addressData (a : Json) : Except String (List Nat) := do
  let payment ← credentialData (← field a ["payment"])
  let stake ← match ← field a ["stake"] with
    | .null => pure (constr 1 [])
    | s => do pure (constr 0 [constr 0 [← credentialData s]])
  pure (constr 0 [payment, stake])

def registryOf (j : Json) : Except String Singular.TokenId := do
  pure ⟨ofBytes (← ofHex (← str j ["registry", "policy"])), ofBytes (← ofHex (← str j ["registry", "name"]))⟩

def preimageOf (role : String) (i : Json) : Except String AH.Preimage := do
  match role with
  | "state" =>
    let index : Nat ← Lean.fromJson? (← field i ["seed", "outputIndex"])
    pure (.state ⟨ofBytes (← ofHex (← str i ["seed", "transactionId"])), index⟩)
  | "active" => pure (.active (← registryOf i) (ofBytes (← ofHex (← str i ["key"]))))
  | "configuration" => pure (.applicationConfiguration (← registryOf i))
  | "termination-approval" => pure (.terminationApproval (← registryOf i) (ofBytes (← ofHex (← str i ["key"]))))
  | "registration-approval" =>
    let some deposit := (← str i ["deposit"]).toNat? | throw "bad deposit"
    pure (.registrationApproval (← registryOf i) (ofBytes (← ofHex (← str i ["key"])))
      (ofBytes (← addressData (← field i ["holdingAddress"])))
      (ofBytes (← ofHex (← str i ["datumHash"]))) deposit)
  | other => throw s!"unknown role {other}"

/-- Reproduce every preimage and name of Singular's committed table. -/
def checkSingular (j : Json) : Except String Nat := do
  let rows ← match ← field j ["vectors"] with
    | .arr rows => pure rows
    | _ => throw "no vectors"
  for row in rows do
    let id ← str row ["id"]
    let p ← preimageOf (← str row ["role"]) (← field row ["input"])
    unless toHex (code p) == (← str row ["preimage"]) do throw s!"{id}: preimage differs"
    unless toHex (unpack (hash (code p))) == (← str row ["name"]) do throw s!"{id}: name differs"
  pure rows.size

end CardanoKeri.ConsumerIdentity.Bytes.Vectors
