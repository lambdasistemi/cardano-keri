grammar: 1
family: checkpoint

story: 3881
title: "Alice registers and waits"
goal: "Make one identity readable after the registration window."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: []
step:
  slot: 0
  who: treasury
  say: "Nothing on chain for this AID: the treasury fails closed, and only a registration can happen first."
  expect:
    verdict: not-present
step:
  slot: 0
  who: alice
  say: "Alice registers her public inception with refund address 1 and pool 10."
  action:
    register:
      refund: 1
      pool0: 10
  expect:
    ok: true
    live:
      sn: 0
      epoch: 0
      poisoned: false
      bornAt: 0
      refundTo: 1
      pool: 10
      frozen: false
    flow:
      dregIn: 1000
      bIn: 5
      poolIn: 10
    verdict: juvenile
step:
  slot: 9
  who: treasury
  say: "Nine slots later the checkpoint is still juvenile: born at slot 0, the window W is 10."
  expect:
    verdict: juvenile
step:
  slot: 10
  who: treasury
  say: "At slot 10 the treasury accepts it: both bonds full, not poisoned, past juvenility."
  expect:
    verdict: consumable
fork:
  id: twice
  at: 3
  title: "Registering the same AID again"
  step:
    slot: 10
    who: alice
    say: "Registering the same AID again is refused: the token is minted once, ever."
    action:
      register:
        refund: 1
        pool0: 10
    expect:
      ok: false
      reason: already-present
      verdict: consumable
