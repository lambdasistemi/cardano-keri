import CardanoKeri.ConsumerJourney

/-! Executable controls use the connected registration as their anchor. Each
candidate change keeps the relying party's context fixed. Finite naming
premises and observation gaps are reported separately from consumer refusals. -/
namespace CardanoKeri.ConsumerIdentity.Witness
open Lean (Json toJson)
open CardanoKeri.Checkpoint SystemWire

/-- An actual full-identity terminal fold, connected to the previous full
registry output and the same economic fold's reference/value observations.
The termination approval is a model token, not a byte encoding claim. -/
def completionIdentity (j : Journey) : Except String SingularApplicationHeld.FoldObservation := do
  let before := j.input.fullFold.after
  let registry := before.identity
  let active := representativeAsset interpretation context
  let approval := SingularApplicationHeld.terminationApproval interpretation.hash interpretation.code
    context.release registry context.aid
  let tx := j.completion.transaction
  let inputs := j.completion.unspent.filter fun item =>
    Singular.inputsContainReference tx.transaction.inputs item.1
  let spent := inputs.map fun item =>
    if item.1 == before.state.reference then before.state else
    SingularApplicationHeld.ObservedOutput.mk item.1 42 item.2.output.lovelace .empty
      (if item.1 == j.booking.request.reference then [(active, 1), (approval, 1)] else [])
  let trie := Singular.trieSet before.trie context.aid (.known .terminal)
  let outputs := tx.outputs.zipIdx.map fun (eo, index) =>
    SingularApplicationHeld.ObservedOutput.mk ⟨tx.identity, index⟩
      (if index == 0 then context.release.statePolicy else eo.output.address.getD 42)
      eo.output.lovelace (if index == 0 then .root (commit trie) else .empty)
      (if index == 0 then [(registry, 1)] else [])
  let some state := outputs[0]? | throw "terminal-state-output-missing"
  let observation : SingularApplicationHeld.FoldObservation := {
    before, after := { before with state, trie },
    assets := {
      spent := tx.transaction.inputs.filterMap (·.ref),
      outputs := outputs.map (fun o => ⟨o.assets⟩),
      mint := [(active, -1), (approval, -1)],
      invoked := [context.release.statePolicy, context.release.applicationPolicy] },
    spentOutputs := spent, outputs, changes := [.terminate j.booking.request.reference context.aid],
    signers := [], interval := ⟨40, 41⟩, fee := tx.transaction.fee, donation := tx.transaction.donation }
  unless SingularApplicationHeld.fold .none interpretation.hash interpretation.code commit context.release observation do
    throw "terminal-full-fold-refused"
  unless moneyAgreementB { j.input with fullFold := observation, unspent := j.completion.unspent, economicTx := tx } do
    throw "terminal-money-disagreement"
  pure observation

