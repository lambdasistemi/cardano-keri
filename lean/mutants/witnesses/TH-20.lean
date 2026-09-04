import CardanoKeri.Cage

open CardanoKeri.Cage
open CardanoKeri.Registry

namespace CardanoKeri.Mutants

/-- CG-09 (A-001 additive): `routeValue.refundAll` returns the exact bond to
the request owner. The frozen `refundAll_never_locks` concludes only that
`locked` is unchanged, so this pins the refund amount directly. -/
theorem CG09_refundAll_returns_exact_bond (p : Params) (acc : Acc) (r : Request) (acc'' : Acc) :
    (routeValue .refundAll p acc r acc'').refunds = acc.refunds ++ [(r.owner, r.op.bond p)] := by
  simp [routeValue]

end CardanoKeri.Mutants

def witness_TH_20_acc : Acc :=
  { leaves := [], ckpts := [], requests := [], nextToken := 0, locked := [], refunds := [] }
def witness_TH_20_acc'' : Acc :=
  { leaves := [], ckpts := [], requests := [], nextToken := 0, locked := [(11, 1000)], refunds := [(2, 3)] }
def witness_TH_20_req : Request := ⟨11, 1, 0, .register⟩

-- Premise: locked is restored from the pre-body accumulator (reachable path).
example : (routeValue .refundAll wp witness_TH_20_acc witness_TH_20_req witness_TH_20_acc'').locked =
    witness_TH_20_acc.locked := by decide
-- Premise: the concrete sensor request carries bond wp.D.
example : witness_TH_20_req.op.bond wp = wp.D := by decide
-- The additive assertion applied to concrete sensor values.
example : (routeValue .refundAll wp witness_TH_20_acc witness_TH_20_req witness_TH_20_acc'').refunds =
    witness_TH_20_acc.refunds ++ [(witness_TH_20_req.owner, witness_TH_20_req.op.bond wp)] :=
  CardanoKeri.Mutants.CG09_refundAll_returns_exact_bond wp witness_TH_20_acc witness_TH_20_req witness_TH_20_acc''
