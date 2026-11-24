import CardanoKeri.CheckpointSystemFixtures

open Lean

-- Keep the actual booking and its carrier value fixed. Only the checkpoint's
-- freeze bond changes, so the registry's combined deposit no longer matches.
open CardanoKeri.Checkpoint SystemFixtures SystemWire in
#guard (do
  let command ← registrationCommand
  let changed := { p with B := 3, hB := by decide }
  match execute (Machine.init deployment) changed (evidenceFor byIdentifier) command with
  | .error why => pure (why == "checkpoint-registration-facts-mismatch")
  | .ok _ => pure false : Except String Bool) matches .ok true

def main : IO Unit := do
  match CardanoKeri.Checkpoint.SystemFixtures.traces with
  | .error why => throw (IO.userError why)
  | .ok traces => IO.println (CardanoKeri.Registry.TraceWire.exactJson (Json.mkObj [
      ("schema", toJson "cardano-keri.checkpoint.system"), ("version", toJson (2 : Nat)),
      ("traces", toJson traces)])).compress
