# Story ladder: what works now

This page separates transactions that have settled from work that is still in
flight or planned.

**KERI** is Key Event Receipt Infrastructure, the off-chain protocol that
maintains an identity's signed key history. A KERI **AID** (Autonomic
Identifier) names the identity, and its **KEL** (Key Event Log) contains the
inception and rotation events for that AID. cardano-keri projects the current
KERI key state into a Cardano **checkpoint UTxO**: an unspent transaction output
that carries one identity-specific token and an inline datum with the current
keys, thresholds, witnesses, and sequence number.

!!! note "What “settled” means"
    The transaction reached a private protocol-11 development network
    configured with Cardano's production transaction limits. This is stronger
    evidence than an emulator or unit test, but it is **not** a mainnet
    deployment or a production-readiness claim.

## The ladder at a glance

The settled small fixture has two controller keys and genuine
`keripy`-produced events and witness receipts. `keripy` is the reference KERI
implementation used to produce and verify the test history.

| Rung | What the user can do | Evidence | State |
|---|---|---|---|
| Register small | Prove a KERI inception in a premint transaction, then create a bonded ACTIVE checkpoint | [PR #146](https://github.com/lambdasistemi/cardano-keri/pull/146) | Settled |
| Close small | Have the current controllers authorize retirement, burn the checkpoint token, and refund the escrow | [PR #147](https://github.com/lambdasistemi/cardano-keri/pull/147) | Settled |
| Rotate small | Relay a genuine witnessed rotation and advance the checkpoint by one event | [PR #148](https://github.com/lambdasistemi/cardano-keri/pull/148) | Settled |
| Freeze and respond, small | Let a hunter present a witnessed conflicting rotation, move ACTIVE to ARMED, then let the honest history advance back to ACTIVE without losing the bond | [PR #150](https://github.com/lambdasistemi/cardano-keri/pull/150) | Settled, including two rounds |
| Seize the delay bond | After an unanswered deadline, pay the recorded hunter and enter FROZEN; later thaw by advancing and re-posting the bond | [Issue #138](https://github.com/lambdasistemi/cardano-keri/issues/138) | In flight |
| Convict a fork, small | Prove a fully witnessed irreconcilable conflict, pay the protected rewards, and leave a terminal tombstone | [Issue #151](https://github.com/lambdasistemi/cardano-keri/issues/151) | Planned |

The four settled rungs are independently useful. Together they establish a
vertical path through the production validators, transaction builder, node
submission, and settlement boundary. They do not imply that later rungs are
open.

## Settlement evidence

A **transaction ID** (txid) is the hash that identifies one settled Cardano
transaction. The IDs below are copied from the merged pull-request records.

### Register — PR #146

The expensive BLAKE3 calculation ran first and minted a short-lived proof
token. Registration then consumed that fact, created the checkpoint, and
locked the two bonds.

| Transaction | Txid |
|---|---|
| BLAKE3 premint | `7222d36ea5f3791877cf8ca779a76d6241cf16a709c8908a058d6ca791b1526b` |
| Register | `84118d89a5c0c57e35a1af9666cd266a7e70818600dbe9499819f69efcb20e90` |

### Close — PR #147

The story registered the same small identity, then its current controllers
authorized a refund to output zero.

| Transaction | Txid |
|---|---|
| Register | `84118d89a5c0c57e35a1af9666cd266a7e70818600dbe9499819f69efcb20e90` |
| Close | `1d8afdf5b9f87ee32c10cb96d4fc82a8e6c23a9d1212074ba2dcd244ebde91b1` |

### Rotate — PR #148

The Advance transaction consumed the registered checkpoint and created its
single ACTIVE successor. The same live run also settled a Close regression.

| Transaction | Txid |
|---|---|
| Advance | `04c3673798c9e555ad1cd0cf32efb9a9265d75ef0b464502eb5bfd8e8bd0b055` |
| Close regression | `7008cd9c93b5c5c252af61b2734831f3ac7f532e95eebd4bf988ecaf7ae50fc7` |

### Freeze, response, and replay rejection — PR #150

This is a two-round security drill, not two copies of a unit test. After the
first response advanced the checkpoint, the runner replayed the exact old
Freeze evidence. The applied checkpoint and enforcement observer rejected it
before submission. A fresh pair of conflicting rotations at the next KERI
sequence then opened and resolved a second challenge normally.

| Step | Txid |
|---|---|
| Register | `c4b315a43c72b8493284c0e30b1dd90bf354e96f35d6f9b90f7f4c21c632e71e` |
| Recorded rotation | `1b4acf5b3f62c09a5627aeac364d798728a375bd3340d7e19bba4765e8c60532` |
| First hunter Freeze | `08cc097782780f02d5a69dba763566d62d74e0e763816c1e3eb3e4155ff501e7` |
| First honest response Advance | `1503db7294bf3ffef24ef44c424714024f2d1784788be4fd730427c91aedde60` |
| Fresh second Freeze | `bc96940734bb3b3866b215ad189bd9a2a8b8c4f4282410b5c836631d9fedd9ec` |
| Second honest response Advance | `6b706faf955a303cd5bb425440595ab729a4e4438948e2f3009080e039f24b3c` |

Both responses preserved the checkpoint's complete value, including the delay
bond. The old evidence failed because it no longer described a rotation ahead
of the new ACTIVE tip. Freeze is therefore tied to the exact state it
challenges: every round needs fresh evidence.

## What is deliberately unavailable

The current small-story checkpoint accepts `Register`, `Close`, `Advance`, and
`Freeze`. It also accepts an `Advance` from ARMED before the recorded deadline,
which is the honest response.

The following boundaries still fail closed:

- **`ClaimFreeze` is unavailable.** A transaction cannot take the delay bond
  after the deadline or create FROZEN state until issue
  [#138](https://github.com/lambdasistemi/cardano-keri/issues/138) opens and
  proves that path.
- **Thaw is not yet a live story.** It depends on ClaimFreeze first creating a
  FROZEN checkpoint. Issue #138 must prove both the claim and the comeback.
- **`Convict` is not exposed by the small-story checkpoint.** The economic and
  tombstone model is planned in issue
  [#151](https://github.com/lambdasistemi/cardano-keri/issues/151); do not treat
  the existing predicate and model tests as settlement evidence.
- **Non-ACTIVE roles are unusable by consumers.** ARMED already fails closed.
  FROZEN and TOMBSTONE remain part of the target lifecycle and will also fail
  closed when their stories open.
- **The real GLEIF-scale identity has not been demonstrated.** The settled
  fixture proves the small two-key rung only.

Failing closed means rejecting the transaction or refusing the identity as
current authority when the required proof or transition is unavailable. It
does not mean guessing a result off chain.

## The GLEIF-scale ladder

The next scale is a genuine Global Legal Entity Identifier Foundation
shape: weighted three-of-seven controller thresholds, the real witness set,
and a real `keripy` lineage. It is deliberately not represented by a smaller
synthetic substitute.

The planned order is:

1. [Register the biggest real identity that fits — #139](https://github.com/lambdasistemi/cardano-keri/issues/139).
   Its 1083-byte-class inception exceeds the present single-chunk BLAKE3 proof,
   so it also needs a production multi-transaction proof.
2. [Close the real identity — #145](https://github.com/lambdasistemi/cardano-keri/issues/145).
3. [Create observer headroom — #149](https://github.com/lambdasistemi/cardano-keri/issues/149),
   before spending more of the Advance reference-script budget.
4. [Rotate the real identity — #144](https://github.com/lambdasistemi/cardano-keri/issues/144).
5. [Freeze and respond at real scale — #140](https://github.com/lambdasistemi/cardano-keri/issues/140).
6. [Seize and thaw at real scale — #141](https://github.com/lambdasistemi/cardano-keri/issues/141).
7. [Convict at real scale — #152](https://github.com/lambdasistemi/cardano-keri/issues/152).

These stories are expected to need a development network with raised execution
units so the project can measure the gap to current mainnet limits without
changing the production validators. “Runs on a pumped devnet” will quantify
cost; it will not mean “fits mainnet.”

## Where to read next

- [Lifecycle and the two bonds](architecture/lifecycle-and-bonds.md) explains
  ACTIVE, ARMED, FROZEN, TOMBSTONE, and why the two deposits have different
  jobs.
- [Observer architecture](architecture/observer-architecture.md) explains the
  thin checkpoint, reference scripts, zero-lovelace withdrawal, and BLAKE3
  fact token.
- [Identity operations](architecture/identity-ops.md) gives the current
  operation-by-operation view.
