import CardanoKeri.ConsumerControls

/-! Generic query mode evaluates explicit interpretation tables. Corpus mode
executes the connected fixture and emits complete queries and observations.
Neither mode accepts a caller-provided expected verdict. -/
open Lean (Json toJson)
open CardanoKeri.ConsumerIdentity CardanoKeri.ConsumerIdentity.Witness

def main (args : List String) : IO Unit := do
  if args == ["--query"] then
    let input ← (← IO.getStdin).getLine
    let result := do
      let q : Wire.Query ← Lean.fromJson? (← Json.parse input)
      Wire.execute q
    IO.println (match result with
      | .ok verdict => Json.mkObj [("ok", toJson verdict)]
      | .error reason => Json.mkObj [("error", toJson reason)]).compress
    return
  let j ← match journey with
    | .error reason => throw (IO.userError reason)
    | .ok j => pure j
  let terminal ← match terminalControls j with
    | .error reason => throw (IO.userError reason)
    | .ok result => pure result
  let checks := genesisControls j ++ namingControls ++ registrationControls j ++ terminal
  for (name, passed) in checks do
    unless passed do throw (IO.userError ("CONTROL-FAILED " ++ name))
  let rival ← IO.ofExcept (rivalQuery j)
  let queries := fieldQueries j ++ [("genuine-rival-registry", rival)]
  for (name, query) in queries do
    let expected : Except String Bool :=
      if name.startsWith "table-" then .error "incomplete-or-ambiguous-interpretation"
      else .ok (["positive-anchor", "maturity-plus-one", "zero-w-birth"].contains name)
    let agrees := match Wire.execute query, expected with
      | .ok a, .ok b => a == b
      | .error a, .error b => a == b
      | _, _ => false
    unless agrees do throw (IO.userError ("CONTROL-FAILED " ++ name))
  for frame in j.frames do
    let name ← IO.ofExcept (frame.getObjValAs? String "name")
    let accepted ← IO.ofExcept ((← IO.ofExcept (frame.getObjVal? "consumer")).getObjVal? "result" >>= fun r => r.getObjValAs? Bool "ok")
    let refused := ["registered-juvenile", "frozen", "rotate-keep-unpaid-frozen", "poisoned",
      "termination-pending", "termination-booked", "retired-after-matching-fold"].contains name
    unless accepted == !refused do throw (IO.userError ("CONTROL-FAILED journey/" ++ name))
  let full ← IO.ofExcept (completionIdentity j)
  let association ← IO.ofExcept (associationEvents j)
  IO.println (CardanoKeri.Registry.TraceWire.exactJson (Json.mkObj [
    ("schema", toJson "cardano-keri.consumer.identity"), ("version", toJson (1 : Nat)),
    ("limits", toJson ["finite model interpretation, not Cardano bytes", "current observation/refinement remains required",
      "money relation does not identify Checkpoint bonds with physical lovelace", "no production conformance"]),
    ("genesis", toJson j.input.genesisTx), ("genesisOutputs", toJson j.input.genesisOutputs),
    ("registrationFold", toJson j.input.fullFold), ("registrationEconomic", toJson j.input.economicTx),
    ("registrationUnspent", toJson j.input.unspent),
    ("terminationFold", toJson full), ("completion", toJson j.completion),
    ("registryMap", toJson ([registryAsset interpretation context,
      registryAsset interpretation { context with seed.tx := 92 }].map fun r => (r, abstractRegistry r))),
    ("namingDomain", toJson (identityDomain interpretation context { context with seed.tx := 92 })),
    ("checks", toJson checks), ("fields", toJson (queries.map fun (name, q) => Wire.cell name q)),
    ("associationEvents", toJson association), ("events", toJson j.events), ("journey", toJson j.frames)])).compress
