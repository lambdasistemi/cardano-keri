# cardano-keri

cardano-keri projects a rotating KERI identity into a stable Cardano
checkpoint.

!!! tip "Play the design before you read it"
    The M1 design is a proved Lean machine, and the two simulations below are
    transcriptions of it, checked against the Lean by replay on every step.
    Pick a story and play it; every refusal names the rule that refused.

    - **[The checkpoint simulator](simulator/index.html)** — one identity, its
      keys, its three sums of money, the hunters, the treasury: fifteen
      stories with their forks, the theorems lighting up as you play.
    - **[The registry simulator](simulator/registry/index.html)** — one incarnation per
      identity: requests, batches, the gating plugin, the leaf every
      identity has.

**KERI** is Key Event Receipt Infrastructure, the identity protocol used by
the Global Legal Entity Identifier Foundation's verifiable LEI ecosystem. A
KERI **AID** (Autonomic Identifier) keeps its identity while its controller
keys rotate. Cardano applications can refer to the AID-derived checkpoint
token instead of permanently binding themselves to one key.

## How to read these pages

The project is mid-way through the **M1 return**: a design settled in
September 2026 that keeps the checkpoint, adds a poison and a registry, and
removes the enforcement economy that `main` still carries. So every claim in
these docs is in one of three states, and each page says which one it is
making:

| State | What it means | Where it lives |
|---|---|---|
| **Shipped on `main` today** | Code you can run, or a program published on preprod | `onchain/`, `offchain/`, `deploy/preprod/m1-manifest.json` |
| **Accepted design** | Proved in Lean and playable in the simulator; no on-chain code yet | `lean/CardanoKeri/Checkpoint.lean`, 87 theorems in `CheckpointGoals.lean`, no `sorry` |
| **Planned** | An epic with an issue number and an acceptance criterion | the [roadmap](roadmap.md) |

Nothing here that is only designed is described as if it were deployed.

---

## Shipped on `main` today

Five applied programs are published as reference scripts on Cardano preprod
(`deploy/preprod/m1-manifest.json`, published 2026-07-28 from commit
`50a5820`):

| Program | Role | Size |
|---|---|---|
| `hash-proof` | minting policy | 9,233 B |
| `observer-lifecycle` | withdrawal observer | 6,523 B |
| `observer-advance` | withdrawal observer | 16,130 B |
| `observer-enforcement` | withdrawal observer | 14,417 B |
| `checkpoint-register` | validator and minting policy | 11,512 B |

Deployment parameters: registration bond 1,000 tADA, freeze bond 5 tADA,
freeze window 10,000 slots.

The checkpoint datum is **pure key state** — nine fields, no lifecycle flag:
the AID, current keys and threshold, next-key commitments and next threshold,
witnesses and `toad`, the Cardano sequence, and the native KERI sequence
(`onchain/lib/cardano_keri/checkpoint/datum.ak`). Enforcement state is carried
by role addresses around the same token.

The packaged `ckeri` exposes `deploy`, `manifest verify`, `register`,
`advance`, `close`, `status`, `list`, `checkpoint`, `payer`, and the five
`board` verbs. It does **not** expose freeze, claim, or convict: those
transactions exist only in the end-to-end harness.

!!! success "The transaction path does not require cardano-cli"
    The packaged `ckeri` can deploy the reference scripts, register an
    identity, advance a rotation, post/update/retire endpoint-board
    records, and close a checkpoint on a machine with no `cardano-cli`
    installed at all. Its runtime closure does not include
    `cardano-cli`; a closure check enforces that boundary and has been
    demonstrated to fail when the retired dependency is reintroduced.

!!! success "Current evidence"
    Settled on preprod on 2026-08-06 with a genuine KLI identity:
    registration `6ecc2e07…`, advance `f0f3a18f…`, close `446f0d83…`.
    Earlier, on a protocol-11 development network running production
    transaction limits, a two-key identity settled Register, Close,
    Advance, and two Freeze/response rounds. Dates, transaction IDs
    and their sources are on the [story ladder](story-ladder.md).
    Separately, a witnessed 2-of-5 KLI identity has registered and
    advanced its live V1 checkpoint on preprod; see
    [Rotate your identity](user/rotate-preprod-identity.md).

!!! warning "Not a production deployment"
    Settled development-network and preprod transactions prove the
    vertical path through the production validators and the node
    boundary. They do not make this a mainnet service. Claim/thaw,
    conviction, real three-of-seven scale, full vLEI credentials, and
    wallet integration still have open stories.

---

## The accepted design: the M1 return

The design settled between 2026-09-02 and 2026-09-03 (project rulings D-022 to
D-040). It is proved in `lean/CardanoKeri/Checkpoint.lean` — 87 theorems in
`CheckpointGoals.lean`, no `sorry`, standard axioms only — and the
simulator above is a transcription of that Lean, checked by replay.

**One UTxO per identity**, holding the current key state, a token minted once
and never again, and three sums of money that never mix:

- `D_reg`, the **conviction bond** — the stake a duplicity proof seizes. Never
  a fee source.
- `B`, the **freeze bond** — what a hunter takes when the pool cannot pay for a
  rotation.
- the **pool** — advance funds; pays the premium `P` to whoever lands a
  rotation.

**Three states, no withdraw.** An identity is **active** (the checkpoint UTxO
exists: live, poisoned or frozen), **parked** (no UTxO; the registry leaf
holds the hash of the last checkpoint) or **convicted** (terminal). A
rotation is the only thing that moves the keys; it carries a bond option
(`keep` or `deposit`) and optionally a new refund address. `deposit` is
the unfreeze: it refills `B` when a hunter has taken it. Every option
other than `keep`, and every new refund address, is signed by the keys of
the epoch the rotation opens (D-038) — so a relayer landing a public
rotation can never park, age, or close the owner.

