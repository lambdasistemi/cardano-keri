# Hunters

!!! note "What ships, and the accepted design"
    The hunter's freeze is one transaction in this generation of the
    checkpoint program, and `ckeri freeze` submits it. It runs on a local test
    chain and is not deployed to preprod; this code is not for mainnet. Top-up
    and the unfreeze are **accepted design**, not shipped. Play
    [The pool runs dry, so Hal freezes her instead](../simulator/index.html)
    and [Two hunters race](../simulator/index.html).

Hal is a hunter: anyone paid to land an owner's rotation on chain, or to
freeze a checkpoint whose pool cannot pay for one. He watches Alice's witnesses. When they [receipt](https://trustoverip.github.io/kswg-keri-specification/#receipt-messages) a
rotation, he lands it and the chain pays him the premium `P` (the fee for
landing a rotation) from her pool of advance funds.
That is story 2 on the [checkpoint simulation](../simulator/index.html). In
KERI's vocabulary Hal is a
[watcher](https://trustoverip.github.io/kswg-keri-specification/#indirect-exchange-via-witnesses-and-watchers) with a wage; the
receipts he waits for are the ones KERI's
[witnessing policy](https://trustoverip.github.io/kswg-keri-specification/#witnessing-policy) requires.

When the pool cannot cover `P`, he freezes her instead. He presents the
later rotation as evidence, exactly as the log exports it, and takes the freeze
bond `B` (what a hunter takes when the pool cannot pay). The datum keeps its old
keys and sequence number; only the frozen flag is set, and the checkpoint then
holds the minimum ADA, the deposit and the pool. `ckeri freeze --aid … --kel
rotation.cesr …` lands it and pays the bond to the funding address. The checkpoint is inert to everyone but the next keys:
consumers reject it; a second freeze is refused; the poison (the owner's own
lock on the checkpoint) still belongs to the current quorum. Alice unfreezes with a `deposit` rotation — the
new keys refill `B`. Deposit is a no-op on full bonds.

Anyone may top up the pool. No signature, no datum change. A freeze is
refused while the pool covers the premium.

Two hunters can race the same rotation. One winner, one refusal. The
closer chooses *when* the reap (the owner's close, a rotation by the next
keys) happens, never *who* is paid: a copied reap with the payee rewritten
is refused.

The earlier freeze-for-lag, ACTIVE to ARMED with a deadline and a claim, is
gone: nothing arms, waits or claims. The freeze that remains is what a hunter
takes when the owner's pool has run dry, in a single transaction.

See [Rotate](rotate-preprod-identity.md), [Poison](poison.md), and the
[consumer checklist](consumer-checklist.md).
