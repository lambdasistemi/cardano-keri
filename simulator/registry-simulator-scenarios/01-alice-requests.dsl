grammar: 1
family: registry

id: 1
slug: alice-requests
story: "Alice posts a registration request"
narrative: "Anyone holding Alice's public inception creates a request UTxO at the cage: her AID, her refund address as owner, the bond D and the tip. Nothing contends; the registry is untouched."
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
  exhibits: [R6, R11]
  note: "The generation is still 0: a request never spends the cage."
fork:
  id: mallory-go
  at: 1
  title: "Mallory posts a go-request by hand"
  expectFinal:
    gen: 0
    plugin: 7
    leaves: []
    ckpts: []
    requests: [{"id":0,"aid":11,"owner":1,"submittedAt":0,"op":"register"}]
    nextReq: 1
    nextToken: 0
  step:
    now: 0
    actor: anyone
    as: "Mallory — posting a go-request by hand"
    action:
      contribute:
        aid: 11
        owner: 4
        submittedAt: 0
        op: goConvicted
    expect:
      ok: false
      reason: not-postable
    note: "Only a reap of a bondless checkpoint creates a go-request."
expectFinal:
  gen: 0
  plugin: 7
  leaves: []
  ckpts: []
  requests: [{"id":0,"aid":11,"owner":1,"submittedAt":0,"op":"register"}]
  nextReq: 1
  nextToken: 0
