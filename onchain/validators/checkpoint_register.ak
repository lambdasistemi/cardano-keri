//// #136 — the small-identity Register vertical.
////
//// This validator deliberately owns only checkpoint creation. Existing
//// lifecycle spending remains in `checkpoint.ak`; keeping it out of this
//// applied program makes a Register reference script deployable under the
//// stock 16 KiB transaction limit.

use aiken/collection/dict
use aiken/collection/list
use aiken/interval
use cardano/address.{Credential, Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of, tokens,
}
use cardano/transaction.{
  InlineDatum, NoDatum, OutputReference, Transaction, Withdraw, find_input,
}
use cardano_keri/checkpoint/close.{
  CloseContext, CloseEvidence, CloseValid, close_predicate,
}
use cardano_keri/checkpoint/datum.{CheckpointDatum, V1}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, ArmedDatumValid, ArmedV1, armed_datum_well_formed,
  freeze_bond_valid, freeze_window_valid,
}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_freeze,
  observe_register, observe_response_advance,
}
use cardano_keri/checkpoint/registration.{valid_registration_deposit}
use cardano_keri/checkpoint/role.{Active, Armed}

/// Registration evidence is carried by the lifecycle observer withdrawal.
pub type MintRedeemer {
  Register
  CloseBurn { checkpoint_ref: OutputReference }
}

pub type SpendRedeemer {
  Close { evidence: CloseEvidence }
  Advance
  Freeze { hunter_pkh: ByteArray }
  ClaimFreeze { hunter_output_index: Int }
}

const checkpoint_min_ada: Int = 2_000_000

validator checkpoint_register(
  _version: Int,
  lifecycle_hash: PolicyId,
  advance_hash: PolicyId,
  enforcement_hash: PolicyId,
  network_id: Int,
  d_reg: Int,
  freeze_bond: Int,
  freeze_window: Int,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, tx: Transaction) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect freeze_window_valid(freeze_window)
    when redeemer is {
      Register -> {
        expect ran_register_check(lifecycle_hash, policy_id, tx)
        validate_register(d_reg, freeze_bond, policy_id, tx)
      }
      CloseBurn { checkpoint_ref } ->
        validate_close_burn(d_reg, freeze_bond, checkpoint_ref, policy_id, tx)
    }
  }

  spend(
    _datum: Option<Data>,
    redeemer: SpendRedeemer,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect freeze_window_valid(freeze_window)
    when redeemer is {
      Close { evidence } ->
        validate_close(network_id, d_reg, freeze_bond, evidence, own_ref, tx)
      Advance -> {
        expect
          ran_advance_check(advance_hash, own_hash(tx, own_ref), own_ref, tx)
        validate_advance(d_reg, freeze_bond, own_ref, tx)
      }
      Freeze { hunter_pkh } -> {
        expect
          ran_enforcement_check(
            enforcement_hash,
            own_hash(tx, own_ref),
            own_ref,
            tx,
          )
        validate_freeze(
          d_reg,
          freeze_bond,
          freeze_window,
          hunter_pkh,
          own_ref,
          tx,
        )
      }
      ClaimFreeze { hunter_output_index } ->
        validate_claim(d_reg, freeze_bond, hunter_output_index, own_ref, tx)
    }
  }

  else(_) {
    fail
  }
}

fn own_hash(tx: Transaction, own_ref: OutputReference) -> PolicyId {
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect Script(hash) = own_input.output.address.payment_credential
  hash
}

fn ran_register_check(
  lifecycle_hash: PolicyId,
  checkpoint_policy: PolicyId,
  tx: Transaction,
) -> Bool {
  let credential: Credential = Script(lifecycle_hash)
  expect
    list.any(
      tx.withdrawals,
      fn(Pair(withdrawal_credential, lovelace)) {
        withdrawal_credential == credential && lovelace == 0
      },
    )
  expect
    list.any(
      tx.redeemers,
      fn(Pair(purpose, redeemer)) {
        when purpose is {
          Withdraw(redeemer_credential) ->
            if redeemer_credential == credential {
              expect envelope: ObserverEnvelope = redeemer
              let claim = envelope.claim
              claim.action == observe_register && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == None
            } else {
              False
            }
          _ -> False
        }
      },
    )
  True
}

