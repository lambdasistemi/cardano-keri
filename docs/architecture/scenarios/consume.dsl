grammar: 1
family: checkpoint

story: 3883
title: "A treasury reads, then refuses poisoned keys"
goal: "Observe why a consumer must check current checkpoint status for every use."
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
step:
  slot: 13
  who: treasury
  say: "The checkpoint is eligible. The application must separately check its own authorization and signature."
  expect:
    verdict: consumable
step:
  slot: 14
  who: alice
  say: "A current epoch quorum authorizes poison. Once landed, consumers stop accepting this epoch."
  evidence:
    add: [{"quorum":[1]}]
  action: poison
  expect:
    ok: true
    live:
      sn: 1
      epoch: 1
      poisoned: true
      pool: 8
    flow: {}
    verdict: poisoned
step:
  slot: 24
  who: treasury
  say: "Waiting does not clear poison. The treasury still refuses the checkpoint."
  expect:
    verdict: poisoned
