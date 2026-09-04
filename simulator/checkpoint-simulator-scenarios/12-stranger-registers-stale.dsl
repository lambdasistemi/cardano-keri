grammar: 1
family: checkpoint

story: 12
title: "A stranger registers Alice at a stale epoch"
goal: "As Mallory, holding keys Alice retired long ago, I register her AID myself and stop advancing at my epoch."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["12.the-checkpoint-is-juvenile-for", "12.anyone-can-advance-it-onward", "12.the-moment-that-happens-mallory", "12.it-can-happen-once-per"]
step:
  slot: 0
  who: mallory
  say: "Mallory registers Alice's public inception, naming her own refund address (4)."
  action:
    register:
      refund: 4
      pool0: 10
  expect:
    ok: true
    live:
      refundTo: 4
    verdict: juvenile
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_states, T8_mint_once, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
step:
  slot: 0
  who: mallory
  say: "Alice's rotation 1 is public. Mallory advances to the epoch whose keys she holds, paying herself the premium."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  action:
    rotate:
      sn': 1
      op: keep
      payee: 4
      refund': null
  expect:
    ok: true
    live:
      epoch: 1
      pool: 8
      refundTo: 4
    verdict: juvenile
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 5
  who: treasury
  say: "Juvenile for W slots: nobody consumes it yet."
  expect:
    verdict: juvenile
step:
  slot: 5
  who: hal
  say: "Anyone advances it onward with Alice's later public rotation."
  evidence:
    add: [{"rotationTo":[1,1,2]}]
  action:
    rotate:
      sn': 2
      op: keep
      payee: 2
      refund': null
  expect:
    ok: true
    live:
      epoch: 2
      pool: 6
    verdict: juvenile
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 5
  who: alice
  say: "The moment Alice's keys sign a refund address at a rotation, Mallory's bonds answer to Alice."
  evidence:
    add: [{"rotationTo":[2,2,3]},{"intentAuthorized":[3,"keep",1]}]
  action:
    rotate:
      sn': 3
      op: keep
      payee: 1
      refund': 1
  expect:
    ok: true
    live:
      epoch: 3
      refundTo: 1
      pool: 4
    verdict: juvenile
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 5
  who: mallory
  say: "Gate control, not part of the play: A redeemer the validator does not know is refused by name."
  hidden: true
  action:
    steal:
      everything: true
  expect:
    ok: false
    reason: invalid-action
    verdict: juvenile
    exhibits: [T9_juvenility_is_consumer_only]
fork:
  id: once
  at: 1
  title: "Registering her again — refused: once per AID"
  step:
    slot: 0
    who: mallory
    say: "It can happen once per AID, ever."
    action:
      register:
        refund: 4
        pool0: 10
    expect:
      ok: false
      reason: already-present
      verdict: juvenile
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: residual
  at: 1
  title: "Nobody lands her later rotations"
  step:
    slot: 10
    who: treasury
    say: "Nobody lands Alice's later rotations. After W slots the treasury accepts Mallory's stale epoch: the residual story 12 states as a limit, the price of a permissionless advance."
    expect:
      verdict: consumable
