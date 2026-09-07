import CardanoKeri.Samaritan
open CardanoKeri.Samaritan
-- WITNESS TH-15 CardanoKeri.Samaritan.samaritan_never_loses profitable stranger non-zero fee
def witness_TH_15_r : Reap := { Mc := 10, Mr := 6, tip := 2, fReap := 1, hFund := by decide }
example : witness_TH_15_r.tip + witness_TH_15_r.fReap <= witness_TH_15_r.Mc := by decide
example : (reap witness_TH_15_r).reaperPays <= (reap witness_TH_15_r).premium + (fold witness_TH_15_r).toOwner := CardanoKeri.Samaritan.samaritan_never_loses witness_TH_15_r (by decide)
