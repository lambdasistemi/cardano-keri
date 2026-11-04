//// The deposit option of Advance (Lean `CardanoKeri.CheckpointDeposit`, #517).
////
//// The controller's witnessed rotation may restore the freeze bond: the
//// successor is unfrozen and holds the bond again. Nobody but the controller
//// chooses that option, because the new current keys of the rotation sign an
//// intent that names everything the transaction decides: the network, the
//// checkpoint policy, the exact output spent, the identifier, the sequence
//// number and the epoch the rotation opens, and the amount that moves into the
//// output.
////
//// The signed bytes are the intent's Plutus Data serialisation. The signers are
//// the current keys the rotation event reveals, at the threshold it declares: a
//// signature is a position in that key list and the signature bytes; a position
//// outside the list never counts, a repeated position counts once, a signature
//// that does not verify never counts, and the distinct counted positions must
//// satisfy the threshold.

use aiken/cbor
use aiken/collection/list
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference}
use cardano_keri/checkpoint/advance.{verified_indices}
use cardano_keri/checkpoint/threshold.{Threshold, evaluate}

/// The domain tag, frozen: a new layout is a new tag.
pub const deposit_domain: ByteArray = "cardano-keri/checkpoint/deposit/v1"

/// What the new keys sign. Constructor 0, eight fields; the constructor index
/// and the field order are protocol surface.
pub type DepositIntent {
  domain: ByteArray,
  network_id: Int,
  checkpoint_policy: PolicyId,
  spent_ref: OutputReference,
  aid: ByteArray,
  new_sn: Int,
  new_epoch: Int,
  deposit: Int,
}

/// The intent the validator requires (Lean `intentFor`). Every argument is a
/// fact the validator reads from the transaction or from its own parameters;
/// none comes from the redeemer.
pub fn required_intent(
  network_id: Int,
  checkpoint_policy: PolicyId,
  spent_ref: OutputReference,
  aid: ByteArray,
  new_sn: Int,
  new_epoch: Int,
  deposit: Int,
) -> DepositIntent {
  DepositIntent {
    domain: deposit_domain,
    network_id,
    checkpoint_policy,
    spent_ref,
    aid,
    new_sn,
    new_epoch,
    deposit,
  }
}

/// The signed bytes of an intent.
pub fn intent_bytes(intent: DepositIntent) -> ByteArray {
  cbor.serialise(intent)
}

/// The keys at the threshold signed the intent (Lean `signed`): the distinct
/// positions whose signature verifies satisfy the threshold.
pub fn deposit_authorized(
  keys: List<ByteArray>,
  threshold: Threshold,
  signatures: List<(Int, ByteArray)>,
  intent: DepositIntent,
) -> Bool {
  evaluate(
    threshold,
    list.length(keys),
    verified_indices(keys, intent_bytes(intent), signatures),
  )
}
