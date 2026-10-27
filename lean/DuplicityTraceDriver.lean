import CardanoKeri.DuplicityExamples

/-! Generic concrete duplicity surface: one JSON Scenario from stdin,
one Boolean result, nonzero exit on malformed input. No per-theorem dispatch. -/
def main : IO Unit := do
  let input ← (← IO.getStdin).readToEnd
  let result := do
    let json ← Lean.Json.parse input
    let scenario ← (Lean.fromJson? json : Except String CardanoKeri.Duplicity.Scenario)
    pure (CardanoKeri.Duplicity.scenarioJson scenario)
  match result with
  | .error message => throw (IO.userError message)
  | .ok json => (← IO.getStdout).putStrLn json.compress
