//// Freeze-bond schema and raw validity-range model (#116 R1).
////
//// This isolated module does not alter validator dispatch. It mirrors
//// `Cardano.KERI.AID.Checkpoint.FreezeBond`: parameter floors, versioned
//// ArmedV1 bytes, and deadline checks all have Haskell-generated vectors.

use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}

/// Mechanical minimum freeze bond in lovelace.
pub const freeze_bond_floor: Int = 5_000_000

/// Whether the configured bond meets the deployment floor.
pub fn freeze_bond_valid(freeze_bond: Int) -> Bool {
  freeze_bond >= freeze_bond_floor
}

/// The response window must contain at least one validity-range time unit.
pub fn freeze_window_valid(freeze_window: Int) -> Bool {
  freeze_window > 0
}

/// Versioned ARMED wire datum. ArmedV1 is constructor 0 with three fields.
pub type ArmedDatum {
  ArmedV1 {
    checkpoint: CheckpointDatumV1,
    hunter_pkh: ByteArray,
    deadline: Int,
  }
}

pub type ArmedDatumError {
  HunterPkhWidth
}

pub type ArmedDatumVerdict {
  ArmedDatumValid
  ArmedDatumInvalid(ArmedDatumError)
}

/// Classify only the version-tagged ArmedDatum wire shape.
pub fn classify(datum: Data) -> Option<ArmedDatum> {
  if datum is armed: ArmedDatum {
    Some(armed)
  } else {
    None
  }
}

/// The hunter is an exact Cardano 28-byte verification-key hash.
pub fn armed_datum_well_formed(armed: ArmedDatum) -> ArmedDatumVerdict {
  when armed is {
    ArmedV1 { hunter_pkh, .. } ->
      if bytearray.length(hunter_pkh) == 28 {
        ArmedDatumValid
      } else {
        ArmedDatumInvalid(HunterPkhWidth)
      }
  }
}

/// Raw endpoint inclusivity is retained and never normalized.
pub type Inclusivity {
  Inclusive
  Exclusive
}

/// Raw validity-range bound, including both infinities.
pub type RawBound {
  NegativeInfinity
  Finite(Int, Inclusivity)
  PositiveInfinity
}

pub type DeadlineError {
  MissingUpperBound
  NonFiniteUpperBound
  NonPositiveFreezeWindow
}

pub type DeadlineVerdict {
  Deadline(Int)
  DeadlineInvalid(DeadlineError)
}

/// Compute u + W_freeze from the finite raw endpoint itself. Aiken integers
/// are arbitrary precision, so no narrower overflow ceiling is introduced.
pub fn arm_deadline(
  freeze_window: Int,
  upper: Option<RawBound>,
) -> DeadlineVerdict {
  if !freeze_window_valid(freeze_window) {
    DeadlineInvalid(NonPositiveFreezeWindow)
  } else {
    when upper is {
      None -> DeadlineInvalid(MissingUpperBound)
      Some(Finite(u, _)) -> Deadline(u + freeze_window)
      Some(_) -> DeadlineInvalid(NonFiniteUpperBound)
    }
  }
}

/// A response needs a finite raw upper endpoint strictly before deadline.
pub fn response_before_deadline(deadline: Int, upper: Option<RawBound>) -> Bool {
  when upper is {
    Some(Finite(u, _)) -> u < deadline
    _ -> False
  }
}

/// A claim needs a finite raw lower endpoint at or after deadline.
pub fn claim_at_or_after_deadline(
  deadline: Int,
  lower: Option<RawBound>,
) -> Bool {
  when lower is {
    Some(Finite(l, _)) -> l >= deadline
    _ -> False
  }
}
