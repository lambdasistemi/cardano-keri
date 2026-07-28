# Trust model

cardano-keri projects public KERI events into a Cardano checkpoint. KERI is
Key Event Receipt Infrastructure; a KERI **AID** (Autonomic Identifier) has a
signed **KEL** (Key Event Log). The chain does not discover KEL events by
itself. It verifies the event evidence supplied in a transaction.

This page distinguishes current guarantees from target lifecycle work. For
settled transaction IDs, see the [story ladder](../story-ladder.md).

## What the current validators guarantee

### Inception bytes bind to the AID

Registration first runs the project's Aiken BLAKE3 implementation in a
premint transaction. The resulting proof token has a deterministic name bound
to the inception bytes and claimed AID.

The Register transaction consumes and burns that token. Its registration
observer then verifies:

- the event fields project to the checkpoint datum;
- indexed controller signatures satisfy the event's weighted threshold;
- indexed witness receipts satisfy `toad`, the event's witness threshold; and
- the thin checkpoint creates exactly one correctly named token in one ACTIVE
  output with the required escrow.

The registrant cannot copy a victim's public inception and substitute attacker
keys. The event, signatures, receipts, AID, and projected checkpoint must
agree.

### Rotation cannot choose an arbitrary successor

Advance verifies one genuine KERI rotation against the exact checkpoint input:

- the event continues from the recorded prior KERI event;
- revealed controller keys match the stored next-key commitments;
- the event's own controller threshold passes;
- the previously committed next threshold also passes;
- witness receipts cover the exact event bytes and satisfy the incoming
  witness threshold; and
- the output is the unique sequence-plus-one successor with the same token and
  complete value.

A relayer may submit the public event but cannot alter its result. A stolen set
of current keys is insufficient to replace the precommitted successor. A
controller-signed event without the required witness receipts is also
insufficient.

### Lifecycle role fails closed

Only a checkpoint at the bare ACTIVE role address is usable as current
authority. ARMED, FROZEN, and TOMBSTONE use distinct script roles and must be
rejected by a consumer.

The settled Freeze story moves ACTIVE to ARMED as soon as a hunter supplies a
witnessed conflict ahead of the current tip. It pays nothing immediately and
preserves the entire escrow. The settled response uses ordinary Advance before
the deadline and returns ACTIVE with the bond intact.

### Old Freeze evidence is not a permanent denial token

Freeze evidence is checked against the current KERI tip. Once a response
advances that tip, the old evidence is stale.

