//// Retained deterministic role-address vectors.

use cardano/address.{from_script, with_delegation_script}
use cardano_keri/checkpoint/role.{Active}

const policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

test role_active_address_stays_byte_compatible() {
  role.address(policy, Active) == from_script(policy)
}

test role_classifier_compares_the_whole_address() {
  role.classify(policy, role.address(policy, Active)) == Some(Active)
}

test role_classifier_fails_closed_on_unknown_staking_script() {
  let unknown = from_script(policy)
    |> with_delegation_script(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      )
  role.classify(policy, unknown) == None
}
