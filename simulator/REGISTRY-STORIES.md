# The Registry Stories

The AID registry of D-024, built as a cage of cardano-mpfs-onchain on the
plugin path, after the rulings of 2026-09-02/03: a leaf per AID that says
active, dormant or convicted; checkpoints that come and go; requests that
never contend; folds that race; reaps that pay for themselves. Told as the
things people do to it. Every story names what the chain checks and what
money moves. The machine is `lean/CardanoKeri/Registry.lean`; the theorems
are `lean/CardanoKeri/RegistryGoals.lean`; the simulator replays every story
against both.

## The cast

- **Alice**, **Bob**, **Carol** — owners of AIDs 11, 12, 13.
- **Hal** — a folder. He watches the inbox, builds folds, collects tips.
- **Mallory** — a stranger with a transaction builder and no scruples.
- **Cora** — a convictor holding duplicity proofs.
- **Sam** — a reaper: anyone who cleans up bondless checkpoints for their
  min-ADA, and rejects expired requests for the tip.

## The words

- **registry** — one UTxO holding the MPF root: one leaf per AID, its
  generation (which spend of it is current), the plugin it delegates to.
- **leaf** — `active(token)` while a checkpoint carries that token;
  `dormant(k)` when the checkpoint has left the chain and `k` is the key
  state a revival must rotate from; `convicted` for ever.
- **checkpoint** — the AID's own UTxO: `live` (bonded), `parked` (bonds
  withdrawn by a rotation, at min-ADA, since some slot), `tombstone`
  (convicted, at min-ADA).
- **request** — an inbox UTxO: an AID, an owner, a bond, the tip, a
  `submitted_at` the requester wrote, and what it asks: `register`, `revive`,
  `convict` (a dormant AID) — or a **go-request**, `go → dormant(k)` /
  `go → convicted`, which only a reap can create.
- **fold** — a permissionless `Modify`: spend the registry at its current
  generation with a non-empty batch, each request processed or rejected. The
  cage applies the leaf operation; the plugin admits it with its evidence and
  couples the mint.
- **reap** — spend a bondless checkpoint, burn its token, post the go-request
  funded from its min-ADA, keep the rest as premium. A parked checkpoint:
  after the grace window, or by the owner at any time. A tombstone: at once.
- **phases** — from `submitted_at`: phase 1 for `process_time` slots (a fold
  may process), phase 2 for `retract_time` slots (only the owner may
  retract), phase 3 after (anyone may reject). A go-request is dated at the
  end of time: never phase 2, never rejectable, only processed.

Deployment values used by every story: `D` = 1000, `tip` = 2, checkpoint
min-ADA `Mc` = 4, request min-ADA `Mr` = 1, `process_time` = 10,
`retract_time` = 10, grace `W` = 5 slots, plugin 7.

## The stories

1. **Alice posts a registration request.** The generation does not move.
   Mallory posts a go-request by hand: refused, only a reap creates one.
2. **Hal folds it.** Phase 1, inception verifies, no leaf: leaf active(0),
   checkpoint token 0 minted, 1000 locked into it, 2 to Hal.
3. **Two folders race.** Hal's fold lands both requests; Mallory's identical
   fold is stale; her empty rebuild is refused.
4. **Mallory registers Alice's AID again.** The absence proof fails against
   a leaf. In phase 3 Sam rejects her request and her bond returns.
5. **Nobody folds; Alice retracts in phase 2.** Too early is refused; in
   phase 2 she gets 1002 back; the registry never moved.
6. **Alice missed phase 2; Sam sweeps.** In phase 1 a reject is refused; in
   phase 3 anyone rejects: 1000 to Alice, 2 to Sam.
7. **An empty fold is refused,** and so is a process in phase 2.
8. **A fold that swaps the plugin is refused,** and so is a registration
   whose inception does not verify.
9. **Alice pauses and resumes without touching the registry.** The parked
   checkpoint keeps key state 1; a depositing rotation makes it live at key
   state 2. Pausing a parked checkpoint, resuming a live one, pausing without
   the next keys, convicting without a proof: all refused.
10. **Alice leaves; after the grace window Sam reaps.** A live checkpoint is
    not reapable; inside the grace window a stranger cannot reap; after it
    Sam burns the token, keeps 1 as premium, posts the go-request with 3, and
    Hal's fold makes the leaf dormant(1), returning Sam's 1.
11. **Alice comes back.** She reaps her own parked checkpoint early with her
    keys; once dormant, her revive request with a rotation from key state 1
    mints token 2 into a live checkpoint at key state 2. A revive of an
    active AID, and a revive without the rotation, are refused.
12. **Cora convicts Bob; the tombstone is reaped; Bob never returns.** The
    live checkpoint becomes a tombstone without a registry write; Sam reaps
    it at once; the leaf is convicted. Registration and revival of his AID
    are refused for ever; a second conviction of the tombstone is refused.
13. **A dormant AID is convicted by a proof against its recorded key
    state.** Cora's conviction request against dormant(1) is folded. A
    conviction request against an active AID is refused: live checkpoints
    are convicted through their own edge.
14. **A go-request cannot be bricked.** Mallory reaps and then tries to make
    the key state disappear: retracting the go-request is refused (phase 2
    never comes), rejecting it inside a batch is refused by the plugin. The
    only way out of the inbox is to be processed, by anyone.
15. **A batch that names a request twice, and a request dated in the
    future.** The second entry finds nothing; the whole fold is refused. A
    future timestamp is rejectable at once.

## What is deliberately not here

Rotations that keep a checkpoint live, poison, the freeze bond and the pool:
the checkpoint simulator. No cryptography: evidence is a table. No fees: the
samaritan theorems carry the fee as a parameter. No receipt token: the
go-request is created by the reap itself in this model.
