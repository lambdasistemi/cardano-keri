//// The booking of a registration.
////
//// ## Responsibility
//// The decision sites of the Lean model's `registrationAsset`,
//// `registrationShape` and `bookRegistration`: a registration approval is
//// minted only for a request booked at the application address, holding
//// exactly that approval, whose committed fields are the ones the approval
//// names, with the clock fixed from the configuration of its registry, at the
//// checkpoint validator the configuration record names.
////
//// ## Dependencies
//// `application/clock`, `application/configuration` and `application/held`;
//// `application/state_policy`; `singular_state/preimage` for the approval
//// preimage and the names; the Aiken standard library.
////
//// ## Assumptions
//// The Singular state script, not this one, decides that the key is absent
//// and that the token reaches the holding the approval commits.
////
//// ## Invariants
//// The name of a registration approval commits the registry, the key, the
//// holding address, the hash of the initial datum and the deposit, so an
//// approval is good for exactly one registration. A request commits the
//// checkpoint validator's address the record names, never the application's.

use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{
  AssetName, PolicyId, flatten, lovelace_of, quantity_of, without_lovelace,
}
use cardano/transaction.{Output, Transaction}
use cardano_keri/application/clock.{booking_clock}
use cardano_keri/application/configuration.{configuration_of}
use cardano_keri/application/held.{
  Registration, RegistrationData, address_of, held_datum,
}
use singular_state/preimage.{
  approval_name, initial_datum_hash, registration_preimage,
}

/// Model `registrationAsset`: the name of the approval of a registration,
/// under the application policy: the hash of the preimage that commits its
/// fields.
pub fn registration_approval(data: RegistrationData) -> AssetName {
  approval_name(
    registration_preimage(
      data.key,
      data.registry,
      data.holding_address,
      initial_datum_hash(data.initial_datum),
      data.deposit,
    ),
  )
}

/// Model `registrationShape`: `output` sits at the application address, holds
/// exactly the approval of `data` besides ADA, and holds at least the deposit.
pub fn registration_shape(
  application_policy: PolicyId,
  output: Output,
  data: RegistrationData,
) -> Bool {
  and {
    output.address.payment_credential == Script(application_policy),
    flatten(without_lovelace(output.value)) == [
      (application_policy, registration_approval(data), 1),
    ],
    data.deposit <= lovelace_of(output.value),
  }
}

/// The request at `index` among the outputs, with its record.
pub fn registration_at(
  outputs: List<Output>,
  index: Int,
) -> Option<(Output, RegistrationData)> {
  when list.at(outputs, index) is {
    Some(output) ->
      when held_datum(output) is {
        Some(Registration { registration }) -> Some((output, registration))
        _ -> None
      }
    None -> None
  }
}

/// Model `requestLovelace`: the exact lovelace a booked request holds: the
/// committed deposit, the registration cost and the registry's minimum tip.
pub fn request_lovelace(
  data: RegistrationData,
  registration_cost: Int,
  minimum_tip: Int,
) -> Int {
  data.deposit + registration_cost + minimum_tip
}

/// Model `bookRegistration`: the output at `index` is a request that books
/// its registration, and exactly one approval of its payload is minted. That
/// nothing else is minted is the caller's accounting (`application/mint`).
pub fn book_registration(
  application_policy: PolicyId,
  minimum_deposit: Int,
  index: Int,
  tx: Transaction,
) -> Bool {
  when registration_at(tx.outputs, index) is {
    Some((output, data)) ->
      when
        configuration_of(application_policy, data.registry, tx.reference_inputs)
      is {
        Some(record) -> and {
            registration_shape(application_policy, output, data),
            data.holding_address == address_of(record.checkpoint_credential),
            record.checkpoint_credential != Script(application_policy),
            quantity_of(
              tx.mint,
              application_policy,
              registration_approval(data),
            ) == 1,
            minimum_deposit <= data.deposit,
            lovelace_of(output.value) == request_lovelace(
              data,
              record.parameters.registration_cost,
              record.parameters.minimum_tip,
            ),
            booking_clock(data, record.parameters, tx.validity_range),
          }
        None -> False
      }
    None -> False
  }
}
