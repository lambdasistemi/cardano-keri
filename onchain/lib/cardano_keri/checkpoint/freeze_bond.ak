//// The freeze bond: the lovelace every checkpoint holds beside its deposit
//// and returns to the convictor. It mirrors
//// `Cardano.KERI.AID.Checkpoint.FreezeBond`.

/// Mechanical minimum freeze bond in lovelace.
pub const freeze_bond_floor: Int = 5_000_000

/// Whether the configured bond meets the deployment floor.
pub fn freeze_bond_valid(freeze_bond: Int) -> Bool {
  freeze_bond >= freeze_bond_floor
}
