grammar: 1
family: checkpoint

story: 7
title: "Mallory steals the current keys; Alice poisons, then rotates"
goal: "As Alice, when my current keys are stolen, I want every consumer to stop trusting this epoch now, before I have managed to rotate."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["7.signatures-at-the-current-threshold", "7.one-stolen-member-key-of", "7.that-the-epoch-is-not"]
step:
  slot: 0
  who: alice
  say: "Registered, bonded, with a short pool."
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
  say: "Mallory has the current keys. Alice's key holders sign a poison declaration at the current threshold; anyone lands it. Consumers stop trusting this epoch now."
  evidence:
    add: [{"quorum":[0]}]
  action: poison
  expect:
    ok: true
    live:
      epoch: 0
      poisoned: true
      pool: 1
      frozen: false
    flow: {}
    verdict: poisoned
    exhibits: [T10_bonds_are_observable, T10_current_quorum_never_restores, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T3_only_poison_sets, T4_current_key_thief_cannot_park, T4_current_quorum_only_poisons, T5_poison_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: alice
  say: "Alice rotates with her next keys. The poison clears: it was local to the keys she just retired. She lands it herself; the pool is short, so nobody is paid."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  action:
    rotate:
      sn': 1
      op: keep
      payee: 2
      refund': null
  expect:
    ok: true
    live:
      sn: 1
      epoch: 1
      poisoned: false
      pool: 1
      frozen: false
    flow: {}
    verdict: consumable
    exhibits: [T10_bonds_are_observable, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_only_rotation_clears, T3_rotation_clears, T4_poisoned_blocks_quorum_and_freeze, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: attempts
  at: 1
  title: "Mallory and Hal try everything on the poisoned checkpoint"
  step:
    slot: 12
    who: alice
    say: "Poisoning twice in one epoch is refused."
    action: poison
    expect:
      ok: false
      reason: already-poisoned
      verdict: poisoned
      exhibits: [T10_bonds_are_observable, T4_poisoned_blocks_quorum_and_freeze, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 12
    who: mallory
    say: "Mallory, with the stolen current keys, tries to close and take the bonds. Under D-036 the poison is no longer what stops her: a close is a witnessed rotation by the next keys, and she cannot present one."
    evidence:
      add: []
    action:
      close:
        sn': 1
        payee: 4
        refund': null
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: poisoned
      exhibits: [T10_bonds_are_observable, T16_close_needs_rotation, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 12
    who: hal
    say: "Hal holds a later witnessed rotation and the pool is short, but a poisoned checkpoint cannot be frozen: it is already unconsumable, nothing to freeze."
    evidence:
      add: [{"rotationTo":[0,0,1]}]
    action:
      freeze:
        sn': 1
        payee: 2
    expect:
      ok: false
      reason: poisoned
      verdict: poisoned
      exhibits: [T10_bonds_are_observable, T4_poisoned_blocks_quorum_and_freeze, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 12
    who: friend
    say: "A top-up lands but changes nothing about trust: the poison stays."
    action:
      topUp:
        x: 5
    expect:
      ok: true
      live:
        poisoned: true
        pool: 6
      verdict: poisoned
      exhibits: [T10_bonds_are_observable, T14_pool_increases_only_by_topup, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T4_poisoned_blocks_quorum_and_freeze, T4_poisoned_nonrotation_inert, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: retired-keys
  at: 2
  title: "Mallory tries the reap with the retired keys — refused"
  step:
    slot: 12
    who: mallory
    say: "Mallory's stolen keys are the retired epoch's. A close is a witnessed rotation by the next keys (D-036); she has none. Her keys are good for nothing on chain."
    evidence:
      add: []
    action:
      close:
        sn': 2
        payee: 4
        refund': null
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: consumable
      exhibits: [T10_bonds_are_observable, T16_close_needs_rotation, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
