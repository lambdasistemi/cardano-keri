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
    modelResult:
      flow:
        dregIn: 1000
        bIn: 5
        poolIn: 10
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
            pool: 10
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
          pool: 10
          toppedUp: false
    flow:
      dregIn: 1000
      bIn: 5
      poolIn: 10
      refund: null
      hunter: null
      convictor: null
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, registration_pool_at_least_premium]
step:
  slot: 10
  who: treasury
  say: Consumable.
  expect:
    verdict: consumable
step:
  slot: 31536010
  who: treasury
  say: "After a year without a new event, this model has no expiry transition: a bonded, unpoisoned checkpoint with no missing rotation remains consumable."
  expect:
    verdict: consumable
step:
  slot: 31536010
  who: hal
  say: "A later witnessed rotation can still advance the checkpoint and pay the premium. Validity expiry is a separate #439 requirement and is not established by this simulation."
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
      epoch: 1
      pool: 8
      bornAt: 0
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
            pool: 8
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
          pool: 8
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
