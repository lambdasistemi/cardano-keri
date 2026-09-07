grammar: 1
family: checkpoint

story: 10
title: "Alice leaves under attack"
goal: "As Alice, I want to leave even while my current keys are stolen, and I want the thief to gain nothing by leaving in my place."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["10.a-witnessed-rotation-by-the", "10.the-signed-close-naming-the", "10.then-it-pays-the-premium", "10.and-everything-else-to-the", "10.the-closer-never-chooses-where"]
step:
  slot: 0
  who: alice
  say: "Registered, bonded, pool of 10."
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
  say: "Mallory has stolen the current keys. Alice’s key holders poison the epoch."
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
  slot: 20
  who: alice
  say: "Alice rotates to fresh keys and leaves in the same move: the reap lands from the poisoned state, because a close is a rotation. Her new keys sign the close, naming herself payee. Everything goes to her refund address, the token burns, the leaf is parked with the hash of key state (1, 1)."
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
    exhibits: [T10_bonds_are_observable, T10_parked_holds_nothing, T16_close_destination, T16_close_needs_rotation, T16_copied_reap_refused, T16_parked_hash_is_the_closed_checkpoints, T16_payments_are_named, T1_sn_monotone_all, T2_close_and_reopen_open_epochs, T4_poisoned_blocks_quorum_and_freeze, T5_close_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_intent_requires_new_keys, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_sn_monotone_all]
fork:
  id: current-keys
  at: 1
  title: "Mallory tries the reap with the stolen current keys — refused"
  step:
    slot: 12
    who: mallory
    say: "Mallory tries to reap Alice with the stolen current keys, naming herself payee. A reap is a witnessed rotation by the next keys; the current keys cannot produce one. Refused: a thief of the current keys cannot park her."
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
fork:
  id: mallory
  at: 1
  title: "Mallory stole the next keys too and reaps"
  step:
    slot: 20
    who: mallory
    say: "Suppose Mallory also stole the next keys: she rotates on KERI, signs the close naming herself payee, and lands it. The token burns and she takes the premium of 2 — but the conviction bond, the freeze bond and the rest of the pool go to Alice’s refund address, which only a rotation signed by the new keys naming a new address could have moved. The closer chooses when and who is paid the premium, never where the bonds go."
    evidence:
      add: [{"rotationTo":[0,0,1]},{"intentAuthorized":[1,{"close":{"payee":4}},null]}]
    action:
      close:
        sn': 1
        payee: 4
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
          addr: 4
          dreg: 0
          b: 0
          pool: 2
      verdict: not-present
      exhibits: [T10_bonds_are_observable, T10_parked_holds_nothing, T16_close_destination, T16_close_needs_rotation, T16_copied_reap_refused, T16_parked_hash_is_the_closed_checkpoints, T16_payments_are_named, T1_sn_monotone_all, T2_close_and_reopen_open_epochs, T4_poisoned_blocks_quorum_and_freeze, T5_close_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_intent_requires_new_keys, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_sn_monotone_all]
  step:
    slot: 20
    who: mallory
    say: "She tries to move the refund address to herself in the same message and land that instead: a second close on a parked identity. Nothing is there to close."
    evidence:
      add: [{"intentAuthorized":[1,{"close":{"payee":4}},4]}]
    action:
      close:
        sn': 1
        payee: 4
        refund': 4
    expect:
      ok: false
      reason: parked-inert
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_parked_only_revives_or_convicts, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: relayer-close
  at: 1
  title: "A relayer with the public rotation tries to reap — refused"
  step:
    slot: 20
    who: hal
    say: "Hal holds Alice’s next public rotation. A reap needs more than public data: the new keys must sign the close with its payee. Refused."
    evidence:
      add: [{"rotationTo":[0,0,1]}]
    action:
      close:
        sn': 1
        payee: 2
        refund': null
    expect:
      ok: false
      reason: intent-not-authorized
      verdict: poisoned
      exhibits: [T10_bonds_are_observable, T16_close_needs_rotation, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 20
    who: hal
    say: "A revival of a checkpoint that is still on chain is refused: only a parked leaf revives."
    action:
      reopen:
        sn': 1
        refund: 2
        pool0: 10
    expect:
      ok: false
      reason: reopen-needs-parked
      verdict: poisoned
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: parked
  at: 2
  title: "What the parked identity refuses"
  step:
    slot: 20
    who: friend
    say: "A registration is refused: the registry leaf is parked, not absent. The AID is not gone for good — a witnessed rotation from the parked key state brings it back (story 6)."
    action:
      register:
        refund: 1
        pool0: 10
    expect:
      ok: false
      reason: parked-inert
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_parked_only_revives_or_convicts, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 20
    who: friend
    say: "Nothing else lands on a parked identity: no top-up, no rotation, no poison. A revival or a duplicity proof, nothing else."
    action:
      topUp:
        x: 1
    expect:
      ok: false
      reason: parked-inert
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_parked_only_revives_or_convicts, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: revive
  at: 2
  title: "Alice comes back: parked is not terminal"
  step:
    slot: 30
    who: mallory
    say: "A stale resurrection is refused: the witnesses receipted a rotation to sequence 1 from key state (1, 1)? No such thing exists — that would be the same sequence again. Even if it did, a revival must be strictly later than the parked sequence."
    evidence:
      add: [{"rotationTo":[1,1,1]}]
    action:
      reopen:
        sn': 1
        refund: 4
        pool0: 10
    expect:
      ok: false
      reason: sequence-not-later
      verdict: not-present
      exhibits: [T10_parked_holds_nothing, T1_close_rotation_cannot_revive, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_parked_only_revives_or_convicts, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 30
    who: alice
    say: "Alice rotates on KERI again from the parked key state; her witnesses receipt sequence 2. She revives with fresh bonds: born again, juvenile, at the next epoch."
    evidence:
      add: [{"rotationTo":[1,1,2]}]
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
        bornAt: 30
        frozen: false
        poisoned: false
        pool: 10
        refundTo: 1
      flow:
        dregIn: 1000
        bIn: 5
        poolIn: 10
      verdict: juvenile
      exhibits: [T10_parked_holds_nothing, T10_reopen_is_juvenile, T1_reopen_strict, T1_sn_monotone_all, T1_trace_sn_monotone, T2_close_and_reopen_open_epochs, T3_epoch_local, T5_reopen_enabled, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_mint_once, T8_only_convicted_is_terminal, T8_parked_only_revives_or_convicts, T8_parked_returns_only_by_revival, T8_present_implies_registered, T8_reopen_actor_is_proof, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff, trace_poison_fold, trace_sn_monotone_all]
  step:
    slot: 40
    who: treasury
    say: "Ten slots later the revived checkpoint is consumable again."
    expect:
      verdict: consumable
