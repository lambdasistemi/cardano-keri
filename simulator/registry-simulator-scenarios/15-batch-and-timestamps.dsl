grammar: 1
family: registry

id: 15
slug: batch-and-timestamps
story: "A batch that names a request twice, and a request dated in the future"
narrative: "A fold lists Alice's request twice: the first entry consumes it, the second finds nothing, the whole fold is refused. Mallory writes submitted_at = 100 at slot 0: in phase 1 until slot 110 and rejectable at once, because a future timestamp is dishonest by definition; Sam rejects it."
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
  now: 0
  actor: anyone
  as: Mallory
  action:
    contribute:
      aid: 12
      owner: 4
      submittedAt: 100
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
  as: "Mallory — naming a request twice"
  action:
    fold:
      folder: 4
      gen: 0
      plugin: 7
      batch: [{"id":0,"do":"process"},{"id":0,"do":"process"}]
  expect:
    ok: false
    reason: unknown-request
step:
  now: 1
  actor: anyone
  as: Sam
  action:
    fold:
      folder: 6
      gen: 0
      plugin: 7
      batch: [{"id":1,"do":"reject"}]
  expect:
    ok: true
    flow:
      refunds: [{"addr":4,"value":1000}]
      tips:
        addr: 6
        value: 2
  exhibits: [R9, R10]
step:
  now: 2
  actor: anyone
  as: Hal
  action:
    fold:
      folder: 3
      gen: 1
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
  exhibits: [R2, R1]
fork:
  id: sam-sweeps-alice-too
  at: 3
  title: "Sam rejects Alice's honest request too"
  expectFinal:
    gen: 0
    plugin: 7
    leaves: []
    ckpts: []
    requests: [{"id":1,"aid":12,"owner":4,"submittedAt":100,"op":"register"},{"id":0,"aid":11,"owner":1,"submittedAt":0,"op":"register"}]
    nextReq: 2
    nextToken: 0
  step:
    now: 1
    actor: anyone
    as: "Sam — Alice's request is in phase 1"
    action:
      fold:
        folder: 6
        gen: 0
        plugin: 7
        batch: [{"id":1,"do":"reject"},{"id":0,"do":"reject"}]
    expect:
      ok: false
      reason: not-rejectable
    exhibits: [R10]
expectFinal:
  gen: 2
  plugin: 7
  leaves: [{"aid":11,"status":{"active":0}}]
  ckpts: [{"aid":11,"ckpt":{"token":0,"k":0,"st":"live"}}]
  requests: []
  nextReq: 2
  nextToken: 1
