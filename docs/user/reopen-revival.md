# No owner exit

!!! note "What ships, and the accepted design"
    `ckeri` no longer offers `close`; the close the M1 V1 release made by
    the **current** keys is recorded on
    [Close your identity checkpoint](close.md). The accepted design has
    no owner exit: no close, no parking and no revival. There is no
    withdraw. Conviction is the only way a checkpoint ends. Play
    [the checkpoint simulator](../simulator/index.html) and
    [the registry simulation](../simulator/registry/index.html).

As an identity owner, Alice keeps her checkpoint alive — bonds, rotations,
unfreezing, top-ups — until it is convicted. There is no step that takes her
checkpoint off chain, parks it or brings it back.

As a relying party, the treasury sees a checkpoint that is either alive
(consumable only when bonded, not poisoned and past the juvenility window `W`)
or convicted. A conviction needs a
[duplicity](https://trustoverip.github.io/kswg-keri-specification/#duplicity)
proof against the checkpoint's key state. It moves the conviction bond to the
convictor and the freeze bond and pool to the refund address, and places the
retained output in pending custody. Only the associated Registry fold consumes
that request, burns the token and permanently retires the registry key.
Registering the same AID again is refused forever: the token is minted once.

What happens to the bonds and pool of an owner who simply stops maintaining a
checkpoint is an open economic question. Today they leave a live checkpoint
only through rotation premiums, a freeze (the freeze bond, to a hunter) and
conviction. Parking was removed because it left unsettled who holds the
deposit while parked and how a sponsor is tracked; it may return only with an
economic model that settles both.

The [close page](close.md) is the V1 command that ships on preprod. Do
not read it as the accepted design.
