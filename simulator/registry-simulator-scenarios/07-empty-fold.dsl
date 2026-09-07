grammar: 1
family: registry

id: 7
slug: empty-fold
story: "An empty fold is refused"
narrative: "A fold with no request would re-create the registry unchanged for the price of a fee, moving its generation and invalidating every fold built against it. It is refused. A process in phase 2 is refused too; nobody folds in phase 1, and Alice retracts in phase 2."
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
  as: "Mallory — churning the cage"
  action:
    fold:
      folder: 4
      gen: 0
      plugin: 7
      batch: []
  expect:
    ok: false
    reason: empty-fold
  exhibits: [R8]
step:
  now: 12
  actor: anyone
  as: "Hal — processing in phase 2"
  action:
    fold:
      folder: 3
      gen: 0
      plugin: 7
      batch: [{"id":0,"do":"process"}]
  expect:
    ok: false
    reason: not-in-phase-1
  exhibits: [R10]
step:
  now: 12
  actor: owner
  as: Alice
  action:
    retract:
      req: 0
  expect:
    ok: true
    flow:
      deposited: 0
      locked: []
      refunds: [{"addr":1,"value":1002}]
      tips: null
      premium: null
      intoRequest: 0
  exhibits: [R9]
expectFinal:
  gen: 0
  plugin: 7
  leaves: []
  ckpts: []
  requests: []
  nextReq: 1
  nextToken: 0
