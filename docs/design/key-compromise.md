# Compromise of the current keys

This page answers one question: an attacker holds the identity's **current**
KERI signing keys — not the pre-rotated successor keys — what can they do, on
Cardano and off it, and what does the owner do about it?

It is the counterpart to [Pre-rotation](aid-model.md#pre-rotation). Pre-rotation
is what stops the attacker from taking the identity *forward*. It is not what
stops them from using it *now*.

!!! abstract "Where this page stands"
    The exposure described here is **what ships on `main` today**. The M1
    return changes the answer in two specific places, each marked below: close
    stops answering to the current keys, and the **poison** becomes the owner's
    on-chain instrument. Both are
    [accepted design](../index.md#the-accepted-design-the-m1-return) — proved
    in the Lean, not built.

## What the stolen current keys authorize

| Surface | Attacker can | Attacker cannot |
|---|---|---|
| KERI KEL | Sign an interaction (`ixn`) event and whatever seals it anchors | Rotate — the `n` commitment names successor keys they do not hold |
| Cardano checkpoint | Authorize `Close`: burn the token and send the whole escrow to an address of their choice | Advance the checkpoint — an Advance is a rotation, and the dual threshold rejects them |
| A consuming application | Satisfy any authorization the application resolves against the ACTIVE checkpoint's current weighted key state | Change which keys the checkpoint publishes |

!!! success "After the M1 return, the `Close` row goes empty"
    Close becomes a **witnessed rotation** that withdraws everything and burns
    the UTxO (ruling D-036), so it needs the next keys exactly like any other
    rotation. Pause, resurrection and a change of refund address are the same
    rotation with a different signed intent, and that intent is signed by the
    keys of the epoch the rotation opens (ruling D-038). A thief holding only
    the current keys is left with exactly one Cardano move — the poison — and
    that is the owner's instrument, not hers.

The last row is the one that matters most and is easiest to miss. An
application built on [Value authorization](../architecture/value-auth.md) asks
*"do the current controllers of this AID authorize this operation?"*. Stolen
current keys answer that question correctly. **No KERI event is involved, and
none is needed.**

## An interaction event is an off-chain instrument

An `ixn` changes no key state. Its entire power is what it *anchors* — seals
pointing at TEL events (ACDC issuance and revocation), delegation approvals.
A thief who publishes an `ixn` is issuing or revoking credentials under the
victim's identifier. That harm lands in the credential graph, not on Cardano.

**V1 cardano-keri does not project `ixn` events at all.** Register admits only
`icp`; Advance admits only `rot`; the event decoder rejects every other type.
This is a stated scope decision, not an oversight — see
[#115](https://github.com/lambdasistemi/cardano-keri/issues/115): *an advance
is a rotation by definition; non-establishment events never touch the
checkpoint.*

Two consequences follow, and they point in opposite directions:

- A thief's `ixn` **cannot** advance, arm, freeze, or convict a checkpoint. It
  is invisible to the chain.
- Publishing an `ixn` is therefore **neither necessary nor helpful** for
  on-chain theft. On-chain exposure comes from key-state authority, above. The
  `ixn` is the off-chain instrument and the stolen keys are the on-chain one.

An identity whose Cardano checkpoint is perfectly current can still be having
credentials issued under it by a thief, because that traffic never reaches
Cardano in V1.

## Why we do not replicate first-seen

A KERI witness applies **first-seen**: it accepts the first event it sees at a
sequence number and refuses conflicting ones. So if the thief's `ixn` reaches
the witness threshold before the owner's honest `ixn` at the same sequence, the
thief's event *is* the event. A served KEL is one linear branch, and the
conflict is not in it. The victim's evidence may never reach a watcher at all.

First-seen is a **witness-local observation**. It is not in the events, not in
any proof, and not on Cardano. The chain does not reconstruct it and does not
substitute for it. Two rules follow, and they hold in both the shipped design
and the M1 return:

- For rules **derivable from event content** — superseding, next-key commitment
  validity, prior-digest chaining, thresholds — the projection must match
  `keripy` exactly.
- Where KERI could only settle a contest by witness-local observation, the
  chain **abstains**. Cardano's settlement slot is evidence, never a verdict.
  Resolving by slot would make the chain the authority, and would diverge from
  KERI exactly whenever the thief reached the witnesses first and the victim
  reached the chain first.

What the chain adds is not a better tie-break. It is a **censorship-resistant
publication path** for what witnesses would otherwise suppress.

!!! warning "The multi-branch record is retired"
    An earlier design answered this with a record tree that kept every event by
    location plus SAID, so rival events at one sequence coexisted, plus a
    cursor over it and a permanent `ever_duplicitous` fact. That design is
    **gone**, and its removal is the point of the M1 return: a record you
    cannot prove complete needs someone to assert completeness, and that
    someone is an oracle. The checkpoint has no evidence set, so there is
    nothing to be complete about.

    What replaces it here is narrower and buildable: the **poison**, below, for
    what the owner can declare, and the **conviction**, for what anyone can
    prove. The reasoning behind the retired shape is preserved as evidence in
    [the record/cursor design note](record-cursor-projection-fidelity.md).

One honest limit applies to both KERI and Cardano: **the victim's own event is
what makes the fork visible.** Until the owner publishes a competing event, the
thief's branch is cryptographically indistinguishable from the controller's.
Neither system detects a thief who is alone on the history.

## Rotation is the remedy

A rotation **supersedes** an interaction event at the same sequence, because
it proves possession of pre-committed keys — strictly stronger evidence than
signing with current keys. Descendants of the superseded event die with it.
The attacker cannot answer: revealing next keys reveals **public** halves, which
permits verification, not production.

The asymmetry is exact and worth stating: a rotation supersedes an interaction,
but a non-delegated rotation **cannot** supersede another rotation. Rotation
beats `ixn`; nothing beats a first-seen rotation.

On Cardano the rotation is an ordinary Advance. It installs the new keys, and
any authorization the thief had bound to the previous checkpoint input becomes
invalid — pending authorization does not silently survive a rotation.

Rotation is **not retroactive**:

- a Cardano transaction that already settled under the older ACTIVE checkpoint
  is not reversed;
- a relying party that already accepted a credential anchored by the superseded
  `ixn` loses it when recovery discards that branch; and
- a poison the owner declared for the stolen epoch is cleared by the rotation,
  because it belonged to the keys the rotation retires. Every poison
  transaction stays on the ledger forever, so the history is the indexer's; the
  chain simply stops asserting a live fact about keys nobody controls any more.

**Operator rule: when in doubt, rotate — never interact.** Rotation supersedes;
interaction contests. A controller who always rotates can never create the
unresolvable case themselves.

## The poison: what the owner does before, and instead of, rotating

Rotation is the remedy, but it takes time to assemble, and sometimes it is not
available at all. The M1 return gives the current keys one power for exactly
those two cases — and only those two.

**What it is.** The owner's key holders sign, at their own `cur_threshold`, a
short declaration over a preimage bound to the register policy, the AID and the
current sequence. Stock `kli sign` produces it, per member; no KERI-side change
is needed, and no BLAKE3 is computed on chain. Anyone may relay it. It is never
witnessed, because it is a Cardano-side declaration and not a projected KERI
event.

**What it does.** One bit in the datum. The checkpoint becomes unconsumable
immediately, and from a poisoned state the only enabled edge is a rotation:
no close, no second poison, no consumer authorization. So the two moves a
current-key thief would otherwise have — using the identity, and cashing it out
— are both gone for every epoch the owner has poisoned.

**Why it needs the threshold.** One stolen member key of a `k`-of-`n` group
cannot poison. In KERI an event signed below threshold is *invalid*, not
duplicitous, and a single compromised member is not compromise of the identity.
A single-key poison would assert more than KERI does, and would hand any one
stolen member key the power to stain the identity and force a rotation
(ruling D-023).

**Why it is epoch-local.** Any witnessed rotation clears it. That is not a
weakness of the mechanism; it is the projection law. Possession of the next
keys is control by KERI's own rule, and a chain that let a current-key
signature outlive a witnessed rotation would be a second authority over a
KERI-legitimate controller.

### The two cases it serves, and the one it does not

| Case | Does the poison help? |
|---|---|
| Current keys stolen; the owner still holds the next keys | **Yes** — it covers the window between detection and the rotation, which the owner can always perform |
| Current keys stolen; the next keys are lost | **Yes, permanently** — no rotation will ever come, so the poison never clears. This is the case KERI itself cannot express |
| Next keys stolen too | **No** — the thief's rotation *is* control, and the chain follows KERI. The poison lasts until that rotation and no longer |

The price of the second row is stated rather than hidden: a poisoned identity
whose next keys are lost is frozen forever, its conviction bond included. The
size of that bond is a deployment parameter and an economic call.

### When the fork is real, not merely suspected

If two witnessed rotations exist at one sequence — the same current keys
revealed, each with receipts from at least `toad` of the witnesses — that is not
a suspicion, it is duplicity, and anyone holding both can prove it on chain. The
identity becomes `Convicted`, terminally, and the convictor takes `D_reg`. See
[Identity operations](../architecture/identity-ops.md#convict--new-shape-in-the-m1-return).

The distinction from the poison is exact and worth keeping: a controller
*declaration* is epoch-local, because the controller can be superseded; a
*proof* of establishment-level duplicity is a KERI verdict, and KERI makes that
permanent.

## Related pages

- [AID cryptographic model](aid-model.md) — pre-rotation and event binding
- [Trust model](trust-model.md) — residuals, including current-key theft
- [Value authorization](../architecture/value-auth.md) — what an application
  must check
- [Identity operations](../architecture/identity-ops.md) — close, poison and
  conviction, shipped and designed
