# Identity operations

This page describes the current sovereign checkpoint design and marks every
unsettled transition explicitly. For the evidence and transaction IDs, start
with the [story ladder](../story-ladder.md).

A **KERI AID** (Key Event Receipt Infrastructure Autonomic Identifier) has a
signed **KEL** (Key Event Log). cardano-keri does not put the whole KEL on
Cardano. It stores one current checkpoint in a sovereign **UTxO** (unspent
transaction output) identified by a quantity-one token derived from the AID.

The inline checkpoint datum carries:

- the AID;
- current controller public keys and their weighted threshold;
- commitments to the next controller keys and their next threshold;
- the current KERI witness set and its threshold, called `toad`;
- a Cardano checkpoint sequence; and
- the native KERI sequence and event digest needed to bind the next event.

The token remains the stable handle while the datum advances.

## Operation status

| Operation | Result | Small-identity status |
|---|---|---|
| Register | Create ACTIVE sequence zero with `min + D_reg + B` escrow | Settled in [PR #146](https://github.com/lambdasistemi/cardano-keri/pull/146) |
| Close | Burn the checkpoint token and refund its complete value to the signed address | Settled in [PR #147](https://github.com/lambdasistemi/cardano-keri/pull/147) |
| Advance | Apply one genuine witnessed KERI rotation and return ACTIVE | Settled in [PR #148](https://github.com/lambdasistemi/cardano-keri/pull/148) |
| Freeze | Move a genuinely lagging or disputed ACTIVE checkpoint to ARMED | Settled in [PR #150](https://github.com/lambdasistemi/cardano-keri/pull/150) |
| Response Advance | Apply the genuine next event before the ARMED deadline and keep `B` | Settled in [PR #150](https://github.com/lambdasistemi/cardano-keri/pull/150) |
| ClaimFreeze | Pay `B` to the recorded hunter and enter FROZEN after the deadline | Fail closed; [#138](https://github.com/lambdasistemi/cardano-keri/issues/138) |
| Thaw Advance | Advance FROZEN back to ACTIVE while re-posting `B` | Depends on #138 |
| Convict | Pay for a fully witnessed irreconcilable fork; burn the AID token and create no successor — the burn is the whole terminal edge | Not exposed by the small-story checkpoint; [#151](https://github.com/lambdasistemi/cardano-keri/issues/151) |

## Register

Registration is permissionless: anyone may relay a public KERI inception and
fund the escrow. The inception itself determines the keys; the relayer cannot
substitute different controller authority.

Registration has two transactions.

### 1. BLAKE3 premint

The KERI AID is a BLAKE3 digest of the inception bytes in KERI's
saidification form. Plutus has no native BLAKE3 builtin, so a dedicated Aiken
policy performs that expensive check and mints a deterministic proof token.

This token records one fact:

```text
the supplied inception bytes have the supplied KERI AID
```

It grants no identity authority.

### 2. Checkpoint mint

The checkpoint transaction:

1. uses the bare mint redeemer `Register`;
2. includes a zero-lovelace withdrawal from the registration observer;
3. puts the complete `RegistrationEvidence` in that observer's envelope;
4. consumes an input carrying the matching proof token and burns it;
5. verifies the inception's controller signatures and witness receipts over
   the exact event bytes;
6. verifies that the new datum projects the event's AID, keys, thresholds,
   next commitments, witnesses, and `toad`;
7. mints exactly one AID-derived checkpoint token; and
8. creates exactly one ACTIVE output holding the token and at least
   `checkpoint minimum + D_reg + B`.

The checkpoint and observer programs are delivered by reference. The evidence
is **not** duplicated in the mint redeemer. See
[Observer architecture](observer-architecture.md#registrations-premint-fact-token)
for the transaction coupling.

### Duplicate registration boundary

Registration uses no shared global registry or absence proof. Two independent
transactions can therefore mint live candidates for the same AID. This avoids
global contention but leaves a deliberate residual: a consumer must resolve
exactly one ACTIVE checkpoint and fail closed on zero or multiple candidates.

A third party who registers somebody else's genuine inception cannot choose
its keys and gains no refund right; they donate the escrow to a checkpoint
controlled by that AID.

## Close

Close is the controller-authorized retirement path that is live today. It is
accepted only from ACTIVE.

The signed Close evidence binds:

- the network;
- checkpoint policy;
- exact checkpoint input reference;
- AID and current sequence;
- refund address; and
- current controller threshold.

The transaction must:

1. consume the exact ACTIVE checkpoint;
2. satisfy the current weighted controller threshold;
3. burn its quantity-one token;
4. create no successor carrying that token; and
5. refund the checkpoint's complete remaining value to the signed refund
   address.

Binding the input reference makes the authorization single-use. Binding the
refund address prevents a transaction builder from redirecting the escrow.
PR [#147](https://github.com/lambdasistemi/cardano-keri/pull/147) settled this
path and rejection vectors cover unauthorized Close attempts.

## Advance

Advance moves one KERI rotation into the on-chain checkpoint. Anyone may relay
it because the public event and its receipts determine the only valid
successor.

The transaction consumes exactly one current checkpoint and creates exactly
one ACTIVE successor with:

- the same quantity-one token;
- the same complete value;
- Cardano sequence increased by one;
- the event's current keys and weighted threshold;
- the event's next-key commitments and next threshold;
- the event's incoming witness set and `toad`; and
- the bound native KERI event sequence and digest.

The heavy checks run in `observer_advance`. They require:

1. the event to continue from the stored prior event;
2. revealed keys to match the stored next-key commitments;
3. both KERI controller thresholds to pass — the event's own threshold and
   the previously committed next threshold;
4. signatures to cover the exact rotation bytes and the reconstructed
   Cardano Advance message;
5. witness receipts to cover the exact event bytes; and
6. witness-set changes to satisfy the **incoming** witness threshold.

When incoming `toad` is greater than zero, elapsed time and controller
signatures never replace the required receipts. This prevents a controller
from activating an unpublished Cardano-first branch and trying to repair the
KERI history afterward.

PR [#148](https://github.com/lambdasistemi/cardano-keri/pull/148) settled a
genuine witnessed two-key Advance and rejected:

- a stolen-current-key attempt;
- signatures below the committed successor threshold; and
- insufficient witness receipts.

## Freeze

Freeze is a public challenge to a checkpoint that KERI evidence shows is
behind. A **hunter** is simply the party that supplies and pays to submit that
evidence.

The thin checkpoint requires an `observer_enforcement` withdrawal. The
observer proves that the contested rotation:

- belongs to the same AID;
- continues from the checkpoint's recorded KERI event;
- is strictly ahead of the ACTIVE tip;
- reveals keys committed by the old checkpoint;
- satisfies its controller threshold; and
- carries enough witness receipts.

The state transition:

```text
ACTIVE -> ARMED {
  checkpoint: unchanged inner checkpoint
  hunter_pkh: hunter payment-key hash
  deadline: transaction upper validity bound + freeze window
}
```

The transaction preserves the complete token and value, including `D_reg+B`.
ARMED is a different script role address, so consumers fail closed
immediately.

## Respond to ARMED

A response is not a special owner-only command. It is the same ordinary
Advance, applied to the ARMED checkpoint before its deadline.

The Advance observer unwraps ARMED only to read the previous checkpoint. It
validates the genuine next event, and the thin checkpoint creates the single
ACTIVE successor. The value is unchanged, so the identity keeps `B` and the
hunter is not paid.

This makes honest KERI catch-up permissionless: a relayer may do the work
without possessing retired or current private keys.

## Multi-round replay protection

Evidence is bound to the challenged KERI tip. After a response advances the
tip, the same evidence is no longer ahead and must reject.

PR [#150](https://github.com/lambdasistemi/cardano-keri/pull/150) settled:

```text
Freeze 1 -> response 1 -> reject exact Freeze-1 replay
         -> fresh Freeze 2 -> response 2
```

The second Freeze used newly generated sibling rotations at the new sequence.
This proves that a hunter needs fresh evidence for every round.

## Claim, thaw, and conviction

These operations belong to the target lifecycle but are not current
small-story claims:

- [Claim and thaw — #138](https://github.com/lambdasistemi/cardano-keri/issues/138)
  must prove the timeout boundary, exact hunter payment, retained
  `min + D_reg`, and the Advance that re-posts `B`.
- [Conviction — #151](https://github.com/lambdasistemi/cardano-keri/issues/151)
  must prove the fully witnessed conflict, protected payouts from every live
  state, and the burn-only terminal edge: the AID token is burned and no
  checkpoint-role successor is created. There is no terminal identity output
  to prove, and #151 must not produce one. Such an output would assert a fact
  about the identity with no key-event preimage, which Core Principle VI of
  the project constitution forbids.

The high-level state and economics are documented in
[Lifecycle and the two bonds](lifecycle-and-bonds.md). The detailed freeze
lifecycle page is intentionally reserved for #138.

## What is off chain

The ledger validates the event presented for a transition. It does not:

- discover new KERI events by itself;
- store or replay the entire KEL;
- operate KERI witnesses;
- decide whether an unseen event exists; or
- submit transactions.

Watchers, controllers, and ordinary relayers discover evidence off chain.
They do not become trusted authorities: the on-chain validators accept or
reject the supplied bytes.
