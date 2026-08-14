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
///
/// `ArmedV2` is constructor 1: the lean #254 successor. It carries exactly the
/// same three fields — the lean checkpoint, the hunter payee, and the existing
/// deadline — and deliberately gains NO generic version/origin envelope and no
/// commitment-specific wrapper. The commitment that established the hunter's
/// entitlement is consumed and burned in the arming transaction itself, so the
/// ARMED state records only its outcome: this payee, this deadline.
///
/// The version bump is what carries the meaning. Under `ArmedV1` the hunter was
/// a caller-supplied redeemer field; under `ArmedV2` it is the payee of a
/// matured, hash-committed reservation. The bytes are shaped alike; the
/// authority behind them is not. `ArmedV1` remains declared because the
/// pre-existing migration family still names it.
pub type ArmedDatum {
  ArmedV1 {
    checkpoint: CheckpointDatumV1,
    hunter_pkh: ByteArray,
    deadline: Int,
  }
  ArmedV2 {
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

/// The hunter is an exact Cardano 28-byte verification-key hash, in either
/// version. Width is a wire property and is checked identically for both.
pub fn armed_datum_well_formed(armed: ArmedDatum) -> ArmedDatumVerdict {
  let hunter_pkh = when armed is {
    ArmedV1 { hunter_pkh, .. } -> hunter_pkh
    ArmedV2 { hunter_pkh, .. } -> hunter_pkh
  }
  if bytearray.length(hunter_pkh) == 28 {
    ArmedDatumValid
  } else {
    ArmedDatumInvalid(HunterPkhWidth)
  }
}

/// The hunter payee recorded in an ARMED state, whichever version it is.
///
/// Claim and the ARMED conviction share read the beneficiary through this
/// accessor and through nothing else: the payee is derived from stored state,
/// never from a redeemer, so neither path can gain a new beneficiary and no
/// party can acquire a veto by withholding a fresh signature.
pub fn armed_hunter(armed: ArmedDatum) -> ByteArray {
  when armed is {
    ArmedV1 { hunter_pkh, .. } -> hunter_pkh
    ArmedV2 { hunter_pkh, .. } -> hunter_pkh
  }
}

/// The lean checkpoint carried by an ARMED state.
pub fn armed_checkpoint(armed: ArmedDatum) -> CheckpointDatumV1 {
  when armed is {
    ArmedV1 { checkpoint, .. } -> checkpoint
    ArmedV2 { checkpoint, .. } -> checkpoint
  }
}

/// The stored hard deadline carried by an ARMED state.
pub fn armed_deadline(armed: ArmedDatum) -> Int {
  when armed is {
    ArmedV1 { deadline, .. } -> deadline
    ArmedV2 { deadline, .. } -> deadline
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
