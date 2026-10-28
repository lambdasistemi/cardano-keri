import CardanoKeri.CheckpointSystemFixtures

open Lean
def main : IO Unit := do
  match CardanoKeri.Checkpoint.SystemFixtures.traces with
  | .error why => throw (IO.userError why)
  | .ok traces => IO.println (CardanoKeri.Registry.TraceWire.exactJson (Json.mkObj [
      ("schema", toJson "cardano-keri.checkpoint.system"), ("version", toJson (1 : Nat)),
      ("traces", toJson traces)])).compress
