import CardanoKeri.ReaderStatus
import CardanoKeri.CheckpointDatumVectors

/-! Vectors of the reader's status (#353).

One context (the transferable identifier of `consumer-identity-vectors.json`
in its base registry) and, per row, the evidence a reader holds and the answer
the Lean classifier gives: the status, the custody it read, the leaf it
replayed from the registry's history, the holder it names and, for that
holder, the consumer predicate's verdict. The
interpretation is the concrete one: the identity bytes of #489 and the version
2 datum decoder of #498, so outputs carry real asset names and datum bytes.

A chain point is an identity; rows use small numbers. The checks run the
actual classifier; they are evidence over the listed rows, not a proof over
all evidence. -/
namespace CardanoKeri.ReaderStatus.Vectors
open Lean (Json toJson)
open CardanoKeri.Checkpoint
open CardanoKeri.ConsumerIdentity
open CardanoKeri.ConsumerIdentity.Bytes
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (toHex ofHex field str policyHex txHex aidE aidE2 aidB)
open CardanoKeri.CheckpointDatum
open CardanoKeri.CheckpointDatum.Vectors (simpleKeys refundBytes natJson hexJson)

/-! ## The context -/

/-- Twenty-eight bytes of a script hash or credential. -/
def hash28 (seed : Nat) : List Nat := (List.range 28).map fun n => (seed * 17 + n * 5) % 256

/-- A 32-byte transaction id. -/
def txId (seed : Nat) : List Nat := (List.range 32).map fun n => (seed * 13 + n * 3) % 256

def release (statePolicy : Nat) : AH.PublishedRelease :=
  { applicationPolicy := pack (hash28 1), applicationCredential := pack (hash28 2),
    stateProgram := pack (hash28 3), statePolicy := statePolicy }

/-- The context of every row: the base registry of the identity vectors and
their transferable identifier, with a full release and checkpoint credential. -/
def contextFor (aid : String) : Except String Context := do
  let base ← ConsumerIdentity.Bytes.Vectors.context ⟨policyHex, txHex, 0, aid⟩
  pure { base with release := release base.release.statePolicy,
                   checkpointCredential := pack (hash28 4) }

def params : Params := { D := 3, B := 2, P := 1, W := 10, hD := by decide, hB := by decide }

def i : Interpretation := CheckpointDatum.interpretation

/-! ## Outputs and observations -/

def refund : Addr := pack (refundBytes 57)

def mature : Live := ⟨7, 3, false, false, 100, refund, 0, false⟩

/-- A checkpoint output of `c` carrying the datum of `state` written for `aid`. -/
def checkpointOutput (c : Context) (aid : AID) (state : State) (tx : Nat) :
    Except String AH.ObservedOutput := do
  let some d := datum aid simpleKeys state | throw "no datum for this state"
  pure { reference := ⟨pack (txId tx), 0⟩, credential := c.checkpointCredential,
         lovelace := 5000000, datum := .application (raw d),
         assets := [(representativeAsset i c, 1)] }

/-- The termination request of `c`'s key. -/
def requestOutput (c : Context) (tx : Nat) : AH.ObservedOutput :=
  { reference := ⟨pack (txId tx), 1⟩, credential := c.release.applicationCredential,
    lovelace := 2000000, datum := .empty,
    assets := [(representativeAsset i c, 1),
      (SingularApplicationHeld.terminationApproval i.hash i.code c.release (registryAsset i c)
        (i.keyOf c.aid), 1)] }

def environment (c : Context) : Environment :=
  { network := c.network, release := some c.release,
    checkpointCredential := some c.checkpointCredential }

/-- The point every row asks at, and another point. -/
def here : ChainPoint := 7001
def elsewhere : ChainPoint := 6990

def holdingAt (c : Context) (holders : List AH.ObservedOutput) : HoldingObservation :=
  { point := here, asset := representativeAsset i c, holders }

/-- A registration of `key`, from the request `n`. -/
def registers (key : Singular.Key) (n : Nat) : SingularApplicationHeld.Change :=
  .register ⟨pack (txId (40 + n)), 0⟩ key 1 5000000

/-- A termination of `key`, from the request `n`. -/
def terminates (key : Singular.Key) (n : Nat) : SingularApplicationHeld.Change :=
  .terminate ⟨pack (txId (60 + n)), 1⟩ key

