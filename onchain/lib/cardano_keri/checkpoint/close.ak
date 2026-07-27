//// #117 S1 validator-free Close message and current-controller predicate.
////
//// The signed constructor-0 preimage is reconstructed from deployment, the
//// named spent outref, OLD, and the evidence's full ledger Address. Distinct
//// current-key indices whose Ed25519 signatures verify over canonical Plutus
//// Data CBOR are evaluated by the shared threshold implementation.

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use cardano/address.{Address}
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, DatumInvalid, DatumValid, datum_well_formed,
}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/threshold.{evaluate}

pub const close_domain: ByteArray = "cardano-keri/checkpoint/close/v1"

/// Frozen constructor-0 signed Close preimage. Field order is protocol data.
pub type CloseMessage {
  domain: ByteArray,
  network_id: Int,
  checkpoint_policy_id: ByteArray,
  aid_asset_name: ByteArray,
  cesr_aid: ByteArray,
  spent_txid: ByteArray,
  spent_index: Int,
  prior_seq: Int,
  prior_native_sn: Int,
  refund_address: Address,
}

/// The only prover-supplied Close fields.
pub type CloseEvidence {
  refund_address: Address,
  ctrl_sigs: List<(Int, ByteArray)>,
}

/// Trusted inputs used to reconstruct the signed preimage.
pub type CloseContext {
  network_id: Int,
  checkpoint_policy_id: ByteArray,
  spent_txid: ByteArray,
  spent_index: Int,
  old: CheckpointDatumV1,
}

pub fn reconstruct_close_message(
  context: CloseContext,
  evidence: CloseEvidence,
) -> CloseMessage {
  CloseMessage {
    domain: close_domain,
    network_id: context.network_id,
    checkpoint_policy_id: context.checkpoint_policy_id,
    aid_asset_name: deriveAidAssetName(context.old.cesr_aid),
    cesr_aid: context.old.cesr_aid,
    spent_txid: context.spent_txid,
    spent_index: context.spent_index,
    prior_seq: context.old.seq,
    prior_native_sn: context.old.native_sn,
    refund_address: evidence.refund_address,
  }
}

pub type ClosePredicateError {
  CloseDatumInvalid
  CloseControllerQuorumUnsatisfied
}

pub type ClosePredicateVerdict {
  CloseValid
  CloseInvalid(ClosePredicateError)
}

/// Verify Close authorization against OLD's current controller threshold.
pub fn close_predicate(
  context: CloseContext,
  evidence: CloseEvidence,
) -> ClosePredicateVerdict {
  when datum_well_formed(context.old) is {
    DatumInvalid(_) -> CloseInvalid(CloseDatumInvalid)
    DatumValid -> {
      let preimage = cbor.serialise(
        reconstruct_close_message(context, evidence),
      )
      let signed = verified_indices(
        context.old.cur_keys,
        preimage,
        evidence.ctrl_sigs,
      )
      if evaluate(
        context.old.cur_threshold,
        list.length(context.old.cur_keys),
        signed,
      ) {
        CloseValid
      } else {
        CloseInvalid(CloseControllerQuorumUnsatisfied)
      }
    }
  }
}

fn verified_indices(
  keys: List<ByteArray>,
  message: ByteArray,
  signatures: List<(Int, ByteArray)>,
) -> List<Int> {
  list.unique(
    list.filter_map(
      signatures,
      fn(pair) {
        let (index, signature) = pair
        when list.at(keys, index) is {
          Some(key) ->
            if verify_ed25519_signature(key, message, signature) {
              Some(index)
            } else {
              None
            }
          None -> None
        }
      },
    ),
  )
}
