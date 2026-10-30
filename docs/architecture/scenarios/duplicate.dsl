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
  retractTime: 5
  root: [203, 242, 156, 228, 132, 34, 35, 37]
id: 3884
slug: architecture-duplicate
story: "A duplicate registration is refused and refunded"
narrative: "The first checkpoint and token remain intact. A second booking cannot replace the active key; an authenticated mismatch rejection returns the duplicate request value less its declared tip. Expiry is a different ground and is refused before both windows end."
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
  duplicity:
    - [11, 0]
    - [11, 1]
    - [11, 2]
  inception: [11]
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
            retractTime: 5
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
        outputs: [{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]},{"contents":{"applicationTags":[],"lovelace":14,"otherAssets":[],"trieReadyTags":[]},"output":{"address":111,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":711,"lovelace":14,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}]},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
        singularMint:
          - [{"registryId":9,"token":{"name":11,"policy":8}},1]
        stateMint: []
        transaction:
          donation: 2
          fee: 1
          inputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":100},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":101},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":1,"tx":101},"role":"request","stateToken":null,"stateTokens":0}]
          mint: []
          outputs: [{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},{"address":111,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":711,"lovelace":14,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0}]
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
        - [{"index":0,"tx":101},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[203,242,156,228,132,34,35,37]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]}]
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
          carriers: [{"aid":11,"k":0,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"st":"live","token":0}]
          config:
            activePolicy: 8
            applicationPolicy: 7
            bookingWidth: 1
            maxFee: 1
            processTime: 5
            registrationCost: 2
            registryId: 9
            retractTime: 5
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
            tx: 300
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
        observations: [{"aid":11,"binding":0,"leaf":{"known":{"s":"active"}},"minAda":4,"supply":1}]
        state:
          bindings:
            - [11, 0]
          carriers: [{"aid":11,"k":0,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"st":"live","token":0}]
          config:
            activePolicy: 8
            applicationPolicy: 7
            bookingWidth: 1
            maxFee: 1
            processTime: 5
            registrationCost: 2
            registryId: 9
            retractTime: 5
            root: [187, 43, 111, 81, 131, 142, 177, 246]
          gen: 1
          nextToken: 1
          registrations: [{"applicationTagsMinted":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"interval":{"lower":0,"upper":1},"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":300},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1},"trieReadyTagsMinted":[{"name":"14272158603032493918","policy":9}]}]
          terminations: []
          treasury: 2
          trie:
            - [11,{"known":{"s":"active"}}]
  note: "Book the registration request"
