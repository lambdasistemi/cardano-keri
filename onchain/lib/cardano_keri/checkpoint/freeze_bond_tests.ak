//// Haskell/Aiken parity tests for the freeze-bond floor and the historical
//// checkpoint and tombstone bytes.

use aiken/cbor
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{TombstoneV1}
use cardano_keri/checkpoint/freeze_bond.{freeze_bond_valid}
use cardano_keri/checkpoint/freeze_bond_vectors as vec
use cardano_keri/checkpoint/threshold.{Unweighted}

fn checkpoint() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    cur_keys: [
      #"0101010101010101010101010101010101010101010101010101010101010101",
    ],
    cur_threshold: Unweighted(1),
    next_keys: [
      #"0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a",
    ],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 0,
    native_sn: 0,
  }
}

test parameter_floor_matches_haskell() {
  and {
    freeze_bond_valid(vec.freeze_bond_floor) == vec.bond_floor_valid,
    freeze_bond_valid(vec.freeze_bond_floor - 1) == vec.bond_below_valid,
  }
}

test historical_checkpoint_bytes_are_unchanged() {
  cbor.serialise(V1(checkpoint())) == vec.golden_checkpoint
}

test historical_tombstone_bytes_are_unchanged() {
  cbor.serialise(
    TombstoneV1 {
      cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      convicted_at_native_sn: 1,
      evidence_said: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    },
  ) == vec.golden_tombstone
}
