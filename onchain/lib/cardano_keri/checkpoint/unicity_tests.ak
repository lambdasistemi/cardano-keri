//// #116 S3 RED — the Aiken mirror of the shared append-only MPFS vectors.

use cardano_keri/checkpoint/unicity as unicity
use cardano_keri/checkpoint/unicity_vectors as vec

test unicity_registered_marker_is_frozen() {
  unicity.registered_marker == #"13506209dad003c83b1b6828034166a601500d6c09d622e3196ba78725f1d8ce"
}

test unicity_empty_root_matches_shared_vector() {
  unicity.empty_root() == vec.empty_root
}

test unicity_registry_thread_name_matches_shared_vector() {
  unicity.registry_thread_name(vec.registry_seed) == vec.registry_thread_name
}

test unicity_accepts_depth_0_absence_transition() {
  unicity.insert_registered(
    vec.depth_0_old_root,
    vec.depth_0_key,
    vec.depth_0_proof,
  ) == vec.depth_0_new_root
}

test unicity_accepts_depth_8_absence_transition() {
  unicity.insert_registered(
    vec.depth_8_old_root,
    vec.depth_8_key,
    vec.depth_8_proof,
  ) == vec.depth_8_new_root
}

test unicity_accepts_depth_16_absence_transition() {
  unicity.insert_registered(
    vec.depth_16_old_root,
    vec.depth_16_key,
    vec.depth_16_proof,
  ) == vec.depth_16_new_root
}

test unicity_rejects_wrong_absence_proof() fail {
  unicity.insert_registered(
    vec.depth_8_old_root,
    vec.depth_8_key,
    vec.depth_16_proof,
  ) == vec.depth_8_new_root
}

test unicity_rejects_stale_root_proof() fail {
  unicity.insert_registered(
    vec.depth_16_old_root,
    vec.depth_8_key,
    vec.depth_8_proof,
  ) == vec.depth_8_new_root
}

test unicity_rejects_present_key_insert() fail {
  unicity.insert_registered(
    vec.depth_0_new_root,
    vec.depth_0_key,
    vec.depth_0_proof,
  ) == vec.depth_0_new_root
}
