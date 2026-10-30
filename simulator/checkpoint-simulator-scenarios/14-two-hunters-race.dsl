grammar: 1
family: checkpoint

story: 14
title: "Two hunters race"
goal: "Both hunters see the rotation. If the pool covers P, the first advance wins and is paid; the second fails on the spent input. If it does not, the first freeze wins B; the second finds nothing to take."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["14.both-see-the-rotation", "14.if-the-pool-covers-p", "14.the-first-advance-wins-and", "14.the-second-fails-on-the", "14.if-it-does-not", "14.the-first-freeze-wins-b", "14.the-second-finds-nothing-to"]
step:
  slot: 0
  who: alice
  say: "Registered with a pool of 3: one premium and a little."
  action:
    register:
      refund: 1
      pool0: 3
  expect:
    ok: true
    verdict: juvenile
    modelResult:
      flow:
        bIn: 5
        convictor: null
        dregIn: 1000
        hunter: null
        poolIn: 3
        refund: null
      state:
        present:
          l:
            bornAt: 0
            epoch: 0
            frozen: false
            poisoned: false
            pool: 3
            refundTo: 1
            sn: 0
    state:
      present:
        l:
          bornAt: 0
          epoch: 0
          frozen: false
          poisoned: false
          pool: 3
          refundTo: 1
          sn: 0
    flow:
      bIn: 5
      convictor: null
      dregIn: 1000
      hunter: null
      poolIn: 3
      refund: null
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired]
step:
  slot: 12
  who: hal
  say: "Alice rotates. Hal lands it first and is paid."
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
      sn: 1
      pool: 1
    verdict: consumable
    modelResult:
      flow:
        bIn: 0
        convictor: null
        dregIn: 0
        hunter:
          addr: 2
          b: 0
          dreg: 0
          pool: 2
        poolIn: 0
        refund: null
      state:
        present:
          l:
            bornAt: 0
            epoch: 1
            frozen: false
            poisoned: false
            pool: 1
            refundTo: 1
            sn: 1
    state:
      present:
        l:
          bornAt: 0
          epoch: 1
          frozen: false
          poisoned: false
          pool: 1
          refundTo: 1
          sn: 1
    flow:
      bIn: 0
      convictor: null
      dregIn: 0
      hunter:
        addr: 2
        b: 0
        dreg: 0
        pool: 2
      poolIn: 0
      refund: null
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: rival
  say: "The rival's advance finds the input spent: the checkpoint is already at epoch 1, sequence 1, and his evidence names epoch 0."
  action:
    rotate:
      sn': 1
      op: keep
      payee: 7
      refund': null
  expect:
    ok: false
    reason: no-witnessed-rotation
    verdict: consumable
    modelResult: null
    exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff]
step:
  slot: 20
  who: hal
  say: "Alice rotates again; the pool (1) no longer covers P. Hal freezes first and takes B."
  evidence:
    add: [{"rotationTo":[1,1,2]}]
  action:
    freeze:
      sn': 2
      payee: 2
  expect:
    ok: true
    live:
      frozen: true
    flow:
      bIn: 0
      convictor: null
      dregIn: 0
      hunter:
        addr: 2
        b: 5
        dreg: 0
        pool: 0
      poolIn: 0
      refund: null
    verdict: frozen
    modelResult:
      flow:
        bIn: 0
        convictor: null
        dregIn: 0
        hunter:
          addr: 2
          b: 5
          dreg: 0
          pool: 0
        poolIn: 0
        refund: null
      state:
        present:
          l:
            bornAt: 0
            epoch: 1
            frozen: true
            poisoned: false
            pool: 1
            refundTo: 1
            sn: 1
    state:
      present:
        l:
          bornAt: 0
          epoch: 1
          frozen: true
          poisoned: false
          pool: 1
          refundTo: 1
          sn: 1
    exhibits: [T10_bonds_are_observable, T15_b_leaves_only_by_freeze, T15_freeze_makes_inert, T16_payments_are_named, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T5_freeze_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_frozen_flips_only_by_rotation_or_freeze, T7_step_iff_stepFn, T7_trace_iff_replay, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 20
  who: rival
  say: "The rival's freeze finds nothing to take."
  action:
    freeze:
      sn': 2
      payee: 7
  expect:
    ok: false
    reason: freeze-bond-missing
    verdict: frozen
    modelResult: null
    exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: topup
  at: 2
  title: "The rival tops up the pool and wins the next rotation"
  step:
    slot: 12
    who: rival
    say: "The rival adds to the pool instead: now it covers the premium again."
    action:
      topUp:
        x: 5
    expect:
      ok: true
      live:
        pool: 6
      flow:
        bIn: 0
        convictor: null
        dregIn: 0
        hunter: null
        poolIn: 5
        refund: null
      verdict: consumable
      modelResult:
        flow:
          bIn: 0
          convictor: null
          dregIn: 0
          hunter: null
          poolIn: 5
          refund: null
        state:
          present:
            l:
              bornAt: 0
              epoch: 1
              frozen: false
              poisoned: false
              pool: 6
              refundTo: 1
              sn: 1
      state:
        present:
          l:
            bornAt: 0
            epoch: 1
            frozen: false
            poisoned: false
            pool: 6
            refundTo: 1
            sn: 1
      exhibits: [T10_bonds_are_observable, T14_pool_increases_only_by_topup, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T4_current_key_thief_cannot_rotate_or_freeze, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, trace_poison_fold, trace_sn_monotone_all]
  step:
    slot: 20
    who: rival
    say: "Alice rotates again; the rival lands it first this time and is paid."
    evidence:
      add: [{"rotationTo":[1,1,2]}]
    action:
      rotate:
        sn': 2
        op: keep
        payee: 7
        refund': null
    expect:
      ok: true
      live:
        epoch: 2
        sn: 2
        pool: 4
      flow:
        bIn: 0
        convictor: null
        dregIn: 0
        hunter:
          addr: 7
          b: 0
          dreg: 0
          pool: 2
        poolIn: 0
        refund: null
      verdict: consumable
      modelResult:
        flow:
          bIn: 0
          convictor: null
          dregIn: 0
          hunter:
            addr: 7
            b: 0
            dreg: 0
            pool: 2
          poolIn: 0
          refund: null
        state:
          present:
            l:
              bornAt: 0
              epoch: 2
              frozen: false
              poisoned: false
              pool: 4
              refundTo: 1
              sn: 2
      state:
        present:
          l:
            bornAt: 0
            epoch: 2
            frozen: false
            poisoned: false
            pool: 4
            refundTo: 1
            sn: 2
      exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: backwards
  at: 4
  title: "A transaction dated before the last — refused"
  step:
    slot: 19
    who: rival
    say: "A transaction dated before the last accepted one is refused: the chain does not go backwards."
    action:
      topUp:
        x: 1
    expect:
      ok: false
      reason: slot-regression
      verdict: frozen
      exhibits: [T10_bonds_are_observable]
