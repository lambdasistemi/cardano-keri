grammar: 1
family: registry

id: 3884
slug: architecture-duplicate
story: "Alice keeps one registry entry"
narrative: "Register Alice, attempt a duplicate, then return its bond after the rejection window."
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
  now: 5
  actor: anyone
  as: Mallory
  action:
    contribute:
      aid: 11
      owner: 4
      submittedAt: 5
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
  now: 6
  actor: anyone
  as: Hal
  action:
    fold:
      folder: 3
      gen: 1
      plugin: 7
      batch: [{"id":1,"do":"process"}]
  expect:
    ok: false
    reason: already-registered
step:
  now: 25
  actor: anyone
  as: Sam
  action:
    fold:
      folder: 6
      gen: 1
      plugin: 7
      batch: [{"id":1,"do":"reject"}]
  expect:
    ok: true
    flow:
      refunds: [{"addr":4,"value":1000}]
      tips:
        addr: 6
        value: 2
fork:
  id: sam-too-early
  at: 3
  title: "Sam rejects Mallory's request in phase 1"
  expectFinal:
    gen: 1
    plugin: 7
    leaves: [{"aid":11,"status":{"active":0}}]
    ckpts: [{"aid":11,"ckpt":{"token":0,"k":0,"st":"live"}}]
    requests: [{"id":1,"aid":11,"owner":4,"submittedAt":5,"op":"register"}]
    nextReq: 2
    nextToken: 1
  step:
    now: 6
    actor: anyone
    as: "Sam — rejecting in phase 1"
    action:
      fold:
        folder: 6
        gen: 1
        plugin: 7
        batch: [{"id":1,"do":"reject"}]
    expect:
      ok: false
      reason: not-rejectable
expectFinal:
  gen: 2
  plugin: 7
  leaves: [{"aid":11,"status":{"active":0}}]
  ckpts: [{"aid":11,"ckpt":{"token":0,"k":0,"st":"live"}}]
  requests: []
  nextReq: 2
  nextToken: 1
