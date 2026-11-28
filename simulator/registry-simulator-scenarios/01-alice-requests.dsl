grammar: 1
family: registry

wireVersion: 3
config:
  activePolicy: 8
  applicationPolicy: 7
  bookingWidth: 1
  maxFee: 1
  processTime: 5
  registrationCost: 2
  registryId: 9
  retractTime: 0
  root: [203, 242, 156, 228, 132, 34, 35, 37]
id: 1
slug: alice-requests
story: "Alice books a registration"
narrative: "The request holds registration cost, tip, retained output value and bond. Booking shows the inception evidence and leaves the registry unchanged."
params:
  D: 10
  Mc: 4
  Mr: 2
  tip: 1
plugin: 7
actors:
  6: "authorized bond recipient"
  7: "termination booker"
  42: "Alice, request refund address"
env:
  convictions: [{"comparison":{"tip":{"aid":11,"epoch":1,"sn":1,"keys":{"curKeys":[[11]],"curThreshold":{"count":{"required":1}},"nextKeys":[[11]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":11,"sn":0,"delegated":false,"nextKeys":[11],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[11],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"writer/11/1"}},"rival":{"event":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"sibling/11/1"},"structureVerified":true,"signatures":[{"signer":11,"event":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"sibling/11/1"},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":105}},{"comparison":{"tip":{"aid":12,"epoch":1,"sn":1,"keys":{"curKeys":[[12]],"curThreshold":{"count":{"required":1}},"nextKeys":[[12]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":12,"sn":0,"delegated":false,"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"writer/12/1"}},"rival":{"event":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"sibling/12/1"},"structureVerified":true,"signatures":[{"signer":12,"event":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"sibling/12/1"},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":106}},{"comparison":{"tip":{"aid":13,"epoch":1,"sn":1,"keys":{"curKeys":[[13]],"curThreshold":{"count":{"required":1}},"nextKeys":[[13]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":13,"sn":0,"delegated":false,"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"writer/13/1"}},"rival":{"event":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[14],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"sibling/13/1"},"structureVerified":true,"signatures":[{"signer":13,"event":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[14],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[],"eventDigest":"sibling/13/1"},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":107}}]
  bookings: [{"identity":100,"assets":{"spent":[],"outputs":[],"mint":[[{"policy":51,"name":11929519872},1],[{"policy":51,"name":11929454336},1]],"invoked":[51]}}]
  convictionTransactions: [{"output":{"index":0,"tx":105},"observation":{"input":{"tx":103,"index":0},"transaction":{"spent":[{"tx":103,"index":0}],"outputs":[],"invoked":[52,53],"mint":[[{"policy":52,"name":54002556},1],[{"policy":53,"name":54002556},1]]}}},{"output":{"index":0,"tx":106},"observation":{"input":{"tx":104,"index":0},"transaction":{"spent":[{"tx":104,"index":0}],"outputs":[],"invoked":[52,53],"mint":[[{"policy":52,"name":54526844},1],[{"policy":53,"name":54526844},1]]}}},{"output":{"index":0,"tx":107},"observation":{"input":{"tx":105,"index":0},"transaction":{"spent":[{"tx":105,"index":0}],"outputs":[],"invoked":[52,53],"mint":[[{"policy":52,"name":55051132},1],[{"policy":53,"name":55051132},1]]}}}]
step:
  now: 0
  actor: "anyone presenting the required evidence"
  as: Alice
  action:
    bookRegistration:
      booking:
        applicationTagsMinted: [{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}]
        interval:
          lower: 0
          upper: 1
        request:
          carrierAda: 14
          contents:
            applicationTags: [{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}]
            lovelace: 17
            otherAssets: []
            trieReadyTags: [{"name":"14272158603032493918","policy":9}]
          datum: 711
          declaredTip: 1
          destination: 111
          key: 11
          reference:
            index: 0
            tx: 100
          refundAddress: 42
          registrationCost: 2
          registryId: 9
          submittedAt: 1
        trieReadyTagsMinted: [{"name":"14272158603032493918","policy":9}]
  expect:
    ok: true
    result:
      ok:
        flow:
          bondReturn: null
          bookingFee: 0
          deposited: 17
          intoRequest: 0
          locked: []
          premium: null
        observations: []
        state:
          bindings: []
          carriers: []
          config:
            activePolicy: 8
            applicationPolicy: 7
            bookingWidth: 1
            maxFee: 1
            processTime: 5
            registrationCost: 2
            registryId: 9
            retractTime: 0
            root: [203, 242, 156, 228, 132, 34, 35, 37]
          gen: 0
          nextToken: 0
          registrations: [{"applicationTagsMinted":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"interval":{"lower":0,"upper":1},"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":100},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1},"trieReadyTagsMinted":[{"name":"14272158603032493918","policy":9}]}]
          terminations: []
          treasury: 0
          trie: []
  note: "Book the registration request"
fork:
  id: wrong-carrier-value
  at: 0
  title: "Try a request with the wrong carrier allocation"
  expectFinal:
    bindings: []
    carriers: []
    config:
      activePolicy: 8
      applicationPolicy: 7
      bookingWidth: 1
      maxFee: 1
      processTime: 5
      registrationCost: 2
      registryId: 9
      retractTime: 0
      root: [203, 242, 156, 228, 132, 34, 35, 37]
    gen: 0
    nextToken: 0
    registrations: []
    terminations: []
    treasury: 0
    trie: []
  step:
    now: 0
    actor: "anyone presenting the required evidence"
    as: Alice
    action:
      bookRegistration:
        booking:
          applicationTagsMinted: [{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}]
          interval:
            lower: 0
            upper: 1
          request:
            carrierAda: 13
            contents:
              applicationTags: [{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}]
              lovelace: 17
              otherAssets: []
              trieReadyTags: [{"name":"14272158603032493918","policy":9}]
            datum: 711
            declaredTip: 1
            destination: 111
            key: 11
            reference:
              index: 0
              tx: 100
            refundAddress: 42
            registrationCost: 2
            registryId: 9
            submittedAt: 1
          trieReadyTagsMinted: [{"name":"14272158603032493918","policy":9}]
    expect:
      ok: false
      reason: keri-registration-value-mismatch
      result:
        error: keri-registration-value-mismatch
    note: "Try a request with the wrong carrier allocation"
fork:
  id: missing-inception
  at: 0
  title: "Try booking without inception evidence"
  env:
    convictions: []
    bookings: []
    convictionTransactions: []
  expectFinal:
    bindings: []
    carriers: []
    config:
      activePolicy: 8
      applicationPolicy: 7
      bookingWidth: 1
      maxFee: 1
      processTime: 5
      registrationCost: 2
      registryId: 9
      retractTime: 0
      root: [203, 242, 156, 228, 132, 34, 35, 37]
    gen: 0
    nextToken: 0
    registrations: []
    terminations: []
    treasury: 0
    trie: []
  step:
    now: 0
    actor: "anyone presenting the required evidence"
    as: Alice
    action:
      bookRegistration:
        booking:
          applicationTagsMinted: [{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}]
          interval:
            lower: 0
            upper: 1
          request:
            carrierAda: 14
            contents:
              applicationTags: [{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}]
              lovelace: 17
              otherAssets: []
              trieReadyTags: [{"name":"14272158603032493918","policy":9}]
            datum: 711
            declaredTip: 1
            destination: 111
            key: 11
            reference:
              index: 0
              tx: 100
            refundAddress: 42
            registrationCost: 2
            registryId: 9
            submittedAt: 1
          trieReadyTagsMinted: [{"name":"14272158603032493918","policy":9}]
    expect:
      ok: false
      reason: keri-inception-refused
      result:
        error: keri-inception-refused
    note: "Try booking without inception evidence"
expectFinal:
  bindings: []
  carriers: []
  config:
    activePolicy: 8
    applicationPolicy: 7
    bookingWidth: 1
    maxFee: 1
    processTime: 5
    registrationCost: 2
    registryId: 9
    retractTime: 0
    root: [203, 242, 156, 228, 132, 34, 35, 37]
  gen: 0
  nextToken: 0
  registrations: [{"applicationTagsMinted":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"interval":{"lower":0,"upper":1},"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":100},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1},"trieReadyTagsMinted":[{"name":"14272158603032493918","policy":9}]}]
  terminations: []
  treasury: 0
  trie: []
