//// The validity interval of a transaction as the model's clock reads it.
////
//// ## Responsibility
//// Reads the validity range as the half-open interval of instants the
//// transaction can be valid at, and decides the booking clock and the two
//// windows of a booked registration: the model's `bookingClock`, `foldWindow`
//// and `returnWindow`.
////
//// ## Dependencies
//// `application/held` for the records; the Aiken standard library.
////
//// ## Assumptions
//// Time is an integer count of milliseconds, and the transaction is valid at
//// the instants from its lower bound, included, to its upper bound, excluded.
////
//// ## Invariants
//// A range without two finite bounds is no clock. Inclusive and exclusive
//// bounds are brought to the one half-open reading before any comparison, and
//// an empty range is in no window.

use aiken/interval.{Finite}
use cardano/transaction.{ValidityRange}
use cardano_keri/application/held.{ApplicationParameters, RegistrationData}

/// The first instant a transaction can be valid at and the first instant it
/// no longer can be.
pub type Bounds {
  lower: Int,
  upper: Int,
}

/// The half-open interval of a validity range, when both bounds are finite.
pub fn validity_bounds(range: ValidityRange) -> Option<Bounds> {
  when (range.lower_bound.bound_type, range.upper_bound.bound_type) is {
    (Finite(lower), Finite(upper)) ->
      Some(
        Bounds {
          lower: if range.lower_bound.is_inclusive {
            lower
          } else {
            lower + 1
          },
          upper: if range.upper_bound.is_inclusive {
            upper + 1
          } else {
            upper
          },
        },
      )
    _ -> None
  }
}

/// Model `bookingClock`: the interval is non-empty, the booking time is its
/// upper bound, its width is within the booking width, and the deadlines are
/// the booking time moved by the processing and the retraction times.
pub fn booking_clock(
  data: RegistrationData,
  parameters: ApplicationParameters,
  range: ValidityRange,
) -> Bool {
  when validity_bounds(range) is {
    Some(Bounds { lower, upper }) -> and {
        lower < upper,
        data.booked_at == upper,
        upper - lower <= parameters.booking_width,
        data.process_deadline == data.booked_at + parameters.process_time,
        data.reclaim_end == data.process_deadline + parameters.retract_time,
      }
    None -> False
  }
}

/// Model `foldWindow`: the whole interval is non-empty and ends by the
/// deadline.
pub fn fold_window(data: RegistrationData, range: ValidityRange) -> Bool {
  when validity_bounds(range) is {
    Some(Bounds { lower, upper }) ->
      lower < upper && upper <= data.process_deadline
    None -> False
  }
}

/// Model `returnWindow`: the whole interval is non-empty and starts at the
/// deadline or later.
pub fn return_window(data: RegistrationData, range: ValidityRange) -> Bool {
  when validity_bounds(range) is {
    Some(Bounds { lower, upper }) ->
      lower < upper && data.process_deadline <= lower
    None -> False
  }
}
