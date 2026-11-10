//// The records held at the address of KERI's application.
////
//// ## Responsibility
//// Declares what an output at the application address can carry, in the words
//// of the Lean model's `ApplicationParameters`, `Configuration` and
//// `RegistrationData`, and reads such an output's datum without failing: a
//// datum of another shape is no record.
////
//// ## Dependencies
//// `singular_state/preimage` for the identity of a registry.
////
//// ## Assumptions
//// The datum of an output is read from the output itself, inline. A datum that
//// is only a hash is no record.
////
//// ## Invariants
//// The field order of the parameters is the public Singular one:
//// registration cost, minimum tip, process time, retract time, booking width.
//// The records are one sum type, numbered as the public open-datum
//// application numbers them (configuration 0, registration 1), so an output
//// carries at most one of them.
////
//// ## Mapping to the Lean model
//// A Lean credential, a natural, is the Plutus `Address` of the script or key
//// it names, without a stake credential: the checkpoint validator's
//// credential in the configuration record is a Plutus `Credential`, and the
//// holding address a request commits is the address built from it. The
//// Lean `initialDatum` of a request, the hash of the initial datum, is the
//// datum itself here; its hash is what the approval commits.

use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address, Credential}
use cardano/transaction.{InlineDatum, Output}
use singular_state/preimage.{RegistryIdentity}

/// The five request parameters of a registry, fixed when it is created.
pub type ApplicationParameters {
  registration_cost: Int,
  minimum_tip: Int,
  process_time: Int,
  retract_time: Int,
  booking_width: Int,
}

/// A booked registration, decoded from the datum of a pending registration.
pub type RegistrationData {
  registry: RegistryIdentity,
  key: ByteArray,
  controller: VerificationKeyHash,
  refund_address: Address,
  holding_address: Address,
  initial_datum: Data,
  deposit: Int,
  booked_at: Int,
  process_deadline: Int,
  reclaim_end: Int,
}

/// The datum of an output at the application address.
pub type HeldDatum {
  Configuration {
    parameters: ApplicationParameters,
    checkpoint_credential: Credential,
  }
  Registration { registration: RegistrationData }
}

/// The record `output` carries inline, when it carries one. A datum of another
/// shape, a datum hash or no datum is no record.
pub fn held_datum(output: Output) -> Option<HeldDatum> {
  when output.datum is {
    InlineDatum(datum) ->
      if datum
      is Configuration { parameters, checkpoint_credential }: HeldDatum {
        Some(Configuration { parameters, checkpoint_credential })
      } else if datum is Registration { registration }: HeldDatum {
        Some(Registration { registration })
      } else {
        None
      }
    _ -> None
  }
}

/// The address a Lean credential names: the payment credential alone.
pub fn address_of(credential: Credential) -> Address {
  Address { payment_credential: credential, stake_credential: None }
}
