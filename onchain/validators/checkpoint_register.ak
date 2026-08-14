//// #136 — the small-identity Register vertical.
////
//// This validator deliberately owns only checkpoint creation. Existing
//// lifecycle spending remains in `checkpoint.ak`; keeping it out of this
//// applied program makes a Register reference script deployable under the
//// stock 16 KiB transaction limit.

use aiken/collection/dict
use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of, tokens,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Redeemer, ScriptPurpose,
  Transaction, Withdraw, find_input,
}
use cardano_keri/checkpoint/close.{
  CloseContext, CloseEvidence, CloseValid, close_predicate,
}
use cardano_keri/checkpoint/datum.{CheckpointDatum, CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement_observer.{authorized_payee}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, ArmedDatumValid, ArmedV2, armed_checkpoint,
  armed_datum_well_formed, armed_deadline, armed_hunter, freeze_bond_valid,
  freeze_window_valid,
}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_freeze, observe_migration, observe_register, observe_response_advance,
}
use cardano_keri/checkpoint/registration.{valid_registration_deposit}
use cardano_keri/checkpoint/role.{Active, Armed}

/// Registration evidence is carried by the lifecycle observer withdrawal.
///
/// The #254 migration arms are appended, never inserted: constructor indices
/// are wire surface, so an existing redeemer must keep the index it was
/// deployed with.
pub type MintRedeemer {
  Register
  CloseBurn { checkpoint_ref: OutputReference }
  ConvictBurn { checkpoint_ref: OutputReference }
  /// Enter this generation from its pinned predecessor (#254 T254-104). The
  /// verdict runs in the promoted migration observer; this arm owns the token
  /// mechanics and requires that exact withdrawal.
  MigrateInMint { source_ref: OutputReference }
  /// Enter this generation from the immutable deployed preprod v0 program,
  /// whose only authorized exit is its own `Close`/`CloseBurn` (#254 T254-105).
  LegacyMigrateInMint { source_ref: OutputReference }
}

pub type SpendRedeemer {
  Close { evidence: CloseEvidence }
  Advance
  Freeze { hunter_pkh: ByteArray }
  ClaimFreeze { hunter_output_index: Int }
  Convict {
    convictor_pkh: ByteArray,
    convictor_output_index: Int,
    hunter_output_index: Int,
  }
  /// Leave this generation under its own controller quorum (#254 T254-104).
  MigrateOut
}

const checkpoint_min_ada: Int = 2_000_000

validator checkpoint_register(
  migration_hash: PolicyId,
  lifecycle_hash: PolicyId,
  advance_hash: PolicyId,
  enforcement_hash: PolicyId,
  /// Applied credential of `observer_entitlement`. Required beside
  /// `observer_enforcement` on every Freeze/Convict settlement; both
  /// withdrawal redeemers must be the same envelope value.
  entitlement_hash: PolicyId,
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
      ConvictBurn { checkpoint_ref } ->
        validate_convict_burn(d_reg, freeze_bond, checkpoint_ref, policy_id, tx)
      MigrateInMint { source_ref } -> {
        expect ran_migration_check(migration_hash, policy_id, source_ref, tx)
        validate_migrate_in_tokens(source_ref, policy_id, tx)
      }
      LegacyMigrateInMint { source_ref } -> {
        expect ran_migration_check(migration_hash, policy_id, source_ref, tx)
        validate_migrate_in_tokens(source_ref, policy_id, tx)
      }
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
            entitlement_hash,
            own_hash(tx, own_ref),
            hunter_pkh,
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
      Convict { convictor_pkh, convictor_output_index, hunter_output_index } -> {
        expect
          ran_convict_check(
            enforcement_hash,
            entitlement_hash,
            own_hash(tx, own_ref),
            convictor_pkh,
            own_ref,
            tx,
          )
        validate_convict(
          d_reg,
          freeze_bond,
          convictor_pkh,
          convictor_output_index,
          hunter_output_index,
          own_ref,
          tx,
        )
      }
      MigrateOut -> {
        let own = own_hash(tx, own_ref)
        expect ran_migration_check(migration_hash, own, own_ref, tx)
        validate_migrate_out_tokens(own, own_ref, tx)
      }
    }
  }

  else(_) {
    fail
  }
}

