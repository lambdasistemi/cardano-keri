# Consumer checklist

!!! note "What ships, and the accepted design"
    No production consumer ships. The checklist below is the accepted
    design's fail-closed rule, playable as
    [The treasury reads Alice's checkpoint](../simulator/index.html).
    What a preprod reader can do today is resolve one ACTIVE V1
    checkpoint by role address and revalidate the token; ARMED and
    FROZEN reject by role.

The treasury is a Cardano validator that authorizes a payment against
Alice's current keys by reading her checkpoint as a CIP-31 reference
input. It never writes the checkpoint. It never reads the registry. What
it reads is Alice's current key state as a KERI
[validator](https://trustoverip.github.io/kswg-keri-specification/#validator) would establish it; the conditions below add
Cardano-side rules on top and take none of KERI's away.

Authorize **iff** all of these hold. Anything else fails closed.

1. **Present.** There is a checkpoint UTxO. Parked and convicted have
   none — no candidate.
2. **The token.** Exact policy, quantity one, the AID-derived asset.
3. **Both bonds full.** `D_reg` is there; `B` is there. Frozen is `B`
   absent.
4. **Not poisoned.** The current quorum's declaration makes the
   checkpoint unconsumable until a rotation clears it.
5. **Older than `W`.** Juvenility is consumer policy. The machine does
   not wait; the treasury does.
6. **The payment's own signature** satisfies the current threshold.
   That check is the consumer's, outside the checkpoint machine.

Zero candidates: reject. Several candidates: reject. The registry is
what makes "several" impossible in the accepted design; until it
ships, a V1 reader cannot prove uniqueness.

Play the story: nothing on chain, the treasury fails closed; nine
slots after registration it is still juvenile; at slot `W` it accepts;
poison, freeze, and park each change the verdict for a reason the
simulation names.

See [Identity operations](../architecture/identity-ops.md) and
[Trust model](../design/trust-model.md).
