namespace CardanoKeri.Cage
example :
    stepFn .ownerKeyed Plugin.registry .delegatedRouting (TxAuth.mk true false) wp noEvidence
        (.fold 1 0 8 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) }, { bypassed with plugin := 8 }) := by decide
end CardanoKeri.Cage
