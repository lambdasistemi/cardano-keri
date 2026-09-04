grammar: 1
family: checkpoint

story: 9
title: "Cora convicts"
goal: "As Cora, holding two of Alice’s rotations at the same sequence, each receipted by a threshold of her witnesses (KERI’s toad), I want to end this identity on chain and take its conviction bond."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["9.the-second-rotation-is-at", "9.reveals-the-same-keys-the", "9.is-signed-at-the-current", "9.carries-receipts-from-at-least", "9.and-differs-from-the-accepted", "9.no-history-needed-the-revealed"]
step:
  slot: 0
  who: alice
  say: "Registered, bonded."
  action:
    register:
      refund: 1
      pool0: 10
  expect:
    ok: true
    verdict: juvenile
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_states, T8_mint_once, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
step:
  slot: 12
  who: alice
  say: "Alice has poisoned the epoch (Mallory has the keys). A conviction does not care which state the checkpoint is in."
  evidence:
    add: [{"quorum":[0]}]
  action: poison
  expect:
    ok: true
    live:
      poisoned: true
    verdict: poisoned
    exhibits: [T10_bonds_are_observable, T10_current_quorum_never_restores, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T3_only_poison_sets, T4_current_key_thief_cannot_park, T4_current_quorum_only_poisons, T5_poison_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: cora
  say: "Cora presents the second rotation at sequence 0, revealing the epoch-0 keys, receipted by Alice’s witnesses. Convicted from a poisoned state: terminal. The conviction bond goes to Cora; the freeze bond and the pool return to the refund address (the story called that open; the Lean fixes it)."
  evidence:
    add: [{"duplicityAt":[0,0]}]
  action:
    convict:
      payee: 3
  expect:
    ok: true
    state: convicted
    flow:
      refund:
        addr: 1
        dreg: 0
        b: 5
        pool: 10
      convictor:
        addr: 3
        dreg: 1000
        b: 0
        pool: 0
    verdict: not-present
    exhibits: [T10_bonds_are_observable, T10_parked_holds_nothing, T12_convict_exact, T16_payments_are_named, T4_current_key_thief_cannot_park, T4_poisoned_blocks_quorum_and_freeze, T4_poisoned_nonrotation_inert, T5_convict_enabled, T6_component_conservation, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: noproof
  at: 1
  title: "Cora without the second rotation"
  step:
    slot: 12
    who: cora
    say: "Without a second receipted rotation at the tip’s sequence there is no conviction."
    action:
      convict:
        payee: 3
    expect:
      ok: false
      reason: no-duplicity-proof
      verdict: poisoned
      exhibits: [T10_bonds_are_observable, T12_convict_exact, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: terminal
  at: 2
  title: "Nothing leaves Convicted"
  step:
    slot: 12
    who: alice
    say: "No rotation, ever."
    evidence:
      add: [{"rotationTo":[0,0,1]}]
    action:
      rotate:
        sn': 1
        op: deposit
        payee: 1
        refund': null
    expect:
      ok: false
      reason: convicted-terminal
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T12_convicted_terminal, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_from_convicted]
  step:
    slot: 12
    who: alice
    say: "No close, ever."
    evidence:
      add: []
    action:
      close:
        sn': 1
        payee: 1
        refund': null
    expect:
      ok: false
      reason: convicted-terminal
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T12_convicted_terminal, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_from_convicted]
  step:
    slot: 12
    who: friend
    say: "Not even a top-up."
    action:
      topUp:
        x: 1
    expect:
      ok: false
      reason: convicted-terminal
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T12_convicted_terminal, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_from_convicted]
