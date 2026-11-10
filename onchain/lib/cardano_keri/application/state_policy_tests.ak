//// The state policy of an application, computed on chain (invariant I4).
////
//// The expected values are the script hashes the pinned compiler's blueprint
//// application produces for the same application policies
//// (`configuration_vectors`), never read back from the code under test.

use aiken/primitive/bytearray
use cardano_keri/application/configuration_vectors as vectors
use cardano_keri/application/state_policy.{state_policy}

const template: ByteArray = vectors.state_template

test state_policy_of_the_scenario_application() {
  state_policy(template, vectors.application_policy) == vectors.state_policy
}

test state_policy_of_another_application() {
  state_policy(template, vectors.foreign_application_policy) == vectors.foreign_state_policy
}

test state_policy_of_a_third_application() {
  state_policy(template, vectors.other_application_policy) == vectors.other_state_policy
}

test the_state_policies_of_different_applications_differ() {
  vectors.state_policy != vectors.foreign_state_policy && vectors.state_policy != vectors.other_state_policy && vectors.foreign_state_policy != vectors.other_state_policy
}

fn change_byte(bytes: ByteArray, index: Int) -> ByteArray {
  let byte = bytearray.at(bytes, index)
  bytearray.concat(
    bytearray.take(bytes, index),
    bytearray.push(bytearray.drop(bytes, index + 1), ( byte + 1 ) % 256),
  )
}

/// One changed template byte, at the start, in the middle and at the end,
/// changes the state policy: the policy depends on every byte of the script.
test one_changed_template_byte_changes_the_state_policy() {
  let last = bytearray.length(template) - 1
  let first = bytearray.length(template) / 2
  [0, 3, first, last - 1, last]
    |> list_all(
        fn(index) {
          state_policy(change_byte(template, index), vectors.application_policy) != vectors.state_policy
        },
      )
}

fn list_all(items: List<Int>, check: fn(Int) -> Bool) -> Bool {
  when items is {
    [] -> True
    [item, ..rest] -> check(item) && list_all(rest, check)
  }
}

test the_state_policy_is_a_script_hash() {
  bytearray.length(state_policy(template, vectors.application_policy)) == 28
}
