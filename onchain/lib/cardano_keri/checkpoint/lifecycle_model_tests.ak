//// T116-R4 parity tests for the pure Lean/Haskell/Aiken lifecycle mirror.

use aiken/collection/list
use aiken/option.{is_some}
use cardano_keri/checkpoint/lifecycle_model.{
  Absent, Action, Active, Advance, Arm, Armed, Bounty, ChallengeClose, Claim,
  CloseIntent, Closing, Config, Convict, Env, FinalizeClose, Frozen, Ledger,
  MachState, Params, Register, Tombstone, Transfer, Tx, balanced, carried,
  dispatch, init_config, run_trace,
}
use cardano_keri/checkpoint/lifecycle_model_vectors as vec

const hunter: Int = 7

const refund: Int = 8

fn params() -> Params {
  Params {
    min_ada: 2,
    deposit: 5,
    bond: 3,
    freeze_window: 10,
    close_window: 20,
  }
}

fn ahead_env() -> Env {
  Env { kel_tip: 2, fork_evidence: False, close_capabilities: [0, 1, 2] }
}

fn tip_env() -> Env {
  Env { kel_tip: 1, fork_evidence: False, close_capabilities: [0, 1] }
}

fn fork_env() -> Env {
  Env { kel_tip: 2, fork_evidence: True, close_capabilities: [0, 1, 2] }
}

fn balanced_config(state: MachState) -> Config {
  Config {
    state,
    ledger: Ledger { deposits: carried(params(), state), outflows: [] },
  }
}

fn active0() -> Config {
  balanced_config(Active(0))
}

fn active1() -> Config {
  balanced_config(Active(1))
}

fn armed0() -> Config {
  balanced_config(Armed(0, hunter, 10))
}

fn closing0() -> Config {
  balanced_config(Closing(0, refund, 20))
}

fn closing1() -> Config {
  balanced_config(Closing(1, refund, 20))
}

fn frozen0() -> Config {
  balanced_config(Frozen(0))
}

fn tombstone0() -> Config {
  balanced_config(Tombstone(0))
}

fn all_actions() -> List<Action> {
  [
    Register,
    Advance,
    Arm(hunter),
    Claim,
    CloseIntent(refund),
    ChallengeClose(hunter),
    FinalizeClose,
    Convict(hunter),
  ]
}

test t116_r4_advance_totality() {
  let verdict = dispatch(
    params(),
    ahead_env(),
    active0(),
    Tx { slot: 0, action: Advance },
  ) == Some(Config { ..active0(), state: Active(1) })
  verdict == vec.advance_totality
}

test t116_r4_no_absorbing_busy_state() {
  let verdict = is_some(
    dispatch(
      params(),
      tip_env(),
      active1(),
      Tx { slot: 0, action: CloseIntent(refund) },
    ),
  )
  verdict == vec.no_absorbing_busy_state
}

test t116_r4_adversarial_advance_is_progress() {
  expect Some(successor) = dispatch(
    params(),
    ahead_env(),
    active0(),
    Tx { slot: 0, action: Advance },
  )
  let verdict = successor.state == Active(1)
  verdict == vec.adversarial_advance_is_progress
}

test t116_r4_bounded_churn() {
  let verdict = is_some(
    run_trace(
      params(),
      Env { kel_tip: 2, fork_evidence: False, close_capabilities: [] },
      0,
      init_config,
      [
        Tx { slot: 0, action: Register },
        Tx { slot: 1, action: Advance },
        Tx { slot: 2, action: Arm(hunter) },
        Tx { slot: 12, action: Claim },
        Tx { slot: 12, action: Advance },
      ],
    ),
  )
  verdict == vec.bounded_churn
}

test t116_r4_armed_exclusive_window() {
  let admitted = all_actions()
    |> list.filter(
        fn(action) {
          dispatch(params(), ahead_env(), armed0(), Tx { slot: 9, action })
            |> is_some
        },
      )
  let verdict = admitted == [Advance]
  verdict == vec.armed_exclusive_window
}

test t116_r4_bond_transfer_only_via_elapsed_window() {
  expect Some(successor) = run_trace(
    params(),
    ahead_env(),
    0,
    init_config,
    [
      Tx { slot: 0, action: Register },
      Tx { slot: 0, action: Arm(hunter) },
      Tx { slot: 10, action: Claim },
    ],
  )
  let verdict = successor.ledger.outflows == [
    Transfer { destination: hunter, amount: params().bond, kind: Bounty },
  ]
  verdict == vec.bond_transfer_only_via_elapsed_window
}

