//// The registry checkpoint validator.
////
//// A checkpoint is the output at this validator's address that holds one
//// token of the registry's state policy named for the checkpoint's key: the
//// active token of the AID (Lean `ConsumerIdentity.representativeAsset`). The
//// registry's state policy and name are applied parameters. The validator
//// mints nothing: the registry's fold delivers the checkpoint with its token,
//// and every spend keeps that token, once, at this address.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Redeemer, ScriptPurpose,
  Transaction, Withdraw, find_input,
}
use cardano_keri/checkpoint/datum.{Live, TerminationPending, pending_aid}
use cardano_keri/checkpoint/deposit.{deposit_authorized, required_intent}
use cardano_keri/checkpoint/enforcement_observer.{authorized_payee}
use cardano_keri/checkpoint/freeze_bond.{freeze_bond_valid}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, observe_advance, observe_convict, observe_freeze,
}
use cardano_keri/checkpoint/refund
use cardano_keri/checkpoint/registration.{valid_registration_deposit}
use cardano_keri/checkpoint/role.{Active}
use cardano_keri/checkpoint/value.{held_value, with_value}
use singular_state/preimage.{
  RegistryIdentity, active_token_name, approval_name, termination_preimage,
}

/// The bond option of an Advance (Lean `BondOp`): keep the bond state, or
/// deposit the bond. Constructor indices are wire surface.
pub type BondOp {
  /// The successor keeps the frozen flag of the spent checkpoint.
  Keep
  /// The successor is unfrozen and holds the bond again. The signatures are
  /// pairs of a position in the successor's current keys and the signature
  /// bytes over the deposit intent (see `cardano_keri/checkpoint/deposit`).
  Deposit { signatures: List<(Int, ByteArray)> }
}

pub type SpendRedeemer {
  /// `payee_output_index` names the output that receives the premium when
  /// the pool covers it; it is not read otherwise. `bond` is the Lean's
  /// `.rotate sn' op payee` option.
  Advance { payee_output_index: Int, bond: BondOp }
  Convict { convictor_pkh: ByteArray, convictor_output_index: Int }
  /// Index two was the retired migration spend. Constructor indices are wire
  /// surface and this generation's builders are the deployed generation's, so
  /// the number stays taken and its arm refuses every transaction.
  Retired
  /// Freeze a live checkpoint whose pool is below the premium, on the
  /// controller's own later witnessed rotation (#345). Appended after
  /// the retired index: nothing renumbers. `hunter_output_index` names the output
  /// that receives the freeze bond.
  Freeze { hunter_output_index: Int }
  /// Add `amount`, at least one premium, to the pool of a live checkpoint
  /// whose top-up mark is clear (#522). Appended after `Freeze`: nothing
  /// renumbers. Anyone may do it; the mark stays set until the next rotation.
  TopUp { amount: Int }
  /// Release the pending output of a convicted checkpoint into the booking of its
  /// termination (Lean `pendingReleased`). Appended after `TopUp`.
  Release
}

pub const checkpoint_min_ada: Int = 2_000_000

