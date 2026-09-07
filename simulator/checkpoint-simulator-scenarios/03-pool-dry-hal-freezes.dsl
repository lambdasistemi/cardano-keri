grammar: 1
family: checkpoint

story: 3
title: "The pool runs dry, so Hal freezes her instead"
goal: "As Hal, when Alice's pool cannot pay me, I want to take the freeze bond and freeze her checkpoint on its old keys, so that no consumer trusts a stale key state and Alice comes back to pay."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["3.exactly-the-advance-predicate-on", "3.that-the-pool-is-below", "3.that-the-checkpoint-is-not", "3.already-unconsumable", "3.nothing-to-freeze", "3.then-it-pays-b-to", "3.and-leaves-the-datum-untouched"]
step:
  slot: 0
  who: alice
  say: "Registered with a pool of 1: below the premium P = 2."
  action:
    register:
      refund: 1
      pool0: 1
  expect:
    ok: true
    verdict: juvenile
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_states, T8_mint_once, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
step:
  slot: 12
  who: alice
  say: "Alice rotates on KERI; her witnesses receipt it. The checkpoint has not seen it."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  expect:
    verdict: consumable
step:
  slot: 12
  who: hal
  say: "Hal submits the same evidence he would use to advance, but as a freeze. The chain pays B to Hal and leaves the datum as it is: the old keys stay."
  action:
    freeze:
      sn': 1
      payee: 2
  expect:
    ok: true
    live:
      sn: 0
      epoch: 0
      poisoned: false
      bornAt: 0
      refundTo: 1
      pool: 1
      frozen: true
    flow:
      hunter:
        addr: 2
        dreg: 0
        b: 5
        pool: 0
    verdict: frozen
    exhibits: [T10_bonds_are_observable, T15_b_leaves_only_by_freeze, T15_freeze_makes_inert, T16_payments_are_named, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T5_freeze_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_frozen_flips_only_by_rotation_or_freeze, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: treasury
  say: "Alice sees her identity refused by the treasury and learns why: the freeze bond is missing. The conviction bond was never touched."
  expect:
    verdict: frozen
fork:
  id: second-freeze
  at: 2
  title: "A second freeze"
  step:
    slot: 12
    who: hal
    say: "A second freeze finds nothing to take."
    action:
      freeze:
        sn': 1
        payee: 2
    expect:
      ok: false
      reason: freeze-bond-missing
      verdict: frozen
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
