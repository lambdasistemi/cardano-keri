# Operational constraints

This page describes the sovereign per-AID checkpoint that has settled in the
small-identity stories. It does not describe the retired shared-registry
design.

## Per-identity serialization

Each KERI AID has its own checkpoint UTxO. An operation spends that UTxO and,
unless it closes or eventually becomes terminal, creates its successor.

Consequences:

- operations for different AIDs do not contend on one global state input;
- two transactions for the same AID still race for the same current UTxO;
- a losing transaction must resolve the new tip, rebuild, and re-evaluate; and
- no transaction builder can reserve the checkpoint ahead of settlement.

This is ordinary Cardano UTxO contention. It scales by identity rather than
globally.

## Transaction and script size

The protocol-11 development network uses:

- 16,384 bytes as the transaction-size limit; and
- 16,133 bytes as the applied reference-script budget.

The current architecture stores the checkpoint and observer programs in
reference-script UTxOs. Operation transactions refer to those outputs instead
of copying several validators inline.

Latest settled sizes:

| Program | Applied size |
|---|---:|
| Thin checkpoint | 9,155 bytes |
| Enforcement observer | 13,548 bytes |
| Advance observer | 16,130 bytes |

The Advance observer's 3-byte margin is a release blocker for further feature
work. [#149](https://github.com/lambdasistemi/cardano-keri/issues/149) must
create at least 1 KB of headroom before the real seven-key rotation.

## Execution budgeting

The transaction builder uses a two-pass process:

1. construct and evaluate the transaction;
2. measure every script purpose;
3. derive declared execution units with the configured margin;
4. prove the aggregate fits the protocol limit; and
5. rebuild and submit the exact transaction with those budgets.

Observed use and declared limits must be reported separately. A script fitting
alone is not enough if all scripts in the same transaction exceed the
aggregate.

## Reference-script lifecycle

Observers are Plutus stake scripts. A deployment must:

1. publish each exact script in a reference output;
2. register its stake credential;
3. preserve the output reference and script hash;
4. verify the reference transaction settled before building dependent
   operations; and
5. prevent the observer credential from being deregistered through an
   unsupported path.

Register, Advance, and Freeze use a zero-lovelace withdrawal to force the
configured observer to execute. See
[Observer architecture](../architecture/observer-architecture.md).

## Validity intervals

Freeze derives its deadline from the transaction's finite upper validity
bound plus the configured response window. An ARMED response must itself have
a finite upper bound strictly before that deadline.

Builders must query the current era history and choose a horizon-aware
interval. Accelerated development networks can have a much shorter forecast
horizon than a production network; fixed wall-clock offsets caused real
`PastHorizon` failures during the story work.

## Indexer and discovery behavior

The AID-derived policy and asset name let any node or indexer locate candidate
checkpoint UTxOs. The result is a convenience for liveness, not authority.

Operational clients should:

- query more than one source when practical;
- revalidate the token, script, datum, AID, and role against the ledger;
- refresh immediately when the outref is already spent;
- fail closed on zero or multiple ACTIVE candidates; and
- never pick a candidate by indexer ordering.

An indexer outage blocks construction. It does not permit fallback to stale or
unverified authority.

## Settlement and monitoring

Submitting a transaction is not settlement. A production operator must track:

- mempool acceptance;
- inclusion in a block;
- the chosen confirmation depth;
- rollback and resubmission;
- the current unspent checkpoint output;
- reference-script availability; and
- KERI events that have not yet reached the checkpoint.

High-value applications must define both Cardano settlement depth and a KERI
freshness policy. Neither is universal.

## Funding

ACTIVE and ARMED require:

```text
checkpoint minimum ADA + D_reg + B
```

Close refunds the complete checkpoint value to the signed address. A future
timeout Claim pays exactly `B` to the recorded hunter and leaves
`minimum + D_reg` in FROZEN. A thaw must add a new `B`.

Anyone may fund permissionless Register or thaw, but funding does not create a
refund right. Commercial relayers need an off-chain payment arrangement.

## Current deployment boundary

The settled stories run on an ephemeral private development network. A
production deployment still needs:

- final validator parameters and economic analysis;
- durable reference-script publication;
- public network addresses and policy IDs;
- redundant KERI event discovery;
- checkpoint/indexer monitoring;
- incident procedures;
- mainnet execution and fee measurements; and
- completion of Claim/thaw, Convict, and the real-scale ladder.
