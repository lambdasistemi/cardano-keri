//// #117 S1 RED: frozen Close message/address bytes and current-controller
//// authorization. Haskell owns the generated fixtures in `close_vectors`.

use aiken/cbor
use aiken/collection/list
use cardano_keri/checkpoint/close.{
  CloseInvalid, CloseValid, close_domain, close_predicate,
  reconstruct_close_message,
}
use cardano_keri/checkpoint/close_vectors as vec

test close_domain_is_frozen() {
  close_domain == "cardano-keri/checkpoint/close/v1"
}

test close_full_refund_address_matches_haskell_plutus_data() {
  cbor.serialise(vec.pos_2key_evidence.refund_address) == vec.golden_refund_address_cbor
}

test close_ten_field_message_matches_haskell_canonical_cbor() {
  cbor.serialise(
    reconstruct_close_message(vec.pos_2key_context, vec.pos_2key_evidence),
  ) == vec.golden_message_cbor_2key
}

test close_accepts_ordinary_two_key_current_threshold() {
  close_predicate(vec.pos_2key_context, vec.pos_2key_evidence) == CloseValid
}

test close_accepts_full_gleif_seven_key_current_threshold() {
  close_predicate(vec.pos_gleif7_context, vec.pos_gleif7_evidence) == CloseValid
}

test close_rejects_malformed_old() {
  invalid(close_predicate(vec.neg_malformed_old_context, vec.pos_2key_evidence))
}

test close_rejects_below_threshold() {
  invalid(
    close_predicate(vec.pos_2key_context, vec.neg_below_threshold_evidence),
  )
}

test close_rejects_bad_and_out_of_range_indices() {
  invalid(close_predicate(vec.pos_2key_context, vec.neg_bad_index_evidence)) && invalid(
    close_predicate(vec.pos_2key_context, vec.neg_out_of_range_evidence),
  )
}

test close_rejects_duplicate_inflation() {
  invalid(close_predicate(vec.pos_2key_context, vec.neg_duplicate_evidence))
}

test close_rejects_wrong_key() {
  invalid(close_predicate(vec.pos_2key_context, vec.neg_wrong_key_evidence))
}

test close_binds_every_reconstructed_field() {
  list.all(
    vec.neg_mutated_contexts,
    fn(context) { invalid(close_predicate(context, vec.pos_2key_evidence)) },
  )
}

test close_binds_the_full_refund_address() {
  invalid(close_predicate(vec.pos_2key_context, vec.neg_redirected_evidence))
}

test close_rejects_fresh_outref_replay() {
  invalid(close_predicate(vec.neg_fresh_outref_context, vec.pos_2key_evidence))
}

fn invalid(verdict) -> Bool {
  when verdict is {
    CloseInvalid(_) -> True
    _ -> False
  }
}
