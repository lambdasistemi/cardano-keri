import Singular.Model.Termination

namespace CardanoKeri.Checkpoint

/-- An establishment position uses the rotation epoch and native event sequence. -/
structure KeyState where
  epoch : Nat
  sn : Nat
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

end CardanoKeri.Checkpoint

namespace CardanoKeri.Application

/-- The termination mint reads the identifier and position from its spent
checkpoint datum. The ledger identifies that input by transaction and index. -/
structure PendingSpend where
  reference : Singular.OutRef
  aid : Nat
  position : Checkpoint.KeyState
  deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

end CardanoKeri.Application
