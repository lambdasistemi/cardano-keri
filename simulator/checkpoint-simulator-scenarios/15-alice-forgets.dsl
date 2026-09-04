grammar: 1
family: checkpoint

story: 15
title: "Alice forgets"
goal: "As Alice, I go quiet for a year."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["15.and-no-rotation-is-missing", "15.nothing-on-chain-says-she", "15.a-validity-alice-renews-by", "15.no-next-key-reveal", "15.if-it-lapses-only-a", "15.the-fields-are-reserved-in", "15.consumable-present", "15.consumable-frozen"]
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
  slot: 10
  who: treasury
  say: Consumable.
  expect:
    verdict: consumable
step:
  slot: 31536010
  who: treasury
  say: "A year of silence. Nothing on chain says she is gone: the checkpoint stays consumable as long as it is bonded and no rotation is missing."
  expect:
    verdict: consumable
step:
  slot: 31536010
  who: hal
  say: "When she finally rotates, a hunter lands it as if no time had passed. Direction D-027 (a validity Alice renews) is not modelled here; the datum fields are reserved."
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
      epoch: 1
      pool: 8
      bornAt: 0
    verdict: consumable
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
