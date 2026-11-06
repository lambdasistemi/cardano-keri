grammar: 1
family: checkpoint

story: 4
title: "Alice unfreezes"
goal: "As Alice, I want my checkpoint back in service, so I land my rotation myself, put the freeze bond back, and top up the pool."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["4.the-advance-predicate", "4.the-new-keys-signature-on", "4.then-the-freeze-bond-is", "4.nothing-else-changes-and-juvenility"]
step:
  slot: 0
  who: alice
  say: "Registered with one premium in the pool."
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
  who: alice
  say: "Alice rotates on KERI."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  expect:
    verdict: consumable
step:
  slot: 12
  who: hal
  say: "Hal lands it and takes the premium; the pool is empty."
  action:
    rotate:
      sn': 1
      op: keep
      payee: 2
  expect:
    ok: true
    live:
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
  say: "Alice rotates again on KERI."
  evidence:
    add: [{"rotationTo":[1,1,2]}]
  expect:
    verdict: consumable
step:
  slot: 12
  who: hal
  say: "Hal freezes her (story 3)."
  action:
    freeze:
      sn': 2
      payee: 2
  expect:
    ok: true
    live:
      pool: 0
      frozen: true
    verdict: frozen
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 0
        refund: null
        hunter:
          addr: 2
          dreg: 0
          b: 5
          pool: 0
        convictor: null
      state:
        present:
          l:
            sn: 1
            epoch: 1
            poisoned: false
            frozen: true
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
          frozen: true
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
        b: 5
        pool: 0
      convictor: null
    exhibits: [T10_bonds_are_observable, T15_b_leaves_only_by_freeze, T15_freeze_makes_inert, T16_payments_are_named, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T5_freeze_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_frozen_flips_only_by_rotation_or_freeze, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, step_from_present_keeps_refund, topped_up_kept_by_poison_and_freeze, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 20
  who: alice
  say: "Keep is enabled from a frozen state too: the rotation lands, unpaid because the pool is short, and the checkpoint stays frozen. The datum moves; the missing bond does not return."
  action:
    rotate:
      sn': 2
      op: keep
      payee: 1
  expect:
    ok: true
    live:
      sn: 2
      epoch: 2
      poisoned: false
      bornAt: 0
      pool: 0
      frozen: true
    verdict: frozen
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
            frozen: true
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
          frozen: true
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
    exhibits: [T10_bonds_are_observable, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, rotation_clears_topped_up, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 20
  who: alice
  say: "Alice rotates again and lands it herself with deposit, bringing the freeze bond back. The bond is full on the output; her juvenility is untouched — a deposit is the unfreeze, not a bonding (D-040) — so she is consumable at once."
  evidence:
    add: [{"rotationTo":[2,2,3]},{"depositAuthorized":[3]}]
  action:
    rotate:
      sn': 3
      op: deposit
      payee: 1
  expect:
    ok: true
    live:
      sn: 3
      epoch: 3
      poisoned: false
      frozen: false
      bornAt: 0
      refundTo: 1
      pool: 0
    verdict: consumable
    modelResult:
      flow:
        dregIn: 0
        bIn: 5
        poolIn: 0
        refund: null
        hunter: null
        convictor: null
      state:
        present:
          l:
            sn: 3
            epoch: 3
            poisoned: false
            frozen: false
            bornAt: 0
            refundTo: 1
            pool: 0
            toppedUp: false
    state:
      present:
        l:
          sn: 3
          epoch: 3
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 1
          pool: 0
          toppedUp: false
    flow:
      dregIn: 0
      bIn: 5
      poolIn: 0
      refund: null
      hunter: null
      convictor: null
    exhibits: [T10_bonds_are_observable, T10_only_deposit_restores, T15_b_returns_only_by_deposit, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T6_component_conservation, T6_deposit_requires_new_keys, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_frozen_flips_only_by_rotation_or_freeze, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, local_progress_unless_pending_or_retired, rotation_clears_topped_up, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 20
  who: alice
  say: "The pool is separate: Alice adds 20 to it. Adding to the pool touches nothing else but the top-up mark of this key state."
  action:
    topUp:
      x: 20
  expect:
    ok: true
    live:
      bornAt: 0
      pool: 20
      toppedUp: true
    verdict: consumable
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 20
        refund: null
        hunter: null
        convictor: null
      state:
        present:
          l:
            sn: 3
            epoch: 3
            poisoned: false
            frozen: false
            bornAt: 0
            refundTo: 1
            pool: 20
            toppedUp: true
    state:
      present:
        l:
          sn: 3
          epoch: 3
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 1
          pool: 20
          toppedUp: true
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 20
      refund: null
      hunter: null
      convictor: null
    exhibits: [T10_bonds_are_observable, T14_pool_increases_only_by_topup, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T4_current_key_thief_cannot_rotate_or_freeze, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, at_most_one_topUp_between_rotations, consumableStateB_iff, step_from_present_keeps_refund, topUp_adds_at_least_premium, topped_up_set_only_by_topUp, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 30
  who: hal
  say: "Hal sees a pool worth landing rotations for again."
  expect:
    verdict: consumable