/-- A complete history of `c`'s registry through the asked point. -/
def historyAt (c : Context) (folds : List (List SingularApplicationHeld.Change)) :
    HistoryObservation :=
  { point := here, registry := registryAsset i c, complete := true, folds }

structure Case where
  id : String
  note : String
  now : Slot
  evidence : Evidence

def cases : Except String (List Case) := do
  let c ← contextFor aidE
  let other ← contextFor aidE2
  let third ← contextFor aidB
  let rival ← ConsumerIdentity.Bytes.Vectors.context ⟨policyHex, txHex, 1, aidE⟩
  let live ← checkpointOutput c c.aid (.present mature) 1
  let frozen ← checkpointOutput c c.aid (.present { mature with frozen := true }) 1
  let poisoned ← checkpointOutput c c.aid (.present { mature with poisoned := true }) 1
  let convicted ← checkpointOutput c c.aid (.terminationPending ⟨3, 7⟩) 2
  let request := requestOutput c 3
  let foreignDatum ← checkpointOutput c other.aid (.present mature) 1
  let foreignPending ← checkpointOutput c other.aid (.terminationPending ⟨3, 7⟩) 2
  let k := i.keyOf c.aid
  let k2 := i.keyOf other.aid
  let k3 := i.keyOf third.aid
  -- Histories of the registry: the other identifier registered first in each.
  let unknownHistory := [[registers k2 1], [terminates k2 4]]
  let activeHistory := [[registers k2 1], [registers k 2]]
  let terminalHistory := [[registers k2 1], [registers k 2], [registers k3 7, terminates k 3]]
  let ev (holding : Option HoldingObservation) (history : Option HistoryObservation) : Evidence :=
    { point := here, environment := environment c, holding, history }
  let held (os : List AH.ObservedOutput) := some (holdingAt c os)
  let told (folds : List (List SingularApplicationHeld.Change)) := some (historyAt c folds)
  let row (id note : String) (evidence : Evidence) (now : Slot := 200) : Case :=
    { id, note, now, evidence }
  pure [
    row "active-holding-only" "one live checkpoint holds the asset; no history"
      (ev (held [live]) none),
    row "active-with-history" "one live checkpoint holds the asset and the history registers the key"
      (ev (held [live]) (told activeHistory)),
    row "active-young" "a live checkpoint read before its juvenility window ends: active, not eligible"
      (ev (held [live]) none) 105,
    row "active-frozen" "a live checkpoint whose bond is frozen: active, not eligible"
      (ev (held [frozen]) none),
    row "active-poisoned" "a live checkpoint its current keys have poisoned: active, not eligible"
      (ev (held [poisoned]) none),
    row "active-history-observed-elsewhere" "a live checkpoint here and a history through another point that terminates the key: the history establishes nothing here"
      (ev (held [live]) (some { historyAt c terminalHistory with point := elsewhere })),
    row "pending-convicted" "the convicted checkpoint holds the asset; no history"
      (ev (held [convicted]) none),
    row "pending-convicted-with-history" "the convicted checkpoint holds the asset and the history registers the key"
      (ev (held [convicted]) (told activeHistory)),
    row "pending-requested" "the termination request holds the asset; no history"
      (ev (held [request]) none),
    row "pending-requested-with-history" "the termination request holds the asset and the history registers the key"
      (ev (held [request]) (told activeHistory)),
    row "active-incomplete-history" "a live checkpoint and a history that misses the fold that registered the key: the holder decides alone"
      (ev (held [live]) (some { historyAt c [[registers k2 1]] with complete := false })),
    row "active-incomplete-history-unreplayable" "a live checkpoint and a history that starts after the registration, so its first fold terminates a key it never saw registered: not complete, so a gap and not a contradiction"
      (ev (held [live]) (some { historyAt c [[terminates k2 4]] with complete := false })),
    row "pending-requested-incomplete-history" "the termination request and a history that is not complete: the holder decides alone"
      (ev (held [request]) (some { historyAt c [[registers k2 1]] with complete := false })),
    row "terminal-history-and-no-holder" "the history registers the key and a later fold terminates it beside another registration; no output holds the asset"
      (ev (held []) (told terminalHistory)),
    row "terminal-history-only" "the history terminates the key; no holding observation"
      (ev none (told terminalHistory)),
    row "terminal-holding-observed-elsewhere" "the history terminates the key here and a live checkpoint was seen at another point: the holding establishes nothing here"
      (ev (some { holdingAt c [live] with point := elsewhere }) (told terminalHistory)),
    row "never-registered-history-and-no-holder" "the history registers and terminates another identifier only; no output holds the asset"
      (ev (held []) (told unknownHistory)),
    row "never-registered-history-only" "the history never names the key; no holding observation"
      (ev none (told unknownHistory)),
    row "never-registered-no-fold" "the registry was created and has no fold yet; no output holds the asset"
      (ev (held []) (told [])),
    row "no-evidence" "neither observation is established" (ev none none),
    row "missing-token-alone" "no output holds the asset and no history is established: neither terminal nor never registered"
      (ev (held []) none),
    row "wrong-network" "a live checkpoint, on another network than the context's"
      { ev (held [live]) none with environment := { environment c with network := 1 } },
    row "unknown-release" "a live checkpoint, the release unresolved"
      { ev (held [live]) none with environment := { environment c with release := none } },
    row "other-release" "a live checkpoint, another release resolved"
      { ev (held [live]) none with environment :=
          { environment c with release := some { c.release with applicationPolicy := pack (hash28 9) } } },
    row "unresolved-checkpoint-credential" "a live checkpoint, the checkpoint credential unresolved"
      { ev (held [live]) none with environment := { environment c with checkpointCredential := none } },
    row "holding-observed-elsewhere" "a live checkpoint seen at another point than the asked one"
      (ev (some { holdingAt c [live] with point := elsewhere }) none),
    row "holding-of-another-asset" "the holders of another registry's asset for the same identifier"
      (ev (some { holdingAt c [live] with asset := representativeAsset i rival }) none),
    row "history-observed-elsewhere" "no holder here and a history through another point that terminates the key"
      (ev (held []) (some { historyAt c terminalHistory with point := elsewhere })),
    row "history-of-another-registry" "no holder here and the history of another registry that terminates the key"
      (ev (held []) (some { historyAt c terminalHistory with registry := registryAsset i rival })),
    row "history-starting-late" "no holder here and a history that misses the fold that registered the key: not complete"
      (ev (held []) (some { historyAt c [[registers k2 1]] with complete := false })),
    row "history-missing-a-fold" "no holder here and a history without the fold that terminated the key: not complete"
      (ev (held []) (some { historyAt c activeHistory with complete := false })),
    row "history-terminating-an-unregistered-key" "no holder here and a history whose first fold terminates the key: no accepted fold does that"
      (ev (held []) (told [[registers k2 1], [terminates k 3]])),
    row "history-registering-twice" "no holder here and a history that registers the key twice before terminating it"
      (ev (held []) (told [[registers k 2], [registers k 5], [terminates k 3]])),
    row "history-terminating-twice" "no holder here and a history that terminates the key twice"
      (ev (held []) (told [[registers k 2], [terminates k 3], [terminates k 6]])),
    row "history-registering-a-terminal-key" "a history that registers the key again after terminating it"
      (ev (held []) (told [[registers k 2], [terminates k 3], [registers k 5]])),
    row "history-with-an-empty-fold" "no holder here and a history with a fold that makes no change"
      (ev (held []) (told [[registers k 2], [], [terminates k 3]])),
    row "live-holder-broken-history" "a live checkpoint beside a complete history whose replay fails: a contradiction, whatever the holder shows"
      (ev (held [live]) (told [[registers k2 1], [terminates k 3]])),
    row "request-holder-broken-history" "the termination request beside a complete history that registers the key twice"
      (ev (held [request]) (told [[registers k 2], [registers k 5]])),
    row "two-holders" "two outputs hold the asset"
      (ev (held [live, { live with reference := ⟨pack (txId 4), 0⟩ }]) none),
    row "holder-quantity-two" "the one holder holds the asset twice"
      (ev (held [{ live with assets := [(representativeAsset i c, 2)] }]) none),
    row "holder-of-another-asset" "the one listed holder holds another registry's asset, not this one"
      (ev (held [{ live with assets := [(representativeAsset i rival, 1)] }]) none),
    row "holder-at-another-credential" "a live datum and the asset, not at the checkpoint credential"
      (ev (held [{ live with credential := pack (hash28 7) }]) none),
    row "holder-malformed-datum" "the holder's datum is a checkpoint datum missing its last byte"
      (ev (held [{ live with datum := match live.datum with
        | .application r => .application (pack (unpack r).dropLast)
        | d => d }]) none),
    row "holder-without-datum" "the holder at the checkpoint credential carries no datum"
      (ev (held [{ live with datum := .empty }]) none),
    row "holder-of-another-identifier" "the holder's datum is a live datum of another identifier"
      (ev (held [foreignDatum]) none),
    row "convicted-holder-of-another-identifier" "the holder's datum is a pending-termination datum of another identifier"
      (ev (held [foreignPending]) none),
    row "request-with-another-approval" "the termination request's shape with the approval of another identifier's key"
      (ev (held [{ request with assets := [(representativeAsset i c, 1),
        (SingularApplicationHeld.terminationApproval i.hash i.code c.release (registryAsset i c)
          k2, 1)] }]) none),
    row "request-without-approval" "an output at the application credential with the asset and no termination approval"
      (ev (held [{ request with assets := [(representativeAsset i c, 1)] }]) none),
    row "request-with-datum" "the termination request's assets under a datum"
      (ev (held [{ request with datum := live.datum }]) none),
    row "request-at-another-credential" "the termination request's shape, not at the application credential"
      (ev (held [{ request with credential := pack (hash28 7) }]) none),
    row "live-holder-terminal-history" "a live checkpoint against a history that terminates the key"
      (ev (held [live]) (told terminalHistory)),
    row "live-holder-unregistered-history" "a live checkpoint against a history that never registers the key"
      (ev (held [live]) (told unknownHistory)),
    row "convicted-holder-terminal-history" "the convicted checkpoint against a history that terminates the key"
      (ev (held [convicted]) (told terminalHistory)),
    row "request-holder-terminal-history" "the termination request against a history that terminates the key"
      (ev (held [request]) (told terminalHistory)),
    row "registered-history-and-no-holder" "the history registers the key and never terminates it, and no output holds the asset"
      (ev (held []) (told activeHistory)),
    row "registered-history-only" "the history registers the key; no holding observation: live or pending is not decided"
      (ev none (told activeHistory))]

