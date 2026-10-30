# User experience: a KERI identity on Cardano

This is the user journey the architecture supports, and the boundaries a
future Veridian integration must make visible.

!!! abstract "Where this page stands"
    The register, rotate and close journeys are **shipped on `main` today** and
    exercised on preprod. The states a UI must distinguish, the three sums of
    money, and the poison journey are the **accepted design**.
    The interface itself is neither: the repository has settled transactions
    and a test harness, not an end-user product.

## The design principle: the owner is dumb on Cardano

The accepted design assumes the identity owner rotates her keys with `kli` and never
touches Cardano except to put money in. Everything on the Cardano side is done
by [hunters](super-watcher.md) — anyone paid to land her rotations, or to
freeze her checkpoint when it cannot pay for one — paid from value she keeps
in her checkpoint.

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
| Juvenile | Registered less than `W` slots ago, the juvenility window; too fresh to trust | designed |
| Frozen | A hunter took the freeze bond `B` because the pool of advance funds ran dry | designed |
| Pending conviction | Duplicity proved; retained custody awaits its associated Registry fold | designed |
| Convicted | Proven duplicity; terminal, and it will never come back | designed |
| No candidate | Nothing on chain for this AID | shipped |
| Multiple candidates | Ambiguous registration; fail closed | shipped — the registry removes it |
| Stale outref | The checkpoint changed; refresh and rebuild | shipped |

"Fail closed" should be visible. Note that **frozen** is not a flag: it is
what the checkpoint's value shows (`B` absent). A UI should read it from
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
and Register transaction IDs; and the confirmation depth. Under the accepted design
it should also show that the checkpoint is **juvenile** and for how long.

## Rotate

Alice rotates in KERI first. Her KERI software creates the event and collects
the configured witness receipts. Any hunter may then land the advance.

The UI should show the old and new KERI sequence; the controller-threshold
result; the witness receipt count and the required `toad`; any witness-set
change; the checkpoint input and expected successor; and the settlement state.

The application must not report the rotation complete merely because KERI has
moved. Until the advance settles, Cardano still has the old key state — and
under the accepted design, whether it settles promptly depends on whether Alice's
pool can pay a hunter.

A rotation is also where Alice exercises every other choice she has: the bond
option (`keep`, or `deposit` to unfreeze) and a
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

## No way out but conviction

There is no owner exit: no close, no parking, no revival, no pause and no
withdraw. As an identity owner, Alice keeps her checkpoint alive — bonds,
rotations, unfreezing — until it is convicted. As a relying party, the
treasury sees a checkpoint that is either alive or convicted (pending
conviction custody first, then convicted after the associated Registry fold).

- **Deposit** is the unfreeze: a rotation that refills `B` after a hunter
  took it. It is a no-op on full bonds, still signed by the new keys.
- **Refund address** changes travel with a rotation, signed by the new keys.
  The address matters only at conviction, when the bonds and the pool go there.

Whether an owner who stops maintaining a checkpoint should recover its bonds
and pool is an open economic question: today they leave a live checkpoint only
through rotation premiums, a freeze (the freeze bond, to a hunter) and
conviction. Parking was removed because it left unsettled who holds the
deposit while parked and how a sponsor is tracked; it may return only with an
economic model that settles both.

Before signing a rotation intent the UI must display the exact checkpoint input, the
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
  never a fee. The pool pays rotation premiums; it is not a loss-free reserve.
  An authorized close returns the remaining bonds and pool to the signed
  destinations while retaining the output’s token and minimum ADA.

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
- the poison, bond and registry paths built at all (epics #322–#325 on the
  [roadmap](../roadmap.md));
- real-scale measurements; and
- credential display and revocation checks.

The [story ladder](../story-ladder.md) is the current evidence ledger, and the
checkpoint simulator on the [home page](../index.md) is where the journeys
above can be played before any of them exists.
