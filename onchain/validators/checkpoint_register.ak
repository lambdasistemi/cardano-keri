//// #136 — the small-identity Register vertical.
////
//// This validator deliberately owns only checkpoint creation. Existing
//// lifecycle spending remains in `checkpoint.ak`; keeping it out of this
//// applied program makes a Register reference script deployable under the
//// stock 16 KiB transaction limit.

use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of, tokens,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Redeemer, ScriptPurpose,
  Transaction, Withdraw, find_input,
}
use cardano_keri/checkpoint/datum.{CheckpointDatum, CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement_observer.{authorized_payee}
use cardano_keri/checkpoint/freeze_bond.{freeze_bond_valid}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_migration, observe_register,
}
use cardano_keri/checkpoint/registration.{valid_registration_deposit}
use cardano_keri/checkpoint/role.{Active}

/// Registration evidence is carried by the lifecycle observer withdrawal.
///
/// Constructor indices are wire surface once a generation is deployed: a
/// deployed generation only ever appends arms. A generation that has no
/// deployment may drop arms, which moves the later ones up.
pub type MintRedeemer {
  Register
  ConvictBurn { checkpoint_ref: OutputReference }
}

pub type SpendRedeemer {
  Advance
  Convict { convictor_pkh: ByteArray, convictor_output_index: Int }
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
  /// `observer_enforcement` on every Convict settlement; both withdrawal
  /// redeemers must be the same envelope value.
  entitlement_hash: PolicyId,
  /// Applied for a stable arity; this program no longer reads it.
  network_id: Int,
  d_reg: Int,
  freeze_bond: Int,
) {
  mint(redeemer: Data, policy_id: PolicyId, tx: Transaction) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect mint_redeemer: MintRedeemer = redeemer
    when mint_redeemer is {
      Register -> {
        expect ran_register_check(lifecycle_hash, policy_id, tx)
        validate_register(d_reg, freeze_bond, policy_id, tx)
      }
      ConvictBurn { checkpoint_ref } ->
        validate_convict_burn(d_reg, freeze_bond, checkpoint_ref, policy_id, tx)
    }
  }

  spend(
    _datum: Option<Data>,
    redeemer: Data,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect spend_redeemer: SpendRedeemer = redeemer
    when spend_redeemer is {
      Advance -> {
        expect
          ran_advance_check(advance_hash, own_hash(tx, own_ref), own_ref, tx)
        validate_advance(d_reg, own_ref, tx)
      }
      Convict { convictor_pkh, convictor_output_index } -> {
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

/// The #254 migrate-out arm delegates its verdict to the promoted observer and
/// keeps the token mechanics here, where they cannot be delegated without
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
              claim.action == observe_advance && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(
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

fn validate_convict_burn(
  d_reg: Int,
  freeze_bond: Int,
  checkpoint_ref: OutputReference,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(checkpoint_input) = find_input(inputs, checkpoint_ref)
  let (tip, protected_lovelace) = convict_source(
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

/// The protected lovelace of a checkpoint a conviction may burn, and its tip.
/// Only an ACTIVE checkpoint is a source: any other role address, or a
/// datum of another family, fails.
fn convict_source(
  d_reg: Int,
  freeze_bond: Int,
  policy_id: PolicyId,
  input: Input,
) -> (CheckpointDatumV1, Int) {
  expect InlineDatum(source_data) = input.output.datum
  expect input.output.address == role.address(policy_id, Active)
  expect V1(tip): CheckpointDatum = source_data
  (tip, checkpoint_min_ada + d_reg + freeze_bond)
}

fn validate_advance(
  d_reg: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(old_datum_data) = own_input.output.datum
  expect V1(old): CheckpointDatum = old_datum_data
  let aid_name = deriveAidAssetName(old.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(own_hash) },
  )
  expect InlineDatum(new_datum_data) = state_output.datum
  expect V1(_new): CheckpointDatum = new_datum_data
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect state_output.value == own_input.output.value
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  expect lovelace_of(state_output.value) >= checkpoint_min_ada + d_reg
  True
}

fn validate_convict(
  d_reg: Int,
  freeze_bond: Int,
  convictor_pkh: ByteArray,
  convictor_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let (tip, protected_lovelace) = convict_source(
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
  expect_exact_payout(
    outputs,
    convictor_output_index,
    convictor_pkh,
    protected_lovelace,
  )
}
