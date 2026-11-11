//// Spending the records at the application address.
////
//// ## Responsibility
//// The Lean model's `spendRegistration`, `spendTermination` and `moneyRouted`
//// for the input a spend handler is run for: a request is folded into its
//// delivered holding by its deadline or returned from its deadline, a pending
//// termination is spent only by the fold that burns its active token, every
//// spend burns the approval it consumes, the refunds of the returns are paid
//// in full and the treasury donation covers the costs of the folds.
////
//// ## Dependencies
//// `application/clock`, `application/configuration`, `application/held`,
//// `application/inception` and `application/registration`;
//// `singular_state/preimage`; the Aiken standard library.
////
//// ## Assumptions
//// The ledger runs the spend handler once for every input at the address of
//// the script, with that input's redeemer, and `transaction.redeemers` lists
//// the redeemer of every spent input.
////
//// ## Invariants
//// An input at the application address is spent only by an action that names
//// it and that its record allows: a configuration record has no action, a
//// checkpoint has none, a request has the fold and the return, a pending
//// termination has the termination fold. Before the deadline only a fold
//// spends a request.

use aiken/collection/list
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, lovelace_of, quantity_of}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Spend, Transaction, find_input,
}
use cardano_keri/application/action.{
  FoldRegistration, FoldTermination, ReturnRegistration, SpendAction,
}
use cardano_keri/application/clock.{fold_window, return_window}
use cardano_keri/application/configuration.{
  Record, configuration_of, parameters_valid,
}
use cardano_keri/application/held.{
  ApplicationParameters, Registration, RegistrationData, address_of, held_datum,
}
use cardano_keri/application/inception.{
  inception_attested, writes_initial_state,
}
use cardano_keri/application/registration.{
  registration_approval, registration_shape,
}
use cardano_keri/application/termination.{
  termination_approval, termination_shape,
}
use singular_state/preimage.{RegistryIdentity, active_token_name}

/// The action a redeemer carries, when it carries one.
pub fn spend_action_of(redeemer: Data) -> Option<SpendAction> {
  if redeemer is FoldRegistration { holding_index }: SpendAction {
    Some(FoldRegistration { holding_index })
  } else if redeemer is ReturnRegistration: SpendAction {
    Some(ReturnRegistration)
  } else if redeemer is FoldTermination { registry, key }: SpendAction {
    Some(FoldTermination { registry, key })
  } else {
    None
  }
}

/// Model `approvalBurned`: the transaction burns exactly the approval of the
/// request it spends.
pub fn approval_burned(
  application_policy: PolicyId,
  name: AssetName,
  tx: Transaction,
) -> Bool {
  quantity_of(tx.mint, application_policy, name) == -1
}

/// Model `delivered`: the output at `index` is the holding the fold delivers:
/// at the committed address, which is the checkpoint validator's, carrying the
/// committed initial datum, holding exactly the committed deposit and the one
/// newly minted active token of the key.
pub fn delivered(
  record: Record,
  initial_floor: Int,
  network_id: Int,
  data: RegistrationData,
  index: Int,
  tx: Transaction,
) -> Option<Output> {
  let active: AssetName = active_token_name(data.registry, data.key)
  when list.at(tx.outputs, index) is {
    Some(holding) ->
      if and {
        holding.address == data.holding_address,
        holding.address == address_of(record.checkpoint_credential),
        holding.datum == InlineDatum(data.initial_datum),
        initial_floor <= data.deposit,
        writes_initial_state(
          holding,
          data.booked_at,
          data.refund_address,
          network_id,
        ),
        lovelace_of(holding.value) == data.deposit,
        quantity_of(holding.value, data.registry.policy, active) == 1,
        quantity_of(tx.mint, data.registry.policy, active) == 1,
      } {
        Some(holding)
      } else {
        None
      }
    None -> None
  }
}

/// Model `spendRegistration`.
pub fn spend_registration(
  lifecycle_observer: ByteArray,
  initial_floor: Int,
  network_id: Int,
  application_policy: PolicyId,
  action: SpendAction,
  input: Output,
  data: RegistrationData,
  tx: Transaction,
) -> Bool {
  when
    configuration_of(application_policy, data.registry, tx.reference_inputs)
  is {
    Some(record) -> and {
        parameters_valid(record.parameters),
        registration_shape(application_policy, input, data),
        approval_burned(application_policy, registration_approval(data), tx),
        when action is {
          FoldRegistration { holding_index } -> and {
              fold_window(data, tx.validity_range),
              when
                delivered(
                  record,
                  initial_floor,
                  network_id,
                  data,
                  holding_index,
                  tx,
                )
              is {
                Some(holding) ->
                  inception_attested(
                    lifecycle_observer,
                    record.checkpoint_credential,
                    holding,
                    data.key,
                    tx,
                  )
                None -> False
              },
            }
          ReturnRegistration -> return_window(data, tx.validity_range)
          FoldTermination { .. } -> False
        },
      }
    None -> False
  }
}

/// Model `spendTermination`: only the fold that reads the registry's
/// configuration record by reference and burns the approval and the active
/// token, with the registry's policy running.
fn spend_termination(
  application_policy: PolicyId,
  input: Output,
  registry: RegistryIdentity,
  key: ByteArray,
  tx: Transaction,
) -> Bool {
  and {
    configuration_of(application_policy, registry, tx.reference_inputs) != None,
    termination_shape(application_policy, input, registry, key),
    quantity_of(
      tx.mint,
      application_policy,
      termination_approval(registry, key),
    ) == -1,
    quantity_of(tx.mint, registry.policy, active_token_name(registry, key)) == -1,
  }
}

