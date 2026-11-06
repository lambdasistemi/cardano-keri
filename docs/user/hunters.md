# Hunters

!!! note "What ships, and the accepted design"
    The hunter's freeze and the controller's deposit rotation, which unfreezes,
    are one transaction each in this generation of the checkpoint program;
    `ckeri freeze` submits the freeze and `ckeri advance --deposit` the deposit
    rotation. The top-up transaction runs through the production scripts on a
    local test chain; `ckeri top-up` plans for preprod only and needs a manifest
    with a premium, which no committed manifest has until the redeployment
    (#356). These run on a local test chain and are not deployed to preprod;
    this code is not for mainnet. Play
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
lock on the checkpoint) still belongs to the current quorum.

Alice unfreezes with her next witnessed rotation, landed with the deposit
option: `ckeri advance --deposit …` writes the exact bytes her new keys sign,
an intent that names the network, the checkpoint policy, the spent output, her
identifier, the new sequence number, the new epoch and the amount, and lands the
rotation with those signatures. The successor is unfrozen and holds `B` again, so
the checkpoint is consumable again; the premium is paid exactly when the pool
covers it, as for any rotation. Nobody else can choose the deposit option for
her rotation, and a signature for one output is worthless for another. On a
checkpoint that is not frozen the intent names an amount of zero and the deposit
brings nothing. See [Rotate your preprod identity](rotate-preprod-identity.md)
for the commands and [The deposit intent](../design/aid-model.md#the-deposit-intent)
for what is signed.

Anyone may top up the pool by at least one premium, once between two
rotations; nobody signs anything. The top-up sets a mark in the datum and
changes nothing else. Every rotation clears the mark and a freeze keeps it. A
freeze is refused while the pool covers the premium. `ckeri top-up --aid … --amount …`
builds and submits the top-up; it plans for preprod only and needs a manifest
with a premium, which no committed manifest has until the redeployment (#356).
It refuses an amount below the premium and a checkpoint already topped up
since its last rotation before it builds anything.

Two hunters can race the same rotation. One winner, one refusal. The
closer chooses *when* the reap (the owner's close, a rotation by the next
keys) happens, never *who* is paid: a copied reap with the payee rewritten
is refused.

The earlier freeze-for-lag, ACTIVE to ARMED with a deadline and a claim, is
gone: nothing arms, waits or claims. The freeze that remains is what a hunter
takes when the owner's pool has run dry, in a single transaction.

See [Rotate](rotate-preprod-identity.md), [Poison](poison.md), and the
[consumer checklist](consumer-checklist.md).
