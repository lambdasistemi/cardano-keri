grammar: 1
family: checkpoint

story: 6
title: "Alice revives her parked identity"
goal: "As Alice, I want my parked identity live again, and I want nobody else to be able to do it in my place."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["6.the-leaf-is-parked", "6.a-witnessed-rotation-from-exactly", "6.strictly-later-than-the-parked", "6.fresh-bonds-and-a-first", "6.the-checkpoint-is-born-now"]
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
  slot: 12
  who: alice
  say: "Alice closes her live checkpoint. The bonds and pool are paid as directed; the output retains the same representative token, min-ADA and key state (1, 1). The registry key stays active."
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
      bIn: 0
      convictor: null
      dregIn: 0
      hunter:
        addr: 1
        b: 0
        dreg: 0
        pool: 2
      poolIn: 0
      refund:
        addr: 1
        b: 5
        dreg: 1000
        pool: 8
    verdict: not-present
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
        refund:
          addr: 1
          b: 5
          dreg: 1000
          pool: 8
      state:
        parked:
          h:
            epoch: 1
            sn: 1
    exhibits: [T10_bonds_are_observable, T16_close_destination, T16_close_needs_rotation, T16_copied_reap_refused, T16_parked_hash_is_the_closed_checkpoints, T16_payments_are_named, T1_sn_monotone_all, T2_close_and_reopen_open_epochs, T5_close_enabled, T6_component_conservation, T6_dreg_never_a_fee, T6_intent_requires_new_keys, T7_step_iff_stepFn, T7_trace_iff_replay, T9_juvenility_is_consumer_only, consumableStateB_iff, parked_and_convicted_hold_no_bonds_or_pool, trace_sn_monotone_all]
step:
  slot: 40
  who: alice
  say: "Alice rotates again on KERI from the key state retained in the parked output; her witnesses receipt sequence 2."
  evidence:
    add: [{"rotationTo":[1,1,2]}]
  expect:
    verdict: not-present
step:
  slot: 40
  who: friend
  say: "Anyone with that public rotation and the bonds can revive her — a sponsor does, naming Alice’s refund address. Fresh bonds, a first pool, born now, at the next epoch: juvenile for W slots."
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
      poisoned: false
      frozen: false
      bornAt: 40
      refundTo: 1
      pool: 10
    flow:
      bIn: 5
      convictor: null
      dregIn: 1000
      hunter: null
      poolIn: 10
      refund: null
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
            bornAt: 40
            epoch: 2
            frozen: false
            poisoned: false
            pool: 10
            refundTo: 1
            sn: 2
    state:
      present:
        l:
          bornAt: 40
          epoch: 2
          frozen: false
          poisoned: false
          pool: 10
          refundTo: 1
          sn: 2
    exhibits: [T10_reopen_is_juvenile, T1_reopen_strict, T1_sn_monotone_all, T1_trace_sn_monotone, T2_close_and_reopen_open_epochs, T3_epoch_local, T5_reopen_enabled, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_parked_only_revives_or_convicts, T8_parked_returns_only_by_revival, T8_reopen_actor_is_proof, T9_juvenility_is_consumer_only, consumableStateB_iff, local_progress_unless_pending_or_retired, parked_and_convicted_hold_no_bonds_or_pool, trace_poison_fold, trace_sn_monotone_all]
fork:
  id: replay
  at: 1
  title: "A stranger replays the close’s own rotation — refused"
  step:
    slot: 40
    who: mallory
    say: "A stranger replays the rotation used to close. The output already retains key state (1, 1); sequence 1 is not strictly later, and the old witness does not authorize a rotation from that state."
    action:
      reopen:
        sn': 1
        refund: 4
        pool0: 10
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: not-present
      modelResult: null
      exhibits: [T1_close_rotation_cannot_revive, T7_step_iff_stepFn, T8_parked_only_revives_or_convicts, T8_reopen_actor_is_proof, T9_juvenility_is_consumer_only, consumableStateB_iff, parked_and_convicted_hold_no_bonds_or_pool]
fork:
  id: thief
  at: 1
  title: "Mallory holds the current keys of the parked key state — refused"
  step:
    slot: 40
    who: mallory
    say: "Mallory holds the keys of epoch 1. Signing as their quorum buys nothing on a parked identity, and she cannot produce a witnessed rotation from that key state: that takes the next keys. Her revival is refused."
    evidence:
      add: [{"quorum":[1]}]
    action:
      reopen:
        sn': 2
        refund: 4
        pool0: 10
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: not-present
      modelResult: null
      exhibits: [T7_step_iff_stepFn, T8_parked_only_revives_or_convicts, T8_reopen_actor_is_proof, T9_juvenility_is_consumer_only, consumableStateB_iff, parked_and_convicted_hold_no_bonds_or_pool]
fork:
  id: convicted
  at: 1
  title: "Cora convicts the parked output into pending custody"
  step:
    slot: 40
    who: cora
    say: "Cora supplies concrete duplicity at retained key state (1, 1). The parked output is consumed into pending termination custody, still retaining the token and key state. No bonds or pool move. Booking and an actual consuming fold are still required for retirement."
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
        bIn: 0
        convictor: null
        dregIn: 0
        hunter: null
        poolIn: 0
        refund: null
      verdict: not-present
      modelResult:
        flow:
          bIn: 0
          convictor: null
          dregIn: 0
          hunter: null
          poolIn: 0
          refund: null
        state:
          terminationPending:
            h:
              epoch: 1
              sn: 1
      exhibits: [T12_convict_parked_exact, T1_sn_monotone_all, T4_current_key_thief_cannot_revive, T5_convict_parked_enabled, T6_component_conservation, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_parked_only_revives_or_convicts, T8_reopen_actor_is_proof, T9_juvenility_is_consumer_only, consumableStateB_iff, parked_and_convicted_hold_no_bonds_or_pool, pending_consumer_refused, pending_custody_observations, trace_sn_monotone_all]
  step:
    slot: 40
    who: alice
    say: "A new rotation cannot revive pending termination custody. Local actions are refused; the associated system journey separately demonstrates booking and completion."
    evidence:
      add: [{"rotationTo":[1,1,2]}]
    action:
      reopen:
        sn': 2
        refund: 1
        pool0: 10
    expect:
      ok: false
      reason: termination-pending
      verdict: not-present
      modelResult: null
      exhibits: [T7_step_iff_stepFn, T8_reopen_actor_is_proof, T9_juvenility_is_consumer_only, consumableStateB_iff, pending_consumer_refused, pending_custody_observations, pending_has_no_local_exit, pending_step_impossible, trace_from_pending]
fork:
  id: twice
  at: 3
  title: "Consumable again; a revival of a live checkpoint — refused"
  step:
    slot: 50
    who: treasury
    say: "Ten slots later: consumable again."
    expect:
      verdict: consumable
  step:
    slot: 50
    who: friend
    say: "A live checkpoint cannot be revived again. Reopening consumes a parked output."
    action:
      reopen:
        sn': 3
        refund: 6
        pool0: 10
    expect:
      ok: false
      reason: reopen-needs-parked
      verdict: consumable
      modelResult: null
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_reopen_actor_is_proof, T9_juvenility_is_consumer_only, consumableStateB_iff]
