//// The mint of the application policy.
////
//// ## Responsibility
//// Decides a transaction's mint and burn under the application policy from
//// the actions its redeemer lists: each action is accepted by its own rule,
//// each asset an action brings into being is minted exactly once, no other
//// positive quantity is minted, and every burn is the approval of a request
//// the transaction spends from the application address.
////
//// ## Dependencies
//// `application/configuration`, `application/held`, `application/registration`;
//// `singular_state/preimage`; the Aiken standard library.
////
//// ## Assumptions
//// The ledger runs the mint handler whenever the policy appears in the mint,
//// and runs the spend handler of every input at the application address.
////
//// ## Invariants
//// Everything minted under the policy is accounted for by an action of the
//// transaction, and everything burned is consumed from an input at the
//// application address, so the closed set of actions is the whole mint and
//// burn.

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, quantity_of, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/application/action.{
  Action, BookRegistration, CreateConfiguration,
}
use cardano_keri/application/configuration.{create_configuration}
use cardano_keri/application/registration.{
  book_registration, registration_approval, registration_at,
}
use singular_state/preimage.{configuration_token_name}

/// The asset an action brings into being, when it does.
fn birth(action: Action, tx: Transaction) -> Option<AssetName> {
  when action is {
    CreateConfiguration { registry, .. } ->
      Some(configuration_token_name(registry))
    BookRegistration { output_index } ->
      when registration_at(tx.outputs, output_index) is {
        Some((_, data)) -> Some(registration_approval(data))
        None -> None
      }
  }
}

/// Model `bookedOnce`: each booked output is booked once.
fn booked_once(actions: List<Action>) -> Bool {
  distinct(
    list.filter_map(
      actions,
      fn(action) {
        when action is {
          BookRegistration { output_index } -> Some(output_index)
          _ -> None
        }
      },
    ),
  )
}

fn distinct(items: List<Int>) -> Bool {
  when items is {
    [] -> True
    [first, ..rest] -> !list.has(rest, first) && distinct(rest)
  }
}

/// One action.
fn action_accepted(
  state_template_hash: ByteArray,
  minimum_deposit: Int,
  application_policy: PolicyId,
  tx: Transaction,
  action: Action,
) -> Bool {
  when action is {
    CreateConfiguration { registry, seed, output_index } ->
      when list.at(tx.outputs, output_index) is {
        Some(output) ->
          create_configuration(
            state_template_hash,
            application_policy,
            registry,
            seed,
            output,
            tx,
          )
        None -> False
      }
    BookRegistration { output_index } ->
      book_registration(application_policy, minimum_deposit, output_index, tx)
  }
}

/// The quantity of `name` the application address's inputs hold.
fn consumed(
  application_policy: PolicyId,
  name: AssetName,
  tx: Transaction,
) -> Int {
  list.foldl(
    tx.inputs,
    0,
    fn(input, total) {
      if input.output.address.payment_credential == Script(application_policy) {
        total + quantity_of(input.output.value, application_policy, name)
      } else {
        total
      }
    },
  )
}

/// Everything minted is born of an action, once; everything burned is
/// consumed from the application address.
fn accounted(
  application_policy: PolicyId,
  births: List<AssetName>,
  tx: Transaction,
) -> Bool {
  and {
    list.all(
      births,
      fn(name) { quantity_of(tx.mint, application_policy, name) == 1 },
    ),
    list.all(
      dict.to_pairs(tokens(tx.mint, application_policy)),
      fn(Pair(name, quantity)) {
        if quantity > 0 {
          list.has(births, name)
        } else {
          quantity == 0 - consumed(application_policy, name, tx)
        }
      },
    ),
  }
}

/// The accepted mint and burn under the application policy of a transaction.
pub fn application_mint(
  state_template_hash: ByteArray,
  minimum_deposit: Int,
  application_policy: PolicyId,
  actions: List<Action>,
  tx: Transaction,
) -> Bool {
  and {
    booked_once(actions),
    list.all(
      actions,
      fn(action) {
        action_accepted(
          state_template_hash,
          minimum_deposit,
          application_policy,
          tx,
          action,
        )
      },
    ),
    accounted(
      application_policy,
      list.filter_map(actions, fn(action) { birth(action, tx) }),
      tx,
    ),
  }
}
