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
        bIn: 5
        convictor: null
        dregIn: 1000
        hunter: null
        poolIn: 10
        refund: null
      state:
        present:
          l:
            bornAt: 0
            epoch: 0
            frozen: false
            poisoned: false
            pool: 10
            refundTo: 1
            sn: 0
    state:
      present:
        l:
          bornAt: 0
          epoch: 0
          frozen: false
          poisoned: false
          pool: 10
          refundTo: 1
          sn: 0
    flow:
      bIn: 5
      convictor: null
      dregIn: 1000
      hunter: null
      poolIn: 10
      refund: null
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired]
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
      refund': null
  expect:
    ok: true
    live:
      epoch: 1
      pool: 8
      bornAt: 0
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
            pool: 8
            refundTo: 1
            sn: 1
    state:
      present:
        l:
          bornAt: 0
          epoch: 1
          frozen: false
          poisoned: false
          pool: 8
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
