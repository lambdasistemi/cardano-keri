# The Registry Stories

The AID registry of D-024, built as a cage of cardano-mpfs-onchain on the
plugin path, told as the things people do to it. Every story names what the
chain checks and what money moves. The machine behind them is
`lean/CardanoKeri/Registry.lean`; the theorems are
`lean/CardanoKeri/RegistryGoals.lean`; the simulator replays every story
against both.

## The cast

- **Alice**, **Bob**, **Carol** — owners of AIDs 11, 12, 13. They post
  requests and, when they must, retract or close.
- **Hal** — a folder. He watches the inbox, builds folds, and collects tips.
- **Mallory** — a stranger with a transaction builder and no scruples.
- **Cora** — a convictor holding a duplicity proof.
- **Sam** — a sweeper: anyone who rejects expired requests for the tip.

## The words

- **registry** — one UTxO holding the MPF root of every registered AID, its
  generation (which spend of it is current) and the plugin it delegates to.
- **request** — an inbox UTxO: an AID, an owner, the bond `D`, the tip, and a
  `submitted_at` the requester wrote.
- **fold** — a permissionless `Modify`: spend the registry at its current
  generation with a non-empty batch, each request processed or rejected.
- **process** — phase 1, inception evidence, the AID absent from the root:
  the row is inserted, the token minted, the bond locked into the
  checkpoint, the tip paid to the folder.
- **reject** — phase 3 (or a future timestamp): the bond goes back to the
  owner, the tip to the folder.
- **retract** — phase 2, the owner only: bond and tip go back, the registry
  is not touched.
- **close** — the checkpoint's current quorum burns the token and deletes the
  row in the same transaction.
- **convict** — a duplicity proof turns the token into a tombstone; the row
  stays.
- **phases** — from `submitted_at`: phase 1 for `process_time` slots, phase 2
  for `retract_time` slots, phase 3 after. A future `submitted_at` is in
  phase 1 and rejectable at once.

Deployment values used by every story: `D` = 1000, `tip` = 2,
`process_time` = 10, `retract_time` = 10 slots, plugin 7.

## The stories

1. **Alice posts a request.** Anyone holding her inception creates the
   request. The registry's generation does not move: a request never spends
   the cage.
2. **Hal folds it and is paid the tip.** Phase 1, inception verifies, AID
   absent: row inserted, token minted, 1000 locked into her checkpoint, 2 to
   Hal. Mallory's close without Alice's keys is refused.
3. **Two folders race.** Alice and Bob both post. Hal's fold at generation 0
   lands both. Mallory's identical fold is refused as stale — on chain, a
   spent input, at no cost. Rebuilt against generation 1, her batch is empty
   and refused.
4. **Mallory registers Alice's AID again.** The absence proof fails against a
   root that holds the row. Her request waits for phase 3, when Sam rejects
   it and her bond returns.
5. **Nobody folds; Alice retracts in phase 2.** Too early is refused; in
   phase 2 she gets 1002 back; the registry never moved.
6. **Alice missed phase 2; Sam sweeps.** Anyone rejects the expired request:
   1000 to Alice, 2 to Sam. No owner key anywhere.
7. **An empty fold is refused.** A no-op respend would churn the generation
   for a fee; the machine does not allow it.
8. **A fold that swaps the plugin is refused.** The plugin is pinned.
9. **Alice closes and later returns.** Close burns the token and deletes the
   row; a fresh request is then processed and she is back.
10. **Cora convicts Bob; Bob can never return.** The tombstone keeps the row.
    A new request for his AID fails the absence proof forever; the tombstone
    cannot be closed; the request is rejected in phase 3.
11. **One fold processes Bob and rejects Alice.** Mixed batches are one
    transaction: one lock, one refund, two tips.
12. **The phases refuse what they should.** A reject in phase 1 and a process
    in phase 2 are both refused; the retract lands.
13. **A request whose inception does not verify.** The plugin refuses the
    process; the request is rejectable in phase 3.
14. **A request dated in the future.** In phase 1 for a hundred slots and
    rejectable at once; Sam rejects it. A process would also have been
    accepted: the folder decides, as on chain.
15. **A batch that names one request twice.** The second entry finds nothing
    in the inbox; the whole fold is refused; the honest fold lands.

## What is deliberately not here

The checkpoint's own life — rotations, bonds, poison — is the checkpoint
simulator. No cryptography: evidence is a table. No fees. No oracle.
