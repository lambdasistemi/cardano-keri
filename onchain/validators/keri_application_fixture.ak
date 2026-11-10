//// The transactions the application tests run over.
////
//// Every name, policy and parameter comes from the generated vectors (the
//// Lean rows with the real `state(A_keri)`); the transactions are built from
//// them here, never read back from the code under test.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Address, from_script, from_verification_key}
use cardano/assets.{AssetName, PolicyId, Value, add, from_lovelace}
use cardano/transaction.{
  Datum, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder,
}
use cardano_keri/application/action.{Action, CreateConfiguration}
use cardano_keri/application/configuration_vectors as vectors
use cardano_keri/application/held.{ApplicationParameters, Configuration}
use singular_state/preimage.{RegistryIdentity, configuration_token_name}

/// One deployment under test: the application policy the validator runs as,
/// the registry its configuration record is for, and the token name of that
/// record.
pub type Deployment {
  application: PolicyId,
  registry: RegistryIdentity,
  seed: OutputReference,
  configuration_name: AssetName,
}

/// KERI's application of the Lean scenario and its own registry.
pub fn keri() -> Deployment {
  Deployment {
    application: vectors.application_policy,
    registry: RegistryIdentity {
      policy: vectors.state_policy,
      name: vectors.registry_name,
    },
    seed: vectors.seed,
    configuration_name: vectors.configuration_name,
  }
}

/// The same scenario for another application: its own application policy and
/// the state policy of its own registry.
pub fn other_application() -> Deployment {
  Deployment {
    application: vectors.foreign_application_policy,
    registry: RegistryIdentity {
      policy: vectors.foreign_state_policy,
      name: vectors.registry_name,
    },
    seed: vectors.seed,
    configuration_name: vectors.foreign_configuration_name,
  }
}

/// A registry that is not KERI's: the registry of `singular_state` applied to
/// another application, with its configuration record created under KERI's
/// application. Everything else about the transaction is perfect.
pub fn foreign_registry() -> Deployment {
  Deployment {
    application: vectors.application_policy,
    registry: RegistryIdentity {
      policy: vectors.foreign_state_policy,
      name: vectors.registry_name,
    },
    seed: vectors.seed,
    configuration_name: vectors.foreign_configuration_name,
  }
}

/// A deployment of KERI's application whose registry is `registry`, with the
/// configuration token named from that registry: every value derived from the
/// registry is recomputed, so the transaction is perfect for it.
pub fn registry_deployment(registry: RegistryIdentity) -> Deployment {
  Deployment {
    ..keri(),
    registry,
    configuration_name: configuration_token_name(registry),
  }
}

pub fn parameters() -> ApplicationParameters {
  ApplicationParameters {
    registration_cost: vectors.registration_cost,
    minimum_tip: vectors.minimum_tip,
    process_time: vectors.process_time,
    retract_time: 0,
    booking_width: vectors.booking_width,
  }
}

pub fn application_address(application: PolicyId) -> Address {
  from_script(application)
}

pub fn key_address() -> Address {
  from_verification_key(
    #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c",
  )
}

pub fn record(address: Address, datum: Datum, extra: Value) -> Output {
  Output {
    address,
    value: extra |> add("", "", vectors.record_lovelace),
    datum,
    reference_script: None,
  }
}

pub fn token(policy: PolicyId, name: AssetName, quantity: Int) -> Value {
  from_lovelace(0) |> add(policy, name, quantity)
}

/// The record's own value with one byte of `bytes` at `index` changed.
pub fn change_byte(bytes: ByteArray, index: Int) -> ByteArray {
  let byte = bytearray.at(bytes, index)
  bytearray.concat(
    bytearray.take(bytes, index),
    bytearray.push(bytearray.drop(bytes, index + 1), ( byte + 1 ) % 256),
  )
}

pub fn seed_input(seed: OutputReference) -> Input {
  Input {
    output_reference: seed,
    output: Output {
      address: key_address(),
      value: from_lovelace(5_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// The whole mint of a transaction, entry by entry.
pub fn mint_of(entries: List<(PolicyId, AssetName, Int)>) -> Value {
  list.foldl(
    entries,
    from_lovelace(0),
    fn((policy, name, quantity), acc) { add(acc, policy, name, quantity) },
  )
}

/// The configuration record of a deployment.
pub fn record_of(
  deployment: Deployment,
  parameters: ApplicationParameters,
) -> Output {
  record(
    application_address(deployment.application),
    InlineDatum(
      Configuration {
        parameters,
        checkpoint_credential: vectors.checkpoint_credential,
      },
    ),
    token(deployment.application, deployment.configuration_name, 1),
  )
}

/// The output a deployment publishes the state script's template at: any
/// address, the template in its inline datum; the application authenticates it by
/// its hash.
pub fn template_input(template: ByteArray) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e",
      output_index: 0,
    },
    output: Output {
      address: key_address(),
      value: from_lovelace(2_000_000),
      datum: InlineDatum(template),
      reference_script: None,
    },
  }
}

/// The perfect genesis transaction of a deployment: the seed is spent once,
/// the state token is minted once, the configuration token is minted once, and
/// the record sits at the application address.
pub fn genesis(deployment: Deployment) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [seed_input(deployment.seed)],
    outputs: [record_of(deployment, parameters())],
    mint: mint_of(
      [
        (deployment.registry.policy, deployment.registry.name, 1),
        (deployment.application, deployment.configuration_name, 1),
      ],
    ),
  }
}

pub fn creation(deployment: Deployment, output_index: Int) -> Action {
  CreateConfiguration {
    registry: deployment.registry,
    seed: deployment.seed,
    output_index,
  }
}
