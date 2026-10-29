import CardanoKeri.CheckpointLifecycleExamples

/-! Proof-interface controls for stored receipt context. These check type
instantiation only; they are not semantic mutation kills. The same-context
other-request refusal and stored-environment replay are separate executable
contracts in CheckpointLifecycleExamples. -/
namespace CardanoKeri.Checkpoint.InterfaceChecks
open CardanoKeri.Registry

def foreignParams : Registry.Params := { Registry.Examples.p with D := 11, hD := by decide }
def foreignEnv : Registry.Env := { Registry.Examples.env with duplicity := fun _ _ => false }
def foreignConfig : Singular.Config := { Registry.Examples.cfg with registryId := 10 }

example : True := by
  have _ : FoldReceipt Registry.Examples.p Registry.Examples.env Registry.Examples.cfg :=
    Examples.completionReceipt
  trivial

example (_receipt : FoldReceipt foreignParams Registry.Examples.env Registry.Examples.cfg) : True := by
  fail_if_success
    have _ : FoldReceipt Registry.Examples.p Registry.Examples.env Registry.Examples.cfg := _receipt
  trivial

example (_receipt : FoldReceipt Registry.Examples.p foreignEnv Registry.Examples.cfg) : True := by
  fail_if_success
    have _ : FoldReceipt Registry.Examples.p Registry.Examples.env Registry.Examples.cfg := _receipt
  trivial

example (_receipt : FoldReceipt Registry.Examples.p Registry.Examples.env foreignConfig) : True := by
  fail_if_success
    have _ : FoldReceipt Registry.Examples.p Registry.Examples.env Registry.Examples.cfg := _receipt
  trivial
end CardanoKeri.Checkpoint.InterfaceChecks
