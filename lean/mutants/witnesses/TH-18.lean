import CardanoKeri.Samaritan
open CardanoKeri.Samaritan
-- WITNESS TH-18 CardanoKeri.Samaritan.unprofitable_when_tip_too_high funded but fee unprofitable
def witness_TH_18_r : Reap := { Mc := 10, Mr := 6, tip := 2, fReap := 9, hFund := by decide }
example : witness_TH_18_r.Mc < witness_TH_18_r.tip + witness_TH_18_r.fReap := by decide
example : (reap witness_TH_18_r).premium + (fold witness_TH_18_r).toOwner < (reap witness_TH_18_r).reaperPays := CardanoKeri.Samaritan.unprofitable_when_tip_too_high witness_TH_18_r (by decide)
