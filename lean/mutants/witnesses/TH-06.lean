import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-06 CardanoKeri.Cage.bypassed_breaks_inv concrete bypassed violates activeCkpt
def witness_TH_06_leaf : Bool := decide (lookup bypassed.leaves 11 == some (.active 0))
def witness_TH_06_nockpt : Bool := decide (lookup bypassed.ckpts 11 == (none : Option Ckpt))
example : ¬ goPending bypassed 11 := by simp [goPending, bypassed]
example : witness_TH_06_leaf = true := by decide
example : witness_TH_06_nockpt = true := by decide
example : ¬ Inv wp bypassed := CardanoKeri.Cage.bypassed_breaks_inv
