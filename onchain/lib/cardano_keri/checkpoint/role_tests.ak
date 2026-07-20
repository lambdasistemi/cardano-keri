//// #116 S3 RED — deterministic full-address role derivation.

use cardano/address.{from_script, with_delegation_script}
use cardano_keri/checkpoint/role.{Active, Frozen, Registry, Tombstone}

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

test role_registry_hash_is_deterministic() {
  role.hash(policy, Registry) == #"d5a386b02d995fcb2295d04733fc0501108a70d7351a504c53ba711e"
}

test role_registry_is_inline_staking_script_credential() {
  role.address(policy, Registry) == (
    from_script(policy)
      |> with_delegation_script(
          #"d5a386b02d995fcb2295d04733fc0501108a70d7351a504c53ba711e",
        )
  )
}

test role_classifier_compares_the_whole_address() {
  and {
    role.classify(policy, role.address(policy, Active)) == Some(Active),
    role.classify(policy, role.address(policy, Frozen)) == Some(Frozen),
    role.classify(policy, role.address(policy, Tombstone)) == Some(Tombstone),
    role.classify(policy, role.address(policy, Registry)) == Some(Registry),
  }
}

test role_classifier_fails_closed_on_unknown_staking_script() {
  let unknown = from_script(policy)
    |> with_delegation_script(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      )
  role.classify(policy, unknown) == None
}