def fieldQueries (j : Journey) : List (String × Wire.Query) := Id.run do
  let r := j.registration
  let anchor : Wire.Query := ⟨tables r.checkpoint, context,
    ⟨context.network, some context.release⟩, cp, 7, r.holding⟩
  let active := representativeAsset interpretation context
  let holding := fun assets => { anchor with holding.assets := assets }
  let release := fun r => { anchor with environment.release := some r }
  let rival := fun c => { anchor with holding.assets := [(representativeAsset interpretation c, 1)] }
  let mut rows := [
    ("positive-anchor", anchor),
    ("maturity-minus-one", { anchor with now := 6 }),
    ("maturity-plus-one", { anchor with now := 8 }),
    ("zero-w-birth", { anchor with params.W := 0, now := 2 }),
    ("wrong-policy", holding [(⟨active.policy + 1, active.name⟩, 1)]),
    ("wrong-name", holding [(⟨active.policy, active.name + 1⟩, 1)]),
    ("missing-token", holding []), ("quantity-zero", holding [(active, 0)]),
    ("quantity-two", holding [(active, 2)]), ("duplicate-entries", holding [(active, 1), (active, 1)]),
    ("other-aid-token", rival { context with aid := 12 }),
    ("rival-seed-transaction", rival { context with seed.tx := 92 }),
    ("rival-seed-index", rival { context with seed.index := 1 }),
    ("rival-registry-policy", rival { context with release.statePolicy := 9 }),
    ("wrong-network", { anchor with environment.network := 1 }),
    ("unknown-release", { anchor with environment.release := none }),
    ("release-application-policy", release { context.release with applicationPolicy := 70 }),
    ("release-credential", release { context.release with applicationCredential := 110 }),
    ("release-state-program", release { context.release with stateProgram := 89 }),
    ("release-state-policy", release { context.release with statePolicy := 9 }),
    ("holding-credential", { anchor with holding.credential := 112 }),
    ("datum-empty", { anchor with holding.datum := .empty }),
    ("datum-root", { anchor with holding.datum := .root 0 }),
    ("datum-malformed", { anchor with holding.datum := .application 999 }),
    ("datum-other-aid", { anchor with tables.datums := [(context.release, 711, ⟨12, r.checkpoint⟩)] }),
    ("table-missing-key", { anchor with tables.keys := [] }),
    ("table-missing-code", { anchor with tables.codes := [] }),
    ("table-missing-hash", { anchor with tables.hashes := [] }),
    ("table-ambiguous-key", { anchor with tables.keys := [(11, 11), (11, 12)] })]
  for (name, state) in [("absent-datum", State.absent), ("terminal-datum", State.convicted)] do
    rows := rows ++ [(name, { anchor with tables := tables state })]
  return rows

def terminalControls (j : Journey) : Except String (List (String × Bool)) := do
  let full ← completionIdentity j
  let some association := j.booked.certified.state.pending context.aid | throw "association-missing"
  let (_, after) ← CardanoKeri.Registry.fold j.input.registryParams j.input.registryEnv
    association.booked association.booked.gen association.booked.config.applicationPolicy
    j.completion.unspent j.completion.transaction
  let rebook := CardanoKeri.Registry.Scenarios.registration after context.aid 300
  let reRegistered := do
    let (_, booked) ← CardanoKeri.Registry.bookRegistration j.input.registryParams after rebook
    let (u, tx) ← S.foldTransaction booked [rebook.request.reference] 42 1 1
    CardanoKeri.Registry.fold j.input.registryParams j.input.registryEnv booked booked.gen
      booked.config.applicationPolicy u tx
  pure [
    ("terminal-full-fold-executed", true),
    ("terminal-economics-agree", moneyAgreementB { j.input with
      fullFold := full, unspent := j.completion.unspent, economicTx := j.completion.transaction }),
    ("terminal-no-active-output", full.outputs.all fun o => AH.quantity o (representativeAsset interpretation context) == 0),
    ("terminal-active-burn", SingularApplicationHeld.Assets.mintQty full.assets (representativeAsset interpretation context) == -1),
    ("system-reregistration-refused", (advance j.terminal (registrationCommand j.input)).toOption.isNone),
    ("system-revival-refused", (advance j.terminal (.local context.aid 42 (.reopen 11 42 5))).toOption.isNone),
    ("registry-reregistration-refused", reRegistered.toOption.isNone),
    ("registry-revival-refused", (CardanoKeri.Registry.revive j.input.registryParams j.input.registryEnv after context.aid).toOption.isNone),
    ("repeat-completion-refused", (advance j.terminal (.complete context.aid j.completion)).toOption.isNone),
    ("pending-revival-refused", (advance j.booked (.local context.aid 38 (.reopen 11 42 5))).toOption.isNone)]


