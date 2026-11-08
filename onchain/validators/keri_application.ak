//// KERI's application validator (RED stub: the behaviour is absent).

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/application/action.{Action}

validator keri_application(_state_template: ByteArray) {
  mint(_redeemer: Action, _policy_id: PolicyId, _tx: Transaction) {
    True
  }

  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_reference: OutputReference,
    _tx: Transaction,
  ) {
    True
  }

  else(_) {
    fail
  }
}
