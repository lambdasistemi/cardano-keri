namespace CardanoKeri.Cage
example :
    stepFn .ownerAndHook Plugin.trivial .delegatedRouting (TxAuth.mk true true) wp noEvidence
        (.fold 1 0 7 [(0, .process)]) 1 pending =
      some ({ locked := [(11, 1000)], tips := some (1, 2) }, bypassed) := by decide
end CardanoKeri.Cage
