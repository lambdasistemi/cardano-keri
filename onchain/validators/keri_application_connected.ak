//// The connected scenario of the application tests: a fold at the real scale of
//// the checkpoint validator's numbers, over the observer's inception vector.
////
//// The application, the lifecycle observer and the checkpoint validator are run
//// over it by the tests that import this module; it imports no validator.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Script, VerificationKey, from_verification_key}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{KeyMaterial, KeyStateView, Live}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/qualified.{code_b, code_d, qualify}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
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
  live_datum_of(vec.pos_2key_datum)
}

/// The initial checkpoint datum of the inception whose key state is `d`.
pub fn live_datum_of(d: KeyStateView) -> Data {
  live_datum_for(d, qb64_aid(d.cesr_aid))
}

/// The initial checkpoint datum of the inception whose key state is `d` and whose identifier text is `aid`.
pub fn live_datum_for(d: KeyStateView, aid: ByteArray) -> Data {
  datum.write(
    Live {
      aid,
      sn: 0,
      epoch: 0,
      poisoned: False,
      frozen: False,
      born_at: 10,
      refund_to: bytearray.push(refund_hash(), 96),
      topped_up: False,
      keys: KeyMaterial {
        ..keys_of(d),
        cur_keys: list.map(
          d.cur_keys,
          fn(key) {
            qualify(
              if bytearray.at(aid, 0) == code_b {
                code_b
              } else {
                code_d
              },
              key,
            )
          },
        ),
      },
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
    cur_keys: list.map(d.cur_keys, fn(key) { qualify(code_d, key) }),
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
  connected_request_of(vec.pos_2key_datum)
}

/// The request of the inception whose key state is `d`.
pub fn connected_request_of(d: KeyStateView) -> RegistrationData {
  connected_request_for(d, qb64_aid(d.cesr_aid))
}

/// The request of the inception whose key state is `d` and whose identifier text is `aid`.
pub fn connected_request_for(
  d: KeyStateView,
  aid: ByteArray,
) -> RegistrationData {
  RegistrationData {
    ..rows.request_data(9001),
    key: aid,
    initial_datum: live_datum_for(d, aid),
    deposit: floor,
  }
}

pub fn proof_name() -> ByteArray {
  proof_name_of(vec.pos_2key_evidence, vec.pos_2key_datum)
}

/// The name of the hash-proof token of an inception: its event bytes and AID.
pub fn proof_name_of(
  evidence: RegistrationEvidence,
  d: KeyStateView,
) -> ByteArray {
  proof_token_name(evidence.event_bytes, d.cesr_aid)
}

pub fn connected_fold() -> Fold {
  Fold {
    ..fold(),
    data: connected_request(),
    request_lovelace: floor + cfg.registration_cost + cfg.minimum_tip,
    holding_lovelace: floor,
    holding_datum: live_datum(),
  }
}
