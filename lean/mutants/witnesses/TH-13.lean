import CardanoKeri.Samaritan
open CardanoKeri.Samaritan
-- WITNESS TH-13 CardanoKeri.Samaritan.reap_conserves funded non-zero request/tip/premium
def witness_TH_13_r : Reap := { Mc := 10, Mr := 6, tip := 2, fReap := 1, hFund := by decide }
example : witness_TH_13_r.hFund = witness_TH_13_r.hFund := rfl
example : (reap witness_TH_13_r).intoRequest + (reap witness_TH_13_r).premium = witness_TH_13_r.Mc := CardanoKeri.Samaritan.reap_conserves witness_TH_13_r
