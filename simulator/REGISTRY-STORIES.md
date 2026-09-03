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
  end of time: never phase 2; the cage would reject it (a future timestamp is
  rejectable) but the plugin refuses; only processed.

Deployment values used by every story: `D` = 1000, `tip` = 2, checkpoint
min-ADA `Mc` = 4, request min-ADA `Mr` = 1, `process_time` = 10,
`retract_time` = 10, grace `W` = 5 slots, plugin 7.

## The stories

Each story is a tree: a trunk and the branches where an attempt is refused or
the world differs. The bullets are the checked prose: every clause of
**The chain checks**, **Money** and **Refused** is a row of
`registry-simulator-clauses.json`, tied to a declaration of the Lean and to a
step of the story's scenario or a refusal name; the scenario gate reconciles
them both ways. Everything else is narrative.

## 1. Alice posts a registration request

Anyone holding Alice's public inception creates a request UTxO at the cage: her AID, her refund address as owner, the bond D and the tip. Nothing contends; the registry is untouched.

Branches: ⋔ Mallory posts a go-request by hand.

- **The chain checks**: a request may be posted for register, revive and convict; the registry is not spent.
- **Money**: the bond and the tip go into the request.
- **Refused**: a go-request posted by hand is refused.

## 2. Hal folds it: a leaf, a checkpoint, a tip

Hal spends the registry at generation 0. Alice's request is in phase 1, her inception verifies, her AID has no leaf: the leaf active(token 0) is inserted, the checkpoint token minted, her bond locked into the checkpoint, the tip paid to Hal.

- **The chain checks**: the fold names the current generation; the plugin is pinned; the request is in phase 1; the inception verifies; the AID has no leaf; the leaf is inserted active with the minted token; the generation moves by one.
- **Money**: the bond is locked into the checkpoint; the tip per request goes to the folder.

## 3. Two folders race

Alice and Bob both post. Hal's fold at generation 0 lands both. Mallory's identical fold is refused as stale — on chain, a spent input, at no cost. Rebuilt against generation 1, her batch is empty and refused.

Branches: ⋔ Mallory's fold lands first.

- **The chain checks**: the fold names the current generation; a fold carries no signature.
- **Refused**: a fold at a spent generation is refused; an empty batch is refused.

## 4. Mallory registers Alice's AID again

With Alice registered, Mallory posts a registration for the same AID. No fold can process it: the absence proof fails against a root that holds the leaf. Her request waits for phase 3, when anyone rejects it and her bond goes back to her.

Branches: ⋔ Sam rejects Mallory's request in phase 1.

- **The chain checks**: after phase 2 anyone rejects; the rejected request leaves the inbox.
- **Money**: the bond returns to the request owner; the tip goes to the folder.
- **Refused**: registering an AID that has a leaf is refused; rejecting in phase 1 is refused.

## 5. Nobody folds; Alice retracts in phase 2

Phase 1 passes with no fold. In phase 2 Alice spends her own request back: bond and tip return to her, and the registry is never touched. Before phase 2 the retract is refused; after it the request is gone.

Branches: ⋔ Sam tries to reject in phase 2.

- **The chain checks**: only in phase 2 may a request be retracted; the owner signs the retract; the request leaves the inbox.
- **Money**: bond and tip return to the owner.
- **Refused**: a retract before phase 2 is refused; a retract of a request that is gone is refused; a reject in phase 2 is refused.

## 6. Alice missed phase 2; Sam sweeps

The request passed phase 2 unretracted. Under an owner-keyed cage it would now be stranded; here anyone rejects it: Sam spends the registry with a batch of one reject, Alice's bond goes back to her, Sam takes the tip. Before phase 3 the same reject is refused.

Branches: ⋔ Alice retracts in phase 2 after all.

- **The chain checks**: after phase 2 anyone rejects; a fold carries no signature.
- **Money**: the bond returns to the request owner; the tip goes to the folder.
- **Refused**: rejecting in phase 1 is refused; a retract after phase 2 is refused.

## 7. An empty fold is refused

A fold with no request would re-create the registry unchanged for the price of a fee, moving its generation and invalidating every fold built against it. It is refused. A process in phase 2 is refused too; nobody folds in phase 1, and Alice retracts in phase 2.

- **The chain checks**: a retract in phase 2 applies.
- **Refused**: an empty batch is refused; a process outside phase 1 is refused.

## 8. A fold that swaps the plugin is refused

Mallory folds Alice's request correctly but re-creates the cage with plugin 8, an always-true script she controls. The plugin is pinned: refused. A request whose inception does not verify is refused by the plugin.

Branches: ⋔ Mallory keeps the plugin: a stranger's fold is as good as Hal's.

- **The chain checks**: a stranger's fold with the pinned plugin applies.
- **Refused**: a fold that re-creates the cage with another plugin is refused; a registration whose inception does not verify is refused.

## 9. Alice pauses and resumes without touching the registry

Alice's next keys withdraw her bonds: the checkpoint stays on chain, parked, at min-ADA, with the key state a revival must rotate from. Later a depositing rotation makes it live again. The registry leaf never changed; the indirection is the token, which survives every rotation. A pause without the next keys, and a resume of a live checkpoint, are refused.

Branches: ⋔ Cora convicts the parked checkpoint.

