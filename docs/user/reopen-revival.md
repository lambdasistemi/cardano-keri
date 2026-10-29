# Close, reopen, revival

!!! note "What ships, and the accepted design"
    What ships today is `ckeri close` by the **current** keys, documented
    on [Close your identity checkpoint](close.md). The accepted design
    (D-036 to D-040) is the reap by the **next** keys and the revival
    from the retained output. Play
    [Alice leaves](../simulator/index.html) and
    [Alice revives her parked identity](../simulator/index.html)
    and [the registry simulation](../simulator/registry/index.html).
    There is no withdraw. Conviction is the only terminal state.

Alice leaves. That is the reap, the only close there is, and not a
current-key close: a witnessed rotation by the *next* keys whose signed
message names the payee of the premium (the fee for landing a rotation) and
the refund address. The premium goes to that payee when the
pool of advance funds covers it; otherwise the payee is paid nothing — an unpaid close
is still a close. The remaining bonds and pool go to the refund address. The parked output
retains its token, minimum ADA and that key state. The registry key stays active.

A relayer with the public rotation cannot reap: the payee and the
address are one message the new keys sign. Mallory holding only the
stolen current keys cannot reap. Mallory holding the next keys *can*:
that is control ([pre-rotation](https://trustoverip.github.io/kswg-keri-specification/#pre-rotation)).

Parked is not gone. Its retained output remains on chain, but consumers refuse it. Top-up, poison (the
owner's own lock),
freeze, rotate, register-again are all refused. Two ways out:

- **Revival.** A witnessed rotation later than the parked key state,
  consuming that retained output with fresh bonds, a first pool, a refund address chosen by whoever
  pays, born juvenile (younger than the window `W` a consumer waits out).
  Replaying the close's own rotation is refused.
- **Conviction.** A [duplicity](https://trustoverip.github.io/kswg-keri-specification/#duplicity) proof against the parked key state.
  The proof consumes the retained output into pending custody. No bonds or
  pool remain to pay. Only the associated Registry fold consumes that request,
  burns the token and permanently retires the registry key.

Coming back, the checkpoint is consumable only after the juvenility
window `W`. Registering the same AID again is refused forever: the
token is minted once.

The [close page](close.md) is the V1 command that ships on preprod. Do
not read it as the accepted design.
