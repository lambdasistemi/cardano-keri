# Convicting a witnessed fork

!!! note "What ships, and the accepted design"
    This page describes the M1 code as deployed on preprod. The accepted design of 2026-09-02/03 (decisions D-036 to D-040, modelled in `lean/CardanoKeri/Checkpoint.lean` and playable in the [checkpoint simulation](../simulator/index.html)) changes the lifecycle it describes: an identity is **active** (one checkpoint UTxO: live, poisoned or frozen), **parked** (no UTxO; the registry leaf holds the hash of the last checkpoint, its key state) or **convicted** (the mark, terminal). There is no pause, no withdraw and no unbonded checkpoint on chain. Leaving is the **reap**: a witnessed rotation by the *next* keys whose signed message names the payee of the premium and the refund address; the premium goes to that payee, everything else to the refund address, the token burns, and the leaf is parked with the hash. Coming back is a **revival**: a witnessed rotation from exactly the parked key state, with fresh bonds, born juvenile. A close authorized by the current keys alone, as below, is what ships today, not the accepted design.

Conviction is the terminal response to a KERI identity publishing two
irreconcilable histories. It is not a response to ordinary delay. A
permissionless submitter may relay the proof, but the validator decides
whether that proof is a fully witnessed conflict and fixes every payout.

## Delay and divergence are different failures

The checkpoint holds two economically separate reserves:

| Reserve | What it polices | What releases it |
|---|---|---|
| Delay bond `B` | A checkpoint failed to answer a later-event challenge before its deadline | An unanswered `ClaimFreeze` pays the recorded hunter; a thaw posts a fresh `B` |
| Divergence bond `D_reg` | The identity published a witnessed, irreconcilable fork | A valid `Convict` pays the convictor as part of burning the checkpoint |

A slow identity may still be honest, so a timeout takes only `B`. Conviction
requires stronger evidence: a conflicting KERI event with the applicable
controller signatures and enough witness receipts to show that the fork was
published. A private signed draft or an event that merely repeats the recorded
history cannot convict.

## One atomic terminal edge

A successful Convict transaction performs all of these actions together:

1. names the exact ACTIVE, ARMED, or FROZEN checkpoint input;
2. validates the conflicting event in the enforcement observer;
3. burns exactly the checkpoint's quantity-one AID token;
4. creates no continuing checkpoint-role output; and
5. pays the exact source-state amounts below.

The settled transaction is the tombstone record. Its spent input, Convict and
ConvictBurn redeemers, witnessed evidence, token burn, and payouts remain in
Cardano's history. There is deliberately no surviving TOMBSTONE UTxO: an
unspendable checkpoint output would permanently retain value while serving no
protocol purpose.

Applications therefore do not discover a terminal datum. They discover that
the formerly current checkpoint outref was spent and that its AID token no
longer exists at any checkpoint role.

## Exact value by source state

`checkpoint minimum ADA` is the ledger reserve held alongside the two protocol
bonds. Convict distributes that minimum too, so no value remains trapped.

| Source | Protected value before Convict | Convictor receives | Recorded hunter receives |
|---|---:|---:|---:|
| ACTIVE | `minimum + D_reg + B` | exactly `minimum + D_reg + B` | nothing |
| ARMED | `minimum + D_reg + B` | exactly `minimum + D_reg` | exactly `B` |
| FROZEN | `minimum + D_reg` | exactly `minimum + D_reg` | nothing; `B` was already claimed |

The ARMED outputs are separately indexed even if the convictor and recorded
hunter happen to use the same payment key. Each selected output must be
datum-free and lovelace-only. FROZEN cannot pay a second delay reward because
its `B` left the checkpoint in the earlier ClaimFreeze transaction.
If a checkpoint input also carries lovelace above the protected value shown in
the table, that surplus remains ordinary transaction change. It is not added
to either protocol payout.

## What evidence is sufficient

The Convict observer binds the candidate event to the AID and the exact
checkpoint tip. It then checks that:

- the event is a genuine KERI rotation at the same native sequence as the
  recorded event;
- it conflicts in the key-state commitments that make the two histories
  irreconcilable;
- the prior controller threshold signed it; and
- distinct witness receipts satisfy the checkpoint's witness threshold.

Removing the witness receipts makes the event unwitnessed and invalid.
Submitting the already-recorded event is also invalid because it supplies no
conflict. A caller cannot replace these facts with a beneficiary choice: the
redeemer names output positions, while the spent state and validator parameters
determine the recipients and amounts.

## Re-registration after conviction

Burning terminates this checkpoint token, not the KERI AID's existence. The
protocol keeps no global “convicted forever” UTxO or once-ever registration
flag. A genuine inception proof may therefore register the same AID again,
minting a fresh quantity-one checkpoint token and posting fresh `D_reg + B`.

Consumers must still follow their own history and risk policy. The new ACTIVE
checkpoint is current on Cardano; the old conviction transaction remains an
immutable fact that an indexer or application may surface when deciding
whether to trust the re-registered identity.

Re-registration does not erase the fork, refund the old bonds, or reactivate
the burned token. It creates a new checkpoint lifecycle from authenticated
KERI evidence.

## Relationship to the freeze lifecycle

[Freeze and timeout handling](freeze-lifecycle.md) protects liveness:
challenge, response, ClaimFreeze, and thaw. Conviction protects truth and can
run from any live state without waiting for a freeze deadline:

- ACTIVE has both bonds available;
- ARMED preserves the recorded hunter's claim to `B`; and
- FROZEN has already paid `B`.

In all three cases only a fully witnessed irreconcilable conflict can take the
divergence reserve.
