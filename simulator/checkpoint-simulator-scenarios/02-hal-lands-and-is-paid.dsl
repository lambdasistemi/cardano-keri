grammar: 1
family: checkpoint

story: 2
title: "Alice rotates, Hal lands it, Hal is paid"
goal: "As Hal, I want to land Alice's rotation the moment her witnesses receipt it, so that her checkpoint stays current and I earn the premium."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["2.signatures-at-the-current-threshold", "2.revealed-keys-match-the-pre", "2.receipts-from-at-least-toad", "2.sequence-strictly-greater", "2.then-it-pays-p-from"]
step:
  slot: 0
  who: alice
  say: "Alice's checkpoint is registered with her own refund address and a pool of 10."
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
  slot: 12
  who: alice
  say: "Alice runs kli rotate; her witnesses receipt the rotation to sequence 1. That is evidence, not a transaction."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  expect:
    verdict: consumable
step:
  slot: 12
  who: hal
  say: "Hal submits the rotation as an advance with keep, naming himself payee. The chain pays P from the pool to Hal."
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
      poisoned: false
      bornAt: 0
      refundTo: 1
      pool: 8
      frozen: false
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
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, rotation_clears_topped_up, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: freeze
  at: 1
  title: "Hal tries to freeze her instead"
  step:
    slot: 12
    who: hal
    say: "Hal cannot freeze her: the pool covers the premium."
    action:
      freeze:
        sn': 1
        payee: 2
    expect:
      ok: false
      reason: pool-covers-premium
      verdict: consumable
      modelResult: null
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: twice
  at: 2
  title: "Landing the rotation twice, and a rotation that goes nowhere"
  step:
    slot: 12
    who: hal
    say: "Landing it twice does nothing: the evidence names epoch 0 at sequence 0; the checkpoint is at epoch 1."
    action:
      rotate:
        sn': 1
        op: keep
        payee: 2
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: consumable
      modelResult: null
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 12
    who: hal
    say: "Suppose the witnesses even receipted a rotation from epoch 1, sequence 1, to sequence 1 (the same event again). It is not later: a checkpoint never rolls back or stands still on a rotation."
    evidence:
      add: [{"rotationTo":[1,1,1]}]
    action:
      rotate:
        sn': 1
        op: keep
        payee: 2
    expect:
      ok: false
      reason: sequence-not-later
      verdict: consumable
      modelResult: null
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff]
