# User experience: a KERI identity on Cardano

This is the user journey the architecture supports, and the boundaries a
future Veridian integration must make visible.

!!! abstract "Where this page stands"
    The register, rotate and close journeys of the earlier deployed design (version 1, published on preprod on 2026-07-28) settled on preprod; the accepted design has no close (the owner exit was removed from the model and the source tree). The states a UI must distinguish, the three sums of
    money, and the poison journey are the **accepted design**.
    The interface itself is neither: the repository has settled transactions
    and a test harness, not an end-user product.

## The design principle: the owner is dumb on Cardano

The accepted design assumes the identity owner rotates her keys with `kli`. On Cardano the controller books the registration with the signed inception and its witness receipts (constitution, principle XII) and the registry's folder processes the booked request; beyond that the owner puts money in and authorizes what her keys alone can authorize. A [hunter](super-watcher.md) can present a later witnessed rotation to advance the checkpoint; when the pool covers the premium, the premium goes to the payee the hunter names, and otherwise the rotation lands unpaid. When the freeze conditions hold, a hunter can freeze the checkpoint, and the freeze bond goes to the payee the freeze names. Anyone may top the pool up with at least one premium while the checkpoint carries no top-up mark.

The UI should show which keys Alice needs for each action. The keys revealed by a rotation authorize its deposit at their threshold. The current key quorum can authorize poison.

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
| Juvenile | `born_at + W` is later than the current slot, `W` being the juvenility window; `born_at` is the booking's validity upper bound, which can precede the fold; too fresh to trust | designed |
| Frozen | A freeze set the frozen bit and paid the freeze bond `B` to the payee it named because the pool of advance funds was below the premium | designed |
| Pending termination | A conviction was accepted; custody is retained until the matching Registry fold consumes the termination request | designed |
| Convicted | Proven duplicity; terminal, and it will never come back | designed |
| No candidate | The reader holds no output for this AID. Alone it does not say whether the identity was never registered, is terminal, or whether the evidence is incomplete; the reader answers *never registered* or *terminal* only from a complete history | designed |
| Multiple candidates | Ambiguous holders; fail closed | the registry admits one active key per AID; version 1 had no such rule |
| Stale outref | The checkpoint changed; refresh and rebuild | holds in both designs |

"Fail closed" should be visible. A freeze sets only the datum's frozen bit and pays the freeze bond `B` to the payee the freeze names. The UI can show the frozen checkpoint with its old keys and explain where the bond went.

## Register

In the deployed V1 registration flow, a relayer can register Alice's public KERI inception without holding her
private keys:

1. prove the inception/AID BLAKE3 binding;
2. submit the Register transaction with observer evidence;
3. fund the bonds; and
4. wait for settlement.
In the accepted design the controller books the registration and the registry's folder processes the booked request; the steps above that belong to version 1 (the premint and the Register transaction) are replaced by that booking and that fold.

The resulting checkpoint is controlled by the keys in Alice's inception, not
by the relayer. Whoever pays chooses the refund address, and it stays theirs
for the checkpoint's whole life: if the checkpoint is convicted, the freeze
bond and the pool go back to that address, whatever Alice's keys sign.

The UI should show the AID; the controller threshold; the witness threshold;
the expected checkpoint policy and asset; each of the three sums; the transaction IDs of the registration (in version 1 the premint and the Register transaction; in the accepted design the booking and the fold); and the confirmation depth. Under the accepted design it should also show that the checkpoint is **juvenile** until the slot `born_at + W`, where `born_at` is the booking's validity upper bound and can precede the fold; at that slot the checkpoint stops being juvenile.

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

A rotation is also where Alice chooses the bond option: `keep`, or `deposit`
to unfreeze. A `deposit` travels in **a message her new keys sign**, so a UI
must display it before signing, exactly as the chain will read it. A rotation
never changes the refund address.

## Poison

This is the journey that is new, and the one worth designing carefully because
it happens on the worst day.

Alice's current keys are stolen. Before she can assemble a rotation, her key holders authorize a poison with the current key quorum, and a poison spend would let anyone land it; the model requires only that the current quorum authorized it, and neither the bytes they sign nor the poison spend are specified or built yet. The
checkpoint is immediately unconsumable, and the thief can do nothing with it:
no close, no second poison, no consumer authorization. The way out of a poison is a witnessed rotation, which clears it because the poison belonged to the keys the rotation retires; a conviction or a termination follows its own rules.

The UI must be honest about the one case this does not cover: if the thief also
holds the **next** keys, her rotation is control by KERI's own rule, and the
poison lasts until that rotation and no longer.

## No way out but conviction

There is no owner exit: no close, no parking, no revival, no pause and no
withdraw. As an identity owner, Alice keeps her checkpoint alive — bonds,
rotations, unfreezing — until it is convicted. As a relying party, the
treasury sees a checkpoint that is either alive or convicted (pending
conviction custody first, then convicted after the associated Registry fold).

- **Deposit** is the unfreeze: a rotation that refills `B` after a freeze paid it to the payee the freeze named. When the bond is full it adds nothing to the bond (an authorized deposit on an unfrozen holding moves zero) and the rotation still happens; it is still signed by the new keys.
- **Refund address** is set by whoever pays the registration and never
  changes. It matters only at conviction, when the freeze bond and the pool go
  there.

Whether an owner who stops maintaining a checkpoint should recover its bonds
and pool is an open economic question: today they leave a live checkpoint only
through rotation premiums, a freeze (the freeze bond, to the payee the freeze names) and
conviction. Parking was removed because it left unsettled who holds the
deposit while parked and how a sponsor is tracked; it may return only with an
economic model that settles both.

Before signing a deposit, the UI should show all eight fields in the intent:
the fixed domain tag, network ID, checkpoint policy, spent output reference,
AID, new sequence number, new epoch and deposit amount. The deposit restores
`B` when the checkpoint is frozen and is zero otherwise.

## Three balances, three explanations

The UI should never present the checkpoint's value as one generic deposit:

- **The pool** funds the premium `P`. When it covers the premium `P`, a landed rotation pays `P` to the payee the submitter names; a rotation lands unpaid when the pool is short. Anyone may top it up, at least `P` once between two rotations, and a pool below `P` is what allows a freeze.
- **The freeze bond `B`** is what a freeze pays to the payee it names when the pool cannot pay. Its absence accompanies the frozen bit in the datum. A depositing rotation restores the bond and clears the bit.
- **The conviction bond `D_reg`** is the stake a duplicity proof seizes. Conviction pays it to the payee of the eligible commitment and sends the freeze bond still held and the remaining pool to the checkpoint’s fixed refund address.

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
- the poison spend, which no validator implements yet, and the deployment of the bond and registry paths that the source tree already implements (epics #322–#325 on the
  [roadmap](../roadmap.md));
- real-scale measurements; and
- credential display and revocation checks.

The [story ladder](../story-ladder.md) is the current evidence ledger, and the
checkpoint simulator on the [home page](../index.md) is where the journeys
above can be played before any of them exists.
