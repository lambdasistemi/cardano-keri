grammar: 1
family: registry

id: 14
slug: go-request-cannot-be-bricked
story: "A go-request can neither be retracted nor rejected"
narrative: "Alice's checkpoint closes through the premise, which names Mallory — an adversary — the recipient of the live bond; her go-request carries the closing rotation's reached key state 1. Mallory then tries to make the key state disappear: retracting is refused, because the request is dated at the end of time and phase 2 never comes; rejecting it is refused by the plugin, wherever it sits in a batch. The only way out of the inbox is to be processed, and anyone can do that: Hal's fold lands it and the leaf keeps key state 1 with no checkpoint, so there is nothing left to reap."
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
  closeAuth:
    - [11, 4]
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
      bondReturn: null
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
      bondReturn: null
step:
  now: 2
  actor: anyone
  as: "Mallory — the premise names her the recipient, so her close succeeds"
  action:
    reap:
      reaper: 4
      aid: 11
      recipient: 4
  expect:
    ok: true
    flow:
      deposited: 0
      locked: []
      refunds: []
      tips: null
      premium:
        addr: 4
        value: 1
      intoRequest: 3
      bondReturn:
        addr: 4
        value: 1000
  exhibits: [R13, R11]
step:
  now: 8
  actor: owner
  as: "Mallory — retracting the go-request"
  action:
    retract:
      req: 1
  expect:
    ok: false
    reason: not-in-phase-2
  exhibits: [R9]
step:
  now: 8
  actor: anyone
  as: Bob
  action:
    contribute:
      aid: 12
      owner: 2
      submittedAt: 8
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
      bondReturn: null
step:
  now: 30
  actor: anyone
  as: "Mallory — rejecting it inside a batch, behind a rejectable request"
  action:
    fold:
      folder: 4
      gen: 1
      plugin: 7
      batch: [{"id":2,"do":"reject"},{"id":1,"do":"reject"}]
  expect:
    ok: false
    reason: go-not-rejectable
  exhibits: [R9]
step:
  now: 31
  actor: anyone
  as: "Hal — the only exit is to be processed"
  action:
    fold:
      folder: 3
      gen: 1
      plugin: 7
      batch: [{"id":1,"do":"process"},{"id":2,"do":"reject"}]
  expect:
    ok: true
    flow:
      deposited: 0
      locked: []
      refunds:
        - addr: 4
          value: 1
        - addr: 2
          value: 1000
      tips:
        addr: 3
        value: 4
      premium: null
      intoRequest: 0
      bondReturn: null
  exhibits: [R11, R1, R12]
step:
  now: 32
  actor: anyone
  as: "Mallory — nothing left to reap: the leaf is dormant and holds no UTxO"
  action:
    reap:
      reaper: 4
      aid: 11
      recipient: 4
  expect:
    ok: false
    reason: no-checkpoint
  exhibits: [R13, R1]
expectFinal:
  gen: 2
  plugin: 7
  leaves: [{"aid":11,"status":{"dormant":1}}]
  ckpts: []
  requests: []
  nextReq: 3
  nextToken: 1