- **The chain checks**: a pause needs a live checkpoint; and a witnessed rotation from its key state; the parked checkpoint records the next key state and the slot; the registry is not spent; a resume needs a parked checkpoint; and a rotation from its key state.
- **Money**: no value moves on a pause or a resume.
- **Refused**: resuming a live checkpoint is refused; pausing a parked one is refused; pausing without the rotation is refused; convicting without a proof is refused.

## 10. Alice leaves; after the grace window Sam reaps her parked checkpoint

Alice parks and never comes back. Inside the grace window a stranger cannot reap. After it Sam spends the parked checkpoint, burns the token, keeps min-ADA less the go-request as premium, and posts the go-request dated at the end of time. Hal folds it: the leaf becomes dormant(1), the key state a revival must rotate from; Sam gets the request's min-ADA back.

Branches: ⋔ Alice resumes inside the grace window.

- **The chain checks**: a live checkpoint is never reapable; a stranger reaps a parked checkpoint only after the grace window; the token is burned and the checkpoint leaves the chain; the go-request is dated at the end of time; the go-request makes the leaf dormant at the parked key state; a leaf changes only by a fold.
- **Money**: the reaper keeps the min-ADA less the go-request; the go-request is funded from the checkpoint; the fold returns the go-request's min-ADA to the reaper.
- **Refused**: reaping a live checkpoint is refused; reaping inside the grace window is refused; reaping an AID without a checkpoint is refused.

## 11. Alice comes back from dormant

Her leaf says dormant(1). She posts a revive request with the bond and a witnessed rotation from key state 1; Hal folds it: a new token is minted (token 2 — Bob took token 1), a live checkpoint at key state 2 is funded from her bond, the leaf is active(2). A revive of an AID that is not dormant is refused; a revive without the rotation is refused on the branch where Mallory tries it.

Branches: ⋔ Mallory's revive carries no rotation from key state 1.

- **The chain checks**: the owner reaps her parked checkpoint at any time; a revive needs a dormant leaf; a witnessed rotation from the recorded key state; and no checkpoint on chain; a new token is minted into a live checkpoint at the next key state; the leaf is active with the new token.
- **Money**: the bond is locked into the checkpoint.
- **Refused**: reviving an AID that is not dormant is refused; reviving without the rotation is refused.

## 12. Cora convicts Bob; the tombstone is reaped; Bob never returns

Cora presents a duplicity proof against Bob's live checkpoint: it becomes a tombstone and the registry is not spent. Sam reaps the tombstone at once — no grace for a convicted identity — and Hal folds the go-request: the leaf is convicted, for ever. A second conviction, a registration and a revival of Bob's AID are all refused.

Branches: ⋔ Cora has no proof.

- **The chain checks**: a checkpoint conviction needs a duplicity proof against its key state; the checkpoint becomes a tombstone; the registry is not spent; a tombstone is reapable at once; the go-request convicts the leaf; a convicted leaf never changes.
- **Money**: the reaper keeps the min-ADA less the go-request; the fold returns the go-request's min-ADA to the reaper.
- **Refused**: convicting a tombstone is refused; registering a convicted AID is refused; reviving it is refused; convicting without a proof is refused.

## 13. A dormant AID is convicted by a proof against its recorded key state

Bob parked and was reaped: dormant(1). Cora posts a conviction request with a duplicity proof against key state 1; Hal folds it and the leaf is convicted. A conviction request for an active AID is refused: a live checkpoint is convicted through its own edge. On the branches the go-request and the conviction share one fold, with and without the proof.

Branches: ⋔ The go-request and the conviction in one fold; ⋔ The same fold without the proof.

- **The chain checks**: a conviction request needs a dormant leaf; and a duplicity proof against its recorded key state; the leaf is convicted; the proof is checked against the accumulator the fold reached.
- **Money**: the request's min-ADA returns to the convictor.
- **Refused**: convicting an active AID through a request is refused; convicting without the proof is refused.

## 14. A go-request can neither be retracted nor rejected

Mallory reaps Alice's parked checkpoint and then tries to make the key state disappear: retracting her own go-request is refused, because it is dated at the end of time and phase 2 never comes; rejecting it is refused by the plugin, wherever it sits in a batch. The only way out of the inbox is to be processed, and anyone can do that.

- **The chain checks**: a go-request is dated at the end of time; phase 2 never comes for it; the plugin refuses to reject it; it is processed by anyone.
- **Money**: the reaper's min-ADA returns when it is processed.
- **Refused**: retracting a go-request is refused; rejecting it inside a batch is refused.

## 15. A batch that names a request twice, and a request dated in the future

A fold lists Alice's request twice: the first entry consumes it, the second finds nothing, the whole fold is refused. Mallory writes submitted_at = 100 at slot 0: in phase 1 until slot 110 and rejectable at once, because a future timestamp is dishonest by definition; Sam rejects it.

Branches: ⋔ Sam rejects Alice's honest request too.

- **The chain checks**: a future timestamp is rejectable at once.
- **Money**: the bond returns to the request owner.
- **Refused**: a batch that names a request twice is refused.

## What is deliberately not here

Rotations that keep a checkpoint live, poison, the freeze bond and the pool:
the checkpoint simulator. No cryptography: evidence is a table. No fees: the
samaritan theorems carry the fee as a parameter. No receipt token: the
go-request is created by the reap itself in this model.
