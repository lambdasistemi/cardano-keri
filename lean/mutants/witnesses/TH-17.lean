import CardanoKeri.Samaritan
open CardanoKeri.Samaritan
-- WITNESS TH-17 CardanoKeri.Samaritan.fold_conserves non-zero request and tip split
def witness_TH_17_r : Reap := { Mc := 10, Mr := 6, tip := 2, fReap := 1, hFund := by decide }
example : witness_TH_17_r.Mr + witness_TH_17_r.tip == 8 := by decide
example : (fold witness_TH_17_r).toOwner + (fold witness_TH_17_r).toFolder = (reap witness_TH_17_r).intoRequest := CardanoKeri.Samaritan.fold_conserves witness_TH_17_r
