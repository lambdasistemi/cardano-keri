import CardanoKeri
import CardanoKeri.RegistryTraceWire
import CardanoKeri.Statements
import Lean

/-! Complete compiled declaration inventory for the imported CardanoKeri
modules, including private/generated declarations and transitive axioms.
The public Singular dependency is audited transitively at every use. -/
open Lean Elab Command
run_cmd do
  let env ← getEnv
  for moduleName in env.header.moduleNames do
    if (`CardanoKeri).isPrefixOf moduleName then logInfo m!"MODULE {moduleName}"
  let owns := fun name => match env.getModuleIdxFor? name with
    | some index => (`CardanoKeri).isPrefixOf env.header.moduleNames[index.toNat]!
    | none => false
  let names := env.constants.toList.map Prod.fst |>.filter owns |>.mergeSort
    (fun a b => a.toString < b.toString)
  let mut count := 0
  for name in names do
    let axioms ← collectAxioms name
    for axiomName in axioms do
      unless #[``propext, ``Quot.sound, ``Classical.choice].contains axiomName do
        throwError m!"unapproved axiom {axiomName} in {name}"
    logInfo m!"AXIOMS {name}: {axioms}"
    count := count + 1
  if count == 0 then throwError "empty compiled declaration inventory"
  logInfo m!"INVENTORY {count}"