/// The #254 migration arms delegate their verdict to the promoted observer and
/// keep the token mechanics here, where they cannot be delegated without
/// circular trust: the observer would otherwise be asserting facts about the
/// very policy whose program is asking it.
///
/// This mirrors `ran_register_check` exactly, and additionally binds the named
/// source output, so an observation of one migration can never satisfy another.
fn ran_migration_check(
  migration_hash: PolicyId,
  checkpoint_policy: PolicyId,
  source_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let credential: Credential = Script(migration_hash)
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
              claim.action == observe_migration && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(
                source_ref,
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

/// Entry token mechanics: exactly one token of the source's name is minted
/// under this policy and confined to one output. Which successor, and whether
/// its state and value are continuous, is the observer's verdict.
fn validate_migrate_in_tokens(
  source_ref: OutputReference,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(source_input) = find_input(inputs, source_ref)
  expect InlineDatum(_) = source_input.output.datum
  expect [Pair(aid_name, 1)] = dict.to_pairs(tokens(mint, policy_id))
  expect [successor] = list.filter(
    outputs,
    fn(output) { quantity_of(output.value, policy_id, aid_name) > 0 },
  )
  expect quantity_of(successor.value, policy_id, aid_name) == 1
  True
}

/// Exit token mechanics: exactly one token of the spent checkpoint's name is
/// burned under this policy, and no output retains it.
fn validate_migrate_out_tokens(
  own: PolicyId,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect InlineDatum(_) = own_input.output.datum
  expect [Pair(aid_name, -1)] = dict.to_pairs(tokens(mint, own))
  expect quantity_of(own_input.output.value, own, aid_name) == 1
  expect
    list.all(
      outputs,
      fn(output) { quantity_of(output.value, own, aid_name) == 0 },
    )
  True
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

/// The combined family's half of the entitlement division of labour.
///
/// The observer holds the actual evidence and owns the entitlement verdict; the
/// register owns the value. What the register must not delegate is WHO it pays:
/// an envelope that authorized the honest hunter would otherwise sit happily
/// beside a redeemer paying an attacker, and each side would be individually
/// satisfied. So the payee this arm is about to route value to is compared
/// against the payee the observer actually reconciled, and the two cannot
/// diverge. `authorized_payee` returns `None` for any action this observer does
/// not own, so no payee can be read out of an envelope that established no
/// entitlement.
fn ran_enforcement_check(
  enforcement_hash: PolicyId,
  entitlement_hash: PolicyId,
  checkpoint_policy: PolicyId,
  payee_pkh: ByteArray,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  ran_observed_enforcement(
    enforcement_hash,
    entitlement_hash,
    checkpoint_policy,
    observe_freeze,
    payee_pkh,
    own_ref,
    tx,
  )
}

fn ran_convict_check(
  enforcement_hash: PolicyId,
  entitlement_hash: PolicyId,
  checkpoint_policy: PolicyId,
  payee_pkh: ByteArray,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  ran_observed_enforcement(
    enforcement_hash,
    entitlement_hash,
    checkpoint_policy,
    observe_convict,
    payee_pkh,
    own_ref,
    tx,
  )
}

fn zero_withdrawal(tx: Transaction, credential: Credential) -> Bool {
  list.any(
    tx.withdrawals,
    fn(Pair(withdrawal_credential, lovelace)) {
      withdrawal_credential == credential && lovelace == 0
    },
  )
}

fn required_envelope(
  tx: Transaction,
  credential: Credential,
) -> ObserverEnvelope {
  expect Some(Pair(_, redeemer)) = list.find(
    tx.redeemers,
    fn(Pair(purpose, _): Pair<ScriptPurpose, Redeemer>) -> Bool {
      when purpose is {
        Withdraw(redeemer_credential) -> redeemer_credential == credential
        _ -> False
      }
    },
  )
  expect envelope: ObserverEnvelope = redeemer
  envelope
}

/// Both applied observer credentials must appear as zero-lovelace
/// withdrawals, and their redeemers must be the same `ObserverEnvelope`
/// value — not two independently asserted payees.
fn ran_observed_enforcement(
  enforcement_hash: PolicyId,
  entitlement_hash: PolicyId,
  checkpoint_policy: PolicyId,
  action: Int,
  payee_pkh: ByteArray,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let enforcement_credential: Credential = Script(enforcement_hash)
  let entitlement_credential: Credential = Script(entitlement_hash)
  expect zero_withdrawal(tx, enforcement_credential)
  expect zero_withdrawal(tx, entitlement_credential)
  let enforcement_envelope = required_envelope(tx, enforcement_credential)
  let entitlement_envelope = required_envelope(tx, entitlement_credential)
  expect enforcement_envelope == entitlement_envelope
  let claim = enforcement_envelope.claim
  claim.action == action && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(
    own_ref,
  ) && authorized_payee(enforcement_envelope) == Some(payee_pkh)
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

fn convict_source(
  d_reg: Int,
  freeze_bond: Int,
  policy_id: PolicyId,
  input: Input,
) -> (CheckpointDatumV1, Int, Option<ByteArray>) {
  expect InlineDatum(source_data) = input.output.datum
  if input.output.address == role.address(policy_id, Active) {
    expect V1(tip): CheckpointDatum = source_data
    (tip, checkpoint_min_ada + d_reg + freeze_bond, None)
  } else if input.output.address == role.address(policy_id, Armed) {
    expect armed: ArmedDatum = source_data
    expect ArmedDatumValid = armed_datum_well_formed(armed)
    (
      armed_checkpoint(armed),
      checkpoint_min_ada + d_reg + freeze_bond,
      Some(armed_hunter(armed)),
    )
  } else if input.output.address == role.address(policy_id, role.Frozen) {
    expect V1(tip): CheckpointDatum = source_data
    (tip, checkpoint_min_ada + d_reg, None)
  } else {
    fail
  }
}

fn validate_convict_burn(
  d_reg: Int,
  freeze_bond: Int,
  checkpoint_ref: OutputReference,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(checkpoint_input) = find_input(inputs, checkpoint_ref)
  let (tip, protected_lovelace, _) = convict_source(
    d_reg,
    freeze_bond,
    policy_id,
    checkpoint_input,
  )
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect
    checkpoint_input.output.value == (
      from_lovelace(lovelace_of(checkpoint_input.output.value))
        |> merge(from_asset(policy_id, aid_name, 1))
    )
  expect lovelace_of(checkpoint_input.output.value) >= protected_lovelace
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
    let old = armed_checkpoint(armed)
    let deadline = armed_deadline(armed)
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
  let armed = ArmedV2 {
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
  let tip = armed_checkpoint(armed)
  let hunter_pkh = armed_hunter(armed)
  let deadline = armed_deadline(armed)
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

fn expect_exact_payout(
  outputs: List<Output>,
  output_index: Int,
  recipient_pkh: ByteArray,
  lovelace: Int,
) -> Bool {
  expect bytearray.length(recipient_pkh) == 28
  expect Some(output) = list.at(outputs, output_index)
  expect output.address == from_verification_key(recipient_pkh)
  expect output.value == from_lovelace(lovelace)
  expect output.datum == NoDatum
  True
}

fn validate_convict(
  d_reg: Int,
  freeze_bond: Int,
  convictor_pkh: ByteArray,
  convictor_output_index: Int,
  hunter_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let (tip, protected_lovelace, hunter_pkh) = convict_source(
    d_reg,
    freeze_bond,
    own_hash,
    own_input,
  )
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect
    own_input.output.value == (
      from_lovelace(lovelace_of(own_input.output.value))
        |> merge(from_asset(own_hash, aid_name, 1))
    )
  expect lovelace_of(own_input.output.value) >= protected_lovelace
  expect dict.to_pairs(tokens(mint, own_hash)) == [Pair(aid_name, -1)]
  expect
    list.all(
      outputs,
      fn(output) { quantity_of(output.value, own_hash, aid_name) == 0 },
    )
  when hunter_pkh is {
    None ->
      expect_exact_payout(
        outputs,
        convictor_output_index,
        convictor_pkh,
        protected_lovelace,
      )
    Some(recorded_hunter) -> {
      expect convictor_output_index != hunter_output_index
      expect
        expect_exact_payout(
          outputs,
          convictor_output_index,
          convictor_pkh,
          checkpoint_min_ada + d_reg,
        )
      expect
        expect_exact_payout(
          outputs,
          hunter_output_index,
          recorded_hunter,
          freeze_bond,
        )
      True
    }
  }
}
