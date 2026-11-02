//// Retained deterministic role-address vectors.

use cardano/address.{from_script, with_delegation_script}
use cardano_keri/checkpoint/freeze_bond_vectors as vec
use cardano_keri/checkpoint/role.{Active, Tombstone}

const policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

test role_active_address_stays_byte_compatible() {
  role.address(policy, Active) == from_script(policy)
}

test role_tombstone_hash_is_deterministic() {
  role.hash(policy, Tombstone) == #"44f8b57fb50b9ffee7ec21037a031a61b5b3919a7fee4f5eab4cea77"
}

test role_tags_are_exact() {
  and {
    role.role_tag(Active) == None,
    role.role_tag(Tombstone) == Some(vec.tombstone_tag),
  }
}

test role_classifier_compares_the_whole_address() {
  and {
    role.classify(policy, role.address(policy, Active)) == Some(Active),
    role.classify(policy, role.address(policy, Tombstone)) == Some(Tombstone),
  }
}

test role_classifier_fails_closed_on_unknown_staking_script() {
  let unknown = from_script(policy)
    |> with_delegation_script(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      )
  role.classify(policy, unknown) == None
}