```mermaid
stateDiagram-v2
    [*] --> Absent
    Absent --> Active : register — registry insert, once ever
    Active --> Active : rotate — next keys + toad receipts, clears the poison
    Active --> Active : poison — current quorum, once per epoch
    Active --> Active : freeze — anyone, when the pool is short
    Active --> Active : deposit — next keys refill B (the unfreeze)
    Active --> Active : top-up — anyone
    Active --> Convicted : convict — a duplicity proof; D_reg to the convictor
    Active --> Parked : close — reap by the next keys; leaf holds the hash
    Parked --> Active : reopen — witnessed rotation from that key state
    Parked --> Convicted : convict parked — a duplicity proof against the hash
    Convicted --> [*]
```

**The poison** is the piece that is genuinely new: a declaration signed by the
current keys at their own threshold, over a short preimage bound to the
policy, the AID and the sequence. Anyone may relay it; it is never witnessed.
It makes the checkpoint unconsumable, and any witnessed rotation clears it —
it belongs to the epoch of the keys that signed it, because in KERI possession
of the next keys *is* control. It buys the owner the window between noticing a
theft and rotating.

**The registry** is one leaf per AID — absent, live (the token is on chain),
parked with the hash, or convicted — so an AID has at most one incarnation
ever. Only **convicted** is terminal; a parked identity returns by a
witnessed rotation later than the parked key state, with fresh bonds. The
registry is the MPFS cage made permissionless (D-037), built today in
[singular](https://github.com/lambdasistemi/singular), where it runs on a
development network; see
[where the registry is built](design/registry-as-mpfs.md#where-the-registry-is-built).

**Leaving** is the reap: a witnessed rotation by the *next* keys whose
signed message names the payee of the premium and the refund address. The
current keys keep exactly one Cardano power, the poison. Close answers to
the next keys, never the current ones.

**The consumer's rule**, and the only thing outside the machine: authorize iff
the checkpoint is present, both bonds are full, it is not poisoned, it is
older than the juvenility window `W`, and the payment's own signature
satisfies the current threshold. Everything else fails closed.

### What the return removes

The record tree and its cursor, occupancy maps, the MPF fork and its upstream
proposal, `ever_duplicitous`, and the whole ARMED/FROZEN enforcement economy —
freeze-for-lag, the bounty, the entitlement, the reap. Interaction events
(`ixn`) never touch the chain. Delegated identities are a later milestone.

The freeze that survives is a different thing: it is what a hunter takes when
the owner's pool has run dry, not a punishment for lag.

---

## What is planned

The M1 return is one milestone across two repositories, thirteen epics. The
[roadmap](roadmap.md) carries the ordering, the dependencies and the
measurements that size the numbers still open. The short version: slim `main`
(#319), measure it (#321), build the owner's edges (#322) and the hunter's (#323),
integrate the registry (#324), put every role behind a `ckeri` command (#325),
replay the fifteen stories as the acceptance suite (#326), and cut over preprod
(#328).

---

## Start here

- [Why Cardano](why-cardano.md) — how this differs from anchoring a KEL on a
  ledger, and what non-oracular trust buys.
- [Story ladder](story-ladder.md) — what has actually settled, dated.
- [Roadmap](roadmap.md) — the M1 plan and its thirteen epics.
- [KERI primer](keri-primer.md) — AIDs, key events, pre-rotation, witnesses,
  and Veridian.
- [The KERI specification](https://trustoverip.github.io/kswg-keri-specification/) — KERI 1.1 as published by the Trust over IP
  working group; every story page links the clause it relies on, at the
  version the [watcher conformance review](design/watcher-conformance.md)
  pins.
- [Identity operations](architecture/identity-ops.md) — the operations, one by
  one, shipped and designed.
- [Observer architecture](architecture/observer-architecture.md) — thin
  checkpoints, reference scripts, zero-lovelace withdrawals, and the BLAKE3
  premint fact token.
- [Register](user/register-preprod-identity.md) — Alice's identity appears
  on Cardano.
- [Rotate](user/rotate-preprod-identity.md) — Alice rotates, Hal lands it.
- [Poison](user/poison.md) — Mallory steals the current keys.
- [Close, reopen, revival](user/reopen-revival.md) — Alice leaves and
  comes back.
- [Hunters](user/hunters.md) — the pool, the freeze, two hunters racing.
- [Consumer checklist](user/consumer-checklist.md) — the treasury reads
  the checkpoint.
- [ACDC primer](acdc-primer.md) — the separate credential layer.

For the financial and institutional concepts behind the later use cases, see
the [Finance primer](finance-primer.md).

## The engineering constraint

`observer-advance` measures 16,130 bytes against a 16,133-byte applied-script
limit — three bytes of headroom. The M1 return's datum change lands on exactly
that script, which is why epic #319 ends with a size table and epic #322's datum
decisions are taken from it rather than from taste. Two things move in the
plan's favour: the advance observer's ARMED-response branch goes, and the
three enforcement role addresses go from `checkpoint_register`. The net effect
is unmeasured until #319.

Full measurements are in
[Observer architecture](architecture/observer-architecture.md#measured-sizes-and-costs).

## Real-world direction: vLEI

The longer-term goal is to let Cardano applications combine:

- a current, consumable AID checkpoint;
- an ACDC credential chain proving a legal or organizational role; and
- current TEL non-revocation evidence.

Registering an AID answers "which keys control this identifier?" It does not
answer "which legal entity is this?" The latter is a credential claim and
remains a later roadmap layer. See the [vLEI design](design/vlei.md) and the
[roadmap](roadmap.md).
