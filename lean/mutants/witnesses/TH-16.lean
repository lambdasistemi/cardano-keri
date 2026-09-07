import CardanoKeri.Samaritan
open CardanoKeri.Samaritan
-- WITNESS TH-16 CardanoKeri.Samaritan.self_folding_reaper_never_loses profitable self-fold both fees non-zero
def witness_TH_16_r : Reap := { Mc := 10, Mr := 6, tip := 2, fReap := 1, hFund := by decide }
def witness_TH_16_fFold : Nat := 1
example : witness_TH_16_r.fReap + witness_TH_16_fFold <= witness_TH_16_r.Mc := by decide
example : (reap witness_TH_16_r).reaperPays + witness_TH_16_fFold <= (reap witness_TH_16_r).premium + (fold witness_TH_16_r).toOwner + (fold witness_TH_16_r).toFolder := CardanoKeri.Samaritan.self_folding_reaper_never_loses witness_TH_16_r witness_TH_16_fFold (by decide)
