# Why Cardano — and how this differs from KEL rooting

Publishing KERI key events on Cardano is not new. A **backer** — a KERI witness
that also writes to a ledger — has been doing it for some time, and it works.
So the first question anyone familiar with the space asks is a fair one:

> Isn't rooting KELs on Cardano already done? What is this?

Both things put KERI data on Cardano. They answer different questions, and only
one of them needs a blockchain at all.

!!! abstract "Where this page stands"
    The comparison with anchoring is about **what ships on `main` today**: the
    validators verify KERI cryptography now. The list of what a checkpoint
    buys under **leg 1** describes the [accepted design](index.md#the-accepted-design-the-m1-return)
    — the Lean machine of the M1 return — and says so item by item.

## What rooting does

A backer takes a key event, verifies it off-chain in its own process, and
submits a Cardano transaction carrying the **full serialized event as
transaction metadata** (metadatum label `13456`). The transaction is an
ordinary self-payment signed by the backer's own payment key.

What the chain contributes is real and worth having:

- **availability** — the complete log is recoverable from public chain data;
- **immutability** — nobody can retract a published event; and
- **global ordering** — every event carries a settled position in time.

What the chain does *not* do is check any of it. It never replays the
controller's signatures, the witness receipts, or the pre-rotation commitment.
To the ledger the event is opaque bytes. Two consequences follow, and they are
structural rather than fixable:

!!! warning "What an anchor cannot express"
    **A script cannot read it.** Metadata is unreachable from a Plutus
    validator, so no Cardano transaction can be made to succeed or fail based
    on an AID's current keys.

    **There is no wrong anchor.** Metadata cannot be rejected. Two
    contradictory events can both be anchored and the ledger holds no opinion
    about the conflict. Nor can it show that a backer *should* have published
    something and did not — omission is invisible on-chain.

And the writer is chosen, not open: a backer only serves AIDs whose key log
designates it. So the anchor means *"a party the controller picked asserts this
event is valid."* Its honesty and its liveness are assumptions you carry.

The detailed comparison, with source references, is in
[Anchor versus verify](architecture/amaru-integration.md#anchor-versus-verify-the-decisive-difference).

## What the checkpoint does

cardano-keri does the KERI cryptography **inside the validator**. Aiken code
replays the controller signatures against both thresholds, checks the required
witness receipts, and checks the pre-rotation binding — and only if all of that
holds may the identity's [checkpoint UTxO](architecture/observer-architecture.md)
advance to its successor. The resulting key state lives in an inline datum that
any contract can read as a CIP-31 reference input.

That buys two distinct properties, with very different maturities. They are
worth separating, because the first is available today and the second is not.

---

## Leg 1 — trust without an intermediary

This is the property most people miss, and it does not require anyone to build
a credential layer or a wallet bridge first.

Every move in the lifecycle may be submitted by anyone, and the submitter has
**no discretion whatsoever**. "Anyone" does not mean "anyone may choose the
next state"; it means anyone may pay the fee to relay public evidence whose
result is **already determined**. Registration, rotation, the poison
declaration, the freeze, the top-up, the conviction, the close and the reopen
are each open to any submitter, and in each case the evidence decides the
outcome — not the relayer, and not any operator. If one relayer refuses,
anyone else may.

### What that is worth, item by item

Each line below is a property of the [accepted design](index.md#the-accepted-design-the-m1-return),
proved in `lean/CardanoKeri/Checkpoint.lean`. None of them is shipped on
`main` yet; the epics that build them are on the [roadmap](roadmap.md).

- **A key compromise is visible.** The owner's current keys can sign one short
  declaration — the **poison** — and every consumer stops trusting the epoch
  immediately, before the rotation is ready. There is nobody to ask and nobody
  to convince. It covers the two cases KERI itself cannot signal: the window
  between noticing a theft and rotating, and the loss of the next keys, where
  no rotation will ever come.
- **Proven duplicity is permanent.** Two witnessed rotations at one sequence
  are a KERI verdict, not an opinion, so the chain makes it terminal: the
  identity is `convicted`, has no way out, and its conviction bond goes to
  whoever proved it. KERI has no event that un-duplicates an identifier, so
  the chain invents no recovery.
- **One incarnation, ever.** The registry holds one leaf per AID and a
  registration must prove absence before it inserts. There is no second
  candidate checkpoint for a consumer to disambiguate, and no stale-key holder
  can mint a rival one.
- **Freshness is visible.** The checkpoint says when it was last bonded and
  what its pool holds; a consumer refuses anything younger than the juvenility
  window `W`, and an identity whose pool has run dry gets frozen by a hunter
  rather than quietly drifting behind its KEL.
- **It is consumable without an oracle.** The key state is in an inline datum.
  A validator reads it as a reference input and decides for itself. There is
  no service to be up, no writer to be honest, and no completeness claim for
  anyone to assert.
- **Every move of value answers to the owner.** The bonds and the pool leave
  only to the refund address the owner controls, and that address moves only
  when the keys of the epoch a rotation opens sign for it. A relayer landing
  the owner's public rotation cannot park her, age her, or close her.
- **Exit and return are the owner's.** Close needs the next keys, exactly like
  any rotation, so a thief holding only the current keys cannot erase the
  identity and take the money. And close is not the end: a witnessed rotation
  later than the tombstone reopens it.

!!! info "This was not the first design"
    An earlier design put a privileged oracle writer in front of a shared
    registry. Adversarial vetting found that such an oracle could **censor**
    rotations and freezes, and that colluding with a stolen key could keep that
    key economically live — *"'cannot forge' holds; 'cannot keep alive' does
    not"* ([finding F7](vetting/canonical-model-findings.md)).

    That shared-registry model is retired, and the M1 return keeps it retired
    for a structural reason rather than an economic one: the checkpoint carries
    no evidence set, so there is nothing for anyone to be complete about, and
    the oracle has no job to return to. See
    [value authorization](architecture/value-auth.md).

**Why this matters even with no on-chain value at stake.** A credential meant
to outlive the organisation that issued it cannot rest on that organisation
still running a service. An anchor is exactly as neutral as the backer that
wrote it; a checkpoint's validity was established by consensus and remains
checkable when every party that created it is gone. That is a different kind of
artifact, and it is available without any further layer.

## Leg 2 — value that depends on identity

The second property is composability: because the key state is script-readable,
a validator can require that a spend be authorized by whoever controls a given
AID *right now*, and reject it after a rotation, a poison, or a revocation.
That is the thing an anchor structurally cannot do.

!!! warning "Not available yet"
    Leg 2 needs two layers that are not delivered. The credential verification
    layer is a later milestone (see the [roadmap](roadmap.md)), and the
    **KERI-wallet ↔ Cardano signing bridge** — which lets keys held in a KERI
    wallet authorize a Cardano transaction at all — is on the critical path of
    every application design and is
    [currently nobody's deliverable](design/business-cases/index.md).

    Until that bridge exists, a KERI credential holder cannot spend on Cardano
    even if they want to. Absence of such usage today is a statement about
    missing plumbing, not about missing demand.

## The two legs side by side

| | Rooting / anchoring | cardano-keri checkpoint |
|---|---|---|
| KERI crypto checked by the chain | no — off-chain, in the writer | yes — in the validator |
| What the chain stores | full event bytes as metadata | key state in an inline datum |
| Readable by a Plutus script | no | yes, as a reference input |
| Who may write | a backer the controller designated | anyone; the evidence decides |
| Wrong or missing publication | invisible to the ledger | provable on-chain, and bonded |
| Trust required | the backer is honest and still running | the witness quorum (below) |
| Available | today | leg 1 today; leg 2 needs the bridge |

## What this page does not claim

The permissionless projection removes an intermediary. It does not remove every
assumption, and the [trust model](design/trust-model.md) is explicit about
which remain:

- **Witness quorum.** For an identity with `toad > 0` the system assumes the
  configured witness threshold provides meaningful public acceptance. The
  validator checks the receipts; it cannot make a colluding quorum honest.
- **`toad = 0` identities** carry no witness receipts at all, and any
  application requiring public KERI acceptance must reject them by policy.
- **Service-level censorship.** A relayer can still refuse to serve you. The
  guarantee is that anyone else may relay instead, not that any particular
  party will.
- **Next-key theft is control.** If a thief holds the next keys, her rotation
  is legitimate by KERI's own rule and the chain follows KERI. The poison lasts
  until that rotation and no longer.
- **The tip never moves backward.** The checkpoint cannot roll back, so KERI's
  superseding-recovery rule is not projected in the one scenario that would
  need it. Stated as a limit, not hidden (ruling D-022).
- **Settlement evidence is not mainnet.** "Settled" means a transaction reached
  a development network running production transaction limits, or preprod.
  Neither is a mainnet deployment or a production service-level commitment. The
  exact transaction IDs and dates are on the [story ladder](story-ladder.md).

## Where to read next

- [Anchor versus verify](architecture/amaru-integration.md#anchor-versus-verify-the-decisive-difference)
  — the detailed comparison, with references into the backer's source.
- [Identity operations](architecture/identity-ops.md) — who may submit what,
  and what determines each result.
- [Trust model](design/trust-model.md) — the full boundary list.
- [Story ladder](story-ladder.md) — what has actually settled.
- [KERI primer](keri-primer.md) — AIDs, pre-rotation, witnesses and backers.
