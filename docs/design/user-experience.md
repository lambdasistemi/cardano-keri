# User experience: a KERI identity on Cardano

This is the user journey supported by the current identity architecture and
the boundaries that a future Veridian integration must make visible.

## First, know the AID

Alice learns Bob's KERI AID through a trusted KERI channel such as an OOBI
(out-of-band introduction), QR code, or direct exchange. The AID identifies
Bob's KERI key history. Cardano does not decide who Bob is in the legal world;
credentials do that later.

## Find the checkpoint

The application:

1. derives the Cardano asset name from Bob's AID;
2. asks an indexer or node for candidate UTxOs;
3. validates the candidates against the ledger; and
4. accepts exactly one well-formed ACTIVE checkpoint.

The UI should distinguish:

| Result | User-facing meaning |
|---|---|
| One ACTIVE checkpoint | Current Cardano key state is available |
| ARMED | A witnessed challenge is open; do not authorize an action |
| FROZEN | The response window expired; do not authorize an action |
| No candidate | No usable checkpoint is visible — including after a conviction burned the token, and before any later re-registration |
| Multiple ACTIVE candidates | Ambiguous registration; fail closed |
| Stale outref | The checkpoint changed; refresh and rebuild |

“Fail closed” should be visible. The application should say why it refuses
rather than silently choosing a checkpoint or old key.

## Register

A relayer can register Alice's public KERI inception without holding her
private keys:

1. prove the inception/AID BLAKE3 binding;
2. submit the bare Register transaction with observer evidence;
3. fund `checkpoint minimum + D_reg + B`; and
4. wait for settlement.

The resulting checkpoint is controlled by the keys in Alice's inception, not
by the relayer. If somebody else pays, they are donating the escrow.

The UI should show:

- AID;
- controller threshold;
- witness threshold;
- expected checkpoint policy and asset;
- `D_reg` and `B`;
- premint txid;
- Register txid; and
- confirmation depth.

## Rotate

Alice rotates in KERI first. Her KERI software creates the event and collects
the configured witness receipts. Any relayer may then submit Advance.

The UI should show:

- old and new KERI sequence;
- controller-threshold result;
- witness receipt count and required `toad`;
- any witness-set change;
- checkpoint input and expected successor; and
- settlement state.

The application must not report rotation complete merely because KERI has
moved. Until Advance settles, Cardano still has the old checkpoint.

## Freeze and respond

A hunter who sees a witnessed conflict ahead of the checkpoint may submit
Freeze. As soon as it settles:

- the checkpoint becomes ARMED;
- applications reject it;
- the complete escrow remains in custody; and
- the UI shows the hunter and deadline.

Before the deadline, an ordinary Advance is the response. If it settles:

- the new checkpoint is ACTIVE;
- the complete delay bond remains; and
- the hunter receives nothing.

An old Freeze proof cannot be replayed after the response. A fresh round needs
fresh evidence at the new sequence.

The detailed timeout claim and thaw journey is intentionally reserved for
[#138](https://github.com/lambdasistemi/cardano-keri/issues/138).

## Close

Close is a controller-authorized action. Before signing, the UI must display:

- exact checkpoint input;
- AID and sequence;
- refund address;
- token burn;
- expected refund value; and
- network and policy.

The signed evidence binds those values. On settlement, no successor
checkpoint token remains.

## Two balances, two explanations

The UI should never present `D_reg+B` as one generic deposit:

- **Delay bond `B`**, about 5 ADA in the reference deployment, pays only after
  a full unanswered Freeze response window. It measures liveness.
- **Divergence bond `D_reg`**, about 1000 ADA in the reference deployment,
  backs a fully witnessed irreconcilable-fork conviction. It measures truth.

Both are deployment parameters. A responsive identity loses neither.

## Current product boundary

The repository has settled development-network stories and a test harness,
not an end-user product. A production experience still needs:

- a published Veridian/Signify integration;
- redundant checkpoint discovery;
- transaction fee and funding UX;
- Cardano settlement and rollback monitoring;
- KERI freshness monitoring;
- Claim/thaw and conviction stories;
- real-scale measurements; and
- credential display and revocation checks.

The [story ladder](../story-ladder.md) is the current evidence ledger.
