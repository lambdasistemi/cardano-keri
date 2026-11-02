//// #136 — the small-identity Register vertical.
////
//// This validator deliberately owns only checkpoint creation. Existing
//// lifecycle spending remains in `checkpoint.ak`; keeping it out of this
//// applied program makes a Register reference script deployable under the
//// stock 16 KiB transaction limit.

use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{Finite}
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of, tokens,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Redeemer, ScriptPurpose,
  Transaction, Withdraw, find_input,
}
use cardano_keri/checkpoint/datum.{
  CheckpointDatum, Live, TerminationPending, V2,
}
use cardano_keri/checkpoint/enforcement_observer.{authorized_payee}
use cardano_keri/checkpoint/freeze_bond.{freeze_bond_valid}
use cardano_keri/checkpoint/message.{aid_digest, deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_migration, observe_register,
}
use cardano_keri/checkpoint/refund
use cardano_keri/checkpoint/registration.{valid_registration_deposit}
use cardano_keri/checkpoint/role.{Active}
use cardano_keri/checkpoint/value.{held_value, with_value}

/// Registration evidence is carried by the lifecycle observer withdrawal.
///
/// Constructor indices are wire surface once a generation is deployed: a
/// deployed generation only ever appends arms. A generation that has no
/// deployment may drop arms, which moves the later ones up.
pub type MintRedeemer {
  Register
}

pub type SpendRedeemer {
  /// `payee_output_index` names the output that receives the premium when
  /// the pool covers it; it is not read otherwise.
  Advance { payee_output_index: Int }
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
  /// The network a refund address must be written for.
  network_id: Int,
  d_reg: Int,
  freeze_bond: Int,
  /// The premium (Lean `Params.P`) a rotation pays from the pool.
  premium: Int,
) {
  mint(redeemer: Data, policy_id: PolicyId, tx: Transaction) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect premium >= 0
    expect mint_redeemer: MintRedeemer = redeemer
    when mint_redeemer is {
      Register -> {
        expect ran_register_check(lifecycle_hash, policy_id, tx)
        validate_register(network_id, d_reg, freeze_bond, policy_id, tx)
      }
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
    expect premium >= 0
    expect spend_redeemer: SpendRedeemer = redeemer
    when spend_redeemer is {
      Advance { payee_output_index } -> {
        expect
          ran_advance_check(advance_hash, own_hash(tx, own_ref), own_ref, tx)
        validate_advance(
          d_reg,
          freeze_bond,
          premium,
          payee_output_index,
          own_ref,
          tx,
        )
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
          network_id,
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
  network_id: Int,
  d_reg: Int,
  freeze_bond: Int,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = tx
  expect [Pair(aid_name, 1)] = dict.to_pairs(tokens(mint, policy_id))
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(policy_id) },
  )
  expect quantity_of(state_output.value, policy_id, aid_name) == 1
  expect InlineDatum(datum_data) = state_output.datum
  expect  
      V2(Live {
        aid,
        sn: 0,
        epoch: 0,
        poisoned: False,
        frozen: False,
        born_at,
        refund_to,
        ..
      }): CheckpointDatum
    = datum_data
  expect Some(digest) = aid_digest(aid)
  expect aid_name == deriveAidAssetName(digest)
  expect Finite(upper) = validity_range.upper_bound.bound_type
  expect born_at == upper
  expect refund.payable(network_id, refund_to)
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

fn validate_advance(
  d_reg: Int,
  freeze_bond: Int,
  premium: Int,
  payee_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(old_data) = own_input.output.datum
  expect V2(old): CheckpointDatum = old_data
  expect Live { aid, epoch, frozen, born_at, refund_to, .. } = old
  expect [Pair(aid_name, 1)] = dict.to_pairs(
    tokens(own_input.output.value, own_hash),
  )
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(own_hash) },
  )
  expect InlineDatum(new_data) = state_output.datum
  expect V2(new): CheckpointDatum = new_data
  expect  
      Live {
        aid: new_aid,
        epoch: new_epoch,
        poisoned: False,
        frozen: new_frozen,
        born_at: new_born_at,
        refund_to: new_refund_to,
        ..
      }
    = new
  expect and {
      new_aid == aid,
      new_epoch == epoch + 1,
      new_frozen == frozen,
      new_born_at == born_at,
      new_refund_to == refund_to,
    }
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  expect Some(pool) = with_value(
    checkpoint_min_ada,
    d_reg,
    freeze_bond,
    old,
    lovelace_of(own_input.output.value),
  )
  let paid = premium <= pool
  let pool_after = if paid {
    pool - premium
  } else {
    pool
  }
  expect
    state_output.value == (
      from_lovelace(
        held_value(checkpoint_min_ada, d_reg, freeze_bond, new, pool_after),
      )
        |> merge(from_asset(own_hash, aid_name, 1))
    )
  if paid {
    expect Some(payee) = list.at(outputs, payee_output_index)
    quantity_of(payee.value, own_hash, aid_name) == 0 && lovelace_of(
      payee.value,
    ) >= premium
  } else {
    True
  }
}

/// Convict a live checkpoint: the token stays at the checkpoint address in a
/// pending termination that holds the minimum ADA, the convictor receives the
/// registration deposit, and the refund address receives the bond (unless
/// frozen) and the pool.
fn validate_convict(
  network_id: Int,
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
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(source_data) = own_input.output.datum
  expect V2(live): CheckpointDatum = source_data
  expect Live { aid, sn, epoch, frozen, refund_to, keys, .. } = live
  expect [Pair(aid_name, 1)] = dict.to_pairs(
    tokens(own_input.output.value, own_hash),
  )
  expect Some(pool) = with_value(
    checkpoint_min_ada,
    d_reg,
    freeze_bond,
    live,
    lovelace_of(own_input.output.value),
  )
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  let terminated = TerminationPending { aid, sn, epoch, keys }
  expect [pending_output] = list.filter(
    outputs,
    fn(output) { quantity_of(output.value, own_hash, aid_name) > 0 },
  )
  let pending_datum: CheckpointDatum = V2(terminated)
  expect and {
      pending_output.address == from_script(own_hash),
      pending_output.datum == InlineDatum(pending_datum),
      pending_output.value == (
        from_lovelace(
          held_value(checkpoint_min_ada, d_reg, freeze_bond, terminated, 0),
        )
          |> merge(from_asset(own_hash, aid_name, 1))
      ),
    }
  let bond_held = if frozen {
    0
  } else {
    freeze_bond
  }
  expect_exact_payout(outputs, convictor_output_index, convictor_pkh, d_reg) && refund_paid(
    network_id,
    outputs,
    convictor_output_index,
    refund_to,
    bond_held + pool,
  )
}

/// Some output other than the convictor's pays at least `required` lovelace
/// to the refund address, whose ledger bytes the datum carries. A refund of
/// nothing needs no output.
fn refund_paid(
  network_id: Int,
  outputs: List<Output>,
  skip_index: Int,
  refund_to: ByteArray,
  required: Int,
) -> Bool {
  required == 0 || list.indexed_foldr(
    outputs,
    False,
    fn(index, output, found) {
      found || index != skip_index && refund.ledger_bytes(
        network_id,
        output.address,
      ) == Some(refund_to) && lovelace_of(output.value) >= required
    },
  )
}
