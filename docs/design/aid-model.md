# AID cryptographic model

A **KERI AID** is an Autonomic Identifier from the Key Event Receipt
Infrastructure. Standard transferable AIDs use an E-code BLAKE3 digest of
their inception event.

cardano-keri uses that qualified AID in two different but connected places:

| Value | Purpose |
|---|---|
| KERI AID | The self-certifying identity used by KERI events and witnesses |
| AID-derived Cardano asset name | A cheap, deterministic locator for the checkpoint token |

The asset name is not a second identity. It is a domain-separated
`blake2b_256` hash of the qualified AID bytes, chosen because Blake2b is a
native Plutus builtin:

```text
aid_asset_name =
  blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG || 0x45 || raw_32_byte_aid)
```

The checkpoint policy ID plus this asset name identifies the sovereign
checkpoint UTxO.

## Genesis byte binding

Registration must prove:

```text
blake3(KERI saidified inception bytes) = AID
```

Plutus has no native BLAKE3 builtin, so a dedicated Aiken policy performs this
work in a premint transaction and creates a deterministic fact token. Register
then consumes and burns the token while the registration observer checks the
event's semantic projection.

The observer requires the new datum to match the event's:

- AID;
- current controller keys and weighted threshold;
- next-key commitments and next threshold;
- witnesses and `toad`; and
- native sequence and event digest.

It also verifies controller signatures and witness receipts over the exact
inception bytes. Copying a public inception cannot give a registrant different
keys, because the signed event fixes those keys.

## Checkpoint datum

The V1 checkpoint is list-shaped so a single key is only the smallest
threshold case:

```text
CheckpointDatumV1 {
  cesr_aid
  current_keys
  current_threshold
  next_keys
  next_threshold
  witnesses
  toad
  seq
  native_sn
  native_event_digest
}
```

Thresholds may be integer or weighted KERI clauses. The datum well-formedness
rules reject empty or malformed key sets, invalid weight encodings,
unsatisfiable clauses, duplicate material where prohibited, and inconsistent
sequence fields.

## Pre-rotation

KERI commits to successor keys before they become current. The checkpoint
stores the standard KERI next-key digests:

```text
next_key_digest = blake3_256(qb64(Ed25519 public key))
```

Advance reveals the next keys and checks them against those stored
commitments. It also applies KERI's dual-threshold rule:

1. signatures satisfy the new event's current threshold; and
2. the revealed keys satisfy the previous checkpoint's committed next
   threshold.

A thief with only the old current keys cannot pick an unrelated successor.

## Witness binding

Controller authority and public KERI acceptance are separate.

For incoming `toad > 0`, Advance requires enough Ed25519 witness receipts over
the exact rotation bytes from the incoming witness set. A witness-set change
is validated against that incoming set, matching the event being activated.

A checkpoint with `toad = 0` is explicitly witnessless. Applications that
require public witness acceptance must reject it by policy.

## Sequence and event binding

Every ordinary Advance:

- consumes the exact current checkpoint outref;
- requires Cardano `seq + 1`;
- binds to the stored native KERI prior event;
- accepts one next KERI event rather than skipping a history segment; and
- creates one unique ACTIVE successor.

Signed Cardano message fields bind the deployment, policy, AID-derived asset,
exact spent outref, prior state, created state, and event evidence. A
signature from one deployment or input cannot authorize another.

## CBOR determinism

Cardano-side signed messages use canonical Plutus Data CBOR. Constructor
indices, field order, integer encoding, and list order are protocol surface.
The validator reconstructs each message from trusted transaction context and
the small set of supplied evidence before serializing it for signature
verification. It never asks a prover which bytes should be signed.

KERI events follow a different rule: proofs carry the exact native KERI event
bytes. The checkpoint logic verifies those bytes and their semantic
projection; it does not translate an event into a new CBOR representation and
then claim that the new bytes are the KERI event.

## Domain separation

Independent uses have independent, versioned domains:

| Use | V1 domain |
|---|---|
| Checkpoint asset locator | `cardano-keri/checkpoint-asset/v1` |
| Signed Advance message | `cardano-keri/checkpoint/adv/v1` |
| Signed Close message | `cardano-keri/checkpoint/close/v1` |
| Non-ACTIVE role-address derivation | `cardano-keri/checkpoint/role/v1` |

The asset derivation also includes the `0x45` E-code byte before the raw AID.
Changing a domain, constructor index, or field order requires a new protocol
version. The old shared Merkle Patricia Forest domains discussed in the
historical vetting record are not part of the sovereign checkpoint wire.

## Duplicate-registration residual

There is no global AID registry or mint-once absence proof. Two independent
transactions may create candidates with the same policy and asset name.

This is handled by an explicit consumer rule:

```text
accept exactly one well-formed ACTIVE checkpoint; otherwise fail closed
```

A third-party registrant cannot take over the AID, because the public
inception fixes the controller keys. They can only fund another candidate
controlled by the same event, creating ambiguity and donating the escrow.

## Role and identity

The datum does not carry a caller-selectable lifecycle status. ACTIVE, ARMED,
and FROZEN are distinguished by script role addresses around the same
AID-derived token. Conviction has no role address: it burns the token, so a
consumer meets an absent checkpoint rather than a terminal status.

The token identifies the checkpoint lineage. The role determines whether a
consumer may use it. Only ACTIVE is acceptable.

## V1 boundaries

The current V1 story covers independent, nondelegated AIDs. It does not yet
cover:

- delegated inception and delegated rotation;
- KERI recovery and superseding events;
- non-establishment events: interaction (`ixn`) events are not projected, so
  anything they anchor — credential issuance and revocation in particular — is
  invisible to the checkpoint (see
  [Compromise of the current keys](key-compromise.md));
- a production-size inception beyond the current single-proof boundary;
- post-quantum controller keys; or
- automatic discovery of unseen KERI events.

The real three-of-seven registration story
[#139](https://github.com/lambdasistemi/cardano-keri/issues/139) adds a
multi-transaction BLAKE3 proof for its 1083-byte-class inception. Delegation
and recovery require a versioned proof protocol, not unchecked fields added to
V1.

## Related pages

- [Identity operations](../architecture/identity-ops.md)
- [Observer architecture](../architecture/observer-architecture.md)
- [Trust model](trust-model.md)
- [Compromise of the current keys](key-compromise.md)
- [Story ladder](../story-ladder.md)
