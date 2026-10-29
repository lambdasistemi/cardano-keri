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
id: 1
slug: alice-requests
story: "Alice books a registration"
narrative: "The request holds registration cost, tip, retained output value and bond. Booking leaves the registry unchanged."
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
  closeAuth:
    - [11, 6]
    - [12, 6]
    - [13, 6]
  duplicity:
    - [11, 0]
    - [11, 1]
    - [11, 2]
    - [12, 0]
    - [12, 1]
    - [12, 2]
    - [13, 0]
    - [13, 1]
    - [13, 2]
  inception: [11, 12, 13, 14, 15]
  rotationFrom:
    - [11, 1]
    - [12, 1]
    - [13, 1]
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
      retractTime: 5
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
    retractTime: 5
    root: [203, 242, 156, 228, 132, 34, 35, 37]
  gen: 0
  nextToken: 0
  registrations: [{"applicationTagsMinted":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"interval":{"lower":0,"upper":1},"request":{"carrierAda":14,"contents":{"applicationTags":[{"assetName":"5369963716140239679","destination":111,"edge":"insertActive","key":11,"owner":42,"policy":7,"signatures":[]}],"lovelace":17,"otherAssets":[],"trieReadyTags":[{"name":"14272158603032493918","policy":9}]},"datum":711,"declaredTip":1,"destination":111,"key":11,"reference":{"index":0,"tx":100},"refundAddress":42,"registrationCost":2,"registryId":9,"submittedAt":1},"trieReadyTagsMinted":[{"name":"14272158603032493918","policy":9}]}]
  terminations: []
  treasury: 0
  trie: []
