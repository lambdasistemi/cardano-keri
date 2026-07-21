//// Retained deterministic #116 role-address vectors.

use cardano/address.{from_script, with_delegation_script}
use cardano_keri/checkpoint/freeze_bond_vectors as vec
use cardano_keri/checkpoint/role.{Active, Armed, Frozen, Tombstone}

const policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

test role_active_address_stays_byte_compatible() {
  role.address(policy, Active) == from_script(policy)
}

test role_frozen_hash_is_deterministic() {
  role.hash(policy, Frozen) == #"881658d75a7a9154184d35b016cab83368059bf0c0da1befde545ea6"
}

test role_tombstone_hash_is_deterministic() {
  role.hash(policy, Tombstone) == #"44f8b57fb50b9ffee7ec21037a031a61b5b3919a7fee4f5eab4cea77"
}

test role_tags_are_exact() {
  and {
    role.role_tag(Active) == None,
    role.role_tag(Frozen) == Some(vec.frozen_tag),
    role.role_tag(Tombstone) == Some(vec.tombstone_tag),
    role.role_tag(Armed) == Some(#"02"),
    role.role_tag(Armed) == Some(vec.armed_tag),
  }
}

test role_armed_hash_uses_tag_0x02() {
  role.hash(policy, Armed) == vec.armed_role_hash
}

test role_classifier_compares_the_whole_address() {
  and {
    role.classify(policy, role.address(policy, Active)) == Some(Active),
    role.classify(policy, role.address(policy, Frozen)) == Some(Frozen),
    role.classify(policy, role.address(policy, Tombstone)) == Some(Tombstone),
    role.classify(policy, role.address(policy, Armed)) == Some(Armed),
  }
}

test role_classifier_fails_closed_on_unknown_staking_script() {
  let unknown = from_script(policy)
    |> with_delegation_script(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      )
  role.classify(policy, unknown) == None
}
