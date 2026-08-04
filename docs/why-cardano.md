# Why Cardano — and how this differs from KEL rooting

Publishing KERI key events on Cardano is not new. A **backer** — a KERI witness
that also writes to a ledger — has been doing it for some time, and it works.
So the first question anyone familiar with the space asks is a fair one:

> Isn't rooting KELs on Cardano already done? What is this?

Both things put KERI data on Cardano. They answer different questions, and only
one of them needs a blockchain at all.

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
anything further.

Every move in the lifecycle may be submitted by anyone, and the submitter has
**no discretion whatsoever**. From
[Lifecycle and the two bonds](architecture/lifecycle-and-bonds.md):

> "Anyone" in this machine does not mean "anyone may choose the next state." It
> means anyone may pay the fee to relay public evidence whose result is
> **already determined**.

Registration, rotation, challenge, response, timeout claim, thaw and conviction
are each open to any submitter, and in each case the evidence decides the
outcome — not the relayer, and not any operator. The
[trust model](design/trust-model.md) states the boundary directly:

> Relayers and hunters are untrusted submitters. They may censor their own
> service, delay submission, or pay fees strategically. They **cannot fabricate**
> valid signatures, receipts, preimages, or conflicts, and they **cannot choose
> a different valid successor**.

And no operator owns the right to relay: if one refuses, anyone else may.

Contradiction also has a **consequence** rather than merely a record. Any party
holding witnessed evidence that an identity has published a conflicting history
can prove it on-chain; the checkpoint moves to a state consumers reject, and
posted bonds settle the outcome. See
[the freeze lifecycle](user/freeze-lifecycle.md) and
[conviction](user/conviction.md).

!!! info "This was not the first design"
    An earlier design put a privileged oracle writer in front of a shared
    registry. Adversarial vetting found that such an oracle could **censor**
    rotations and freezes, and that colluding with a stolen key could keep that
    key economically live — *"'cannot forge' holds; 'cannot keep alive' does
    not"* ([finding F7](vetting/canonical-model-findings.md)).

    That shared-registry model is retired. The current pages are written to
    keep it retired: [value authorization](architecture/value-auth.md) exists
    partly so that "later application validators do not reintroduce the retired
    shared-registry model."

**Why this matters even with no on-chain value at stake.** A credential meant
to outlive the organisation that issued it cannot rest on that organisation
still running a service. An anchor is exactly as neutral as the backer that
wrote it; a checkpoint's validity was established by consensus and remains
checkable when every party that created it is gone. That is a different kind of
artifact, and it is available without any further layer.

## Leg 2 — value that depends on identity

The second property is composability: because the key state is script-readable,
a validator can require that a spend be authorized by whoever controls a given
AID *right now*, and reject it after a rotation, a challenge, or a revocation.
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
- **Settlement evidence is not mainnet.** "Settled" means a transaction reached
  a development network running production transaction limits, and the M1
  programs are published on preprod. Neither is a mainnet deployment or a
  production service-level commitment. The exact transaction IDs are on the
  [story ladder](story-ladder.md).

## Where to read next

- [Anchor versus verify](architecture/amaru-integration.md#anchor-versus-verify-the-decisive-difference)
  — the detailed comparison, with references into the backer's source.
- [Lifecycle and the two bonds](architecture/lifecycle-and-bonds.md) — who may
  submit what, and what determines each result.
- [Trust model](design/trust-model.md) — the full boundary list.
- [Story ladder](story-ladder.md) — what has actually settled.
- [KERI primer](keri-primer.md) — AIDs, pre-rotation, witnesses and backers.
