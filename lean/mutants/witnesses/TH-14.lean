import CardanoKeri.Samaritan
open CardanoKeri.Samaritan
-- WITNESS TH-14 CardanoKeri.Samaritan.reaper_recovers funded non-zero request/tip/premium
def witness_TH_14_r : Reap := { Mc := 10, Mr := 6, tip := 2, fReap := 1, hFund := by decide }
example : witness_TH_14_r.Mr + witness_TH_14_r.tip <= witness_TH_14_r.Mc := witness_TH_14_r.hFund
example : (reap witness_TH_14_r).premium + (fold witness_TH_14_r).toOwner = witness_TH_14_r.Mc - witness_TH_14_r.tip := CardanoKeri.Samaritan.reaper_recovers witness_TH_14_r
