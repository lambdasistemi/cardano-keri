namespace CardanoKeri.Cage
example :
    stepFn .delegated Plugin.registry .delegatedRouting (TxAuth.mk false true) wp noEvidence
        (.fold 1 0 7 [(0, .reject)]) 25 pending =
      stepFn .delegated Plugin.registry .delegatedRouting (TxAuth.mk true true) wp noEvidence
        (.fold 1 0 7 [(0, .reject)]) 25 pending := by decide
end CardanoKeri.Cage
