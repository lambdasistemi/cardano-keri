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
  say: "Registered, bonded, with one premium in the pool."
  action:
    register:
      refund: 1
      pool0: 2
  expect:
    ok: true
    verdict: juvenile
    modelResult:
      flow:
        dregIn: 1000
        bIn: 5
        poolIn: 2
        refund: null
        hunter: null
        convictor: null
      state:
        present:
          l:
            sn: 0
            epoch: 0
            poisoned: false
            frozen: false
            bornAt: 0
            refundTo: 1
            pool: 2
            toppedUp: false
    state:
      present:
        l:
          sn: 0
          epoch: 0
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 1
          pool: 2
          toppedUp: false
    flow:
      dregIn: 1000
      bIn: 5
      poolIn: 2
      refund: null
      hunter: null
      convictor: null
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, registration_pool_at_least_premium]
step:
  slot: 12
  who: hal
  say: "Alice rotates once on KERI; Hal lands it and takes the premium. The pool is empty now."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  action:
    rotate:
      sn': 1
      op: keep
      payee: 2
  expect:
    ok: true
    live:
      sn: 1
      epoch: 1
      pool: 0
    verdict: consumable
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 0
        refund: null
        hunter:
          addr: 2
          dreg: 0
          b: 0
          pool: 2
        convictor: null
      state:
        present:
          l:
            sn: 1
            epoch: 1
            poisoned: false
            frozen: false
            bornAt: 0
            refundTo: 1
            pool: 0
            toppedUp: false
    state:
      present:
        l:
          sn: 1
          epoch: 1
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 1
          pool: 0
          toppedUp: false
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 0
      refund: null
      hunter:
        addr: 2
        dreg: 0
        b: 0
        pool: 2
      convictor: null
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, rotation_clears_topped_up, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: alice
  say: "Mallory has the current keys. Alice's key holders sign a poison declaration at the current threshold; anyone lands it. Consumers stop trusting this epoch now."
  evidence:
    add: [{"quorum":[1]}]
  action: poison
  expect:
    ok: true
    live:
      epoch: 1
      poisoned: true
      pool: 0
      frozen: false
    verdict: poisoned
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 0
        refund: null
        hunter: null
        convictor: null
      state:
        present:
          l:
            sn: 1
            epoch: 1
            poisoned: true
            frozen: false
            bornAt: 0
            refundTo: 1
            pool: 0
            toppedUp: false
    state:
      present:
        l:
          sn: 1
          epoch: 1
          poisoned: true
          frozen: false
          bornAt: 0
          refundTo: 1
          pool: 0
          toppedUp: false
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 0
      refund: null
      hunter: null
      convictor: null
    exhibits: [T10_bonds_are_observable, T10_current_quorum_never_restores, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T3_only_poison_sets, T4_current_key_thief_cannot_rotate_or_freeze, T4_current_quorum_only_poisons, T5_poison_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, step_from_present_keeps_refund, topped_up_kept_by_poison_and_freeze, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: alice
  say: "Alice rotates with her next keys. The poison clears: it was local to the keys she just retired. She lands it herself; the pool is short, so nobody is paid."
  evidence:
    add: [{"rotationTo":[1,1,2]}]
  action:
    rotate:
      sn': 2
      op: keep
      payee: 2
  expect:
    ok: true
    live:
      sn: 2
      epoch: 2
      poisoned: false
      pool: 0
      frozen: false
    verdict: consumable
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 0
        refund: null
        hunter: null
        convictor: null
      state:
        present:
          l:
            sn: 2
            epoch: 2
            poisoned: false
            frozen: false
            bornAt: 0
            refundTo: 1
            pool: 0
            toppedUp: false
    state:
      present:
        l:
          sn: 2
          epoch: 2
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 1
          pool: 0
          toppedUp: false
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 0
      refund: null
      hunter: null
      convictor: null
    exhibits: [T10_bonds_are_observable, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_only_rotation_clears, T3_rotation_clears, T4_poisoned_blocks_quorum_and_freeze, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, rotation_clears_topped_up, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: attempts
  at: 2
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
      modelResult: null
      exhibits: [T10_bonds_are_observable, T4_poisoned_blocks_quorum_and_freeze, T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 12
    who: hal
    say: "Hal holds a later witnessed rotation and the pool is short, but a poisoned checkpoint cannot be frozen: it is already unconsumable, nothing to freeze."
    evidence:
      add: [{"rotationTo":[1,1,2]}]
    action:
      freeze:
        sn': 2
        payee: 2
    expect:
      ok: false
      reason: poisoned
      verdict: poisoned
      modelResult: null
      exhibits: [T10_bonds_are_observable, T4_poisoned_blocks_quorum_and_freeze, T7_step_iff_stepFn, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, consumableStateB_iff]
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
        pool: 5
      verdict: poisoned
      modelResult:
        flow:
          dregIn: 0
          bIn: 0
          poolIn: 5
          refund: null
          hunter: null
          convictor: null
        state:
          present:
            l:
              sn: 1
              epoch: 1
              poisoned: true
              frozen: false
              bornAt: 0
              refundTo: 1
              pool: 5
              toppedUp: true
      state:
        present:
          l:
            sn: 1
            epoch: 1
            poisoned: true
            frozen: false
            bornAt: 0
            refundTo: 1
            pool: 5
            toppedUp: true
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 5
        refund: null
        hunter: null
        convictor: null
      exhibits: [T10_bonds_are_observable, T14_pool_increases_only_by_topup, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T4_poisoned_blocks_quorum_and_freeze, T4_poisoned_nonrotation_inert, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, step_from_present_keeps_refund, topUp_adds_at_least_premium, topped_up_set_only_by_topUp, trace_poison_fold, trace_sn_monotone_all]
