//// The records held at the address of KERI's application.
////
//// ## Responsibility
//// Declares what an output at the application address can carry, in the words
//// of the Lean model's `ApplicationParameters` and `OutputDatum`. At this
//// revision the only record is the configuration of a registry.
////
//// ## Dependencies
//// None.
////
//// ## Assumptions
//// The datum of an output is read from the output itself, inline. A datum that
//// is only a hash is no record.
////
//// ## Invariants
//// The field order of the parameters is the public Singular one:
//// registration cost, minimum tip, process time, retract time, booking width.

use cardano/transaction.{InlineDatum, Output}

/// The five request parameters of a registry, fixed when it is created.
pub type ApplicationParameters {
  registration_cost: Int,
  minimum_tip: Int,
  process_time: Int,
  retract_time: Int,
  booking_width: Int,
}

/// The datum of an output at the application address.
pub type HeldDatum {
  Configuration { parameters: ApplicationParameters }
}

/// The record `output` carries inline, when it carries one. A datum of another
/// shape, a datum hash or no datum is no record.
pub fn held_datum(output: Output) -> Option<HeldDatum> {
  when output.datum is {
    InlineDatum(datum) ->
      if datum is Configuration { parameters }: HeldDatum {
        Some(Configuration { parameters })
      } else {
        None
      }
    _ -> None
  }
}
