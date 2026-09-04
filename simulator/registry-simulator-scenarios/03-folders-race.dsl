grammar: 1
family: registry

id: 3
slug: folders-race
story: "Two folders race"
narrative: "Alice and Bob both post. Hal's fold at generation 0 lands both. Mallory's identical fold is refused as stale — on chain, a spent input, at no cost. Rebuilt against generation 1, her batch is empty and refused."
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
  inception: [11, 12]
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
  as: Bob
  action:
    contribute:
      aid: 12
      owner: 2
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
  now: 2
  actor: anyone
  as: "Hal — first fold"
  action:
    fold:
      folder: 3
      gen: 0
      plugin: 7
      batch: [{"id":0,"do":"process"},{"id":1,"do":"process"}]
  expect:
    ok: true
    flow:
      locked: [{"aid":11,"value":1000},{"aid":12,"value":1000}]
      tips:
        addr: 3
        value: 4
  exhibits: [R1, R2, R6, R11]
step:
  now: 2
  actor: anyone
  as: "Mallory — the same fold, one block later"
  action:
    fold:
      folder: 4
      gen: 0
      plugin: 7
      batch: [{"id":0,"do":"process"},{"id":1,"do":"process"}]
  expect:
    ok: false
    reason: stale-generation
  exhibits: [R7]
  note: "Both requesters were served by Hal's fold; Mallory lost only the tips."
step:
  now: 3
  actor: anyone
  as: "Mallory — rebuilt against generation 1"
  action:
    fold:
      folder: 4
      gen: 1
      plugin: 7
      batch: []
  expect:
    ok: false
    reason: empty-fold
  exhibits: [R8]
fork:
  id: mallory-first
  at: 2
  title: "Mallory's fold lands first"
  expectFinal:
    gen: 1
    plugin: 7
    leaves: [{"aid":12,"status":{"active":1}},{"aid":11,"status":{"active":0}}]
    ckpts: [{"aid":12,"ckpt":{"token":1,"k":0,"st":"live"}},{"aid":11,"ckpt":{"token":0,"k":0,"st":"live"}}]
    requests: []
    nextReq: 2
    nextToken: 2
  step:
    now: 2
    actor: anyone
    as: "Mallory — her fold lands first"
    action:
      fold:
        folder: 4
        gen: 0
        plugin: 7
        batch: [{"id":0,"do":"process"},{"id":1,"do":"process"}]
    expect:
      ok: true
      flow:
        locked: [{"aid":11,"value":1000},{"aid":12,"value":1000}]
        tips:
          addr: 4
          value: 4
    exhibits: [R1, R11, R12]
    note: "Anyone may fold: the requesters are served whoever lands it."
  step:
    now: 2
    actor: anyone
    as: "Hal — one block later"
    action:
      fold:
        folder: 3
        gen: 0
        plugin: 7
        batch: [{"id":0,"do":"process"},{"id":1,"do":"process"}]
    expect:
      ok: false
      reason: stale-generation
    exhibits: [R7]
expectFinal:
  gen: 1
  plugin: 7
  leaves: [{"aid":12,"status":{"active":1}},{"aid":11,"status":{"active":0}}]
  ckpts: [{"aid":12,"ckpt":{"token":1,"k":0,"st":"live"}},{"aid":11,"ckpt":{"token":0,"k":0,"st":"live"}}]
  requests: []
  nextReq: 2
  nextToken: 2
