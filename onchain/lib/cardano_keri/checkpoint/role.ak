//// Deterministic full-address lifecycle roles for the combined checkpoint
//// validator (#116). The staking credential is a marker, never authority.

use aiken/builtin.{blake2b_224}
use aiken/crypto.{ScriptHash}
use aiken/primitive/bytearray
use cardano/address.{Address, from_script, with_delegation_script}
use cardano/assets.{PolicyId}

pub type Role {
  Active
  Frozen
  Tombstone
  Armed
}

const domain: ByteArray = "cardano-keri/checkpoint/role/v1"

pub fn role_tag(role: Role) -> Option<ByteArray> {
  when role is {
    Active -> None
    Frozen -> Some(#"00")
    Tombstone -> Some(#"01")
    Armed -> Some(#"02")
  }
}

pub fn hash(policy: PolicyId, role: Role) -> ScriptHash {
  expect Some(tag) = role_tag(role)
  blake2b_224(domain |> bytearray.concat(policy) |> bytearray.concat(tag))
}

pub fn address(policy: PolicyId, role: Role) -> Address {
  when role is {
    Active -> from_script(policy)
    _ -> from_script(policy) |> with_delegation_script(hash(policy, role))
  }
}

pub fn classify(policy: PolicyId, candidate: Address) -> Option<Role> {
  if candidate == address(policy, Active) {
    Some(Active)
  } else if candidate == address(policy, Frozen) {
    Some(Frozen)
  } else if candidate == address(policy, Tombstone) {
    Some(Tombstone)
  } else if candidate == address(policy, Armed) {
    Some(Armed)
  } else {
    None
  }
}
