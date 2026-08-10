import Lean

/-!
An executable oracle over the exact Lean environment used by the pinned bridge
packages.

The shell audit supplies the reference inventory as TSV.  Module references
are resolved by Lean's own module search and imported with `Lean.importModules`;
name references are decided by Lean's global-name resolver in the resulting
environment.  The declaration-membership mode exists only as a negative
control proving why an `Environment.contains` approximation is insufficient
for exported aliases.
-/

namespace KeriBlaster.CompatibilityOracle

inductive ResolutionMode
  | elaborator
  | declarationMembership

structure Reference where
  source : String
  package : String
  name : String
  kind : String

def parseReference (line : String) : Except String Reference :=
  match line.splitOn "\t" with
  | [source, package, name, kind] =>
      if source.isEmpty || package.isEmpty || name.isEmpty then
        throw s!"empty compatibility reference field: {line}"
      else if kind != "module" && kind != "namespace" && kind != "name" then
        throw s!"unknown compatibility reference kind: {kind}"
      else
        pure { source, package, name, kind }
  | _ => throw s!"malformed compatibility reference row: {line}"

def readReferences (path : System.FilePath) : IO (List Reference) := do
  let contents ← IO.FS.readFile path
  let lines := contents.splitOn "\n" |>.filter (fun line => !line.isEmpty)
  match lines.mapM parseReference with
  | .ok references => pure references
  | .error message => throw (IO.userError message)

def moduleAvailable (moduleName : String) : IO Bool := do
  try
    let _ ← Lean.findOLean moduleName.toName
    pure true
  catch _ =>
    pure false

def loadEnvironment (references : List Reference) : IO Lean.Environment := do
  let moduleNames :=
    references
      |>.filter (fun reference => reference.kind == "module")
      |>.map (fun reference => reference.name)
      |>.eraseDups
  let mut imports : Array Lean.Import := #[]
  for moduleName in moduleNames do
    if ← moduleAvailable moduleName then
      imports := imports.push {
        module := moduleName.toName
        importAll := false
        isExported := false
        isMeta := false
      }
  Lean.importModules imports {} 0 #[] false true

def elaboratorAccepts (environment : Lean.Environment)
    (name : Lean.Name) : IO Bool := do
  let context : Lean.Core.Context := {
    fileName := "<compatibility-oracle>"
    fileMap := default
  }
  let state : Lean.Core.State := { env := environment }
  let action : Lean.CoreM (List (Lean.Name × List String)) :=
    Lean.resolveGlobalName name
  let (resolved, _) ← EIO.toIO
    (fun _ => IO.userError "Lean name resolution failed")
    ((action.run context) state)
  pure (!resolved.isEmpty)

def emitResolution (environment : Lean.Environment)
    (mode : ResolutionMode) (reference : Reference) : IO Unit := do
  let resolved ←
    if reference.kind == "module" then
      moduleAvailable reference.name
    else if reference.kind == "namespace" then
      pure (environment.isNamespace reference.name.toName)
    else
      match mode with
      | .elaborator => elaboratorAccepts environment reference.name.toName
      | .declarationMembership =>
          pure (environment.contains reference.name.toName)
  IO.println s!"{reference.source}\t{reference.package}\t{reference.name}\t{reference.kind}\t{resolved}"

def run (mode : ResolutionMode) (path : System.FilePath) : IO Unit := do
  let sysroot ← Lean.findSysroot
  Lean.initSearchPath sysroot
  let references ← readReferences path
  if references.isEmpty then
    throw (IO.userError "compatibility reference inventory is empty")
  let environment ← loadEnvironment references
  for reference in references do
    emitResolution environment mode reference

end KeriBlaster.CompatibilityOracle

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
      try
        KeriBlaster.CompatibilityOracle.run .elaborator path
        pure 0
      catch error =>
        IO.eprintln s!"compatibility-oracle: {error}"
        pure 1
  | ["--declaration-membership", path] =>
      try
        KeriBlaster.CompatibilityOracle.run .declarationMembership path
        pure 0
      catch error =>
        IO.eprintln s!"compatibility-oracle: {error}"
        pure 1
  | _ =>
      IO.eprintln "usage: compatibility-oracle [--declaration-membership] REFERENCES.tsv"
      pure 64
