grammar: 1
family: checkpoint

story: 8
title: "The refund address stays the sponsor’s"
goal: "As a sponsor, I pay Alice’s registration — the conviction bond, the freeze bond and the first pool — and I want the bond and the pool I paid to go back to the refund address I chose if her checkpoint is ever convicted."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["8.the-registration-takes-the-refund", "8.with-no-signature-over-it", "8.a-rotation-leaves-the-refund", "8.so-does-a-deposit", "8.a-top-up-adds-to-the", "8.a-conviction-pays-the-freeze"]
step:
  slot: 0
  who: friend
  say: "A sponsor pays Alice’s registration — the conviction bond, the freeze bond and a first pool of 10 — and names his own refund address (6). The machine asks no signature over it."
  action:
    register:
      refund: 6
      pool0: 10
  expect:
    ok: true
    live:
      sn: 0
      epoch: 0
      refundTo: 6
      pool: 10
      frozen: false
    state:
      present:
        l:
          sn: 0
          epoch: 0
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 6
          pool: 10
    flow:
      dregIn: 1000
      bIn: 5
      poolIn: 10
      refund: null
      hunter: null
      convictor: null
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
            refundTo: 6
            pool: 10
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired]
    verdict: juvenile
step:
  slot: 12
  who: alice
  say: "Alice rotates on KERI; her witnesses receipt sequence 1."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  expect:
    verdict: consumable
step:
  slot: 12
  who: hal
  say: "Hal lands Alice’s rotation and is paid the premium. The refund address stays the sponsor’s."
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
      refundTo: 6
      pool: 8
      frozen: false
    state:
      present:
        l:
          sn: 1
          epoch: 1
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 6
          pool: 8
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
            refundTo: 6
            pool: 8
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
    verdict: consumable
step:
  slot: 12
  who: alice
  say: "At her next rotation Alice’s new keys (epoch 2) sign a deposit and she lands it herself. On full bonds a deposit is a keep (D-040). The refund address stays the sponsor’s: no message her keys sign can move it."
  evidence:
    add: [{"rotationTo":[1,1,2]},{"depositAuthorized":[2]}]
  action:
    rotate:
      sn': 2
      op: deposit
      payee: 1
  expect:
    ok: true
    live:
      sn: 2
      epoch: 2
      refundTo: 6
      pool: 6
      frozen: false
    state:
      present:
        l:
          sn: 2
          epoch: 2
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 6
          pool: 6
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 0
      refund: null
      hunter:
        addr: 1
        dreg: 0
        b: 0
        pool: 2
      convictor: null
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 0
        refund: null
        hunter:
          addr: 1
          dreg: 0
          b: 0
          pool: 2
        convictor: null
      state:
        present:
          l:
            sn: 2
            epoch: 2
            poisoned: false
            frozen: false
            bornAt: 0
            refundTo: 6
            pool: 6
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_deposit_on_full_is_keep, T5_every_bond_option, T6_component_conservation, T6_deposit_requires_new_keys, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
    verdict: consumable
step:
  slot: 13
  who: alice
  say: "Alice tops up the pool herself. What she adds goes, on conviction, to the same refund address."
  action:
    topUp:
      x: 4
  expect:
    ok: true
    live:
      sn: 2
      epoch: 2
      refundTo: 6
      pool: 10
      frozen: false
    state:
      present:
        l:
          sn: 2
          epoch: 2
          poisoned: false
          frozen: false
          bornAt: 0
          refundTo: 6
          pool: 10
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 4
      refund: null
      hunter: null
      convictor: null
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 4
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
            refundTo: 6
            pool: 10
    exhibits: [T10_bonds_are_observable, T14_pool_increases_only_by_topup, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T3_epoch_local, T4_current_key_thief_cannot_rotate_or_freeze, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_refund_fixed, T6_refund_fixed_along_trace, T6_refund_is_registration_address, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, step_from_present_keeps_refund, trace_poison_fold, trace_sn_monotone_all]
    verdict: consumable
step:
  slot: 14
  who: cora
  say: "Cora proves duplicity at Alice’s current key state. The conviction bond goes to Cora; the freeze bond and the whole pool, Alice’s top-up included, go to the sponsor’s address."
  evidence:
    add: [{"duplicityAt":[2,2]}]
  action:
    convict:
      payee: 3
  expect:
    ok: true
    state:
      terminationPending:
        h:
          epoch: 2
          sn: 2
    flow:
      dregIn: 0
      bIn: 0
      poolIn: 0
      refund:
        addr: 6
        dreg: 0
        b: 5
        pool: 10
      hunter: null
      convictor:
        addr: 3
        dreg: 1000
        b: 0
        pool: 0
    modelResult:
      flow:
        dregIn: 0
        bIn: 0
        poolIn: 0
        refund:
          addr: 6
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
            epoch: 2
            sn: 2
    exhibits: [T10_bonds_are_observable, T12_convict_exact, T16_payments_are_named, T1_sn_monotone_all, T4_current_key_thief_cannot_rotate_or_freeze, T5_convict_enabled, T6_component_conservation, T6_conviction_refunds_registration_address, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_freeze_and_convict_actors_are_proof, T9_juvenility_is_consumer_only, consumableStateB_iff, pending_consumer_refused, pending_custody_observations, step_from_present_keeps_refund, trace_sn_monotone_all]
    verdict: not-present
