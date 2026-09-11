# Hunters

!!! note "What ships, and the accepted design"
    The hunter's freeze, the premium, and top-up are **accepted design**,
    not shipped. Play
    [The pool runs dry, so Hal freezes her instead](../simulator/index.html)
    and [Two hunters race](../simulator/index.html). What ships today is
    Freeze as an ARMED role-address for lag, with a response window —
    a different machine, retired by the M1 return.

Hal watches Alice's witnesses. When they [receipt](https://trustoverip.github.io/kswg-keri-specification/#receipt-messages) a
rotation, he lands it and the chain pays him the premium `P` from her pool.
That is story 2 on the [checkpoint simulation](../simulator/index.html). In
KERI's vocabulary Hal is a
[watcher](https://trustoverip.github.io/kswg-keri-specification/#indirect-exchange-via-witnesses-and-watchers) with a wage; the
receipts he waits for are the ones KERI's
[witnessing policy](https://trustoverip.github.io/kswg-keri-specification/#witnessing-policy) requires.

When the pool cannot cover `P`, he freezes her instead. He presents the
later rotation as evidence, takes the freeze bond `B`, and leaves the
datum untouched. The checkpoint is inert to everyone but the next keys:
consumers reject it; a second freeze is refused; poison still belongs
to the current quorum. Alice unfreezes with a `deposit` rotation — the
new keys refill `B`. Deposit is a no-op on full bonds.

Anyone may top up the pool. No signature, no datum change. A freeze is
refused while the pool covers the premium.

Two hunters can race the same rotation. One winner, one refusal. The
closer chooses *when* the reap happens, never *who* is paid: a copied
reap with the payee rewritten is refused.

The freeze that ships on preprod today is not this. It is freeze-for-lag:
ACTIVE to ARMED, a deadline, a claim. That economy goes. The freeze that
survives is what a hunter takes when the owner's pool has run dry.

See [Rotate](rotate-preprod-identity.md), [Poison](poison.md), and the
[consumer checklist](consumer-checklist.md).