/-! ## Rendering -/

def tokenJson (t : Singular.TokenId) : Json :=
  Json.mkObj [("policy", hexJson (unpack t.policy)), ("name", hexJson (unpack t.name))]

def referenceJson (r : Singular.OutRef) : Json :=
  Json.mkObj [("transactionId", hexJson (unpack r.tx)), ("outputIndex", natJson r.index)]

def releaseJson (r : AH.PublishedRelease) : Json := Json.mkObj [
  ("applicationPolicy", hexJson (unpack r.applicationPolicy)),
  ("applicationCredential", hexJson (unpack r.applicationCredential)),
  ("stateProgram", hexJson (unpack r.stateProgram)),
  ("statePolicy", hexJson (unpack r.statePolicy))]

def datumJson : SingularApplicationHeld.OutputDatum → Json
  | .application r => Json.mkObj [("application", hexJson (unpack r))]
  | .empty => toJson "empty"
  | .root r => Json.mkObj [("root", natJson r)]
  | .configuration _ => toJson "configuration"

def outputJson (o : AH.ObservedOutput) : Json := Json.mkObj [
  ("reference", referenceJson o.reference), ("credential", hexJson (unpack o.credential)),
  ("lovelace", natJson o.lovelace), ("datum", datumJson o.datum),
  ("assets", Json.arr (o.assets.map fun (t, q) => Json.mkObj [
    ("policy", hexJson (unpack t.policy)), ("name", hexJson (unpack t.name)),
    ("quantity", natJson q)]).toArray)]

