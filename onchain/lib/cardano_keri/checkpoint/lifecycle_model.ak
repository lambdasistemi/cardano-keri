//// Pure executable mirror of lean/CardanoKeri/Lifecycle.lean.
////
//// This module is test-only abstraction. It does not dispatch the live
//// checkpoint validator and deliberately models only state, guards, deposits,
//// and cumulative transfers.

use aiken/collection/list
use aiken/option

pub type Params {
  min_ada: Int,
  deposit: Int,
  bond: Int,
  freeze_window: Int,
  close_window: Int,
}

pub type Env {
  kel_tip: Int,
  fork_evidence: Bool,
  close_capabilities: List<Int>,
}

pub type MachState {
  Absent
  Active(Int)
  Armed(Int, Int, Int)
  Frozen(Int)
  Closing(Int, Int, Int)
  Tombstone(Int)
}

pub type TransferKind {
  Bounty
  Forfeiture
  Refund
}

pub type Transfer {
  destination: Int,
  amount: Int,
  kind: TransferKind,
}

pub type Ledger {
  deposits: Int,
  outflows: List<Transfer>,
}

pub type Config {
  state: MachState,
  ledger: Ledger,
}

pub type Action {
  Register
  Advance
  Arm(Int)
  Claim
  CloseIntent(Int)
  ChallengeClose(Int)
  FinalizeClose
  Convict(Int)
}

pub type Tx {
  slot: Int,
  action: Action,
}

pub const init_config: Config =
  Config { state: Absent, ledger: Ledger { deposits: 0, outflows: [] } }

pub fn has_event(env: Env, sequence: Int) -> Bool {
  sequence >= 0 && sequence <= env.kel_tip
}

pub fn behind(env: Env, sequence: Int) -> Bool {
  has_event(env, sequence + 1)
}

pub fn carried(params: Params, state: MachState) -> Int {
  when state is {
    Absent -> 0
    Active(_) -> params.min_ada + params.deposit + params.bond
    Armed(_, _, _) -> params.min_ada + params.deposit + params.bond
    Frozen(_) -> params.min_ada + params.deposit
    Closing(_, _, _) -> params.min_ada + params.deposit + params.bond
    Tombstone(_) -> params.min_ada
  }
}

pub fn balanced(params: Params, config: Config) -> Bool {
  carried(params, config.state) + outflow_total(config.ledger.outflows) == config.ledger.deposits
}

fn outflow_total(outflows: List<Transfer>) -> Int {
  list.foldl(outflows, 0, fn(transfer, total) { total + transfer.amount })
}

pub fn register(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  if config.state == Absent && tx.action == Register && has_event(env, 0) {
    Some(
      Config {
        state: Active(0),
        ledger: Ledger {
          ..config.ledger,
          deposits: config.ledger.deposits + params.min_ada + params.deposit + params.bond,
        },
      },
    )
  } else {
    None
  }
}

pub fn advance_active(
  _params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when config.state is {
    Active(sequence) ->
      if tx.action == Advance && behind(env, sequence) {
        Some(Config { ..config, state: Active(sequence + 1) })
      } else {
        None
      }
    _ -> None
  }
}

pub fn advance_armed(
  _params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when config.state is {
    Armed(sequence, _, deadline) ->
      if tx.action == Advance && behind(env, sequence) && tx.slot < deadline {
        Some(Config { ..config, state: Active(sequence + 1) })
      } else {
        None
      }
    _ -> None
  }
}

pub fn advance_frozen(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when config.state is {
    Frozen(sequence) ->
      if tx.action == Advance && behind(env, sequence) {
        Some(
          Config {
            state: Active(sequence + 1),
            ledger: Ledger {
              ..config.ledger,
              deposits: config.ledger.deposits + params.bond,
            },
          },
        )
      } else {
        None
      }
    _ -> None
  }
}

pub fn advance_closing(
  _params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when config.state is {
    Closing(sequence, _, _) ->
      if tx.action == Advance && behind(env, sequence) {
        Some(Config { ..config, state: Active(sequence + 1) })
      } else {
        None
      }
    _ -> None
  }
}

pub fn arm(params: Params, env: Env, config: Config, tx: Tx) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Active(sequence), Arm(hunter)) ->
      if behind(env, sequence) {
        Some(
          Config {
            ..config,
            state: Armed(sequence, hunter, tx.slot + params.freeze_window),
          },
        )
      } else {
        None
      }
    _ -> None
  }
}

pub fn claim(
  params: Params,
  _env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when config.state is {
    Armed(sequence, hunter, deadline) ->
      if tx.action == Claim && deadline <= tx.slot {
        Some(
          Config {
            state: Frozen(sequence),
            ledger: Ledger {
              ..config.ledger,
              outflows: list.concat(
                config.ledger.outflows,
                [
                  Transfer {
                    destination: hunter,
                    amount: params.bond,
                    kind: Bounty,
                  },
                ],
              ),
            },
          },
        )
      } else {
        None
      }
    _ -> None
  }
}

