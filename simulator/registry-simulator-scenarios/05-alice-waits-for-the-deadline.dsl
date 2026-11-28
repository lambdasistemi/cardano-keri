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
id: 5
slug: alice-waits-for-the-deadline
story: "Alice cannot cancel her request before its deadline"
narrative: "Until the deadline only a fold may spend the request, Alice included. From the deadline anyone may return it without a signature; the refund address receives the contents less the tip."
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
  inception: [11, 12, 13, 14, 15]
  convictions: [{"comparison":{"tip":{"aid":11,"epoch":1,"sn":1,"keys":{"curKeys":[[11]],"curThreshold":{"count":{"required":1}},"nextKeys":[[11]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":11,"sn":0,"delegated":false,"nextKeys":[11],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[11],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]}},"rival":{"event":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"structureVerified":true,"signatures":[{"signer":11,"event":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":105}},{"comparison":{"tip":{"aid":12,"epoch":1,"sn":1,"keys":{"curKeys":[[12]],"curThreshold":{"count":{"required":1}},"nextKeys":[[12]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":12,"sn":0,"delegated":false,"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]}},"rival":{"event":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"structureVerified":true,"signatures":[{"signer":12,"event":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":106}},{"comparison":{"tip":{"aid":13,"epoch":1,"sn":1,"keys":{"curKeys":[[13]],"curThreshold":{"count":{"required":1}},"nextKeys":[[13]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":13,"sn":0,"delegated":false,"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]}},"rival":{"event":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[14],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"structureVerified":true,"signatures":[{"signer":13,"event":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[14],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":107}}]
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
step:
  now: 6
  actor: "anyone presenting the required evidence"
  as: Alice
  action:
    returnRequests:
      unspent:
        - [{"tx":100,"index":0},{"output":{"role":"request","datum":"inline","address":0,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":17,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":17,"applicationTags":[{"signatures":[],"policy":7,"key":11,"owner":42,"destination":111,"assetName":"5369963716140239679","edge":"insertActive"}],"trieReadyTags":[{"policy":9,"name":"14272158603032493918"}],"otherAssets":[]},"singularTags":[],"request":{"registration":{"request":{"registryId":9,"key":11,"refundAddress":42,"destination":111,"submittedAt":1,"registrationCost":2,"declaredTip":1,"carrierAda":14,"reference":{"tx":100,"index":0},"contents":{"lovelace":17,"applicationTags":[{"signatures":[],"policy":7,"key":11,"owner":42,"destination":111,"assetName":"5369963716140239679","edge":"insertActive"}],"trieReadyTags":[{"policy":9,"name":"14272158603032493918"}],"otherAssets":[]},"datum":711}}}}]
        - [{"tx":101,"index":0},{"output":{"role":"state","datum":"inline","address":null,"stateTokens":1,"config":{"registryId":9,"maxFee":1,"processTime":5,"retractTime":0,"applicationPolicy":7,"activePolicy":8,"root":[203,242,156,228,132,34,35,37],"registrationCost":2,"bookingWidth":1},"commitment":null,"assets":[],"lovelace":0,"reference":null,"datumValue":null,"stateToken":{"policy":9,"name":0}},"contents":{"lovelace":0,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
        - [{"tx":101,"index":1},{"output":{"role":"owner","datum":"none","address":0,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":0,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":0,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
      transaction:
        transaction:
          identity: 102
          outputs: [{"output":{"role":"owner","datum":"none","address":42,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":16,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":16,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
          transaction:
            inputs: [{"role":"request","datum":"inline","stateTokens":0,"approvals":0,"lovelace":0,"assets":[],"datumValue":null,"ref":{"tx":100,"index":0},"stateToken":null}]
            outputs: [{"role":"owner","datum":"none","address":42,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":16,"reference":null,"datumValue":null,"stateToken":null}]
            mint: []
            signers: []
            refunds: []
            referenceInputs: [{"role":"request","datum":"inline","stateTokens":0,"approvals":0,"lovelace":0,"assets":[],"datumValue":null,"ref":{"tx":101,"index":0},"stateToken":null}]
            validity:
              lower: 6
              upper: 7
            fee: 1
            donation: 0
          trieReadyMint:
            - [{"policy":9,"name":"14272158603032493918"},-1]
          applicationMint:
            - [{"policy":7,"name":"5369963716140239679"},-1]
          stateMint: []
          singularMint: []
        stateReference:
          tx: 101
          index: 0
        members:
          - [{"tx":100,"index":0},"expired"]
  expect:
    ok: true
    result:
      ok:
        flow:
          bondReturn: null
          bookingFee: 0
          deposited: 0
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
          registrations: []
          terminations: []
          treasury: 0
          trie: []
  note: "Return the request at its deadline, without a signature"
fork:
  id: cancel-in-window
  at: 1
  title: "Try cancelling inside the processing window"
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
  step:
    now: 3
    actor: "anyone presenting the required evidence"
    as: Alice
    action:
      returnRequests:
        unspent:
          - [{"tx":100,"index":0},{"output":{"role":"request","datum":"inline","address":0,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":17,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":17,"applicationTags":[{"signatures":[],"policy":7,"key":11,"owner":42,"destination":111,"assetName":"5369963716140239679","edge":"insertActive"}],"trieReadyTags":[{"policy":9,"name":"14272158603032493918"}],"otherAssets":[]},"singularTags":[],"request":{"registration":{"request":{"registryId":9,"key":11,"refundAddress":42,"destination":111,"submittedAt":1,"registrationCost":2,"declaredTip":1,"carrierAda":14,"reference":{"tx":100,"index":0},"contents":{"lovelace":17,"applicationTags":[{"signatures":[],"policy":7,"key":11,"owner":42,"destination":111,"assetName":"5369963716140239679","edge":"insertActive"}],"trieReadyTags":[{"policy":9,"name":"14272158603032493918"}],"otherAssets":[]},"datum":711}}}}]
          - [{"tx":101,"index":0},{"output":{"role":"state","datum":"inline","address":null,"stateTokens":1,"config":{"registryId":9,"maxFee":1,"processTime":5,"retractTime":0,"applicationPolicy":7,"activePolicy":8,"root":[203,242,156,228,132,34,35,37],"registrationCost":2,"bookingWidth":1},"commitment":null,"assets":[],"lovelace":0,"reference":null,"datumValue":null,"stateToken":{"policy":9,"name":0}},"contents":{"lovelace":0,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
          - [{"tx":101,"index":1},{"output":{"role":"owner","datum":"none","address":0,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":0,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":0,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
        transaction:
          transaction:
            identity: 102
            outputs: [{"output":{"role":"owner","datum":"none","address":42,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":16,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":16,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
            transaction:
              inputs: [{"role":"request","datum":"inline","stateTokens":0,"approvals":0,"lovelace":0,"assets":[],"datumValue":null,"ref":{"tx":100,"index":0},"stateToken":null}]
              outputs: [{"role":"owner","datum":"none","address":42,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":16,"reference":null,"datumValue":null,"stateToken":null}]
              mint: []
              signers: []
              refunds: []
              referenceInputs: [{"role":"request","datum":"inline","stateTokens":0,"approvals":0,"lovelace":0,"assets":[],"datumValue":null,"ref":{"tx":101,"index":0},"stateToken":null}]
              validity:
                lower: 3
                upper: 4
              fee: 1
              donation: 0
            trieReadyMint:
              - [{"policy":9,"name":"14272158603032493918"},-1]
            applicationMint:
              - [{"policy":7,"name":"5369963716140239679"},-1]
            stateMint: []
            singularMint: []
          stateReference:
            tx: 101
            index: 0
          members:
            - [{"tx":100,"index":0},"expired"]
    expect:
      ok: false
      reason: keri-return-before-deadline
      result:
        error: keri-return-before-deadline
    note: "Return inside the processing window"
fork:
  id: cancel-across-deadline
  at: 1
  title: "Try a return whose interval starts before the deadline"
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
  step:
    now: 5
    actor: "anyone presenting the required evidence"
    as: Alice
    action:
      returnRequests:
        unspent:
          - [{"tx":100,"index":0},{"output":{"role":"request","datum":"inline","address":0,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":17,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":17,"applicationTags":[{"signatures":[],"policy":7,"key":11,"owner":42,"destination":111,"assetName":"5369963716140239679","edge":"insertActive"}],"trieReadyTags":[{"policy":9,"name":"14272158603032493918"}],"otherAssets":[]},"singularTags":[],"request":{"registration":{"request":{"registryId":9,"key":11,"refundAddress":42,"destination":111,"submittedAt":1,"registrationCost":2,"declaredTip":1,"carrierAda":14,"reference":{"tx":100,"index":0},"contents":{"lovelace":17,"applicationTags":[{"signatures":[],"policy":7,"key":11,"owner":42,"destination":111,"assetName":"5369963716140239679","edge":"insertActive"}],"trieReadyTags":[{"policy":9,"name":"14272158603032493918"}],"otherAssets":[]},"datum":711}}}}]
          - [{"tx":101,"index":0},{"output":{"role":"state","datum":"inline","address":null,"stateTokens":1,"config":{"registryId":9,"maxFee":1,"processTime":5,"retractTime":0,"applicationPolicy":7,"activePolicy":8,"root":[203,242,156,228,132,34,35,37],"registrationCost":2,"bookingWidth":1},"commitment":null,"assets":[],"lovelace":0,"reference":null,"datumValue":null,"stateToken":{"policy":9,"name":0}},"contents":{"lovelace":0,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
          - [{"tx":101,"index":1},{"output":{"role":"owner","datum":"none","address":0,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":0,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":0,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
        transaction:
          transaction:
            identity: 102
            outputs: [{"output":{"role":"owner","datum":"none","address":42,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":16,"reference":null,"datumValue":null,"stateToken":null},"contents":{"lovelace":16,"applicationTags":[],"trieReadyTags":[],"otherAssets":[]},"singularTags":[],"request":null}]
            transaction:
              inputs: [{"role":"request","datum":"inline","stateTokens":0,"approvals":0,"lovelace":0,"assets":[],"datumValue":null,"ref":{"tx":100,"index":0},"stateToken":null}]
              outputs: [{"role":"owner","datum":"none","address":42,"stateTokens":0,"config":null,"commitment":null,"assets":[],"lovelace":16,"reference":null,"datumValue":null,"stateToken":null}]
              mint: []
              signers: []
              refunds: []
              referenceInputs: [{"role":"request","datum":"inline","stateTokens":0,"approvals":0,"lovelace":0,"assets":[],"datumValue":null,"ref":{"tx":101,"index":0},"stateToken":null}]
              validity:
                lower: 5
                upper: 7
              fee: 1
              donation: 0
            trieReadyMint:
              - [{"policy":9,"name":"14272158603032493918"},-1]
            applicationMint:
              - [{"policy":7,"name":"5369963716140239679"},-1]
            stateMint: []
            singularMint: []
          stateReference:
            tx: 101
            index: 0
          members:
            - [{"tx":100,"index":0},"expired"]
    expect:
      ok: false
      reason: keri-return-before-deadline
      result:
        error: keri-return-before-deadline
    note: "Return with an interval straddling the deadline"
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
