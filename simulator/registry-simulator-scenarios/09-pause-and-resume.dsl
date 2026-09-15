grammar: 1
family: registry

id: 9
slug: close-and-revive
story: "Alice closes under the premise and revives from the retained key state"
narrative: "Alice's checkpoint is live at key state 0. Sam closes it through the close-authorization premise, which names him the opaque recipient of the live bond: the closing rotation's reached key state 1 rides out in a go-request dated at the end of time. The go-request cannot be retracted; Hal's fold lands it and the leaf keeps key state 1 with no checkpoint at all — dormant holds no UTxO, so reaping it is refused. Alice then revives from exactly that retained state: a fresh token mints and the checkpoint returns live at key state 2. On the branch Cora convicts the live checkpoint with a duplicity proof; the tombstone then reaps at once, permissionlessly, refunding no live bond a second time, and the fold lands the conviction."
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
  closeAuth:
    - [11, 6]
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
  now: 5
  actor: anyone
  as: "Sam — closing through the premise that names him the recipient"
  action:
    reap:
      reaper: 6
      aid: 11
      recipient: 6
  expect:
    ok: true
    flow:
      deposited: 0
      locked: []
      refunds: []
      tips: null
      premium:
        addr: 6
        value: 1
      intoRequest: 3
      bondReturn:
        addr: 6
        value: 1000
  exhibits: [R13, R11]
step:
  now: 6
  actor: owner
  as: "Sam — retracting the go-request dated at the end of time"
  action:
    retract:
      req: 1
  expect:
    ok: false
    reason: not-in-phase-2
  exhibits: [R9]
step:
  now: 7
  actor: anyone
  as: "Hal — the close fold lands: the leaf keeps the reached key state 1"
  action:
    fold:
      folder: 3
      gen: 1
      plugin: 7
      batch: [{"id":1,"do":"process"}]
  expect:
    ok: true
    flow:
      deposited: 0
      locked: []
      refunds:
        - addr: 6
          value: 1
      tips:
        addr: 3
        value: 2
      premium: null
      intoRequest: 0
      bondReturn: null
  exhibits: [R12, R1]
step:
  now: 8
  actor: anyone
  as: "Sam — reaping a dormant AID: dormant holds no UTxO"
  action:
    reap:
      reaper: 6
      aid: 11
      recipient: 6
  expect:
    ok: false
    reason: no-checkpoint
  exhibits: [R13, R1]
step:
  now: 9
  actor: anyone
  as: "Alice — reviving from exactly the retained key state 1"
  action:
    contribute:
      aid: 11
      owner: 1
      submittedAt: 9
      op: revive
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
  now: 10
  actor: anyone
  as: "Hal — the revival fold: a fresh token, live again at key state 2"
  action:
    fold:
      folder: 3
      gen: 2
      plugin: 7
      batch: [{"id":2,"do":"process"}]
  expect:
    ok: true
    flow:
      deposited: 0
      locked:
        - aid: 11
          value: 1000
      refunds: []
      tips:
        addr: 3
        value: 2
      premium: null
      intoRequest: 0
      bondReturn: null
  exhibits: [R1, R2, R11, R12]
fork:
  id: convicted-while-live
  at: 2
  title: "Cora convicts the live checkpoint before the close"
  env:
    inception: [11]
    rotationFrom:
      - [11, 0]
      - [11, 1]
    duplicity:
      - [11, 0]
    closeAuth:
      - [11, 6]
  step:
    now: 6
    actor: proof
    as: "Cora — a duplicity proof against key state 0"
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
        bondReturn: null
    exhibits: [R6, R14]
  step:
    now: 7
    actor: anyone
    as: "Sam — a tombstone is reaped at once, no premise, recipient 4 un-named and irrelevant"
    action:
      reap:
        reaper: 6
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
          addr: 6
          value: 1
        intoRequest: 3
        bondReturn: null
    exhibits: [R13, R11]
  step:
    now: 8
    actor: anyone
    as: Hal
    action:
      fold:
        folder: 3
        gen: 1
        plugin: 7
        batch: [{"id":1,"do":"process"}]
    expect:
      ok: true
      flow:
        deposited: 0
        locked: []
        refunds:
          - addr: 6
            value: 1
        tips:
          addr: 3
          value: 2
        premium: null
        intoRequest: 0
        bondReturn: null
    exhibits: [R11, R12]
expectFinal:
  gen: 3
  plugin: 7
  leaves: [{"aid":11,"status":{"active":1}}]
  ckpts: [{"aid":11,"ckpt":{"token":1,"k":2,"st":"live"}}]
  requests: []
  nextReq: 3
  nextToken: 2
