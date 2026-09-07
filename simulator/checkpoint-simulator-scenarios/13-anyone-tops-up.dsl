grammar: 1
family: checkpoint

story: 13
title: "Anyone tops up the pool"
goal: "As a friend of Alice, I want to pay for her maintenance."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["13.add-value-to-the-pool", "13.the-datum-is-untouched", "13.no-signature"]
step:
  slot: 0
  who: alice
  say: "Registered with an empty pool."
  action:
    register:
      refund: 1
      pool0: 0
  expect:
    ok: true
    live:
      pool: 0
    verdict: juvenile
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_states, T8_mint_once, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
step:
  slot: 3
  who: friend
  say: "A friend adds 7 to the pool. The datum is untouched; no signature; juvenility is not restarted."
  action:
    topUp:
      x: 7
  expect:
    ok: true
    live:
      bornAt: 0
      pool: 7
      sn: 0
      epoch: 0
    flow:
      poolIn: 7
    verdict: juvenile
    exhibits: [T10_bonds_are_observable, T14_pool_increases_only_by_topup, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T4_current_key_thief_cannot_park, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: hal
  say: "Hunters now have a reason to serve her."
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
      pool: 5
    flow:
      hunter:
        addr: 2
        dreg: 0
        b: 0
        pool: 2
    verdict: consumable
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: not-lovelace
  at: 1
  title: "Amounts that are not lovelace — refused by name"
  step:
    slot: 3
    who: friend
    say: "A negative amount is not lovelace: refused by name."
    action:
      topUp:
        x: -5
    expect:
      ok: false
      reason: invalid-nat
      verdict: juvenile
      exhibits: [T9_juvenility_is_consumer_only]
  step:
    slot: 3
    who: friend
    say: "Neither is a fraction."
    action:
      topUp:
        x: 2.5
    expect:
      ok: false
      reason: invalid-nat
      verdict: juvenile
      exhibits: [T9_juvenility_is_consumer_only]
fork:
  id: stranger-deposit
  at: 2
  title: "A stranger lands her rotation as a deposit"
  step:
    slot: 20
    who: rival
    say: "Ten slots later, past juvenility, Alice rotates again on KERI."
    evidence:
      add: [{"rotationTo":[1,1,2]}]
    expect:
      verdict: consumable
  step:
    slot: 20
    who: rival
    say: "A stranger lands it with deposit on a checkpoint whose bonds are full: it would bring nothing and pay him the premium like a keep — but a deposit is signed by the keys the rotation reveals, and nobody signed this one. Refused; the keep he may land carries no signature and resets nothing."
    action:
      rotate:
        sn': 2
        op: deposit
        payee: 7
        refund': null
    expect:
      ok: false
      verdict: consumable
      reason: intent-not-authorized
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
