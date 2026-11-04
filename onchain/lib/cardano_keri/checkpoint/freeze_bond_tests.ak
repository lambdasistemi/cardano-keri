//// Haskell/Aiken parity test for the freeze-bond floor.

use cardano_keri/checkpoint/freeze_bond.{freeze_bond_valid}
use cardano_keri/checkpoint/freeze_bond_vectors as vec

test parameter_floor_matches_haskell() {
  and {
    freeze_bond_valid(vec.freeze_bond_floor) == vec.bond_floor_valid,
    freeze_bond_valid(vec.freeze_bond_floor - 1) == vec.bond_below_valid,
  }
}