validator checkpoint_register(
  /// The state policy of the registry whose checkpoints these are, and the
  /// registry's name: together the registry identity the active token of an
  /// AID is named in.
  state_policy: PolicyId,
  registry_name: ByteArray,
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
  /// The application policy the termination approvals are minted under.
  application_policy: PolicyId,
) {
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
    let registry = RegistryIdentity {
      policy: state_policy,
      name: registry_name,
    }
    when spend_redeemer is {
      Advance { payee_output_index, bond } -> {
        expect
          ran_rotation_check(
            advance_hash,
            own_hash(tx, own_ref),
            observe_advance,
            own_ref,
            tx,
          )
        validate_advance(
          registry,
          network_id,
          d_reg,
          freeze_bond,
          premium,
          payee_output_index,
          bond,
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
          registry,
          network_id,
          d_reg,
          freeze_bond,
          convictor_pkh,
          convictor_output_index,
          own_ref,
          tx,
        )
      }
      Retired -> False
      Freeze { hunter_output_index } -> {
        expect
          ran_rotation_check(
            advance_hash,
            own_hash(tx, own_ref),
            observe_freeze,
            own_ref,
            tx,
          )
        validate_freeze(
          registry,
          d_reg,
          freeze_bond,
          premium,
          hunter_output_index,
          own_ref,
          tx,
        )
      }
      TopUp { amount } ->
        validate_top_up(
          registry,
          d_reg,
          freeze_bond,
          premium,
          amount,
          own_ref,
          tx,
        )
      Release -> validate_release(registry, application_policy, own_ref, tx)
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

/// The rotation observer ran for this action over this spent output: an
/// Advance claims `observe_advance`, a Freeze `observe_freeze`.
fn ran_rotation_check(
  advance_hash: PolicyId,
  checkpoint_policy: PolicyId,
  action: Int,
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
              claim.action == action && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(
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
  registry: RegistryIdentity,
  network_id: Int,
  d_reg: Int,
  freeze_bond: Int,
  premium: Int,
  payee_output_index: Int,
  bond: BondOp,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(old_data) = own_input.output.datum
  let old = datum.read(old_data)
  expect Live { aid, frozen, born_at, refund_to, .. } = old
  let aid_name = active_token_name(registry, aid)
  expect quantity_of(own_input.output.value, registry.policy, aid_name) == 1
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(own_hash) },
  )
  expect InlineDatum(new_data) = state_output.datum
  let new = datum.read(new_data)
  expect  
      Live {
        sn: new_sn,
        epoch: new_epoch,
        poisoned: False,
        frozen: new_frozen,
        born_at: new_born_at,
        refund_to: new_refund_to,
        topped_up: False,
        keys: new_keys,
        ..
      }
    = new
  expect and {
      new_born_at == born_at,
      new_refund_to == refund_to,
    }
  // The bond option (Lean `Env.bondOpOk`). Keep leaves the frozen flag as it
  // was. Deposit unfreezes, and the keys the rotation reveals (the successor's
  // current keys, proved by the rotation observer) signed the intent for this
  // spent output and this amount, `B - bHeld`: the bond when the spent state is
  // frozen, nothing when it is not.
  expect
    when bond is {
      Keep -> new_frozen == frozen
      Deposit { signatures } ->
        !new_frozen && deposit_authorized(
          new_keys.cur_keys,
          new_keys.cur_threshold,
          signatures,
          required_intent(
            network_id,
            own_hash,
            own_ref,
            aid,
            new_sn,
            new_epoch,
            if frozen {
              freeze_bond
            } else {
              0
            },
          ),
        )
    }
  expect quantity_of(mint, registry.policy, aid_name) == 0
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
        |> merge(from_asset(registry.policy, aid_name, 1))
    )
  if paid {
    expect Some(payee) = list.at(outputs, payee_output_index)
    quantity_of(payee.value, registry.policy, aid_name) == 0 && lovelace_of(
      payee.value,
    ) >= premium
  } else {
    True
  }
}

/// Freeze a live checkpoint (Lean `Step.freeze`): the pool is below the premium,
/// the checkpoint is neither frozen nor poisoned, and the successor is the same
/// datum with `frozen` set, holding the minimum ADA, the deposit and the pool.
/// The freeze bond leaves to the hunter output. The rotation evidence is the
/// observer's, bound to this output by `ran_rotation_check`.
fn validate_freeze(
  registry: RegistryIdentity,
  d_reg: Int,
  freeze_bond: Int,
  premium: Int,
  hunter_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(old_data) = own_input.output.datum
  let old = datum.read(old_data)
  expect  
      Live {
        aid,
        sn,
        epoch,
        poisoned: False,
        frozen: False,
        born_at,
        refund_to,
        topped_up,
        keys,
      }
    = old
  let aid_name = active_token_name(registry, aid)
  expect quantity_of(own_input.output.value, registry.policy, aid_name) == 1
  expect Some(pool) = with_value(
    checkpoint_min_ada,
    d_reg,
    freeze_bond,
    old,
    lovelace_of(own_input.output.value),
  )
  expect pool < premium
  expect quantity_of(mint, registry.policy, aid_name) == 0
  let frozen = Live {
    aid,
    sn,
    epoch,
    poisoned: False,
    frozen: True,
    born_at,
    refund_to,
    topped_up,
    keys,
  }
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(own_hash) },
  )
  expect state_output.datum == InlineDatum(datum.write(frozen))
  expect
    state_output.value == (
      from_lovelace(
        held_value(checkpoint_min_ada, d_reg, freeze_bond, frozen, pool),
      )
        |> merge(from_asset(registry.policy, aid_name, 1))
    )
  expect Some(hunter) = list.at(outputs, hunter_output_index)
  quantity_of(hunter.value, registry.policy, aid_name) == 0 && lovelace_of(
    hunter.value,
  ) >= freeze_bond
}

