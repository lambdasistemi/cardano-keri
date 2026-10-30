//// #495 — the consumer's decoded state is exactly the Lean `Checkpoint.State`:
//// absent, present, termination pending, convicted, in that order. The state
//// is read off the wire by constructor index, so the order is the contract; a
//// fifth constructor between `Present` and `TerminationPending` would shift
//// every later index.

use aiken/builtin
use cardano_keri/consumer.{
  Absent, Convicted, Hash, Live, Present, State, TerminationPending,
}

/// The wire order, written out independently of the type under test.
type LeanOrder {
  AbsentAt0
  PresentAt1(Live)
  TerminationPendingAt2(Hash)
  ConvictedAt3
}

fn live() -> Live {
  Live {
    sn: 3,
    epoch: 1,
    poisoned: False,
    frozen: False,
    born_at: 9,
    refund_to: 7,
    pool: 5,
  }
}

test absent_is_constructor_0() {
  let wire: Data = AbsentAt0
  expect state: State = wire
  state == Absent
}

test present_is_constructor_1() {
  let wire: Data = PresentAt1(live())
  expect state: State = wire
  state == Present(live())
}

test termination_pending_is_constructor_2() {
  let wire: Data = TerminationPendingAt2(Hash { epoch: 4, sn: 6 })
  expect state: State = wire
  state == TerminationPending(Hash { epoch: 4, sn: 6 })
}

test convicted_is_constructor_3() {
  let wire: Data = ConvictedAt3
  expect state: State = wire
  state == Convicted
}

/// The type has exactly four constructors: index 4 is not a state.
test no_fifth_state_constructor() fail {
  let wire: Data = builtin.constr_data(4, [])
  expect _state: State = wire
  True
}
