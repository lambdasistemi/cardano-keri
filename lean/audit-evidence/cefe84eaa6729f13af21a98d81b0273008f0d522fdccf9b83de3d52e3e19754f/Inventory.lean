import CardanoKeri
import Lean
open Lean Elab Command
run_cmd do
  let env ← getEnv
  for (name, info) in env.constants.toList do
    if name.toString.startsWith "CardanoKeri." then
      match info with
      | .thmInfo _ => logInfo m!"THEOREM {name}"
      | .inductInfo i =>
        if [``CardanoKeri.Checkpoint.Step, ``CardanoKeri.Registry.Action, ``CardanoKeri.Registry.Op].contains name then
          for ctor in i.ctors do logInfo m!"CONSTRUCTOR {name} {ctor}"
      | _ => pure ()