/// Convict a live checkpoint: the token stays at the checkpoint address in a
/// pending termination that holds the minimum ADA, the convictor receives the
/// registration deposit, and the refund address receives the bond (unless
/// frozen) and the pool.
fn validate_convict(
  registry: RegistryIdentity,
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
  let live = datum.read(source_data)
  expect Live { aid, sn, epoch, frozen, refund_to, .. } = live
  let aid_name = active_token_name(registry, aid)
  expect quantity_of(own_input.output.value, registry.policy, aid_name) == 1
  expect Some(pool) = with_value(
    checkpoint_min_ada,
    d_reg,
    freeze_bond,
    live,
    lovelace_of(own_input.output.value),
  )
  expect quantity_of(mint, registry.policy, aid_name) == 0
  let terminated = TerminationPending { aid, sn, epoch }
  expect [pending_output] = list.filter(
    outputs,
    fn(output) { quantity_of(output.value, registry.policy, aid_name) > 0 },
  )
  let pending_datum: Data = datum.write(terminated)
  expect and {
      pending_output.address == from_script(own_hash),
      pending_output.datum == InlineDatum(pending_datum),
      pending_output.value == (
        from_lovelace(
          held_value(checkpoint_min_ada, d_reg, freeze_bond, terminated, 0),
        )
          |> merge(from_asset(registry.policy, aid_name, 1))
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

/// Top up a live checkpoint (Lean `Step.topUp`): anyone adds at least one
/// premium to the pool, once per key state. The successor is the spent datum
/// with the top-up mark set and holds exactly the amount more; nothing is
/// signed, no observer runs and no validity range is read. The token stays
/// and nothing is minted or burnt under the policy.
fn validate_top_up(
  registry: RegistryIdentity,
  d_reg: Int,
  freeze_bond: Int,
  premium: Int,
  amount: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(old_data) = own_input.output.datum
  let old = datum.read(old_data)
  expect  
      Live {
        aid,
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        refund_to,
        topped_up: False,
        keys,
      }
    = old
  expect premium <= amount
  let aid_name = active_token_name(registry, aid)
  expect quantity_of(own_input.output.value, registry.policy, aid_name) == 1
  expect Some(pool) = with_value(
    checkpoint_min_ada,
    d_reg,
    freeze_bond,
    old,
    lovelace_of(own_input.output.value),
  )
  expect quantity_of(mint, registry.policy, aid_name) == 0
  expect
    list.length(
      list.filter(
        inputs,
        fn(input) {
          input.output.address.payment_credential == Script(own_hash)
        },
      ),
    ) == 1
  let marked = Live {
    aid,
    sn,
    epoch,
    poisoned,
    frozen,
    born_at,
    refund_to,
    topped_up: True,
    keys,
  }
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(own_hash) },
  )
  expect state_output.datum == InlineDatum(datum.write(marked))
  let held = held_value(
    checkpoint_min_ada,
    d_reg,
    freeze_bond,
    marked,
    pool + amount,
  )
  state_output.value == (
    from_lovelace(held) |> merge(from_asset(registry.policy, aid_name, 1))
  )
}

/// Release the pending output of a convicted checkpoint (Lean
/// `pendingReleased`): the transaction mints exactly one termination approval
/// of this registry and of the key of the pending datum's AID, under the
/// application policy. Nothing else is read: the application checks the rest
/// of the booking.
fn validate_release(
  registry: RegistryIdentity,
  application_policy: PolicyId,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect InlineDatum(raw) = own_input.output.datum
  when pending_aid(raw) is {
    Some(aid) ->
      quantity_of(
        tx.mint,
        application_policy,
        approval_name(termination_preimage(aid, registry)),
      ) == 1
    None -> False
  }
}
