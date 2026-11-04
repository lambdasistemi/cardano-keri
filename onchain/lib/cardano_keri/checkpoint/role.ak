//// The full-address role of a checkpoint output. Only the active role has an
//// address: the payment credential alone, with no staking credential.

use cardano/address.{Address, from_script}
use cardano/assets.{PolicyId}

pub type Role {
  Active
}

pub fn address(policy: PolicyId, _role: Role) -> Address {
  from_script(policy)
}

pub fn classify(policy: PolicyId, candidate: Address) -> Option<Role> {
  if candidate == address(policy, Active) {
    Some(Active)
  } else {
    None
  }
}