test t116_r4_abandonment_pays_exactly_B() {
  expect Some(successor) = dispatch(
    params(),
    ahead_env(),
    armed0(),
    Tx { slot: 10, action: Claim },
  )
  let verdict = successor.state == Frozen(0) && successor.ledger.outflows == [
    Transfer { destination: hunter, amount: params().bond, kind: Bounty },
  ]
  verdict == vec.abandonment_pays_exactly_B
}

test t116_r4_frozen_implies_true_silence() {
  expect Some(successor) = run_trace(
    params(),
    ahead_env(),
    0,
    init_config,
    [
      Tx { slot: 0, action: Register },
      Tx { slot: 0, action: Arm(hunter) },
      Tx { slot: 10, action: Claim },
    ],
  )
  let verdict = successor.state == Frozen(0) && 0 + params().freeze_window <= 10
  verdict == vec.frozen_implies_true_silence
}

test t116_r4_close_lie_always_voidable() {
  let verdict = and {
    dispatch(
      params(),
      ahead_env(),
      closing0(),
      Tx { slot: 0, action: ChallengeClose(hunter) },
    )
      |> is_some,
    dispatch(params(), ahead_env(), closing0(), Tx { slot: 0, action: Advance })
      |> is_some,
  }
  verdict == vec.close_lie_always_voidable
}

test t116_r4_close_at_tip_unchallengeable() {
  let verdict = and {
    !is_some(
      dispatch(
        params(),
        tip_env(),
        closing1(),
        Tx { slot: 20, action: ChallengeClose(hunter) },
      ),
    ),
    !is_some(
      dispatch(
        params(),
        tip_env(),
        closing1(),
        Tx { slot: 20, action: Advance },
      ),
    ),
    is_some(
      dispatch(
        params(),
        tip_env(),
        closing1(),
        Tx { slot: 20, action: FinalizeClose },
      ),
    ),
  }
  verdict == vec.close_at_tip_unchallengeable
}

test t116_r4_current_state_is_quiet() {
  let admitted = all_actions()
    |> list.filter(
        fn(action) {
          dispatch(params(), tip_env(), active1(), Tx { slot: 0, action })
            |> is_some
        },
      )
  let verdict = admitted == [CloseIntent(refund)]
  verdict == vec.current_state_is_quiet
}

test t116_r4_value_conservation() {
  expect Some(successor) = dispatch(
    params(),
    ahead_env(),
    init_config,
    Tx { slot: 0, action: Register },
  )
  let verdict = balanced(params(), init_config) && balanced(params(), successor)
  verdict == vec.value_conservation
}

test t116_r4_value_conservation_trace() {
  expect Some(successor) = run_trace(
    params(),
    ahead_env(),
    0,
    init_config,
    [
      Tx { slot: 0, action: Register },
      Tx { slot: 0, action: Arm(hunter) },
      Tx { slot: 10, action: Claim },
      Tx { slot: 10, action: Advance },
    ],
  )
  let verdict = balanced(params(), successor)
  verdict == vec.value_conservation_trace
}

test t116_r4_convict_dominance() {
  let verdict = [active0(), armed0(), frozen0(), closing0()]
    |> list.all(
        fn(config) {
          dispatch(
            params(),
            fork_env(),
            config,
            Tx { slot: 0, action: Convict(hunter) },
          )
            |> is_some
        },
      )
  verdict == vec.convict_dominance
}

test t116_r4_tombstone_terminal_but_no_aid_bar() {
  let terminal = all_actions()
    |> list.all(
        fn(action) {
          !is_some(
            dispatch(params(), fork_env(), tombstone0(), Tx { slot: 0, action }),
          )
        },
      )
  let distinct_instance_registers = dispatch(
    params(),
    ahead_env(),
    init_config,
    Tx { slot: 0, action: Register },
  )
    |> is_some
  let verdict = terminal && distinct_instance_registers
  verdict == vec.tombstone_terminal_but_no_aid_bar
}

test t116_r4_replay_convergence() {
  expect Some(successor) = run_trace(
    params(),
    Env { kel_tip: 2, fork_evidence: False, close_capabilities: [] },
    0,
    init_config,
    [
      Tx { slot: 0, action: Register },
      Tx { slot: 1, action: Advance },
      Tx { slot: 2, action: Advance },
    ],
  )
  let verdict = successor.state == Active(2)
  verdict == vec.replay_convergence
}

test t116_r4_close_cycle_requires_elapsed_window() {
  expect Some(successor) = run_trace(
    params(),
    tip_env(),
    0,
    init_config,
    [
      Tx { slot: 0, action: Register },
      Tx { slot: 1, action: CloseIntent(refund) },
      Tx { slot: 21, action: FinalizeClose },
    ],
  )
  let verdict = successor.state == Absent && 1 + params().close_window <= 21
  verdict == vec.close_cycle_requires_elapsed_window
}
