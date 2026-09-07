grammar: 1
family: registry

id: 9
slug: pause-and-resume
story: "Alice pauses and resumes without touching the registry"
narrative: "Alice's next keys withdraw her bonds: the checkpoint stays on chain, parked, at min-ADA, with the key state a revival must rotate from. Later a depositing rotation makes it live again. The registry leaf never changed; the indirection is the token, which survives every rotation. A pause without the next keys, and a resume of a live checkpoint, are refused."
params:
  D: 1000
  tip: 2
  Mc: 4
  Mr: 1
  process: 10
  retract: 10
  W: 5
  far: 1000000000
plugin: 7
actors:
  1: Alice
  2: Bob
  3: "Hal (folder)"
  4: Mallory
  5: "Cora (convictor)"
  6: "Sam (reaper)"
env:
  inception: [11]
  rotationFrom:
    - [11, 0]
    - [11, 1]
step:
  now: 0
  actor: anyone
  as: Alice
  action:
    contribute:
      aid: 11
      owner: 1
      submittedAt: 0
      op: register
  expect:
    ok: true
    flow:
      deposited: 1002
      locked: []
      refunds: []
      tips: null
      premium: null
      intoRequest: 0
step:
  now: 1
  actor: anyone
  as: Hal
  action:
    fold:
      folder: 3
      gen: 0
      plugin: 7
      batch: [{"id":0,"do":"process"}]
  expect:
    ok: true
    flow:
      deposited: 0
      locked: [{"aid":11,"value":1000}]
      refunds: []
      tips:
        addr: 3
        value: 2
      premium: null
      intoRequest: 0
step:
  now: 4
  actor: next-keys
  as: "Alice — resuming a live checkpoint"
  action:
    resume:
      aid: 11
  expect:
    ok: false
    reason: not-parked
step:
  now: 5
  actor: next-keys
  as: Alice
  action:
    pause:
      aid: 11
  expect:
    ok: true
    state:
      gen: 1
      plugin: 7
      leaves: [{"aid":11,"status":{"active":0}}]
      ckpts: [{"aid":11,"ckpt":{"token":0,"k":1,"st":{"parked":5}}}]
      requests: []
      nextReq: 1
      nextToken: 1
    flow:
      deposited: 0
      locked: []
      refunds: []
      tips: null
      premium: null
      intoRequest: 0
  exhibits: [R6, R11, R1]
step:
  now: 6
  actor: next-keys
  as: "Alice — pausing a parked checkpoint"
  action:
    pause:
      aid: 11
  expect:
    ok: false
    reason: not-live
step:
  now: 7
  actor: next-keys
  as: Alice
  action:
    resume:
      aid: 11
  expect:
    ok: true
    flow:
      deposited: 0
      locked: []
      refunds: []
      tips: null
      premium: null
      intoRequest: 0
  exhibits: [R6, R1]
step:
  now: 8
  actor: next-keys
  as: "Alice — pausing again without a rotation from k=2"
  action:
    pause:
      aid: 11
  expect:
    ok: false
    reason: no-rotation
step:
  now: 8
  actor: proof
  as: "Cora — convicting Alice without a proof"
  action:
    convictCkpt:
      aid: 11
  expect:
    ok: false
    reason: no-duplicity-proof
  exhibits: [R14]
fork:
  id: convicted-while-parked
  at: 4
  title: "Cora convicts the parked checkpoint"
  env:
    inception: [11]
    rotationFrom:
      - [11, 0]
      - [11, 1]
    duplicity:
      - [11, 1]
  expectFinal:
    gen: 1
    plugin: 7
    leaves: [{"aid":11,"status":{"active":0}}]
    ckpts: []
    requests: [{"id":1,"aid":11,"owner":6,"submittedAt":1000000000,"op":"goConvicted"}]
    nextReq: 2
    nextToken: 1
  step:
    now: 6
    actor: proof
    as: "Cora — a proof against key state 1"
    action:
      convictCkpt:
        aid: 11
    expect:
      ok: true
      flow:
        deposited: 0
        locked: []
        refunds: []
        tips: null
        premium: null
        intoRequest: 0
    exhibits: [R6, R11]
  step:
    now: 7
    actor: next-keys
    as: "Alice — resuming a tombstone"
    action:
      resume:
        aid: 11
    expect:
      ok: false
      reason: not-parked
  step:
    now: 7
    actor: anyone
    as: "Sam — a tombstone is reaped at once"
    action:
      reap:
        reaper: 6
        aid: 11
    expect:
      ok: true
      flow:
        premium:
          addr: 6
          value: 1
        intoRequest: 3
    exhibits: [R13, R11]
expectFinal:
  gen: 1
  plugin: 7
  leaves: [{"aid":11,"status":{"active":0}}]
  ckpts: [{"aid":11,"ckpt":{"token":0,"k":2,"st":"live"}}]
  requests: []
  nextReq: 1
  nextToken: 1