def leafJson : Singular.Leaf → Json
  | .unknown => "unknown"
  | .known .active => "active"
  | .known .terminal => "terminal"
  | .known .absent => "absent"

def statusJson (status : Status) : Json := toJson status.word

def custodyJson : Custody → Json
  | .notEstablished => "not-established"
  | .absent => "absent"
  | .live l => Json.mkObj [("live", Json.mkObj [("sn", natJson l.sn), ("epoch", natJson l.epoch),
      ("poisoned", toJson l.poisoned), ("frozen", toJson l.frozen), ("bornAt", natJson l.bornAt),
      ("refundTo", hexJson (unpack l.refundTo)), ("toppedUp", toJson l.toppedUp)])]
  | .convicted h => Json.mkObj [("convicted", Json.mkObj [("sn", natJson h.sn),
      ("epoch", natJson h.epoch)])]
  | .request => "request"
  | .inconsistent => "inconsistent"

def optionJson {α : Type} (f : α → Json) : Option α → Json
  | some a => f a
  | none => Json.null

def environmentJson (e : Environment) : Json := Json.mkObj [
  ("network", natJson e.network), ("release", optionJson releaseJson e.release),
  ("checkpointCredential", optionJson (fun n => hexJson (unpack n)) e.checkpointCredential)]

