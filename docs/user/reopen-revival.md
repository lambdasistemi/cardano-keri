# Close, reopen, revival

!!! note "What ships, and the accepted design"
    What ships today is `ckeri close` by the **current** keys, documented
    on [Close your identity checkpoint](close.md). The accepted design
    (D-036 to D-040) is the reap by the **next** keys and the revival
    through the registry. Play
    [Alice leaves](../simulator/index.html) and
    [Alice comes back through the registry](../simulator/index.html)
    and [the registry simulation](../simulator/registry/index.html).
    There is no withdraw. Conviction is the only terminal state.

Alice leaves. That is not a current-key close. It is a witnessed
rotation by the *next* keys whose signed message names the payee of the
premium and the refund address. The premium goes to that payee when the
pool covers it; otherwise the payee is paid nothing — an unpaid close
is still a close. Everything else goes to the refund address; the
token burns; the registry leaf is parked holding the hash of that key
state.

A relayer with the public rotation cannot reap: the payee and the
address are one message the new keys sign. Mallory holding only the
stolen current keys cannot reap. Mallory holding the next keys *can*:
that is control.

Parked is not gone. Nothing on chain but the leaf. Top-up, poison,
freeze, rotate, register-again are all refused. Two ways out:

- **Revival.** A witnessed rotation later than the parked key state,
  with fresh bonds, a first pool, a refund address chosen by whoever
  pays, born juvenile. Replaying the close's own rotation is refused.
- **Conviction.** A duplicity proof against the parked key state.
  Terminal. No value flows: there is no UTxO to seize.

Coming back, the checkpoint is consumable only after the juvenility
window `W`. Registering the same AID again is refused forever: the
token is minted once.

The [close page](close.md) is the V1 command that ships on preprod. Do
not read it as the accepted design.
