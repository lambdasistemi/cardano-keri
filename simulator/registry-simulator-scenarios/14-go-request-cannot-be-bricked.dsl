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
id: 14
slug: go-request-cannot-be-bricked
story: "A pending termination has only the consuming fold exit"
narrative: "Generic retraction and expiry rejection refuse a termination. Its fold has no registration processing deadline; residual value enters the registry treasury."
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
  convictions: [{"comparison":{"tip":{"aid":11,"epoch":1,"sn":1,"keys":{"curKeys":[[11]],"curThreshold":{"count":{"required":1}},"nextKeys":[[11]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":11,"sn":0,"delegated":false,"nextKeys":[11],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[11],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]}},"rival":{"event":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"structureVerified":true,"signatures":[{"signer":11,"event":{"aid":11,"sn":1,"kind":"rotation","priorDigest":0,"keys":[11],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":105}},{"comparison":{"tip":{"aid":12,"epoch":1,"sn":1,"keys":{"curKeys":[[12]],"curThreshold":{"count":{"required":1}},"nextKeys":[[12]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":12,"sn":0,"delegated":false,"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[12],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]}},"rival":{"event":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"structureVerified":true,"signatures":[{"signer":12,"event":{"aid":12,"sn":1,"kind":"rotation","priorDigest":0,"keys":[12],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":106}},{"comparison":{"tip":{"aid":13,"epoch":1,"sn":1,"keys":{"curKeys":[[13]],"curThreshold":{"count":{"required":1}},"nextKeys":[[13]],"nextThreshold":{"count":{"required":1}},"witnesses":[],"toad":0},"previous":{"aid":13,"sn":0,"delegated":false,"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"witnesses":[]},"writer":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[13],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]}},"rival":{"event":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[14],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"structureVerified":true,"signatures":[{"signer":13,"event":{"aid":13,"sn":1,"kind":"rotation","priorDigest":0,"keys":[13],"threshold":{"count":{"required":1}},"nextKeys":[14],"nextThreshold":{"count":{"required":1}},"cuts":[],"adds":[],"witnessThreshold":0,"extension":[]},"verified":true}],"receipts":[]}},"output":{"index":0,"tx":107}}]
  bookings: [{"identity":100,"assets":{"spent":[],"outputs":[],"mint":[[{"policy":51,"name":11929519872},1]],"invoked":[51]}}]
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
step:
  now: 0
  actor: "anyone presenting the required evidence"
  as: Hal
  action:
    fold:
      expectedGen: 0
      expectedPlugin: 7
      transaction:
        applicationMint:
          - [{"name":"5369963716140239679","policy":7},-1]
        identity: 102
        outputs: [{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]},{"contents":{"applicationTags":[],"lovelace":14,"otherAssets":[],"trieReadyTags":[]},"output":{"address":111,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":711,"lovelace":14,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}]},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
        singularMint:
          - [{"registryId":9,"token":{"name":11,"policy":8}},1]
        stateMint: []
        transaction:
          donation: 2
          fee: 1
          inputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":100},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":101},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":1,"tx":101},"role":"request","stateToken":null,"stateTokens":0}]
          mint: []
          outputs: [{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},{"address":111,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":711,"lovelace":14,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0}]
          referenceInputs: []
          refunds: []
          signers: []
          validity:
            lower: 2
            upper: 3
        trieReadyMint:
          - [{"name":"14272158603032493918","policy":9},-1]
      unspent:
        - [{"index":0,"tx":100},{"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":null,"lovelace":17,"reference":null,"role":"request","stateToken":null,"stateTokens":0},"request":{"registration":{"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":100},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1}}},"singularTags":[]}]
        - [{"index":0,"tx":101},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[203,242,156,228,132,34,35,37]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]}]
        - [{"index":1,"tx":101},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
  expect:
    ok: true
    result:
      ok:
        flow:
          bondReturn: null
          bookingFee: 0
          deposited: 0
          intoRequest: 0
          locked:
            - [11, 10]
          premium: null
        observations: [{"aid":11,"binding":0,"leaf":{"known":{"s":"active"}},"minAda":4,"supply":1}]
        state:
          bindings:
            - [11, 0]
          carriers: [{"aid":11,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"pendingSpend":null,"token":0}]
          config:
            activePolicy: 8
            applicationPolicy: 7
            bookingWidth: 1
            maxFee: 1
            processTime: 5
            registrationCost: 2
            registryId: 9
            retractTime: 0
            root: [187, 43, 111, 81, 131, 142, 177, 246]
          gen: 1
          nextToken: 1
          registrations: []
          terminations: []
          treasury: 2
          trie:
            - [11,{"known":{"s":"active"}}]
  note: "Process the selected requests"
step:
  now: 0
  actor: "anyone presenting the required evidence"
  as: Cora
  action:
    convictCkpt:
      aid: 11
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
        observations: [{"aid":11,"binding":0,"leaf":{"known":{"s":"active"}},"minAda":4,"supply":1}]
        state:
          bindings:
            - [11, 0]
          carriers: [{"aid":11,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"pendingSpend":{"aid":11,"position":{"epoch":1,"sn":1},"reference":{"index":0,"tx":105}},"token":0}]
          config:
            activePolicy: 8
            applicationPolicy: 7
            bookingWidth: 1
            maxFee: 1
            processTime: 5
            registrationCost: 2
            registryId: 9
            retractTime: 0
            root: [187, 43, 111, 81, 131, 142, 177, 246]
          gen: 1
          nextToken: 1
          registrations: []
          terminations: []
          treasury: 2
          trie:
            - [11,{"known":{"s":"active"}}]
  note: "Present duplicity evidence against this key"
step:
  now: 0
  actor: "anyone presenting the required evidence"
  as: Sam
  action:
    bookTermination:
      aid: 11
      booker: 7
      booking:
        custodyInputs: [{"datum":711,"key":11,"kind":"active","output":111}]
        request:
          carrierAda: 2
          contents:
            applicationTags: []
            lovelace: 3
            otherAssets: []
            trieReadyTags: [{"name":"5600603241348410377","policy":9}]
          declaredTip: 1
          destination: 111
          key: 11
          reference:
            index: 0
            tx: 200
          refundAddress: null
          registryId: 9
          singularTags: [{"registryId":9,"token":{"name":11,"policy":8}}]
          submittedAt: null
        trieReadyTagsMinted: [{"name":"5600603241348410377","policy":9}]
        pendingReference:
          index: 0
          tx: 105
        position:
          epoch: 1
          sn: 1
      fee: 1
  expect:
    ok: true
    result:
      ok:
        flow:
          bondReturn: null
          bookingFee: 1
          deposited: 0
          intoRequest: 3
          locked: []
          premium: [7, 1]
        observations: [{"aid":11,"binding":0,"leaf":{"known":{"s":"active"}},"minAda":0,"supply":1}]
        state:
          bindings:
            - [11, 0]
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
            root: [187, 43, 111, 81, 131, 142, 177, 246]
          gen: 1
          nextToken: 1
          registrations: []
          terminations: [{"booking":{"custodyInputs":[{"datum":711,"key":11,"kind":"active","output":111}],"request":{"carrierAda":2,"contents":{"applicationTags":[],"lovelace":3,"otherAssets":[],"trieReadyTags":[{"name":"5600603241348410377","policy":9}]},"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":200},"refundAddress":null,"registryId":9,"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}],"submittedAt":null},"trieReadyTagsMinted":[{"name":"5600603241348410377","policy":9}]},"payload":{"aid":11,"booker":7,"bookingFee":1,"original":{"datum":711,"key":11,"kind":"active","output":111},"spend":{"aid":11,"position":{"epoch":1,"sn":1},"reference":{"index":0,"tx":105}},"token":0}}]
          treasury: 2
          trie:
            - [11,{"known":{"s":"active"}}]
  note: "Book the convicted carrier for termination"
step:
  now: 0
  actor: "anyone presenting the required evidence"
  as: Hal
  action:
    fold:
      expectedGen: 1
      expectedPlugin: 7
      transaction:
        applicationMint: []
        identity: 202
        outputs: [{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,130,142,176,99]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
        singularMint:
          - [{"registryId":9,"token":{"name":11,"policy":8}},-1]
        stateMint: []
        transaction:
          donation: 2
          fee: 1
          inputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":200},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":201},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":1,"tx":201},"role":"request","stateToken":null,"stateTokens":0}]
          mint: []
          outputs: [{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,130,142,176,99]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0}]
          referenceInputs: []
          refunds: []
          signers: []
          validity:
            lower: 20
            upper: 21
        trieReadyMint:
          - [{"name":"5600603241348410377","policy":9},-1]
      unspent:
        - [{"index":0,"tx":200},{"contents":{"applicationTags":[],"lovelace":3,"otherAssets":[],"trieReadyTags":[{"name":"5600603241348410377","policy":9}]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":null,"lovelace":3,"reference":null,"role":"request","stateToken":null,"stateTokens":0},"request":{"termination":{"request":{"carrierAda":2,"contents":{"applicationTags":[],"lovelace":3,"otherAssets":[],"trieReadyTags":[{"name":"5600603241348410377","policy":9}]},"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":200},"refundAddress":null,"registryId":9,"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}],"submittedAt":null}}},"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}]}]
        - [{"index":0,"tx":201},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]}]
        - [{"index":1,"tx":201},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
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
        observations: [{"aid":11,"binding":0,"leaf":{"known":{"s":"terminal"}},"minAda":0,"supply":0}]
        state:
          bindings:
            - [11, 0]
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
            root: [187, 43, 111, 81, 130, 142, 176, 99]
          gen: 2
          nextToken: 1
          registrations: []
          terminations: []
          treasury: 4
          trie:
            - [11,{"known":{"s":"terminal"}}]
  note: "Process the selected requests"
fork:
  id: control-5-return-termination-refused
  at: 4
  title: "Try returning the pending termination"
  expectFinal:
    bindings:
      - [11, 0]
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
      root: [187, 43, 111, 81, 131, 142, 177, 246]
    gen: 1
    nextToken: 1
    registrations: []
    terminations: [{"booking":{"custodyInputs":[{"datum":711,"key":11,"kind":"active","output":111}],"request":{"carrierAda":2,"contents":{"applicationTags":[],"lovelace":3,"otherAssets":[],"trieReadyTags":[{"name":"5600603241348410377","policy":9}]},"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":200},"refundAddress":null,"registryId":9,"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}],"submittedAt":null},"trieReadyTagsMinted":[{"name":"5600603241348410377","policy":9}]},"payload":{"aid":11,"booker":7,"bookingFee":1,"original":{"datum":711,"key":11,"kind":"active","output":111},"spend":{"aid":11,"position":{"epoch":1,"sn":1},"reference":{"index":0,"tx":105}},"token":0}}]
    treasury: 2
    trie:
      - [11,{"known":{"s":"active"}}]
  step:
    now: 0
    actor: "anyone presenting the required evidence"
    as: Sam
    action:
      returnRequests:
        unspent:
          - [{"index":0,"tx":200},{"contents":{"applicationTags":[],"lovelace":3,"otherAssets":[],"trieReadyTags":[{"name":"5600603241348410377","policy":9}]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":null,"lovelace":3,"reference":null,"role":"request","stateToken":null,"stateTokens":0},"request":{"termination":{"request":{"carrierAda":2,"contents":{"applicationTags":[],"lovelace":3,"otherAssets":[],"trieReadyTags":[{"name":"5600603241348410377","policy":9}]},"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":200},"refundAddress":null,"registryId":9,"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}],"submittedAt":null}}},"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}]}]
          - [{"index":0,"tx":201},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]}]
          - [{"index":1,"tx":201},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
        transaction:
          transaction:
            applicationMint: []
            identity: 202
            outputs: [{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,130,142,176,99]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
            singularMint:
              - [{"registryId":9,"token":{"name":11,"policy":8}},-1]
            stateMint: []
            transaction:
              donation: 2
              fee: 1
              inputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":200},"role":"request","stateToken":null,"stateTokens":0}]
              mint: []
              outputs: [{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":0,"root":[187,43,111,81,130,142,176,99]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0}]
              referenceInputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":201},"role":"request","stateToken":null,"stateTokens":0}]
              refunds: []
              signers: []
              validity:
                lower: 20
                upper: 21
            trieReadyMint:
              - [{"name":"5600603241348410377","policy":9},-1]
          stateReference:
            index: 0
            tx: 201
          members:
            - [{"index":0,"tx":200},"expired"]
    expect:
      ok: false
      reason: keri-return-registration-only
      result:
        error: keri-return-registration-only
    note: "Return the pending termination as if it were a registration"
expectFinal:
  bindings:
    - [11, 0]
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
    root: [187, 43, 111, 81, 130, 142, 176, 99]
  gen: 2
  nextToken: 1
  registrations: []
  terminations: []
  treasury: 4
  trie:
    - [11,{"known":{"s":"terminal"}}]