step:
  now: 0
  actor: "anyone presenting the required evidence"
  as: Sam
  action:
    genericRejection:
      transaction:
        members:
          - [{"index":0,"tx":300},{"mismatch":{"leaf":{"known":{"s":"active"}}}}]
        stateReference:
          index: 0
          tx: 301
        transaction:
          applicationMint:
            - [{"name":"5369963716140239679","policy":7},-1]
          identity: 302
          outputs: [{"contents":{"applicationTags":[],"lovelace":16,"otherAssets":[],"trieReadyTags":[]},"output":{"address":42,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":16,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
          singularMint: []
          stateMint: []
          transaction:
            donation: 0
            fee: 0
            inputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":300},"role":"request","stateToken":null,"stateTokens":0}]
            mint: []
            outputs: [{"address":42,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":16,"reference":null,"role":"owner","stateToken":null,"stateTokens":0}]
            referenceInputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":301},"role":"request","stateToken":null,"stateTokens":0}]
            refunds: []
            signers: []
            validity:
              lower: 2
              upper: 3
          trieReadyMint:
            - [{"name":"14272158603032493918","policy":9},-1]
      unspent:
        - [{"index":0,"tx":300},{"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":null,"lovelace":17,"reference":null,"role":"request","stateToken":null,"stateTokens":0},"request":{"registration":{"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":300},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1}}},"singularTags":[]}]
        - [{"index":0,"tx":301},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]}]
        - [{"index":1,"tx":301},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":0,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
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
          carriers: [{"aid":11,"k":0,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"st":"live","token":0}]
          config:
            activePolicy: 8
            applicationPolicy: 7
            bookingWidth: 1
            maxFee: 1
            processTime: 5
            registrationCost: 2
            registryId: 9
            retractTime: 5
            root: [187, 43, 111, 81, 131, 142, 177, 246]
          gen: 1
          nextToken: 1
          registrations: []
          terminations: []
          treasury: 2
          trie:
            - [11,{"known":{"s":"active"}}]
  note: "Authenticate the current state and return the registration refund"
fork:
  id: control-3-key-exists
  at: 3
  title: "Try processing another registration of this AID"
  expectFinal:
    bindings:
      - [11, 0]
    carriers: [{"aid":11,"k":0,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"st":"live","token":0}]
    config:
      activePolicy: 8
      applicationPolicy: 7
      bookingWidth: 1
      maxFee: 1
      processTime: 5
      registrationCost: 2
      registryId: 9
      retractTime: 5
      root: [187, 43, 111, 81, 131, 142, 177, 246]
    gen: 1
    nextToken: 1
    registrations: [{"applicationTagsMinted":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"interval":{"lower":0,"upper":1},"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":300},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1},"trieReadyTagsMinted":[{"name":"14272158603032493918","policy":9}]}]
    terminations: []
    treasury: 2
    trie:
      - [11,{"known":{"s":"active"}}]
  step:
    now: 0
    actor: "anyone presenting the required evidence"
    as: Hal
    action:
      fold:
        expectedGen: 1
        expectedPlugin: 7
        transaction:
          applicationMint:
            - [{"name":"5369963716140239679","policy":7},-1]
          identity: 302
          outputs: [{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]},{"contents":{"applicationTags":[],"lovelace":14,"otherAssets":[],"trieReadyTags":[]},"output":{"address":111,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":711,"lovelace":14,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[{"registryId":9,"token":{"name":11,"policy":8}}]},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
          singularMint:
            - [{"registryId":9,"token":{"name":11,"policy":8}},1]
          stateMint: []
          transaction:
            donation: 2
            fee: 1
            inputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":300},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":301},"role":"request","stateToken":null,"stateTokens":0},{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":1,"tx":301},"role":"request","stateToken":null,"stateTokens":0}]
            mint: []
            outputs: [{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},{"address":111,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":711,"lovelace":14,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0}]
            referenceInputs: []
            refunds: []
            signers: []
            validity:
              lower: 2
              upper: 3
          trieReadyMint:
            - [{"name":"14272158603032493918","policy":9},-1]
        unspent:
          - [{"index":0,"tx":300},{"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":null,"lovelace":17,"reference":null,"role":"request","stateToken":null,"stateTokens":0},"request":{"registration":{"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":300},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1}}},"singularTags":[]}]
          - [{"index":0,"tx":301},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]}]
          - [{"index":1,"tx":301},{"contents":{"applicationTags":[],"lovelace":1,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":1,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
    expect:
      ok: false
      reason: key-exists
      result:
        error: key-exists
    note: "Try processing another registration of this AID"
fork:
  id: control-4-reject-not-expired
  at: 3
  title: "Try expiry rejection before both windows end"
  expectFinal:
    bindings:
      - [11, 0]
    carriers: [{"aid":11,"k":0,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"st":"live","token":0}]
    config:
      activePolicy: 8
      applicationPolicy: 7
      bookingWidth: 1
      maxFee: 1
      processTime: 5
      registrationCost: 2
      registryId: 9
      retractTime: 5
      root: [187, 43, 111, 81, 131, 142, 177, 246]
    gen: 1
    nextToken: 1
    registrations: [{"applicationTagsMinted":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"interval":{"lower":0,"upper":1},"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":300},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1},"trieReadyTagsMinted":[{"name":"14272158603032493918","policy":9}]}]
    terminations: []
    treasury: 2
    trie:
      - [11,{"known":{"s":"active"}}]
  step:
    now: 0
    actor: "anyone presenting the required evidence"
    as: Sam
    action:
      genericRejection:
        transaction:
          members:
            - [{"index":0,"tx":300},"expired"]
          stateReference:
            index: 0
            tx: 301
          transaction:
            applicationMint:
              - [{"name":"5369963716140239679","policy":7},-1]
            identity: 302
            outputs: [{"contents":{"applicationTags":[],"lovelace":16,"otherAssets":[],"trieReadyTags":[]},"output":{"address":42,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":16,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
            singularMint: []
            stateMint: []
            transaction:
              donation: 0
              fee: 0
              inputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":300},"role":"request","stateToken":null,"stateTokens":0}]
              mint: []
              outputs: [{"address":42,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":16,"reference":null,"role":"owner","stateToken":null,"stateTokens":0}]
              referenceInputs: [{"approvals":0,"assets":[],"datum":"inline","datumValue":null,"lovelace":0,"ref":{"index":0,"tx":301},"role":"request","stateToken":null,"stateTokens":0}]
              refunds: []
              signers: []
              validity:
                lower: 2
                upper: 3
            trieReadyMint:
              - [{"name":"14272158603032493918","policy":9},-1]
        unspent:
          - [{"index":0,"tx":300},{"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"inline","datumValue":null,"lovelace":17,"reference":null,"role":"request","stateToken":null,"stateTokens":0},"request":{"registration":{"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":300},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1}}},"singularTags":[]}]
          - [{"index":0,"tx":301},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":null,"assets":[],"commitment":null,"config":{"activePolicy":8,"applicationPolicy":7,"bookingWidth":1,"maxFee":1,"processTime":5,"registrationCost":2,"registryId":9,"retractTime":5,"root":[187,43,111,81,131,142,177,246]},"datum":"inline","datumValue":null,"lovelace":0,"reference":null,"role":"state","stateToken":{"name":0,"policy":9},"stateTokens":1},"request":null,"singularTags":[]}]
          - [{"index":1,"tx":301},{"contents":{"applicationTags":[],"lovelace":0,"otherAssets":[],"trieReadyTags":[]},"output":{"address":0,"assets":[],"commitment":null,"config":null,"datum":"none","datumValue":null,"lovelace":0,"reference":null,"role":"owner","stateToken":null,"stateTokens":0},"request":null,"singularTags":[]}]
    expect:
      ok: false
      reason: reject-not-expired
      result:
        error: reject-not-expired
    note: "Try expiry rejection before both windows end"
expectFinal:
  bindings:
    - [11, 0]
  carriers: [{"aid":11,"k":0,"minAda":4,"original":{"datum":711,"key":11,"kind":"active","output":111},"st":"live","token":0}]
  config:
    activePolicy: 8
    applicationPolicy: 7
    bookingWidth: 1
    maxFee: 1
    processTime: 5
    registrationCost: 2
    registryId: 9
    retractTime: 5
    root: [187, 43, 111, 81, 131, 142, 177, 246]
  gen: 1
  nextToken: 1
  registrations: []
  terminations: []
  treasury: 2
  trie:
    - [11,{"known":{"s":"active"}}]