pub fn close_intent(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Active(sequence), CloseIntent(refund)) ->
      if list.has(env.close_capabilities, sequence) {
        Some(
          Config {
            ..config,
            state: Closing(sequence, refund, tx.slot + params.close_window),
          },
        )
      } else {
        None
      }
    _ -> None
  }
}

pub fn challenge_close(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Closing(sequence, _, _), ChallengeClose(challenger)) ->
      if behind(env, sequence) {
        Some(
          Config {
            ..config,
            state: Armed(sequence, challenger, tx.slot + params.freeze_window),
          },
        )
      } else {
        None
      }
    _ -> None
  }
}

pub fn finalize_close(
  params: Params,
  _env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when config.state is {
    Closing(_, refund, deadline) ->
      if tx.action == FinalizeClose && deadline <= tx.slot {
        Some(
          Config {
            state: Absent,
            ledger: Ledger {
              ..config.ledger,
              outflows: list.concat(
                config.ledger.outflows,
                [
                  Transfer {
                    destination: refund,
                    amount: params.min_ada + params.deposit + params.bond,
                    kind: Refund,
                  },
                ],
              ),
            },
          },
        )
      } else {
        None
      }
    _ -> None
  }
}

pub fn convict_active(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Active(sequence), Convict(convictor)) ->
      convict_with(
        params,
        env,
        config,
        sequence,
        [
          Transfer {
            destination: convictor,
            amount: params.deposit,
            kind: Forfeiture,
          },
          Transfer {
            destination: convictor,
            amount: params.bond,
            kind: Forfeiture,
          },
        ],
      )
    _ -> None
  }
}

pub fn convict_armed(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Armed(sequence, hunter, _), Convict(convictor)) ->
      convict_with(
        params,
        env,
        config,
        sequence,
        [
          Transfer {
            destination: convictor,
            amount: params.deposit,
            kind: Forfeiture,
          },
          Transfer { destination: hunter, amount: params.bond, kind: Bounty },
        ],
      )
    _ -> None
  }
}

pub fn convict_frozen(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Frozen(sequence), Convict(convictor)) ->
      convict_with(
        params,
        env,
        config,
        sequence,
        [
          Transfer {
            destination: convictor,
            amount: params.deposit,
            kind: Forfeiture,
          },
        ],
      )
    _ -> None
  }
}

pub fn convict_closing(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Closing(sequence, _, _), Convict(convictor)) ->
      convict_with(
        params,
        env,
        config,
        sequence,
        [
          Transfer {
            destination: convictor,
            amount: params.deposit,
            kind: Forfeiture,
          },
          Transfer {
            destination: convictor,
            amount: params.bond,
            kind: Forfeiture,
          },
        ],
      )
    _ -> None
  }
}

fn convict_with(
  _params: Params,
  env: Env,
  config: Config,
  sequence: Int,
  transfers: List<Transfer>,
) -> Option<Config> {
  if env.fork_evidence {
    Some(
      Config {
        state: Tombstone(sequence),
        ledger: Ledger {
          ..config.ledger,
          outflows: list.concat(config.ledger.outflows, transfers),
        },
      },
    )
  } else {
    None
  }
}

pub fn dispatch(
  params: Params,
  env: Env,
  config: Config,
  tx: Tx,
) -> Option<Config> {
  when Pair(config.state, tx.action) is {
    Pair(Absent, Register) -> register(params, env, config, tx)
    Pair(Active(_), Advance) -> advance_active(params, env, config, tx)
    Pair(Armed(_, _, _), Advance) -> advance_armed(params, env, config, tx)
    Pair(Frozen(_), Advance) -> advance_frozen(params, env, config, tx)
    Pair(Closing(_, _, _), Advance) -> advance_closing(params, env, config, tx)
    Pair(Active(_), Arm(_)) -> arm(params, env, config, tx)
    Pair(Armed(_, _, _), Claim) -> claim(params, env, config, tx)
    Pair(Active(_), CloseIntent(_)) -> close_intent(params, env, config, tx)
    Pair(Closing(_, _, _), ChallengeClose(_)) ->
      challenge_close(params, env, config, tx)
    Pair(Closing(_, _, _), FinalizeClose) ->
      finalize_close(params, env, config, tx)
    Pair(Active(_), Convict(_)) -> convict_active(params, env, config, tx)
    Pair(Armed(_, _, _), Convict(_)) -> convict_armed(params, env, config, tx)
    Pair(Frozen(_), Convict(_)) -> convict_frozen(params, env, config, tx)
    Pair(Closing(_, _, _), Convict(_)) ->
      convict_closing(params, env, config, tx)
    _ -> None
  }
}

pub fn run_trace(
  params: Params,
  env: Env,
  lower: Int,
  config: Config,
  txs: List<Tx>,
) -> Option<Config> {
  when txs is {
    [] -> Some(config)
    [tx, ..rest] ->
      if lower <= tx.slot {
        dispatch(params, env, config, tx)
          |> option.and_then(
              fn(next) { run_trace(params, env, tx.slot, next, rest) },
            )
      } else {
        None
      }
  }
}
