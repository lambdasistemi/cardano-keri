# Identity operations

Every operation, one by one: what the shipped validators do, and what the M1
return replaces it with.

!!! abstract "Where this page stands"
    The **Shipped today** sections describe programs published on preprod and
    exercised by settled transactions. The **After the M1 return** sections
    describe the [accepted design](../index.md#the-accepted-design-the-m1-return),
    proved in `lean/CardanoKeri/Checkpoint.lean` and playable in the
    checkpoint simulator. Nothing designed is built. For evidence and
    transaction IDs, start with the [story ladder](../story-ladder.md).

A **KERI AID** (Key Event Receipt Infrastructure Autonomic Identifier) has a
signed **KEL** (Key Event Log). cardano-keri does not put the whole KEL on
Cardano. It stores one current checkpoint in a sovereign **UTxO** (unspent
transaction output) identified by a quantity-one token derived from the AID.

## The datum

Shipped today, `CheckpointDatumV1` is **pure key state** — nine fields, no
lifecycle flag (`onchain/lib/cardano_keri/checkpoint/datum.ak`):

- the AID;
- current controller public keys and their weighted threshold;
- commitments to the next controller keys and their next threshold;
- the current KERI witness set and its threshold, called `toad`;
- a Cardano checkpoint sequence; and
- the native KERI sequence.

Lifecycle state lives outside it, in the script role address the token sits at.

Datum V2, in the M1 return, adds what the new machine needs: `poisoned`,
`born_at` (juvenility), `refund_to`, and `alive_at` and `valid_until`
reserved for a future validity edge. The three sums of money — `D_reg`, `B`
and the pool — are value, not fields. That change lands on `observer_advance`,
which has three bytes of headroom, so epic
[K1](https://github.com/lambdasistemi/cardano-keri/issues/319) measures before
epic [K4](https://github.com/lambdasistemi/cardano-keri/issues/322) decides.

## Operation status

| Operation | Shipped today | After the M1 return |
|---|---|---|
| Register | Creates a bonded checkpoint at sequence zero. No uniqueness rule | A registry request: absence proof, insert, mint — once ever per AID |
| Advance | Applies one genuine witnessed rotation | The same, plus a bond option, an optional new refund address, and the premium `P` to whoever landed it |
| Close | Current controllers burn the token and take the refund | A **rotation** that withdraws everything and burns; needs the **next** keys; reopenable |
| Freeze | Moves a lagging checkpoint to ARMED for the response window | A hunter's payment when the pool is short. The datum is untouched; `B` leaves |
| ClaimFreeze / thaw | Pays the recorded hunter after the deadline; thaw re-posts `B` | **Gone.** No deadline, no claim, no timeout economy |
| Convict | Burns the token on a witnessed irreconcilable fork | A terminal `Convicted` state on a duplicity proof; `D_reg` in full to the convictor |
| Poison | — | New: the current quorum declares the epoch compromised |
| Top-up | — | New: anyone adds to the pool. No signature, no datum change |
| Reopen | — | New: a closed identity returns on a rotation later than its tombstone |

## Register

### Shipped today

Registration is permissionless: anyone may relay a public KERI inception and
fund the escrow. The inception itself determines the keys; the relayer cannot
substitute different controller authority. It has two transactions.

**1. BLAKE3 premint.** The KERI AID is a BLAKE3 digest of the inception bytes
in KERI's saidification form. Plutus has no native BLAKE3 builtin, so a
dedicated Aiken policy performs that expensive check and mints a deterministic
proof token. The token records one fact — *the supplied inception bytes have
the supplied KERI AID* — and grants no identity authority.

**2. Checkpoint mint.** The checkpoint transaction:

1. uses the bare mint redeemer `Register`;
2. includes a zero-lovelace withdrawal from the registration observer;
3. puts the complete `RegistrationEvidence` in that observer's envelope;
4. consumes an input carrying the matching proof token and burns it;
5. verifies the inception's controller signatures and witness receipts over
   the exact event bytes;
6. verifies that the new datum projects the event's AID, keys, thresholds,
   next commitments, witnesses, and `toad`;
7. mints exactly one AID-derived checkpoint token; and
8. creates exactly one output holding the token and the required escrow.

The checkpoint and observer programs are delivered by reference; the evidence
is **not** duplicated in the mint redeemer. See
[Observer architecture](observer-architecture.md#registrations-premint-fact-token).

**The duplicate-registration residual.** Registration uses no shared registry
and no absence proof, so two independent transactions can mint live candidates
for the same AID. A consumer must resolve exactly one and fail closed on zero
or several — and it cannot prove no other exists. A holder of some retired
epoch's keys can therefore mint a rival checkpoint and advance it exactly to
their epoch.

### After the M1 return

Registration becomes a **request** against the registry: it carries the
inception, the bonds and a refund address chosen by whoever pays, and it is
applied in a batch by anyone. Application checks that the AID has **no leaf**,
inserts one, and mints the checkpoint in the same transaction. That is the only
way the token can ever be minted, so an AID has at most one incarnation ever
(rulings D-024, D-037).

The new checkpoint is **juvenile**: unconsumable for `W` slots. That window is
what bounds the stale-key registration above — anyone can advance the
checkpoint onward with the controller's later public rotations, and the moment
that happens the registrant's bonds answer to the controller's keys.

## Advance

### Shipped today

Advance moves one KERI rotation into the checkpoint. Anyone may relay it
because the public event and its receipts determine the only valid successor.

The transaction consumes exactly one current checkpoint and creates exactly
one successor with the same quantity-one token, the same complete value, the
Cardano sequence increased by one, and the event's keys, thresholds, next
commitments, witnesses and `toad`.

The heavy checks run in `observer_advance`. They require:

1. the event to continue from the stored prior event;
2. revealed keys to match the stored next-key commitments;
3. both KERI controller thresholds to pass — the event's own and the
   previously committed next threshold;
4. signatures to cover the exact rotation bytes;
5. witness receipts to cover the exact event bytes; and
6. witness-set changes to satisfy the **incoming** witness threshold.

When incoming `toad` is greater than zero, elapsed time and controller
signatures never replace the required receipts. This prevents a controller from
activating an unpublished Cardano-first branch and repairing the KERI history
afterwards.

`ixn`, `dip` and `drt` are rejected: advance requires the type span to read
`rot`.

!!! warning "An unsettled parity question"
    The validator tallies receipts against the **new** witness set and the
    **new** `toad`. Whether `keripy` does the same, or tallies against the
    parent's set, is not established. Epic
    [K2](https://github.com/lambdasistemi/cardano-keri/issues/320) builds the
    oracle that settles it. The two rules disagree exactly on rotations that
    cut or add witnesses — that is, on witness replacement after a compromise.

### After the M1 return

The predicate is unchanged. What is added is everything around it:

- a **bond option** — `keep`, `withdraw` (pause), or `deposit` (return, or
  unfreeze) — which restores or releases `D_reg` and `B`;
- an optional **new refund address**;
- the **premium** `P` paid from the pool to the payee the transaction names,
  when the pool covers it. An unpaid rotation is still a valid rotation: no
  transition ever requires the pool;
- the **poison cleared**, unconditionally.

Every option other than `keep`, and every new address, travels in **one message
signed by the keys of the epoch the rotation opens** (ruling D-038). A relayer
landing the owner's public rotation therefore cannot park her, reset her
juvenility, or move her money. Absent means keep and unchanged.

## Close

### Shipped today

Close is the controller-authorized retirement path. Its signed evidence binds
the network, checkpoint policy, exact checkpoint input reference, AID and
current sequence, refund address, and current controller threshold. The
transaction consumes the exact checkpoint, satisfies the current weighted
threshold, burns the quantity-one token, creates no successor, and refunds the
complete remaining value to the signed address.

Binding the input reference makes the authorization single-use. Binding the
refund address prevents a transaction builder from redirecting the escrow.

**The exposure it leaves.** Close answers to the *current* keys, so a thief who
steals them can burn the identity and take the escrow. The signed refund
address limits where the money goes but not whether the identity dies.

### After the M1 return

Close is a **witnessed rotation** that withdraws everything and burns the UTxO
(ruling D-036). It needs the next keys exactly like any other rotation, so the
current-key thief loses this move entirely — the only Cardano power the current
keys retain is the poison, and a rotation clears that.

Close and pause differ only by the burn. And close is **not terminal**: the
registry leaf becomes `closed(epoch, sn)`, a tombstone, and a witnessed
rotation later than that sequence reopens the identity with fresh bonds and a
fresh juvenility window. Only a conviction is final.

## Freeze

### Shipped today

Freeze is a public challenge to a checkpoint that KERI evidence shows is
behind. The thin checkpoint requires an `observer_enforcement` withdrawal,
which proves the contested rotation belongs to the same AID, continues from the
recorded event, is strictly ahead of the tip, reveals committed keys, satisfies
its controller threshold, and carries enough receipts. The checkpoint moves to
ARMED — a different role address, so consumers fail closed — with the hunter
and a deadline recorded, and the complete escrow preserved.

A response is not an owner-only command: it is the same ordinary advance,
applied before the deadline. Evidence is bound to the challenged tip, so after
a response the old proof is stale and a new round needs fresh evidence at the
new sequence.

### After the M1 return

Freeze survives, with a different job. It is not a punishment for lag — the
party who can prove a later witnessed rotation can simply **land** it, which
costs the owner nothing and leaves the checkpoint fresh, so paying for the
freeze instead would pay for the harmful move.

Instead a hunter freezes only when the owner's **pool is short**: it presents
exactly the advance evidence, takes `B`, and leaves the datum untouched — the
old keys stay. Frozen is the absence of `B`, a value-level fact, not a role or
a flag. There is no deadline, no claim, no thaw window: the owner comes back by
a rotation with `deposit`, which restores both bonds.

There is no ARMED, no FROZEN role address, no recorded hunter in the datum, and
no timeout.

## Poison — new in the M1 return

A poison is the current quorum's declaration that this epoch is compromised.
The key holders sign, at `cur_threshold`, a short preimage bound to the
register policy, the AID and the current sequence — producible with stock
`kli sign`, no KERI-side change, no BLAKE3 — and anyone lands it. It is never
witnessed, because it is a Cardano-side declaration and not a projected KERI
event.

Its effect is one bit. The checkpoint becomes unconsumable, and from a poisoned
state the only enabled edge is a rotation: no close, no second poison, no
consumer authorization. The rotation clears it.

Two properties are worth stating precisely:

- **The threshold matters.** One stolen member key of a `k`-of-`n` group cannot
  poison. In KERI an event signed below threshold is invalid rather than
  duplicitous, so a single-key poison would assert more than KERI does.
- **It is epoch-local.** Any witnessed rotation clears it, because possession
  of the next keys is control by KERI's own rule. It serves the window between
  detection and rotation, and the case of lost next keys where no rotation will
  ever come. It does not serve next-key theft, where the thief's rotation *is*
  control.

## Convict — new shape in the M1 return

### Shipped today

`convict_predicate` accepts a **second** rotation at the tip's `native_sn` that
reveals exactly the tip's current keys, is signed at `cur_threshold`, carries
receipts from at least `toad` of the tip's witnesses, and differs in content. It
needs no history, because the revealed keys *are* the current keys. On the
shipped machine this burns the token and leaves no successor, and the CLI
exposes no command for it.

### After the M1 return

The same proof, a different effect. The convictor names a payee and takes
`D_reg` in full; `B` and the pool go to the refund address; the checkpoint
becomes `Convicted`, a tombstone the token stays with, and there is **no
transition out** — no rotate, no poison, no close (rulings D-030, D-031).

Terminality is not severity. KERI has no event that un-duplicates an
identifier: superseding recovery is a rotation over an interaction, by rule and
not by duplicity, while two establishment events at one sequence is duplicity
and KERI's only answer is permanent distrust. A clearable conviction would be
the chain inventing a recovery KERI lacks.

Who can trigger it is narrow. A stranger cannot: only a holder of the
pre-committed keys could have signed the second rotation, and only colluding
witnesses could have receipted both. The residual is real and bounded: a
next-key thief with `toad` colluding witnesses can convict the identity she
already controls under KERI and take `D_reg` on the way out. Exposure is
`D_reg` and the witness set the controller chose.

## Top-up and reopen — new in the M1 return

**Top-up** adds value to the pool. No signature, no datum change, anyone. It is
how a friend, an employer or a consortium pays for an identity's maintenance.

**Reopen** brings a closed identity back: a witnessed rotation later than the
tombstone's sequence, fresh bonds, a first pool, and a refund address chosen by
whoever pays. A rotation at or below the closed sequence cannot reopen — that
is what stops a stale resurrection.

## What is off chain

The ledger validates the event presented for a transition. It does not:

- discover new KERI events by itself;
- store or replay the entire KEL;
- operate KERI witnesses;
- decide whether an unseen event exists; or
- submit transactions.

[Hunters](../design/super-watcher.md), controllers and ordinary relayers
discover evidence off chain. They do not become trusted authorities: the
on-chain validators accept or reject the supplied bytes.