// ---- the money a transaction moves ---------------------------------------------

/// A spent request that a return or a fold names: whether it is a return, the
/// lovelace the input holds, its refund address, and the parameters it is paid
/// under.
type Spent {
  returned: Bool,
  lovelace: Int,
  refund_address: Address,
  parameters: ApplicationParameters,
}

/// The requests the transaction folds or returns, read from the redeemers of
/// the inputs at the application address.
fn spent_requests(application_policy: PolicyId, tx: Transaction) -> List<Spent> {
  list.filter_map(
    tx.redeemers,
    fn(Pair(purpose, redeemer)) {
      when (purpose, spend_action_of(redeemer)) is {
        (Spend(reference), Some(kind)) ->
          when find_input(tx.inputs, reference) is {
            Some(spent) ->
              when held_datum(spent.output) is {
                Some(Registration { registration }) ->
                  if spent.output.address.payment_credential == Script(
                    application_policy,
                  ) {
                    when
                      configuration_of(
                        application_policy,
                        registration.registry,
                        tx.reference_inputs,
                      )
                    is {
                      Some(record) ->
                        Some(
                          Spent {
                            returned: kind == ReturnRegistration,
                            lovelace: lovelace_of(spent.output.value),
                            refund_address: registration.refund_address,
                            parameters: record.parameters,
                          },
                        )
                      None -> None
                    }
                  } else {
                    None
                  }
                _ -> None
              }
            None -> None
          }
        _ -> None
      }
    },
  )
}

/// The lovelace the outputs pay to `address`.
fn paid_to(outputs: List<Output>, address: Address) -> Int {
  list.foldr(
    outputs,
    0,
    fn(output, total) {
      if output.address == address {
        total + lovelace_of(output.value)
      } else {
        total
      }
    },
  )
}

/// Model `requiredRefunds`: what a return owes its refund address is
/// everything but the tip (never below zero).
fn owed(spent: Spent) -> Int {
  if spent.lovelace > spent.parameters.minimum_tip {
    spent.lovelace - spent.parameters.minimum_tip
  } else {
    0
  }
}

/// Model `terminationDonation`, summed: what the terminating folds of the
/// transaction owe the treasury, each its request's lovelace less the minimum
/// tip of its registry's record (never below zero). A fold whose registry has
/// no record owes nothing here and is refused by `spend_termination`.
fn termination_dues(application_policy: PolicyId, tx: Transaction) -> Int {
  list.foldr(
    tx.redeemers,
    0,
    fn(Pair(purpose, redeemer), total) {
      when (purpose, spend_action_of(redeemer)) is {
        (Spend(reference), Some(FoldTermination { registry, .. })) ->
          when
            (
              find_input(tx.inputs, reference),
              configuration_of(
                application_policy,
                registry,
                tx.reference_inputs,
              ),
            )
          is {
            (Some(spent), Some(record)) ->
              if spent.output.address.payment_credential == Script(
                application_policy,
              ) {
                total + at_least_zero(
                  lovelace_of(spent.output.value) - record.parameters.minimum_tip,
                )
              } else {
                total
              }
            _ -> total
          }
        _ -> total
      }
    },
  )
}

fn at_least_zero(amount: Int) -> Int {
  if amount > 0 {
    amount
  } else {
    0
  }
}

/// Model `moneyRouted`: refunds are paid in full per address, and the treasury
/// donation covers the registration costs of the folded requests and the
/// termination donations of the terminating folds.
pub fn money_routed(application_policy: PolicyId, tx: Transaction) -> Bool {
  let spent = spent_requests(application_policy, tx)
  let returns = list.filter(spent, fn(s) { s.returned })
  and {
    list.all(
      returns,
      fn(entry) {
        list.foldr(
          returns,
          0,
          fn(other, total) {
            if other.refund_address == entry.refund_address {
              total + owed(other)
            } else {
              total
            }
          },
        ) <= paid_to(tx.outputs, entry.refund_address)
      },
    ),
    list.foldr(
      spent,
      0,
      fn(s, total) {
        if s.returned {
          total
        } else {
          total + s.parameters.registration_cost
        }
      },
    ) + termination_dues(application_policy, tx) <= when
      tx.treasury_donation
    is {
      Some(donation) -> donation
      None -> 0
    },
  }
}

/// The spend of the input `own_reference`: the action of its redeemer decides
/// it, and the money the whole transaction moves must be routed.
pub fn application_spend(
  lifecycle_observer: ByteArray,
  initial_floor: Int,
  network_id: Int,
  redeemer: Data,
  own_reference: OutputReference,
  tx: Transaction,
) -> Bool {
  expect Some(action) = spend_action_of(redeemer)
  when find_input(tx.inputs, own_reference) is {
    Some(spent) ->
      when spent.output.address.payment_credential is {
        Script(application_policy) -> and {
            when held_datum(spent.output) is {
              Some(Registration { registration }) ->
                spend_registration(
                  lifecycle_observer,
                  initial_floor,
                  network_id,
                  application_policy,
                  action,
                  spent.output,
                  registration,
                  tx,
                )
              _ ->
                when action is {
                  FoldTermination { registry, key } ->
                    spend_termination(
                      application_policy,
                      spent.output,
                      registry,
                      key,
                      tx,
                    )
                  _ -> False
                }
            },
            money_routed(application_policy, tx),
          }
        _ -> False
      }
    None -> False
  }
}
