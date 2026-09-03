# User experience: a KERI identity on Cardano

This is the user journey the architecture supports, and the boundaries a
future Veridian integration must make visible.

!!! abstract "Where this page stands"
    The register, rotate and close journeys are **shipped on `main` today** and
    exercised on preprod. The states a UI must distinguish, the three sums of
    money, and the poison journey are the **accepted design** of the M1 return.
    The interface itself is neither: the repository has settled transactions
    and a test harness, not an end-user product.

## The design principle: the owner is dumb on Cardano

The M1 return assumes the identity owner rotates her keys with `kli` and never
touches Cardano except to put money in. Everything on the Cardano side is done
by [hunters](super-watcher.md), paid from value she parks in her checkpoint.

A user interface that forgets this will be wrong in a specific way: it will
present Cardano operations as things the owner must perform on a schedule. The
two things she actually does are **fund** and, if her keys are stolen,
**poison**.

## First, know the AID

Alice learns Bob's KERI AID through a trusted KERI channel such as an OOBI
(out-of-band introduction), QR code, or direct exchange. The AID identifies
Bob's KERI key history. Cardano does not decide who Bob is in the legal world;
credentials do that later.

## Find the checkpoint

The application:

1. derives the Cardano asset name from Bob's AID;
2. asks an indexer or node for candidate UTxOs;
3. validates the candidate against the ledger; and
4. accepts it only if the consumer's predicate holds.

The UI should distinguish, and say why it refuses rather than silently choosing
a checkpoint or an old key:

| Result | User-facing meaning | State |
|---|---|---|
| Consumable checkpoint | Current key state is available and answerable | designed |
| Poisoned | The controller has declared this epoch compromised; do not authorize | designed |
| Juvenile | Registered or resurrected less than `W` slots ago; too fresh to trust | designed |
| Paused | The owner withdrew her bonds and parked the identity | designed |
| Frozen | A hunter took the freeze bond because the pool ran dry | designed |
| Convicted | Proven duplicity; terminal, and it will never come back | designed |
| Closed | The owner left. It can return by a later witnessed rotation | designed |
| No candidate | Nothing on chain for this AID | shipped |
| Multiple candidates | Ambiguous registration; fail closed | shipped — the registry removes it |
| Stale outref | The checkpoint changed; refresh and rebuild | shipped |

"Fail closed" should be visible. Note that **paused** and **frozen** are not
flags: they are what the checkpoint's value shows. A UI should read them from
the bonds rather than looking for a status field that does not exist.

## Register

A relayer can register Alice's public KERI inception without holding her
private keys:

1. prove the inception/AID BLAKE3 binding;
2. submit the Register transaction with observer evidence;
3. fund the bonds; and
4. wait for settlement.

The resulting checkpoint is controlled by the keys in Alice's inception, not
by the relayer. If somebody else pays, they are donating: the refund address is
theirs only until Alice's first rotation moves it, and the money then answers
to her keys.

The UI should show the AID; the controller threshold; the witness threshold;
the expected checkpoint policy and asset; each of the three sums; the premint
and Register transaction IDs; and the confirmation depth. Under the M1 return
it should also show that the checkpoint is **juvenile** and for how long.

## Rotate

Alice rotates in KERI first. Her KERI software creates the event and collects
the configured witness receipts. Any hunter may then land the advance.

The UI should show the old and new KERI sequence; the controller-threshold
result; the witness receipt count and the required `toad`; any witness-set
change; the checkpoint input and expected successor; and the settlement state.

The application must not report the rotation complete merely because KERI has
moved. Until the advance settles, Cardano still has the old key state — and
under the M1 return, whether it settles promptly depends on whether Alice's
pool can pay a hunter.

A rotation is also where Alice exercises every other choice she has: the bond
option (`keep`, `withdraw` to pause, `deposit` to come back or unfreeze) and a
new refund address. All of them travel in **one message her new keys sign**, so
a UI must display the intent and the address together, before signing, exactly
as the chain will read them.

## Poison

This is the journey that is new, and the one worth designing carefully because
it happens on the worst day.

Alice's current keys are stolen. Before she can assemble a rotation, her key
holders sign a short declaration — with stock `kli sign`, over a preimage bound
to the policy, her AID and her current sequence — and anyone lands it. The
checkpoint is immediately unconsumable, and the thief can do nothing with it:
no close, no second poison, no consumer authorization. The only way out is a
rotation, which clears the poison because the poison belonged to the keys the
rotation retires.

The UI must be honest about the one case this does not cover: if the thief also
holds the **next** keys, her rotation is control by KERI's own rule, and the
poison lasts until that rotation and no longer.

## Pause, return, and leaving

- **Pause** is a rotation that withdraws everything to the refund address. The
  state stays on chain, unbonded and unconsumable, and answers only to another
  rotation — so a current-key thief can do nothing with a parked identity.
- **Return** is a rotation that deposits the bonds again. There is no replay;
  the state never left the chain. The checkpoint is juvenile again.
- **Close** is a rotation that withdraws everything and burns the UTxO. It
  needs the next keys, poisoned or not. It is not the end: a witnessed rotation
  later than the tombstone reopens the identity with fresh bonds.

Before signing any of these the UI must display the exact checkpoint input, the
AID and sequence, the destination address, the amounts of all three components,
and the network and policy — because that is precisely the set of facts the
signed intent binds.

## Three balances, three explanations

The UI should never present the checkpoint's value as one generic deposit:

- **The pool** is a wage fund. It pays the premium `P` to whoever lands a
  rotation. Anyone may top it up, and its depletion is what invites a freeze.
- **The freeze bond `B`** is what a hunter takes when the pool cannot pay. Its
  absence *is* the frozen state, and only a depositing rotation restores it.
- **The conviction bond `D_reg`** is the stake a duplicity proof seizes. It is
  never a fee. A responsive, honest identity never loses any of the three.

All three are deployment parameters, and the numbers are not yet set — they
wait on the measurements in the [roadmap](../roadmap.md).

## Current product boundary

The repository has settled development-network and preprod stories and a test
harness, not an end-user product. A production experience still needs:

- a published Veridian/Signify integration;
- redundant checkpoint discovery;
- transaction fee and funding UX;
- Cardano settlement and rollback monitoring;
- KERI freshness monitoring;
- the poison, bond and registry paths built at all (epics K4–K7 on the
  [roadmap](../roadmap.md));
- real-scale measurements; and
- credential display and revocation checks.

The [story ladder](../story-ladder.md) is the current evidence ledger, and the
checkpoint simulator on the [home page](../index.md) is where the journeys
above can be played before any of them exists.