fn ran_advance_check(
  advance_hash: PolicyId,
  checkpoint_policy: PolicyId,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let credential: Credential = Script(advance_hash)
  expect
    list.any(
      tx.withdrawals,
      fn(Pair(withdrawal_credential, lovelace)) {
        withdrawal_credential == credential && lovelace == 0
      },
    )
  expect
    list.any(
      tx.redeemers,
      fn(Pair(purpose, redeemer)) {
        when purpose is {
          Withdraw(redeemer_credential) ->
            if redeemer_credential == credential {
              expect envelope: ObserverEnvelope = redeemer
              let claim = envelope.claim
              (
                claim.action == observe_advance || claim.action == observe_response_advance
              ) && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(
                own_ref,
              )
            } else {
              False
            }
          _ -> False
        }
      },
    )
  True
}

fn ran_enforcement_check(
  enforcement_hash: PolicyId,
  checkpoint_policy: PolicyId,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let credential: Credential = Script(enforcement_hash)
  expect
    list.any(
      tx.withdrawals,
      fn(Pair(withdrawal_credential, lovelace)) {
        withdrawal_credential == credential && lovelace == 0
      },
    )
  expect
    list.any(
      tx.redeemers,
      fn(Pair(purpose, redeemer)) {
        when purpose is {
          Withdraw(redeemer_credential) ->
            if redeemer_credential == credential {
              expect envelope: ObserverEnvelope = redeemer
              let claim = envelope.claim
              claim.action == observe_freeze && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(
                own_ref,
              )
            } else {
              False
            }
          _ -> False
        }
      },
    )
  True
}

fn validate_register(
  d_reg: Int,
  freeze_bond: Int,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect [Pair(aid_name, 1)] = dict.to_pairs(tokens(mint, policy_id))
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(policy_id) },
  )
  expect quantity_of(state_output.value, policy_id, aid_name) == 1
  expect InlineDatum(datum_data) = state_output.datum
  expect V1(d): CheckpointDatum = datum_data
  expect aid_name == deriveAidAssetName(d.cesr_aid)
  expect
    list.all(
      inputs,
      fn(input) { input.output.address.payment_credential != Script(policy_id) },
    )
  expect
    state_output.value == (
      from_lovelace(lovelace_of(state_output.value))
        |> merge(from_asset(policy_id, aid_name, 1))
    )
  expect
    lovelace_of(state_output.value) >= checkpoint_min_ada + d_reg + freeze_bond
  True
}

fn validate_close_burn(
  d_reg: Int,
  freeze_bond: Int,
  checkpoint_ref: OutputReference,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(checkpoint_input) = find_input(inputs, checkpoint_ref)
  expect checkpoint_input.output.address == from_script(policy_id)
  expect InlineDatum(datum_data) = checkpoint_input.output.datum
  expect V1(old): CheckpointDatum = datum_data
  let aid_name = deriveAidAssetName(old.cesr_aid)
  expect
    checkpoint_input.output.value == (
      from_lovelace(lovelace_of(checkpoint_input.output.value))
        |> merge(from_asset(policy_id, aid_name, 1))
    )
  expect
    lovelace_of(checkpoint_input.output.value) >= checkpoint_min_ada + d_reg + freeze_bond
  expect dict.to_pairs(tokens(mint, policy_id)) == [Pair(aid_name, -1)]
  expect
    list.length(
      list.filter(
        inputs,
        fn(input) { quantity_of(input.output.value, policy_id, aid_name) == 1 },
      ),
    ) == 1
  expect
    list.all(
      outputs,
      fn(output) { quantity_of(output.value, policy_id, aid_name) == 0 },
    )
  True
}

fn validate_close(
  network_id: Int,
  d_reg: Int,
  freeze_bond: Int,
  evidence: CloseEvidence,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == from_script(own_hash)
  expect InlineDatum(datum_data) = own_input.output.datum
  expect V1(old): CheckpointDatum = datum_data
  let aid_name = deriveAidAssetName(old.cesr_aid)
  expect
    own_input.output.value == (
      from_lovelace(lovelace_of(own_input.output.value))
        |> merge(from_asset(own_hash, aid_name, 1))
    )
  expect
    lovelace_of(own_input.output.value) >= checkpoint_min_ada + d_reg + freeze_bond
  expect
    close_predicate(
      CloseContext {
        network_id,
        checkpoint_policy_id: own_hash,
        spent_txid: own_ref.transaction_id,
        spent_index: own_ref.output_index,
        old,
      },
      evidence,
    ) == CloseValid
  expect dict.to_pairs(tokens(mint, own_hash)) == [Pair(aid_name, -1)]
  expect evidence.refund_address.payment_credential != Script(own_hash)
  expect [refund] = list.filter(
    outputs,
    fn(output) { output.address == evidence.refund_address },
  )
  expect refund.datum == NoDatum
  expect
    refund.value == merge(
      own_input.output.value,
      from_asset(own_hash, aid_name, -1),
    )
  expect
    list.all(
      outputs,
      fn(output) { quantity_of(output.value, own_hash, aid_name) == 0 },
    )
  True
}