def changeJson : SingularApplicationHeld.Change → Json
  | .register reference key index deposit => Json.mkObj [("register", Json.mkObj [
      ("requestReference", referenceJson reference), ("key", hexJson (unpack key)),
      ("holdingIndex", natJson index), ("approvedDeposit", natJson deposit)])]
  | .terminate reference key => Json.mkObj [("terminate", Json.mkObj [
      ("requestReference", referenceJson reference), ("key", hexJson (unpack key))])]

def evidenceJson (ev : Evidence) : Json := Json.mkObj [
  ("point", natJson ev.point), ("environment", environmentJson ev.environment),
  ("holding", optionJson (fun h => Json.mkObj [("point", natJson h.point),
    ("asset", tokenJson h.asset), ("holders", Json.arr (h.holders.map outputJson).toArray)])
    ev.holding),
  ("history", optionJson (fun h => Json.mkObj [("point", natJson h.point),
    ("registry", tokenJson h.registry), ("complete", toJson h.complete),
    ("folds", Json.arr (h.folds.map fun changes =>
      Json.arr (changes.map changeJson).toArray).toArray)]) ev.history)]

def contextJson (aid : String) (c : Context) : Json := Json.mkObj [
  ("network", natJson c.network), ("release", releaseJson c.release),
  ("seed", referenceJson c.seed), ("aid", toJson aid),
  ("checkpointCredential", hexJson (unpack c.checkpointCredential))]

/-- The reader's answer on one evidence value: the status, the two readings,
the holder it names and the consumer predicate's verdict on that holder. -/
def answerJson (c : Context) (now : Slot) (ev : Evidence) : Json := Json.mkObj [
  ("status", statusJson (classify i c ev)),
  ("custody", custodyJson (holdingCustody i c ev)),
  ("leaf", if brokenHistory i c ev then toJson "broken"
    else optionJson leafJson (establishedLeaf i c ev)),
  ("holder", optionJson (fun o => referenceJson o.reference) (holder i c ev)),
  ("eligible", optionJson (fun o => toJson (consumableHoldingB i c ev.environment params now o))
    (holder i c ev))]

def rowJson (c : Context) (k : Case) : Json := Json.mkObj [
  ("id", toJson k.id), ("note", toJson k.note), ("now", natJson k.now),
  ("evidence", evidenceJson k.evidence), ("answer", answerJson c k.now k.evidence)]

