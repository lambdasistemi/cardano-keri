import CardanoKeri.ApplicationCustodyExample
import CardanoKeri.CheckpointTraceWire

open CardanoKeri CardanoKeri.Checkpoint CardanoKeri.Checkpoint.TraceWire

private def registered (codes : List (Nat × String)) (digests : List (Duplicity.Content × Nat)) :=
  let writers := {WriterTable.fixture 11 711 [] with prefixes := some ⟨codes, digests⟩}
  let table : EnvTable := ⟨[], [], [], [], writers⟩
  ((table.toEnv 11).initialHistory 11 (some 711)).isSome

private def body := (Duplicity.writerFixture 11 0 .inception).event
#guard registered [(11, "D")] []
#guard !registered [] []
#guard registered [(11, "E")] [(body, 11)]
#guard !registered [(11, "E")] [(body, 12)]
#guard !registered [(11, "E")] [({body with extension := [7]}, 11)]

def main : IO Unit := IO.println (Lean.toJson CardanoKeri.Application.Custody.Examples.inceptionReferenceCases).compress
