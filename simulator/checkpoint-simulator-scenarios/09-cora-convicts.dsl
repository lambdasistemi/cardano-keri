grammar: 1
family: checkpoint

story: 9
title: "Cora convicts"
goal: "As Cora, I want concrete duplicity to place the checkpoint into pending termination custody, receive the conviction bond, and enable a later consuming fold to retire the registry key."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["9.the-second-rotation-is-at", "9.satisfies-the-common-prior-next", "9.satisfies-its-own-current", "9.carries-own-derived-receipts", "9.and-differs-in-complete-content", "9.both-validate-authenticated-context"]
step:
  slot: 0
  who: alice
  say: "Registered, bonded."
  action:
    register:
      refund: 1
      pool0: 12
  expect:
    ok: true
    verdict: juvenile
    modelResult:
      flow:
        dregIn: 1000
        bIn: 5
        poolIn: 12
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
            pool: 12
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
          pool: 12
          toppedUp: false
    flow:
      dregIn: 1000
      bIn: 5
      poolIn: 12
      refund: null
      hunter: null
      convictor: null
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, registration_pool_at_least_premium]
step:
  slot: 1
  who: alice
  say: "Alice lands her first rotation. Its prior-next commitment anchors both branches of the later duplicity proof."
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
      pool: 10
    verdict: juvenile
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
            pool: 10
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
          pool: 10
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
  say: "Alice has poisoned the epoch (Mallory has the keys). A conviction does not care which state the checkpoint is in."
  evidence:
    add: [{"quorum":[1]}]
  action: poison
  expect:
    ok: true
    live:
      poisoned: true
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
            pool: 10
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
          pool: 10
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
  who: cora
  say: "Cora supplies a conflicting rotation at sequence 1. Both branches satisfy the common prior-next commitment and their signing and derived-witness thresholds. The checkpoint enters termination-pending custody, keeping its token and key state. D goes to Cora; B and the pool return to the refund address. The registry key remains active until the later consuming fold."
  evidence:
    add: [{"duplicityAt":[1,1]}]
  action:
    convict:
      payee: 3
  expect:
    ok: true
    state:
      terminationPending:
        h:
          epoch: 1
          sn: 1
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 0
      refund:
        addr: 1
        dreg: 0
        b: 5
        pool: 10
      hunter: null
      convictor:
        addr: 3
        dreg: 1000
        b: 0
        pool: 0
    verdict: not-present
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 0
        refund:
          addr: 1
          dreg: 0
          b: 5
          pool: 10
        hunter: null
        convictor:
          addr: 3
          dreg: 1000
          b: 0
          pool: 0
      state:
        terminationPending:
          h:
            epoch: 1
            sn: 1
    exhibits: [T10_bonds_are_observable, T12_convict_exact, T16_payments_are_named, T1_sn_monotone_all, T4_current_key_thief_cannot_rotate_or_freeze, T4_poisoned_blocks_quorum_and_freeze, T4_poisoned_nonrotation_inert, T5_convict_enabled, T6_component_conservation, T6_conviction_refunds_registration_address, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, pending_consumer_refused, pending_custody_observations, step_from_present_keeps_refund, trace_sn_monotone_all]
fork:
  id: noproof
  at: 2
  title: "Cora without the second rotation"
  step:
    slot: 12
    who: cora
    say: "Without a second receipted rotation at the tip’s sequence there is no conviction."
    action:
      convict:
        payee: 3
    expect:
      ok: false
      reason: no-duplicity-proof
      verdict: poisoned
      modelResult: null
      exhibits: [T10_bonds_are_observable, T12_convict_exact, T7_step_iff_stepFn, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: terminal
  at: 3
  title: "Pending custody refuses local actions"
  step:
    slot: 12
    who: alice
    say: "Pending termination custody refuses a local rotation."
    evidence:
      add: [{"rotationTo":[0,0,1]}]
    action:
      rotate:
        sn': 1
        op: deposit
        payee: 1
    expect:
      ok: false
      reason: termination-pending
      verdict: not-present
      modelResult: null
      exhibits: [T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff, pending_consumer_refused, pending_custody_observations, pending_has_no_local_exit, pending_step_impossible, trace_from_pending]
  step:
    slot: 12
    who: friend
    say: "Pending termination custody refuses a top-up."
    action:
      topUp:
        x: 1
    expect:
      ok: false
      reason: termination-pending
      verdict: not-present
      modelResult: null
      exhibits: [T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff, pending_consumer_refused, pending_custody_observations, pending_has_no_local_exit, pending_step_impossible, trace_from_pending]
fork:
  id: sequence-zero
  at: 0
  title: "Inception is not an ordinary rotation"
  step:
    slot: 0
    who: cora
    say: "A sequence-zero sibling cannot be later than its prior establishment. The concrete rotation predicate refuses this evidence."
    evidence:
      add: [{"duplicityAt":[0,0]}]
    action:
      convict:
        payee: 3
    expect:
      ok: false
      reason: no-duplicity-proof
      verdict: juvenile
      modelResult: null
      exhibits: [T10_bonds_are_observable, T12_convict_exact, T7_step_iff_stepFn, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, consumableStateB_iff]