def genesisControls (j : Journey) : List (String × Bool) :=
  let q := j.input
  let refuses := fun cfg tx outputs =>
    (createRegistry interpretation context abstractRegistry cfg commit tx outputs).toOption.isNone
  let tx := q.genesisTx
  let os := q.genesisOutputs
  let change := fun f => os.map f
  [ ("genesis-positive", (createRegistry interpretation context abstractRegistry q.configuration commit tx os).toOption.isSome),
    ("genesis-no-seed", refuses q.configuration { tx with spent := [] } os),
    ("genesis-double-seed", refuses q.configuration { tx with spent := [context.seed, context.seed] } os),
    ("genesis-wrong-seed", refuses q.configuration { tx with spent := [⟨92, 0⟩] } os),
    ("genesis-no-invocation", refuses q.configuration { tx with invoked := [] } os),
    ("genesis-wrong-mint", refuses q.configuration { tx with mint := [] } os),
    ("genesis-no-output", refuses q.configuration tx []),
    ("genesis-double-output", refuses q.configuration tx (os ++ os)),
    ("genesis-wrong-credential", refuses q.configuration tx (change fun o => { o with credential := 90 })),
    ("genesis-wrong-policy", refuses q.configuration tx (change fun o => { o with assets := [(⟨90, (registryAsset interpretation context).name⟩, 1)] })),
    ("genesis-wrong-name", refuses q.configuration tx (change fun o => { o with assets := [(⟨8, 99⟩, 1)] })),
    ("genesis-wrong-quantity", refuses q.configuration tx (change fun o => { o with assets := [(registryAsset interpretation context, 2)] })),
    ("genesis-wrong-datum", refuses q.configuration tx (change fun o => { o with datum := .empty })),
    ("genesis-wrong-root", refuses q.configuration tx (change fun o => { o with datum := .root 99 })),
    ("genesis-nonbare", refuses q.configuration tx (change fun o => { o with assets := o.assets ++ [(⟨99, 99⟩, 1)] })),
    ("configuration-registry", refuses { q.configuration with registryId := 99 } tx os),
    ("configuration-application", refuses { q.configuration with applicationPolicy := 99 } tx os),
    ("configuration-active", refuses { q.configuration with activePolicy := 99 } tx os) ]

def finiteEncodingB (code : AH.Codec) (domain : List AH.Preimage) : Bool :=
  domain.all fun p => domain.all fun q => code p != code q || decide (p = q)
def finiteCollisionB (hash : AH.Hash) (code : AH.Codec) (domain : List AH.Preimage) : Bool :=
  domain.all fun p => domain.all fun q => hash (code p) != hash (code q) || code p == code q

def namingControls : List (String × Bool) :=
  let rival := { context with seed.tx := 92 }
  let domain := identityDomain interpretation context rival
  let a := registryAsset interpretation context
  let b := registryAsset interpretation rival
  let faithful := fun (f : Singular.TokenId → Nat) => [a, b].all fun x => [a, b].all fun y =>
    f x != f y || x == y
  [ ("nonempty-distinct-preimage-domain", domain.length == 4 && decide domain.Nodup),
    ("finite-encoding", finiteEncodingB interpretation.code domain),
    ("finite-collision-free", finiteCollisionB interpretation.hash interpretation.code domain),
    ("constant-code-violates-premise", !finiteEncodingB (fun _ => []) domain),
    ("constant-hash-violates-premise", !finiteCollisionB (fun _ => 0) interpretation.code domain),
    ("distinct-aid-keys", interpretation.keyOf 11 != interpretation.keyOf 12),
    ("faithful-registry-map", faithful abstractRegistry),
    ("constant-registry-map-violates-premise", !faithful (fun _ => 9)) ]

