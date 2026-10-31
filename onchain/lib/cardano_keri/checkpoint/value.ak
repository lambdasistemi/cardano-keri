//// The lovelace a checkpoint output holds (Lean `CardanoKeri.Checkpoint`
//// `State.heldValue`, `State.valueFloor`, `State.withValue`) and the
//// registration carrier rule.
////
//// The datum carries the facts of a checkpoint; the deposit, the freeze bond
//// and the premium pool are held in the output's value. Every function takes
//// the amounts as arguments: `mc` the registry's minimum ADA, `d` the
//// checkpoint deposit, `b` the freeze bond. A live output holds `mc + d`, the
//// bond unless frozen, and its pool; a pending-termination output holds
//// exactly `mc`.

use cardano_keri/checkpoint/datum.{CheckpointDatumV2, Live, TerminationPending}

/// Lean `State.valueFloor`: the amount below which an output with these datum
/// facts cannot hold the deposit and freeze bond its state says it holds.
pub fn value_floor(mc: Int, d: Int, b: Int, facts: CheckpointDatumV2) -> Int {
  when facts is {
    Live { frozen, .. } ->
      if frozen {
        mc + d
      } else {
        mc + d + b
      }
    TerminationPending { .. } -> mc
  }
}

/// Lean `State.heldValue`: the lovelace the output holds. A pending
/// termination holds the minimum ADA whatever pool is given.
pub fn held_value(
  mc: Int,
  d: Int,
  b: Int,
  facts: CheckpointDatumV2,
  pool: Int,
) -> Int {
  when facts is {
    Live { .. } -> value_floor(mc, d, b, facts) + pool
    TerminationPending { .. } -> mc
  }
}

/// Lean `State.withValue`: the pool the datum facts and the lovelace
/// determine. A live output's pool is what it holds above its floor; a
/// pending termination holds exactly `mc` and reads as pool 0. `None` below
/// the floor (live) or away from `mc` (pending).
pub fn with_value(
  mc: Int,
  d: Int,
  b: Int,
  facts: CheckpointDatumV2,
  lovelace: Int,
) -> Option<Int> {
  when facts is {
    Live { .. } -> {
      let floor = value_floor(mc, d, b, facts)
      if floor <= lovelace {
        Some(lovelace - floor)
      } else {
        None
      }
    }
    TerminationPending { .. } ->
      if lovelace == mc {
        Some(0)
      } else {
        None
      }
  }
}

/// The registration booking rule (Lean `lean/checkpoint-value-vectors.json`
/// `rules.registration`): a carrier books exactly when it holds the minimum
/// ADA, the deposit and the freeze bond, and the initial pool is what is
/// left. `None` is the refusal.
pub fn registration_pool(mc: Int, d: Int, b: Int, carrier: Int) -> Option<Int> {
  let floor = mc + d + b
  if floor <= carrier {
    Some(carrier - floor)
  } else {
    None
  }
}
