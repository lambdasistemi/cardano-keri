//// The registry a checkpoint validator is applied to in the tests.
////
//// A checkpoint is recognised by the one token that stands for its AID in the
//// registry (Lean `ConsumerIdentity.representativeAsset`): the registry's state
//// policy and the active name of the AID. The registry is the one the
//// application tests deliver checkpoints for, so a fold's output and a
//// checkpoint spend run over the same asset.

use cardano/address.{Address, from_script, with_delegation_key}
use cardano/assets.{
  AssetName, PolicyId, Value, from_asset, from_lovelace, lovelace_of, merge,
  zero,
}
use cardano/transaction.{Input, Output, Transaction}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/checkpoint/message.{deriveAidAssetName, qb64_aid}
use singular_state/preimage.{RegistryIdentity, active_token_name}

pub fn registry() -> RegistryIdentity {
  RegistryIdentity { policy: cfg.state_policy, name: cfg.registry_name }
}

pub fn state_policy() -> PolicyId {
  cfg.state_policy
}

/// The application policy the registry's state policy is computed from: the
/// checkpoint validator is applied to it to know the termination approvals.
pub fn application_policy() -> PolicyId {
  cfg.application_policy
}

pub fn registry_name() -> ByteArray {
  cfg.registry_name
}

/// The active name of the AID whose CESR digest is `digest`, in the registry.
pub fn active_name(digest: ByteArray) -> AssetName {
  active_token_name(registry(), qb64_aid(digest))
}

/// `quantity` of the representative asset of the AID with digest `digest`.
pub fn representative(digest: ByteArray, quantity: Int) -> Value {
  from_asset(cfg.state_policy, active_name(digest), quantity)
}

/// The active name of the key `key` (an AID's qualified text), in the registry.
pub fn active_name_of_key(key: ByteArray) -> AssetName {
  active_token_name(registry(), key)
}

/// What a checkpoint input or successor holds in place of the representative
/// asset of its AID, each differing from the genuine holding in one fact.
pub type Holding {
  /// No token at all.
  Nothing
  /// The token of the same key and registry name under another state policy.
  OtherStatePolicy
  /// The token of the same key under the same state policy and another
  /// registry name.
  OtherRegistryName
  /// The token of another key in the same registry.
  OtherKey
  /// Exactly the token the retired register mint produced: the checkpoint
  /// policy's own token named after the AID.
  RetiredRegisterToken
  /// Two of the representative asset.
  QuantityTwo
}

fn other_key_digest() -> ByteArray {
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"
}

pub fn holding(
  kind: Holding,
  digest: ByteArray,
  checkpoint_policy: PolicyId,
) -> Value {
  when kind is {
    Nothing -> zero
    OtherStatePolicy ->
      from_asset(
        cfg.foreign_state_policy,
        active_token_name(
          RegistryIdentity {
            policy: cfg.foreign_state_policy,
            name: cfg.registry_name,
          },
          qb64_aid(digest),
        ),
        1,
      )
    OtherRegistryName ->
      from_asset(
        cfg.state_policy,
        active_token_name(
          RegistryIdentity {
            policy: cfg.state_policy,
            name: cfg.configuration_name,
          },
          qb64_aid(digest),
        ),
        1,
      )
    OtherKey -> representative(other_key_digest(), 1)
    RetiredRegisterToken ->
      from_asset(checkpoint_policy, deriveAidAssetName(digest), 1)
    QuantityTwo -> representative(digest, 2)
  }
}

fn lovelace_only(value: Value, token: Value) -> Value {
  from_lovelace(lovelace_of(value)) |> merge(token)
}

/// The transaction with the first input's tokens replaced by `token`.
pub fn with_input_token(tx: Transaction, token: Value) -> Transaction {
  expect [first, ..rest] = tx.inputs
  Transaction {
    ..tx,
    inputs: [
      Input {
        ..first,
        output: Output {
          ..first.output,
          value: lovelace_only(first.output.value, token),
        },
      },
      ..rest
    ],
  }
}

/// The transaction with the first output's tokens replaced by `token`.
pub fn with_successor_token(tx: Transaction, token: Value) -> Transaction {
  expect [first, ..rest] = tx.outputs
  Transaction {
    ..tx,
    outputs: [
      Output { ..first, value: lovelace_only(first.value, token) },
      ..rest
    ],
  }
}

/// The transaction with the first output moved to `address`.
pub fn with_successor_address(tx: Transaction, address: Address) -> Transaction {
  expect [first, ..rest] = tx.outputs
  Transaction { ..tx, outputs: [Output { ..first, address }, ..rest] }
}

/// The checkpoint address of the validator `hash` with a stake credential.
pub fn staked(hash: PolicyId) -> Address {
  with_delegation_key(
    from_script(hash),
    #"55555555555555555555555555555555555555555555555555555555",
  )
}
