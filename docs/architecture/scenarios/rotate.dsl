grammar: 1
family: checkpoint

story: 3882
title: "Alice rotates; Hal is paid"
goal: "Separate witnessed evidence from the transaction that advances the checkpoint."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: []
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
step:
  slot: 12
  who: alice
  say: "The model is given witnessed rotation evidence from epoch 0, sequence 0 to sequence 1. No transaction has landed yet."
  evidence:
    add: [{"rotationTo":[0,0,1]}]
  expect:
    verdict: consumable
    live:
      sn: 0
      epoch: 0
      pool: 10
step:
  slot: 12
  who: hal
  say: "Hal submits the rotation as an advance with keep, naming himself payee. The chain pays P from the pool to Hal."
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
      poisoned: false
      bornAt: 0
      refundTo: 1
      pool: 8
      frozen: false
    flow:
      hunter:
        addr: 2
        dreg: 0
        b: 0
        pool: 2
    verdict: consumable
fork:
  id: twice
  at: 2
  title: "Hal tries to land the same rotation again"
  step:
    slot: 12
    who: hal
    say: "Landing it twice does nothing: the evidence names epoch 0 at sequence 0; the checkpoint is at epoch 1."
    action:
      rotate:
        sn': 1
        op: keep
        payee: 2
        refund': null
    expect:
      ok: false
      reason: no-witnessed-rotation
      verdict: consumable
      live:
        sn: 1
        epoch: 1
        pool: 8
