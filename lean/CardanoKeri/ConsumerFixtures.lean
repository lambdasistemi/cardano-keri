import CardanoKeri.ConsumerIdentity
import CardanoKeri.CheckpointSystemFixtures
import CardanoKeri.RegistryScenarioFixtures

/-! Connected model fixture. Structural naturals, not Plutus bytes,
cryptography, a KERI datum codec or ledger execution. Both imported folds run.
The separate Checkpoint and Registry money abstractions remain unchanged. -/
namespace CardanoKeri.ConsumerIdentity.Witness
open CardanoKeri.Checkpoint
namespace R
export CardanoKeri.Registry (Sys bookRegistration bindingAt)
end R
namespace S
export CardanoKeri.Registry.Scenarios (p cfg env registration foldTransaction)
end S

def cp : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def evidence : TraceWire.EnvTable := {
  rotationTo := (List.range 12).map fun n => (n, n, n + 1)
  intentAuthorized := (List.range 13).flatMap fun n => [(n, .deposit, none), (n, .close 6, none)]
  quorum := List.range 13
  duplicityAt := (List.range 13).map fun n => (n, n) }
def ce : Env := evidence.toEnv
def registryEnvironment : CardanoKeri.Registry.TraceWire.EnvTable := {
  inception := [11, 12, 13], rotationFrom := [(11, 1)], closeAuth := [(11, 6)],
  duplicity := [11, 12, 13].flatMap fun aid => (List.range 13).map fun n => (aid, n) }
def context : Context := {
  network := 0
  release := { applicationPolicy := 7, applicationCredential := 111, stateProgram := 88, statePolicy := 8 },
  seed := ⟨91, 0⟩, aid := 11 }
def fixtureCodec : AH.Codec
  | .state seed => [0, seed.tx, seed.index]
  | .active registry key => [1, registry.policy, registry.name, key]
  | .applicationConfiguration registry => [2, registry.policy, registry.name]
  | .registrationApproval registry key address datum deposit =>
    [3, registry.policy, registry.name, key, address, datum, deposit]
  | .terminationApproval registry key => [4, registry.policy, registry.name, key]
def interpretation : Interpretation := {
  hash := fun xs => xs.foldl (fun acc n => acc * 1000003 + n + 1) 0
  code := fixtureCodec
  keyOf := id
  decode := fun release raw => if release == context.release && raw == 711 then
    some ⟨11, .present ⟨0, 0, false, false, 2, 42, 5⟩⟩ else none }
def abstractRegistry (r : Singular.TokenId) : Nat :=
  if r == registryAsset interpretation context then 9 else r.name + 100
-- Finite witness interpretation only, not a cryptographic root implementation.
def commit : SingularApplicationHeld.TrieCommit := List.length

def inputFor (context : Context) : Except String RegistrationInput := do
  let initial := CardanoKeri.Registry.Sys.init S.cfg
  let booking := S.registration initial 11 100
  let (_, booked) ← R.bookRegistration S.p initial booking
  let (u, tx) ← S.foldTransaction booked [booking.request.reference] 2 1 1
  let registry := registryAsset interpretation context
  let active := representativeAsset interpretation context
  let approval := SingularApplicationHeld.registrationApproval interpretation.hash interpretation.code
    context.release registry 11 booking.request.destination 711 booking.request.carrierAda
  let some stateInput := u.find? (fun item => item.2.output.role == .state)
    | throw "fixture-no-economic-state"
  let genesisOutput : AH.ObservedOutput := {
    reference := stateInput.1, credential := context.release.statePolicy,
    lovelace := stateInput.2.output.lovelace, datum := .root (commit []), assets := [(registry, 1)] }
  let genesisTx : SingularApplicationHeld.Assets.TxView := {
    spent := [context.seed], outputs := [⟨genesisOutput.assets⟩],
    mint := [(registry, 1)], invoked := [context.release.statePolicy] }
  let fullInputs := (u.filter fun item => Singular.inputsContainReference tx.transaction.inputs item.1).map fun item =>
    if item.1 == stateInput.1 then genesisOutput else
    SingularApplicationHeld.ObservedOutput.mk item.1 42 item.2.output.lovelace .empty
      (if item.1 == booking.request.reference then [(approval, 1)] else [])
  let nextTrie := Singular.trieSet [] 11 (.known .active)
  let fullOutputs := tx.outputs.zipIdx.map fun (eo, index) =>
    SingularApplicationHeld.ObservedOutput.mk ⟨tx.identity, index⟩
      (if index == 0 then context.release.statePolicy else eo.output.address.getD 42)
      eo.output.lovelace
      (if index == 0 then .root (commit nextTrie) else
        if index == 1 then .application 711 else .empty)
      (if index == 0 then [(registry, 1)] else if index == 1 then [(active, 1)] else [])
  let some stateAfter := fullOutputs[0]? | throw "fixture-state-output-missing"
  let before : SingularApplicationHeld.PublicRegistry := {
    identity := registry, seed := context.seed, state := genesisOutput, trie := [] }
  let fullFold : SingularApplicationHeld.FoldObservation := {
    before := before, after := { before with state := stateAfter, trie := nextTrie },
    assets := {
      spent := tx.transaction.inputs.filterMap (·.ref),
      outputs := fullOutputs.map (fun o => ⟨o.assets⟩), mint := [(active, 1), (approval, -1)],
      invoked := [context.release.statePolicy, context.release.applicationPolicy] },
    spentOutputs := fullInputs, outputs := fullOutputs,
    changes := [.register booking.request.reference 11 1 booking.request.carrierAda],
    signers := [], interval := ⟨2, 3⟩, fee := tx.transaction.fee, donation := tx.transaction.donation }
  pure {
    registryParams := S.p, registryEnv := registryEnvironment.toEnv, configuration := S.cfg,
    checkpointParams := cp, checkpointEnv := ce, now := 2, refund := 42, pool := 5,
    genesisTx := genesisTx, genesisOutputs := [genesisOutput], booking := booking,
    unspent := u, economicTx := tx, fullFold := fullFold, holdingIndex := 1 }

def input : Except String RegistrationInput := inputFor context

def run : Except String (RegistrationInput × Registered) := do
  let q ← input
  let r ← registerJoint interpretation context abstractRegistry commit q
  pure (q, r)
end CardanoKeri.ConsumerIdentity.Witness