PR [#150](https://github.com/lambdasistemi/cardano-keri/pull/150)
explicitly replayed first-round evidence against the advanced ACTIVE output and
observed rejection, then settled a second round with fresh evidence. An
attacker needs a new witnessed conflict for each state they challenge.

### Close cannot redirect the refund

Close requires the current controller threshold. Its signed evidence binds the
network, checkpoint policy, exact input reference, AID, sequence, and refund
address. The transaction burns the checkpoint token and refunds the complete
checkpoint value only to that address.

## Two economic reserves

The checkpoint escrow separates two risks:

```text
checkpoint minimum ADA + D_reg + B
```

- `B`, about 5 ADA in the reference deployment, is the **delay bond**. It
  polices liveness. Freeze keeps it, a timely response keeps it, an unanswered
  ClaimFreeze will pay it to the recorded hunter, and thaw will re-post it.
- `D_reg`, about 1000 ADA in the reference deployment, is the **divergence
  bond**. It polices truth. A fully witnessed irreconcilable conflict will
  make it fund Convict payouts and a terminal TOMBSTONE.

The numbers are deployment parameters, not universal economic constants.
Ordinary lag cannot take `D_reg`, and Freeze alone cannot prove dishonesty.
See [Lifecycle and the two bonds](../architecture/lifecycle-and-bonds.md).

## Current fail-closed boundary

The small production-story checkpoint exposes Register, Close, Advance,
Freeze, and the ARMED response Advance. It deliberately does not expose later
verbs merely because supporting predicates or model tests exist elsewhere in
the repository.

| Boundary | Current result | Opening story |
|---|---|---|
| Claim after the ARMED deadline | Reject | [#138](https://github.com/lambdasistemi/cardano-keri/issues/138) |
| FROZEN thaw | Unreachable through the current story until Claim opens | [#138](https://github.com/lambdasistemi/cardano-keri/issues/138) |
| Fully witnessed conviction | Not exposed by the small-story checkpoint | [#151](https://github.com/lambdasistemi/cardano-keri/issues/151) |
| Real three-of-seven identity | No settled vertical evidence | [#139](https://github.com/lambdasistemi/cardano-keri/issues/139) and following stories |
| Full vLEI credential authorization | Not part of the identity checkpoint story | Later roadmap layers |

FROZEN and TOMBSTONE describe the target state machine. They are not claims
that the current small story can create those outputs.

## Advance-totality

The target machine is designed so a genuine next KERI event can always make
progress:

- ACTIVE advances directly;
- ARMED advances directly before its deadline;
- expired ARMED protects the hunter's earned claim, then thaw advances from
  FROZEN while re-posting `B`; and
- no operator owns the right to relay these public projections.

This is **advance-totality**. It permits up to two transitions after an ARMED
deadline—ClaimFreeze, then thaw—so the liveness guarantee does not erase the
hunter's earned timeout reward.

Claim and thaw remain issue #138 work. The invariant explains the required
shape; it does not promote that path to delivered status.

## Trust and responsibility boundaries

### KERI witnesses

For an identity with `toad > 0`, the system assumes the configured KERI
witness threshold provides meaningful public acceptance. The validator checks
the receipts; it cannot make a colluding witness quorum honest.

An identity may choose `toad = 0`. That weaker mode carries no witness
receipts, so an application that requires public KERI acceptance must reject
it by policy.

### Relayers and hunters

Relayers and hunters are untrusted submitters. They may censor their own
service, delay submission, or pay fees strategically. They cannot fabricate
valid signatures, receipts, preimages, or conflicts, and they cannot choose a
different valid successor.

Permissionless submission gives other parties the ability to relay the same
public truth. It does not guarantee inclusion against block-level censorship.

### Indexers

An indexer maps the AID-derived policy and asset name to a candidate UTxO
reference. The consuming transaction revalidates the token, script, datum,
AID, sequence, and ACTIVE role against the ledger.

A stale reference points to a spent output and rejects. A false reference does
not match. An unavailable indexer affects liveness only.

### Full KEL history

The checkpoint stores current state, not the complete KEL. Off-chain software
discovers and preserves the history, detects conflicts, and constructs
evidence. The on-chain observer validates the specific event and proof used by
the transition.

### Cardano settlement

Freeze and conviction are prospective containment. They cannot reverse a
Cardano transaction that already settled under an older ACTIVE checkpoint.
This is why witness receipts are checked during Advance before new keys become
active, and why each application still needs a freshness policy for unseen
off-chain events.

## Known residuals

### Duplicate live registration

There is no shared global AID registry or absence proof. Independent
transactions may create more than one ACTIVE candidate for the same AID.

A consumer must fail closed unless it resolves exactly one accepted ACTIVE
checkpoint. Duplicate registration is expensive self-harm or a donation: the
event fixes the controller keys, while the registrant funds `D_reg+B`.

### Next-key theft

Pre-rotation protects against theft of current keys. It does not solve theft of
the committed successor private keys or total loss of all current and reserve
keys. Those are KERI key-management and recovery problems outside the current
independent-AID protocol.

### Discovery lag

Cardano cannot react to a KERI event nobody has submitted. Between KERI
publication and a settled Advance or Freeze, an application may still see the
old ACTIVE checkpoint. High-value applications must state how they monitor
KERI and how fresh a checkpoint must be.

### Scale

The two-key fixture fits production protocol limits. The real
three-of-seven GLEIF shape has not completed the vertical ladder and is
expected to exceed current mainnet execution limits in later operations.
Pumped-devnet measurements will quantify that gap; they are not mainnet-fit
evidence.

## Threat summary

| Attempt | Required on-chain response |
|---|---|
| Register public inception with attacker keys | Reject because projected keys and signed event disagree |
| Activate a Cardano-first rotation without witness acceptance | Reject because incoming witness receipts are insufficient |
| Rotate with stolen current keys only | Reject because committed successor keys and dual thresholds do not match |
| Freeze with invalid, under-signed, or under-witnessed evidence | Reject in the enforcement observer |
| Replay a resolved old Freeze proof | Reject because the proof is not ahead of the new tip |
| Use ARMED as current authority | Consumer rejects by role address |
| Claim the delay bond today | Reject until #138 opens the path |
| Convict through the small-story checkpoint today | Reject/unavailable until #151 opens and settles the path |
