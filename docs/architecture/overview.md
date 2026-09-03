# Architecture overview

cardano-keri gives one KERI identity a stable Cardano checkpoint while its keys
rotate. KERI is Key Event Receipt Infrastructure; its **AID** (Autonomic
Identifier) names an identity, and its **KEL** (Key Event Log) is the signed
history of that identity's key events.

!!! abstract "Where this page stands"
    The transaction architecture — thin checkpoint, reference observers,
    zero-lovelace withdrawal, BLAKE3 premint — is **shipped on `main` today**
    and survives the M1 return unchanged. How lifecycle state is *represented*
    changes: today it is role addresses, in the
    [accepted design](../index.md#the-accepted-design-the-m1-return) it is one
    bit plus the checkpoint's own value. Both are described below, marked.

## The identity plane

Every registered AID owns a sovereign **checkpoint UTxO** (unspent transaction
output) carrying one AID-derived token and an inline datum with its current key
state.

```mermaid
flowchart LR
    KEL["KERI KEL<br/>inception · rotations · witness receipts"]
    PRE["BLAKE3 premint<br/>one-use fact token"]
    TX["Cardano operation tx"]
    CK["Sovereign checkpoint UTxO<br/>AID token · inline key state · value"]
    OBS["Reference observers"]
    APP["Consumer validator"]

    KEL --> PRE
    KEL --> TX
    PRE --> TX
    TX --> CK
    OBS -->|"zero-lovelace withdrawal<br/>in the same tx"| TX
    CK -->|"CIP-31 reference input"| APP
```

The parts have deliberately narrow jobs:

- **KERI** produces the identity events, controller signatures, and witness
  receipts.
- **The BLAKE3 premint policy** proves that inception bytes bind to the AID and
  mints a short-lived fact token.
- **The thin checkpoint validator** protects the token, value, exact input, and
  unique successor.
- **Reference observers** validate large KERI evidence through a zero-lovelace
  withdrawal in the same transaction.
- **The checkpoint UTxO** is the current Cardano projection. A rotation spends
  it and creates its next version; no shared root or inclusion proof is needed
  for the key state.

## Stable identity, changing authority

The checkpoint token's asset name is derived from the qualified KERI AID. That
policy ID and asset name form the stable Cardano handle. The datum changes as
KERI rotates. Shipped today it is nine fields of pure key state:

```text
CheckpointDatumV1 {
  cesr_aid
  current controller keys and weighted threshold
  next-key commitments and committed next threshold
  witnesses and toad
  Cardano sequence
  native KERI sequence
}
```

**CESR** is KERI's compact encoding format. `toad` is the threshold of
accountable duplicity: the number of witness receipts required by the event.

An indexer may locate a candidate UTxO by policy and asset name, but it does
not establish authority. A consuming Cardano transaction must revalidate the
exact policy and quantity-one asset, an accepted checkpoint script and version,
the expected AID and a well-formed datum, and its own authorization rule. A
stale index result points to a spent input and fails; an indexer outage can
block discovery, but cannot create false authority.

## How lifecycle state is represented

### Shipped today: role addresses

State is carried by the script role address the token sits at, not by a
caller-controlled status field:

| Role | Meaning | Consumer result |
|---|---|---|
| ACTIVE | current checkpoint | may be considered, subject to all other checks |
| ARMED | a later-event challenge is open | reject |
| FROZEN | the delay bond was claimed | reject |

There is no conviction role: conviction burns the AID token and creates no
successor, so a consumer meets the no-candidate case. That follows from the
projection law — the chain never originates identity state, and no key event
says "this AID is dead" for a validator to project.

### After the M1 return: one bit and the value

The three roles go. What replaces them is smaller and reads directly off the
checkpoint a consumer already resolves:

| Condition | How it is represented | Consumer result |
|---|---|---|
| poisoned | one bit in the datum, set by the current quorum | reject |
| paused | `D_reg` and `B` absent — the owner withdrew | reject |
| frozen | `B` absent — a hunter took it | reject |
| juvenile | `now − born_at < W` | reject |
| convicted | a tombstone state, terminal | reject |
| closed | the UTxO is burned; the registry leaf is `closed(epoch, sn)` | no candidate |

Nothing there is a flag a caller can set. The poison is signed at the current
threshold; the rest are facts about what the UTxO holds and when it was bonded.
The consumer's whole predicate is: present, both bonds full, not poisoned,
older than `W`, and the payment's own signature satisfies the current
threshold.

## Uniqueness: the one shared object

Today there is none. Registration uses no absence proof, so more than one
candidate checkpoint can exist for an AID and a consumer cannot prove
otherwise.

The M1 return adds exactly one shared structure, and confines it to the
narrowest possible job: a **registry** mapping each AID to a leaf — absent,
`live`, `closed(epoch, sn)`, or `convicted`. A registration must prove absence
before inserting, which makes the token mint-once by construction. Register,
reopen, close and convict change the leaf; rotate, poison, freeze and top-up
never touch it, and consumers never read it.

It is a registry of 32-byte keys, not a record of events — the record tree and
its cursor are retired. Its mechanics are upstream work: MPFS made
permissionless, so requests are independent UTxOs anyone submits and anyone
applies in batches (ruling D-037). A stalled registry delays registrations and
forges nothing.

## Transaction architecture

The checkpoint is intentionally small. Heavy KERI verification runs in
operation-specific observer reference scripts:

```mermaid
sequenceDiagram
    participant R as Relayer
    participant C as Thin checkpoint
    participant O as Observer reference script
    participant L as Cardano ledger

    R->>L: transaction + checkpoint input/output
    R->>L: zero-lovelace observer withdrawal + envelope
    L->>C: evaluate state, token, value, observer claim
    L->>O: evaluate KERI evidence against the same transaction
    C-->>L: accept only the exact coupled transition
    O-->>L: accept only valid KERI evidence
    L-->>R: settle or reject atomically
```

The observer families shipped today are the lifecycle observer for Register,
the advance observer for rotations and ARMED responses, and the enforcement
observer for Freeze. The M1 return removes the third: `observer_advance`
verifies the evidence for both an advance and a freeze — they present the same
rotation and differ only in effect — and `checkpoint_register` dispatches that
effect.

The scripts are stored in reference-script outputs; copying them inline would
exceed the transaction-size limit. See
[Observer architecture](observer-architecture.md) for the wire shape, the
BLAKE3 fact token, sizes and costs — including the three bytes of headroom on
`observer_advance` that make every datum decision a measured one.

## Permissionless does not mean unauthenticated

Register, advance, freeze, top-up, poison relay and conviction may be submitted
by anyone because their result is fixed by public evidence. The submitter
cannot choose new keys, skip a sequence, lower a threshold, or remove required
witnesses.

Where authority *is* needed, it is a signature over exactly the thing being
decided. Today, close binds the refund address in a message the current
controllers sign. Under the M1 return the same principle covers more: every
bond option other than `keep`, and every new refund address, is signed by the
keys of the epoch the rotation opens — so a relayer landing a public rotation
can never park, age, or close the owner.

## Current boundary and future planes

The repository proves the identity-plane rungs on a protocol-11 development
network and on preprod. It does **not** provide the M1 return's machine on
chain at all, real three-of-seven GLEIF-scale settlement, a production
deployment or mainnet service, a vLEI credential-chain verifier, a credential
revocation mirror, or a wallet-to-Cardano authorization product.

The credential verifier, revocation state, value-cage authorization and wallet
integration remain later layers. They consume the checkpoint as a reference
input; they are not part of the identity story itself.

## Related pages

- [Story ladder](../story-ladder.md) — settled evidence, dated.
- [Roadmap](../roadmap.md) — the thirteen epics and what each measures.
- [Identity operations](identity-ops.md) — exact operation behavior, shipped
  and designed.
- [Observer architecture](observer-architecture.md) — reference-script
  composition and measured budgets.
- [Trust model](../design/trust-model.md) — guarantees, assumptions, and
  fail-closed boundaries.
