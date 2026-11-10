//// The connected scenario of the application tests: a fold at the real scale of
//// the checkpoint validator's numbers, over the observer's inception vector.
////
//// The application, the lifecycle observer and the checkpoint validator are run
//// over it by the tests that import this module; it imports no validator.

use aiken/primitive/bytearray
use cardano/address.{Script, VerificationKey, from_verification_key}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{KeyMaterial, KeyStateView, Live}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/registration.{proof_token_name}
use cardano_keri/checkpoint/registration_vectors as vec
use keri_application_requests.{Fold, fold, reference}

pub const hash_proof_policy: ByteArray =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

/// The deployment of the connected scenario: the checkpoint program's own numbers
/// (`d_reg`, the freeze bond, the premium, the minimum ADA). The observer asks a
/// holding to hold at least the minimum ADA and the deposit; a fold delivers a
/// register carrier: that and the freeze bond and one premium. A booking commits
/// at least the registry's minimum ADA and deposit, which is the checkpoint
/// deposit and the freeze bond.
pub const d_reg: Int = 1_000_000_000

pub const freeze_bond: Int = 5_000_000

pub const premium: Int = 2_000_000

pub const checkpoint_min_ada: Int = 2_000_000

pub const observer_floor: Int = 1_002_000_000

pub const booking_floor: Int = 1_007_000_000

pub const floor: Int = 1_009_000_000

pub fn live_datum() -> Data {
  let d = vec.pos_2key_datum
  datum.write(
    Live {
      aid: qb64_aid(d.cesr_aid),
      sn: 0,
      epoch: 0,
      poisoned: False,
      frozen: False,
      born_at: 10,
      refund_to: bytearray.push(refund_hash(), 96),
      topped_up: False,
      keys: keys_of(d),
    },
  )
}

pub fn refund_hash() -> ByteArray {
  when rows.refund_address.payment_credential is {
    VerificationKey(hash) -> hash
    Script(hash) -> hash
  }
}

pub fn keys_of(d: KeyStateView) -> KeyMaterial {
  KeyMaterial {
    cur_keys: d.cur_keys,
    cur_threshold: d.cur_threshold,
    next_keys: d.next_keys,
    next_threshold: d.next_threshold,
    witnesses: d.witnesses,
    toad: d.toad,
  }
}

pub fn as_data(value: Data) -> Data {
  value
}

/// The request of the connected scenario: the AID of the observer's inception
/// vector, committing the datum the observer attests and a deposit at the floor.
pub fn connected_request() -> RegistrationData {
  RegistrationData {
    ..rows.request_data(9001),
    key: qb64_aid(vec.pos_2key_datum.cesr_aid),
    initial_datum: live_datum(),
    deposit: floor,
  }
}

pub fn proof_name() -> ByteArray {
  proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
}

pub fn connected_fold(burn_proof: Bool) -> Fold {
  let data = connected_request()
  let proof_input = Input {
    output_reference: reference(90),
    output: Output {
      address: from_verification_key(
        #"0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee",
      ),
      value: add(from_lovelace(2_000_000), hash_proof_policy, proof_name(), 1),
      datum: NoDatum,
      reference_script: None,
    },
  }
  Fold {
    ..fold(),
    data,
    request_lovelace: floor + cfg.registration_cost + cfg.minimum_tip,
    holding_lovelace: floor,
    holding_datum: live_datum(),
    payload: as_data(vec.pos_2key_evidence),
    extra_inputs: [proof_input],
    extra_mint: if burn_proof {
      [(hash_proof_policy, proof_name(), -1)]
    } else {
      []
    },
  }
}