fn validate_advance(
  d_reg: Int,
  freeze_bond: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect InlineDatum(old_datum_data) = own_input.output.datum
  let (old, expected_value, protected_lovelace) = if own_input.output.address == role.address(
    own_hash,
    Active,
  ) {
    expect V1(old): CheckpointDatum = old_datum_data
    (old, own_input.output.value, checkpoint_min_ada + d_reg)
  } else if own_input.output.address == role.address(own_hash, Armed) {
    expect armed: ArmedDatum = old_datum_data
    expect ArmedDatumValid = armed_datum_well_formed(armed)
    let ArmedV1 { checkpoint: old, deadline, .. } = armed
    expect !interval.is_empty(validity_range)
    expect interval.Finite(upper) = validity_range.upper_bound.bound_type
    expect upper < deadline
    (old, own_input.output.value, checkpoint_min_ada + d_reg + freeze_bond)
  } else if own_input.output.address == role.address(own_hash, role.Frozen) {
    expect V1(old): CheckpointDatum = old_datum_data
    (
      old,
      own_input.output.value |> merge(from_lovelace(freeze_bond)),
      checkpoint_min_ada + d_reg + freeze_bond,
    )
  } else {
    fail
  }
  let aid_name = deriveAidAssetName(old.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(own_hash) },
  )
  expect InlineDatum(new_datum_data) = state_output.datum
  expect V1(_new): CheckpointDatum = new_datum_data
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect state_output.value == expected_value
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  expect lovelace_of(state_output.value) >= protected_lovelace
  True
}

fn validate_freeze(
  d_reg: Int,
  freeze_bond: Int,
  freeze_window: Int,
  hunter_pkh: ByteArray,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(tip_data) = own_input.output.datum
  expect V1(tip): CheckpointDatum = tip_data
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect
    lovelace_of(own_input.output.value) >= checkpoint_min_ada + d_reg + freeze_bond
  expect !interval.is_empty(validity_range)
  expect interval.Finite(upper) = validity_range.upper_bound.bound_type
  let armed = ArmedV1 {
    checkpoint: tip,
    hunter_pkh,
    deadline: upper + freeze_window,
  }
  expect ArmedDatumValid = armed_datum_well_formed(armed)
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, Armed) },
  )
  expect state_output.value == own_input.output.value
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect InlineDatum(successor_data) = state_output.datum
  expect successor: ArmedDatum = successor_data
  expect successor == armed
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  True
}

fn validate_claim(
  d_reg: Int,
  freeze_bond: Int,
  hunter_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, role.Armed)
  expect InlineDatum(armed_data) = own_input.output.datum
  expect armed: ArmedDatum = armed_data
  expect ArmedDatumValid = armed_datum_well_formed(armed)
  let ArmedV1 { checkpoint: tip, hunter_pkh, deadline } = armed
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect
    lovelace_of(own_input.output.value) >= checkpoint_min_ada + d_reg + freeze_bond
  expect !interval.is_empty(validity_range)
  expect interval.Finite(lower) = validity_range.lower_bound.bound_type
  expect lower >= deadline
  expect Some(hunter_output) = list.at(outputs, hunter_output_index)
  expect hunter_output.address == from_verification_key(hunter_pkh)
  expect hunter_output.value == from_lovelace(freeze_bond)
  expect NoDatum = hunter_output.datum
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, role.Frozen) },
  )
  let expected_value = own_input.output.value
    |> merge(from_lovelace(-freeze_bond))
  expect state_output.value == expected_value
  expect lovelace_of(state_output.value) >= checkpoint_min_ada + d_reg
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect InlineDatum(successor_data) = state_output.datum
  expect V1(successor): CheckpointDatum = successor_data
  expect successor == tip
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  True
}
