grammar: 1
family: checkpoint

story: 6
title: "Alice comes back through the registry"
goal: "As Alice, I want my parked identity live again, and I want nobody else to be able to do it in my place."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["6.the-leaf-is-parked", "6.a-witnessed-rotation-from-exactly", "6.strictly-later-than-the-parked", "6.fresh-bonds-and-a-first", "6.the-checkpoint-is-born-now"]
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
  say: "Alice leaves (story 5), landing her own reap: her money comes home, the token burns, the leaf holds the hash of the checkpoint the rotation reached — key state epoch 1, sequence 1."
  evidence:
    add: [{"rotationTo":[0,0,1]},{"intentAuthorized":[1,{"close":{"payee":1}},null]}]
  action:
    close:
      sn': 1
      payee: 1
      refund': null
  expect:
    ok: true
    state:
      parked:
        h:
          epoch: 1
          sn: 1
    flow:
      refund:
        addr: 1
        dreg: 1000
        b: 5
        pool: 8
      hunter:
        addr: 1
        dreg: 0
        b: 0
        pool: 2
    verdict: not-present
    exhibits: [T10_bonds_are_observable, T10_parked_holds_nothing, T16_close_destination, T16_close_needs_rotation, T16_copied_reap_refused, T16_parked_hash_is_the_closed_checkpoints, T16_payments_are_named, T1_sn_monotone_all, T2_close_and_reopen_open_epochs, T5_close_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_intent_requires_new_keys, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_sn_monotone_all]
step:
  slot: 40
  who: alice
  say: "Alice rotates again on KERI, from exactly the key state the leaf holds; her witnesses receipt sequence 2."
  evidence:
    add: [{"rotationTo":[1,1,2]}]
  expect:
    verdict: not-present
step:
  slot: 40
  who: friend
  say: "Anyone with that public rotation and the bonds can revive her — a sponsor does, naming Alice’s refund address. Fresh bonds, a first pool, born now, at the next epoch: juvenile for W slots."
  action:
    reopen:
      sn': 2
      refund: 1
      pool0: 10
  expect:
    ok: true
    live:
      sn: 2
      epoch: 2
      poisoned: false
      frozen: false
      bornAt: 40
      refundTo: 1
      pool: 10
    flow:
      dregIn: 1000
      bIn: 5
      poolIn: 10
    verdict: juvenile
    exhibits: [T10_parked_holds_nothing, T10_reopen_is_juvenile, T1_reopen_strict, T1_sn_monotone_all, T1_trace_sn_monotone, T2_close_and_reopen_open_epochs, T3_epoch_local, T5_reopen_enabled, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_mint_once, T8_only_convicted_is_terminal, T8_parked_only_revives_or_convicts, T8_parked_returns_only_by_revival, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: replay
  at: 1
  title: "A stranger replays the close’s own rotation — refused"
  step:
    slot: 40
    who: mallory
    say: "Much later a stranger replays the public rotation the close presented, to revive her to himself. The leaf holds key state (1, 1); a rotation to sequence 1 is not a rotation from it. Refused: the close’s own rotation cannot revive."
    action:
      reopen:
        sn': 1
        refund: 4
        pool0: 10
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T1_close_rotation_cannot_revive, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_parked_only_revives_or_convicts, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: thief
  at: 1
  title: "Mallory holds the current keys of the parked key state — refused"
  step:
    slot: 40
    who: mallory
    say: "Mallory holds the keys of epoch 1. Signing as their quorum buys nothing on a parked identity, and she cannot produce a witnessed rotation from that key state: that takes the next keys. Her revival is refused."
    evidence:
      add: [{"quorum":[1]}]
    action:
      reopen:
        sn': 2
        refund: 4
        pool0: 10
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_parked_only_revives_or_convicts, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: convicted
  at: 1
  title: "Cora proves her duplicitous while parked"
  step:
    slot: 40
    who: cora
    say: "Cora holds two of Alice’s rotations at sequence 1, both revealing the epoch-1 keys and receipted: a duplicity proof against the parked key state. The leaf is marked convicted; nothing was held, so nothing moves."
    evidence:
      add: [{"duplicityAt":[1,1]}]
    action:
      convict:
        payee: 3
    expect:
      ok: true
      state: convicted
      flow: {}
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T12_convict_parked_exact, T4_current_key_thief_cannot_revive, T5_convict_parked_enabled, T6_component_conservation, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_parked_only_revives_or_convicts, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 40
    who: alice
    say: "Alice rotates again; her revival is refused. Convicted is terminal: no KERI event un-duplicates an identifier."
    evidence:
      add: [{"rotationTo":[1,1,2]}]
    action:
      reopen:
        sn': 2
        refund: 1
        pool0: 10
    expect:
      ok: false
      reason: convicted-terminal
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T12_convicted_terminal, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_from_convicted]
fork:
  id: twice
  at: 3
  title: "Consumable again; a revival of a live checkpoint — refused"
  step:
    slot: 50
    who: treasury
    say: "Ten slots later: consumable again."
    expect:
      verdict: consumable
  step:
    slot: 50
    who: friend
    say: "A revival of a live checkpoint is refused: only a parked leaf revives."
    action:
      reopen:
        sn': 3
        refund: 6
        pool0: 10
    expect:
      ok: false
      reason: reopen-needs-parked
      verdict: consumable
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
