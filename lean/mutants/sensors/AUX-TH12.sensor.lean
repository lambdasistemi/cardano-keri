namespace CardanoKeri.Cage
example :
    (stepFn .ownerKeyed Plugin.trivial .refundAll (TxAuth.mk true true) wp noEvidence
      (.fold 1 0 7 [(0, .process)]) 1 pending).map (fun x => x.1.locked) = some [] := by decide
end CardanoKeri.Cage
