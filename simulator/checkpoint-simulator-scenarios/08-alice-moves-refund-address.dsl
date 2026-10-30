grammar: 1
family: checkpoint

story: 8
title: "Alice moves her refund address"
goal: "As Alice, I want the money to come back to me and not to whoever registered my checkpoint."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["8.the-signature-over-the-new", "8.a-relayer-submitting-her-public"]
step:
  slot: 0
  who: friend
  say: "A stranger registered Alice’s checkpoint with his own refund address (6)."
  action:
    register:
      refund: 6
      pool0: 10
  expect:
    ok: true
    live:
      refundTo: 6
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
            refundTo: 6
            sn: 0
    state:
      present:
        l:
          bornAt: 0
          epoch: 0
          frozen: false
          poisoned: false
          pool: 10
          refundTo: 6
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
  say: "The same relayer submits the rotation with no address at all: it lands, and the refund address stays the stranger’s."
  action:
    rotate:
      sn': 1
      op: keep
      payee: 2
      refund': null
  expect:
    ok: true
    live:
      sn: 1
      epoch: 1
      refundTo: 6
      pool: 8
      frozen: false
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
            refundTo: 6
            sn: 1
    state:
      present:
        l:
          bornAt: 0
          epoch: 1
          frozen: false
          poisoned: false
          pool: 8
          refundTo: 6
          sn: 1
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_relayer_cannot_park_age_or_close, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, trace_poison_fold, trace_sn_monotone_all]
step:
  slot: 12
  who: alice
  say: "At her next rotation Alice’s new keys (epoch 2) sign her address along with the rotation. The address moves."
  evidence:
    add: [{"rotationTo":[1,1,2]},{"intentAuthorized":[2,"keep",1]}]
  action:
    rotate:
      sn': 2
      op: keep
      payee: 1
      refund': 1
  expect:
    ok: true
    live:
      sn: 2
      epoch: 2
      refundTo: 1
      pool: 6
      frozen: false
    flow:
      bIn: 0
      convictor: null
      dregIn: 0
      hunter:
        addr: 1
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
          addr: 1
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
            pool: 6
            refundTo: 1
            sn: 2
    state:
      present:
        l:
          bornAt: 0
          epoch: 2
          frozen: false
          poisoned: false
          pool: 6
          refundTo: 1
          sn: 2
    exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_every_bond_option, T5_keep_is_rotated, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: unrelated-intent
  at: 2
  title: "a signed deposit is not a signed address"
  step:
    slot: 12
    who: alice
    say: "Alice rotates again and her new keys (epoch 2) sign a deposit, no address named."
    evidence:
      add: [{"rotationTo":[1,1,2]},{"intentAuthorized":[2,"deposit",null]}]
  step:
    slot: 12
    who: hal
    say: "A relayer lands the rotation as a keep asking to move the refund address to Alice. The message her keys signed is a deposit without an address, not a keep with one. Refused."
    action:
      rotate:
        sn': 2
        op: keep
        payee: 2
        refund': 1
    expect:
      ok: false
      reason: intent-not-authorized
      modelResult: null
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff]
  step:
    slot: 12
    who: hal
    say: "The signed message itself lands: the deposit — on full bonds a keep in all but its signature (D-040): nothing brought, the premium paid, juvenility untouched — and the address stays the stranger’s."
    action:
      rotate:
        sn': 2
        op: deposit
        payee: 2
        refund': null
    expect:
      ok: true
      live:
        refundTo: 6
        frozen: false
        bornAt: 0
        pool: 6
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
              epoch: 2
              frozen: false
              poisoned: false
              pool: 6
              refundTo: 6
              sn: 2
      state:
        present:
          l:
            bornAt: 0
            epoch: 2
            frozen: false
            poisoned: false
            pool: 6
            refundTo: 6
            sn: 2
      exhibits: [T10_bonds_are_observable, T14_pool_decreases_only_by_premium, T16_payments_are_named, T1_rotate_strict, T1_sn_monotone, T1_sn_monotone_all, T1_trace_sn_monotone, T2_epoch_only_by_rotation, T3_epoch_local, T3_rotation_clears, T5_deposit_on_full_is_keep, T5_every_bond_option, T6_component_conservation, T6_dreg_never_a_fee, T6_dreg_never_moves_between_present_states, T6_intent_requires_new_keys, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: relayer-address
  at: 1
  title: "A relayer asks to move the address — refused"
  step:
    slot: 12
    who: hal
    say: "Alice rotates on KERI. A relayer submits her public rotation asking to move the refund address to Alice’s: the new keys did not sign the address, so the rotation is refused as submitted."
    action:
      rotate:
        sn': 1
        op: keep
        payee: 2
        refund': 1
    expect:
      ok: false
      reason: intent-not-authorized
      verdict: consumable
      modelResult: null
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T9_juvenility_is_consumer_only, consumableStateB_iff]
