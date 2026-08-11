# Value authorization

Value authorization is a future consumer of the identity checkpoint. The
small settled stories prove checkpoint creation and lifecycle transitions;
they do not yet ship an application that authorizes value writes from it.

This page states the current integration boundary so later application
validators do not reintroduce the retired shared-registry model.

## Resolve current authority

Given a KERI AID, an application derives the expected checkpoint asset:

```text
(checkpoint_policy_id, deriveAidAssetName(cesr_aid))
```

It includes the candidate checkpoint as a **CIP-31 reference input**. CIP-31
lets the transaction read the UTxO without spending it.

The application validator must require:

1. exactly one supplied candidate for that AID;
2. the accepted checkpoint policy and script lineage;
3. exactly one AID-derived token;
4. a well-formed inline `CheckpointDatumV1`;
5. the expected AID and current sequence;
6. the bare ACTIVE role address; and
7. the operation's controller authorization against the current weighted key
   state.

Every other case fails closed:

- no checkpoint;
- multiple ACTIVE candidates;
- stale or already spent outref;
- wrong policy or asset;
- malformed or mismatched datum;
- ARMED; or
- FROZEN.

A convicted identity is not a further role to reject. Conviction burns the AID
token, so the terminal edge leaves nothing to resolve and the application meets
the first case above — no checkpoint.

There is no identity-root inclusion proof and no separate Freeze-registry
absence proof. Freeze changes the sovereign checkpoint's own role address.

## Indexer boundary

An indexer may return the candidate outref for
`(checkpoint_policy_id, aid_asset_name)`. It is not trusted for authority.
The ledger validations above remain mandatory.

- A stale result refers to an input that no longer exists and rejects.
- A false result fails token, script, datum, or AID validation.
- An outage prevents construction but cannot authorize a fallback key.

Clients should refresh on contention and fail over between indexers or local
chain sync when availability matters.

## Authorization modes

Two application patterns remain useful.

### Native Cardano signer

The application may require Cardano transaction signatures corresponding to
the current checkpoint controller keys. This is simple for software that can
make those KERI-controlled Ed25519 keys available through a compatible signing
interface.

The validator:

1. resolves the ACTIVE checkpoint;
2. reads the current weighted key set;
3. checks the required transaction signatories; and
4. evaluates the checkpoint's threshold.

This mode binds authorization to the complete Cardano transaction body but may
not fit existing KERI wallet APIs.

### Detached intent signature

A future wallet bridge may put domain-separated signatures in the redeemer.
The signed intent must bind at least:

```text
AuthorizationIntent {
  domain
  network_id
  application_policy
  operation
  checkpoint_policy
  aid_asset_name
  checkpoint_input
  checkpoint_sequence
  application_input
  intended_output_or_effect
  nonce_or_counter
  valid_from
  valid_until
}
```

The application reconstructs this message rather than accepting
caller-supplied message bytes. It then evaluates signatures under the current
checkpoint's weighted controller threshold.

Binding the exact checkpoint input and sequence makes an authorization stale
after rotation. Binding application input/output or operation effect prevents
a batcher from repurposing a valid signature. Domain, network, policy, and
validity fields prevent cross-protocol and cross-deployment replay.

The exact envelope remains a later roadmap deliverable. This shape is a
security requirement, not a claim that the SDK is published.

## Value-cage oracle

Some MPFS value-cage designs have an operator or oracle that serializes writes
to their own cage UTxO. That authority is separate from AID authority.

If a cage keeps an oracle, a mutation should require both:

- the AID controller threshold resolved from the current ACTIVE checkpoint;
  and
- the cage's own operator authorization.

The oracle is then necessary but not sufficient. It may affect liveness or
ordering, but it cannot forge the identity owner's authorization.

## Rotation and transaction races

A value transaction references one exact checkpoint UTxO. If Advance spends
that checkpoint first, the value transaction becomes invalid and must be
rebuilt against the successor.

This is the desired safety property: pending authorization does not silently
survive a key rotation. It is also an operational race that builders must
handle.

## Freeze behavior

As soon as Freeze settles, the checkpoint token moves from ACTIVE to ARMED.
A value transaction referring to the old ACTIVE input is stale, and a new
transaction resolving ARMED must reject by role.

A timely response Advance creates a new ACTIVE checkpoint at the next
sequence, so the application must obtain fresh authorization against that
input.

A future FROZEN output follows the same fail-closed rule. Conviction produces
no output to resolve at all: the token is burned, so the application meets the
no-checkpoint case rather than a role it must recognise.

## Credential-gated actions

Identity authorization answers:

> Do the current controllers of this AID authorize the operation?

It does not answer:

> Does this AID represent a particular legal entity or hold a current role?

A credential-gated application must additionally verify the required ACDC
credential chain and TEL non-revocation evidence. Those layers are later
roadmap work.

## Minimum consumer checklist

Before treating an integration as secure, prove with applied-boundary tests
that it rejects:

- the right token at the wrong role;
- the right AID with multiple ACTIVE candidates;
- a stale checkpoint outref;
- a well-signed intent for another checkpoint sequence;
- a well-signed intent for another application input or output;
- signatures below the weighted threshold;
- an expired intent;
- a wrong network or policy; and
- a valid identity signature with missing or revoked credentials when the
  application requires credentials.

See the [Trust model](../design/trust-model.md) and
[Architecture overview](overview.md).