def registrationControls (j : Journey) : List (String × Bool) :=
  let q := j.input
  let refuses := fun q => (registerJoint interpretation context abstractRegistry commit q).toOption.isNone
  let correspondenceRefuses := fun q => match registerJoint interpretation context abstractRegistry commit q with
    | .error reason => reason == "registration-correspondence-mismatch"
    | .ok _ => false
  let changedInputs := q.fullFold.spentOutputs.map fun o =>
    if o.reference == q.booking.request.reference then { o with lovelace := o.lovelace + 1 } else o
  let changedOutputs := q.fullFold.outputs.map fun o =>
    if o.assets.isEmpty then { o with lovelace := o.lovelace + 1 } else o
  [ ("registration-positive", (registerJoint interpretation context abstractRegistry commit q).toOption.isSome),
    ("registration-no-holding", refuses { q with holdingIndex := 99 }),
    ("registration-full-fold-required", refuses { q with fullFold.changes := [] }),
    ("registration-fee-correspondence", correspondenceRefuses { q with fullFold.fee := q.fullFold.fee + 1 }),
    ("registration-donation-correspondence", correspondenceRefuses { q with fullFold.donation := q.fullFold.donation + 1 }),
    ("registration-interval-correspondence", correspondenceRefuses { q with fullFold.interval := ⟨9, 10⟩ }),
    ("registration-complete-spent-correspondence", correspondenceRefuses { q with fullFold.assets.spent := q.fullFold.assets.spent ++ [⟨999, 0⟩] }),
    ("registration-spent-value-correspondence", correspondenceRefuses { q with fullFold.spentOutputs := changedInputs }),
    ("registration-output-value-correspondence", correspondenceRefuses { q with fullFold.outputs := changedOutputs }),
    ("registration-checkpoint-datum-correspondence", correspondenceRefuses { q with refund := q.refund + 1 }) ]


/-- The rival is created and registered by the same two actual model folds.
Its own finite reduced identifier allocation does not authenticate it to the
original treasury, whose complete Context stays unchanged. -/
def rivalQuery (j : Journey) : Except String Wire.Query := do
  let rival := { context with seed.tx := 92 }
  let q ← inputFor rival
  let allocation := fun r => if r == registryAsset interpretation rival then 9 else r.name + 100
  let r ← registerJoint interpretation rival allocation commit q
  pure ⟨tables j.registration.checkpoint, context,
    ⟨context.network, some context.release⟩, cp, 7, r.holding⟩

/-- Real unrelated and mixed folds, beginning at this journey's actual stored
association. The foreign fold is valid but cannot complete Alice; the mixed
fold consumes her exact recorded pending request. -/
def associationEvents (j : Journey) : Except String (List Json) := do
  let some a := j.booked.certified.state.pending context.aid | throw "association-missing"
  let apply := fun s action => do
    let (_, next) ← CardanoKeri.Registry.stepFn j.input.registryParams j.input.registryEnv action s
    pure next
  let b := CardanoKeri.Registry.Scenarios.registration a.booked 12 101
  let s1 ← apply a.booked (.bookRegistration b)
  let (u, tx) ← S.foldTransaction s1 [b.request.reference] 2 1 1
  let foldAction : CardanoKeri.Registry.Action := .fold s1.gen s1.config.applicationPolicy u tx
  let s2 ← apply s1 foldAction
  let s3 ← apply s2 (.convictCkpt 12)
  let b2 ← CardanoKeri.Registry.Scenarios.termination s3 12 201
  let s4 ← apply s3 (.bookTermination 12 7 1 b2)
  let history := [.bookRegistration b, foldAction, .convictCkpt 12, .bookTermination 12 7 1 b2]
  let (fu, ft) ← S.foldTransaction s4 [b2.request.reference] 40 1 1
  let (mu, mt) ← S.foldTransaction s4 [j.booking.request.reference, b2.request.reference] 40 1 1
  let foreign : Command := .complete context.aid ⟨history, fu, ft⟩
  let mixed : Command := .complete context.aid ⟨history, mu, mt⟩
  -- Execute the valid economic foreign fold independently before checking the association refusal.
  let _ ← CardanoKeri.Registry.fold j.input.registryParams j.input.registryEnv s4 s4.gen s4.config.applicationPolicy fu ft
  unless (advance j.booked foreign).toOption.isNone do throw "foreign-completion-accepted"
  let terminal ← advance j.booked mixed
  unless decide (terminal.certified.state.states context.aid = .convicted) do throw "mixed-completion-not-terminal"
  pure [(SystemWire.cell "valid-foreign-fold-refused" cp evidence j.booked foreign).1,
    (SystemWire.cell "mixed-fold-completes-recorded-request" cp evidence j.booked mixed).1]

end CardanoKeri.ConsumerIdentity.Witness