def table : Except String Json := do
  let c ← contextFor aidE
  let rows := (← cases).map (rowJson c)
  pure (Json.mkObj [
    ("description", toJson ("Vectors of the reader's status: for one context, the evidence a reader " ++
      "holds at a chain point and the answer: one of five statuses, the custody read, the leaf " ++
      "replayed from the registry's history, the holder named and the consumer predicate's verdict " ++
      "on that holder.")),
    ("model", toJson "lean/CardanoKeri/ReaderStatus.lean"),
    ("identity", toJson "lean/consumer-identity-vectors.json: state policy, seed and the representative asset of the identifier"),
    ("datums", toJson "lean/checkpoint-datum-vectors.json: the version 2 checkpoint datum layout"),
    ("singular", toJson "d69ab005c3b710aeebf033d3c5cd08c56feb5643"),
    ("layout", Json.mkObj [
      ("point", toJson "the identity of a chain point; compared for equality only, never ordered or subtracted"),
      ("holding", toJson "null when not established; otherwise every unspent output holding the named asset at the named point"),
      ("history", toJson "null when the reader holds none; otherwise the named registry's folds through the named point, in order from its creation, each fold the list of its changes (register or terminate, with the request reference and the key); complete is false for a history that starts late or misses a fold"),
      ("answer.leaf", toJson "the leaf of the identifier's key replayed from a complete history: unknown, active or terminal; broken when a complete history fails its replay, which makes the answer unavailable; null when no leaf is established"),
      ("datum", toJson "empty, or the inline datum bytes of an application datum"),
      ("answer.custody", toJson "not-established, absent, live with the datum facts, convicted with the key state, request or inconsistent"),
      ("answer.holder", toJson "the reference of the one recognised holder, or null"),
      ("answer.eligible", toJson "the consumer predicate on that holder at the row's slot, or null")]),
    ("context", contextJson aidE c),
    ("derived", Json.mkObj [
      ("key", hexJson (unpack (i.keyOf c.aid))),
      ("registryAsset", tokenJson (registryAsset i c)),
      ("representativeAsset", tokenJson (representativeAsset i c)),
      ("terminationApproval", tokenJson (SingularApplicationHeld.terminationApproval i.hash i.code
        c.release (registryAsset i c) (i.keyOf c.aid)))]),
    ("params", Json.mkObj [("W", natJson params.W)]),
    ("statuses", toJson ([Status.active, .pendingTermination, .terminal, .neverRegistered,
      .unavailable].map Status.word)),
    ("rows", Json.arr rows.toArray)])

/-! ## Reading a scenario -/

def natOf (j : Json) (path : List String) : Except String Nat := do
  match ← field j path with
  | .str text => match text.toNat? with
    | some n => pure n
    | none => throw s!"not-a-number {path}"
  | n => Lean.fromJson? n

def bytesOf (j : Json) (path : List String) : Except String Nat := do
  pure (pack (← ofHex (← str j path)))

def tokenOf (j : Json) (path : List String) : Except String Singular.TokenId := do
  pure ⟨← bytesOf j (path ++ ["policy"]), ← bytesOf j (path ++ ["name"])⟩

def referenceOf (j : Json) (path : List String) : Except String Singular.OutRef := do
  pure ⟨← bytesOf j (path ++ ["transactionId"]), ← natOf j (path ++ ["outputIndex"])⟩

def releaseOf (j : Json) : Except String AH.PublishedRelease := do
  pure { applicationPolicy := ← bytesOf j ["applicationPolicy"],
         applicationCredential := ← bytesOf j ["applicationCredential"],
         stateProgram := ← bytesOf j ["stateProgram"], statePolicy := ← bytesOf j ["statePolicy"] }

def optionOf {α : Type} (j : Json) (path : List String) (f : Json → Except String α) :
    Except String (Option α) := do
  match ← field j path with
  | .null => pure none
  | found => pure (some (← f found))

def datumOf (j : Json) : Except String SingularApplicationHeld.OutputDatum := do
  match j with
  | .str "empty" => pure .empty
  | found => pure (.application (← bytesOf found ["application"]))

def outputOf (j : Json) : Except String AH.ObservedOutput := do
  let assets ← match ← field j ["assets"] with
    | .arr entries => entries.toList.mapM fun e => do
        pure ((← tokenOf e []), ← natOf e ["quantity"])
    | _ => throw "assets-not-a-list"
  pure { reference := ← referenceOf j ["reference"], credential := ← bytesOf j ["credential"],
         lovelace := ← natOf j ["lovelace"], datum := ← datumOf (← field j ["datum"]), assets }

def changeOf (j : Json) : Except String SingularApplicationHeld.Change := do
  match j.getObjVal? "register", j.getObjVal? "terminate" with
  | .ok r, .error _ => pure (.register (← referenceOf r ["requestReference"]) (← bytesOf r ["key"])
      (← natOf r ["holdingIndex"]) (← natOf r ["approvedDeposit"]))
  | .error _, .ok t => pure (.terminate (← referenceOf t ["requestReference"]) (← bytesOf t ["key"]))
  | _, _ => throw "change-neither-register-nor-terminate"

def evidenceOf (j : Json) : Except String Evidence := do
  let environment : Environment := {
    network := ← natOf j ["environment", "network"],
    release := ← optionOf j ["environment", "release"] releaseOf,
    checkpointCredential := ← optionOf j ["environment", "checkpointCredential"]
      fun found => do pure (pack (← ofHex (← str found []))) }
  let holding ← optionOf j ["holding"] fun h => do
    let holders ← match ← field h ["holders"] with
      | .arr entries => entries.toList.mapM outputOf
      | _ => throw "holders-not-a-list"
    pure ({ point := ← natOf h ["point"], asset := ← tokenOf h ["asset"], holders } :
      HoldingObservation)
  let history ← optionOf j ["history"] fun h => do
    let folds ← match ← field h ["folds"] with
      | .arr entries => entries.toList.mapM fun fold => match fold with
        | .arr changes => changes.toList.mapM changeOf
        | _ => throw "fold-not-a-list"
      | _ => throw "folds-not-a-list"
    let complete : Bool ← Lean.fromJson? (← field h ["complete"])
    pure ({ point := ← natOf h ["point"], registry := ← tokenOf h ["registry"], complete, folds } :
      HistoryObservation)
  pure { point := ← natOf j ["point"], environment, holding, history }

def contextOf (j : Json) : Except String Context := do
  let aid ← str j ["aid"]
  unless ConsumerIdentity.Bytes.Vectors.qualifiedAid aid do throw s!"not-a-qualified-aid {aid}"
  pure { network := ← natOf j ["network"], release := ← releaseOf (← field j ["release"]),
         seed := ← referenceOf j ["seed"], aid := aidOfCesr aid,
         checkpointCredential := ← bytesOf j ["checkpointCredential"] }

/-- Answer one scenario: `{context, now, evidence}`, in the layout of the
table. The juvenility window is the table's. -/
def run (j : Json) : Except String Json := do
  pure (answerJson (← contextOf (← field j ["context"])) (← natOf j ["now"])
    (← evidenceOf (← field j ["evidence"])))

/-! ## Checking a committed table -/

def rowsOf (j : Json) : Except String (Array Json) := do
  match ← field j ["rows"] with
  | .arr a => pure a
  | _ => throw "no rows"

/-- The classifier's answer on the row's own committed evidence equals the
row's committed answer. -/
def answersRow (c : Context) (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let ev ← evidenceOf (← field row ["evidence"])
  unless answerJson c (← natOf row ["now"]) ev == (← field row ["answer"]) do
    throw s!"{id}: the committed evidence does not get the committed answer"

/-- A committed row equals the Lean's row of its id, and its own committed
evidence gets its committed answer. -/
def verifyRow (c : Context) (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some k := (← cases).find? (·.id == id) | throw s!"{id}: no such case"
  unless row == rowJson c k do throw s!"{id}: differs from the Lean's row"
  answersRow c row

/-- Every leaf of every committed row except the free-text `id` and `note`,
changed in turn, must fail its row's verification. -/
def fieldControls (c : Context) (rs : Array Json) : Except String Nat := do
  let mut count := 0
  for row in rs do
    for path in CheckpointDatum.Vectors.leaves row [] do
      if path == ["id"] || path == ["note"] then continue
      match verifyRow c (CheckpointDatum.Vectors.mutateAt row path) with
      | .ok () => throw s!"changing {path} of {← str row ["id"]} still verifies"
      | .error _ => count := count + 1
  pure count

/-- The rows of each status, which must each be at least one. -/
def statusCounts (rs : Array Json) : Except String (List (String × Nat)) := do
  let names := [Status.active, .pendingTermination, .terminal, .neverRegistered,
    .unavailable].map Status.word
  let counted ← names.mapM fun name => do
    let n := (← rs.toList.filterM fun row => do pure ((← str row ["answer", "status"]) == name)).length
    if n == 0 then throw s!"no row is answered {name}"
    pure (name, n)
  unless (counted.map (·.2)).sum == rs.size do throw "a row has a status outside the five"
  pure counted

def checkTable (j : Json) : Except String (Nat × List (String × Nat) × Nat) := do
  let committed ← rowsOf j
  unless j == (← table) do throw "committed table differs from the Lean's table"
  let c ← contextOf (← field j ["context"])
  unless decide (c = (← contextFor aidE)) do throw "the committed context does not read back"
  unless committed.size == (← cases).length do throw "row count differs from the Lean cases"
  for row in committed do verifyRow c row
  pure (committed.size, ← statusCounts committed, ← fieldControls c committed)

end CardanoKeri.ReaderStatus.Vectors
