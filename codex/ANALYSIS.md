Executive summary: the proposed design has the right core idea for cheap
on-chain authorization, but the spec is not yet cryptographically tight. The
largest issues are that inception does not prove control of `cur_key`,
signature messages lack explicit protocol, network, registry, and script
domains, CBOR determinism is not mandated, and value-write authorization is
bound only to the identity snapshot, not to the value-state transition being
performed. Rotation is the strongest operation as written, because the
pre-committed next key and `seq + 1` prevent ordinary same-registry replay, but
it still needs stronger message context and clearer root anchoring.

## Vetting questions

### 1. Inception replay

An adversary can front-run a pending inception by copying the public
`InceptionEvent` from the mempool and submitting a higher-fee transaction that
registers the same `aid` first. The MPF absence proof prevents two final
registrations, but it does not ensure that the first registering transaction was
submitted by the controller of `cur_key`.

This does not steal cryptographic control if the copied inception contains the
honest user's `cur_key` and `next_digest`, because the resulting key-state still
points at the honest user's keys. It is still a registration griefing and
ordering attack: the honest transaction fails, any registration-time side
effects can be captured by the front-runner unless separately constrained, and
the protocol has no way to distinguish "registered by the controller" from
"registered by anyone who saw the preimage".

The more serious inception issue is not replay of the same event, but creation
of a fresh event containing someone else's public key. Since `cur_key` is
public, an attacker can choose:

```
InceptionEvent { cur_key = victim_pubkey, next_digest = blake2b_256(attacker_next_pubkey) }
```

The attacker can register the resulting AID without knowing the victim's
private key, then immediately rotate using `attacker_next_pubkey`. This does
not reproduce the victim's legitimate AID, but it does create an AID whose
inception state falsely suggests the victim's key participated. If relying
systems interpret inception as a live proof of key control, this is a forgery
of participation.

### 2. Rotation replay

For a single canonical identity registry, `rot_msg = cbor({ aid, seq: seq + 1,
new_next })` is mostly sufficient against simple replay. Reusing an old
rotation after it succeeds fails because the current `seq` has changed, so the
validator reconstructs a different message. Reusing it before it succeeds can
only race to perform the same state update, assuming the identity UTxO update
is correctly anchored to the consumed current root.

The missing checks are contextual. The signed message does not include an
operation/domain tag, protocol version, network id, identity registry policy id,
identity thread token, input identity root, or current key-state digest. An
attacker who can get the same key to sign a structurally identical CBOR message
in another protocol, on another network, or in a forked registry can replay that
signature as a rotation if the tuple `{ aid, seq + 1, new_next }` matches.

`new_next` collision is not a practical replay vector if `KeyDigest` is
`blake2b_256(PubKey)` and Blake2b-256 remains collision and preimage resistant.
However, the script accepts `new_next` as arbitrary bytes. A signer can set it
to a digest with no known pubkey preimage, permanently bricking future rotation.
An attacker can also set it equal to a known AID or other 32-byte identifier as
a type-confusion or log-pollution trick unless the spec domain-separates
`KeyDigest` from `AID`.

### 3. Value-write replay

Binding `auth_msg` to `identity_root` prevents replay across rotations only if
every rotation changes the identity root and MPF root collisions are infeasible.
That is useful, but it is not full replay protection for MPFS value writes.

The missing check is that the signature does not bind the value-state
transition. `auth_msg = cbor({ aid, op, identity_root })` omits the MPFS value
cage identity, input value root, output value root, consumed value UTxO,
operation proof hash, validity interval, nonce, and any recipient or side
effect fields. An attacker who observes a valid authorization can replay or
front-run it while the identity root is unchanged. Depending on `MpfsOp`
semantics, this can reapply an idempotent update, apply a delayed stale update,
race the honest transaction, or apply the same signed operation against a
different value-cage instance.

Predictability of an MPF root is not itself a problem. Collision or
second-preimage weakness is the problem. If an attacker can produce two
different identity tries with the same `identity_root`, a signature over one
snapshot can authorize operations under the other. The MPF hash scheme therefore
needs explicit domain-separated leaf, branch, empty, and value encodings.

### 4. Rotation after key compromise

If `cur_key` is stolen, the attacker cannot rotate under the current rotation
rule because rotation requires the pre-committed `next` private key. That part
of the design is sound.

The attacker can still sign any value-write authorization accepted by the MPFS
value cage until the legitimate controller rotates. They can also front-run,
spam, or hold value-write authorizations, and they may be able to race
legitimate value operations. They should not be able to block the identity
rotation cryptographically, because spending the identity UTxO for rotation
requires the next key, not the current key. Blocking is limited to ordinary
mempool congestion or denial of service unless another registry path lets
`cur_key` consume the identity state.

The spec should state the operational consequence directly: compromise of
`cur_key` means complete compromise of MPFS writes authorized by the current
snapshot until a rotation confirms.

### 5. Inception event malleability

Deterministic CBOR is not mandated. The spec uses `cbor(...)` as if it were a
single canonical byte string, but it does not define map ordering, definite
versus indefinite lengths, integer minimality, tags, duplicate-key handling, or
whether records encode as arrays or maps.

This is exploitable at the protocol boundary. Different encodings of the same
semantic `InceptionEvent` can produce different AIDs, allowing duplicate
semantic identities and disagreement between off-chain verifiers. For signed
messages, a signer and validator that serialize the same structure differently
will produce unverifiable signatures. If any redeemer supplies pre-serialized
bytes rather than typed data that the script serializes itself, encoding
malleability can become a direct replay and confusion surface.

The spec should mandate one deterministic encoding, preferably RFC 8949
deterministic CBOR or a precise Plutus/Aiken data encoding, and should reject
non-canonical encodings off-chain before signing.

### 6. next_digest grinding

Grinding a usable `new_next` that equals a chosen AID requires finding a pubkey
whose `blake2b_256(pubkey)` equals that 32-byte AID. That is a preimage attack
and should be infeasible.

However, because `new_next` is just a raw 32-byte field, a signer can set it to
any AID value without knowing a pubkey preimage. That does not let the signer
rotate later, but it does pollute the namespace if tools or users display AIDs
and key digests interchangeably. The spec should make `AID` and `KeyDigest`
domain-separated hash types:

```
AID       = blake2b_256("cardano-keri:aid:v1" || canonical_inception_event)
KeyDigest = blake2b_256("cardano-keri:key-digest:v1" || pubkey)
```

It should also make clear that `new_next` is allowed to be any 32 bytes only at
the cost of future liveness, and that controllers must generate it from a known
next public key.

### 7. Missing: inception self-auth

Preimage knowledge of `blake2b_256(cbor(inception))` is not sufficient to prove
control of the inception key. The preimage contains `cur_key`, which is public,
and `next_digest`, which the attacker can choose. The security claim only says
an attacker cannot match a chosen AID. It does not say the creator of a new AID
controls the public key embedded in that AID.

A self-auth step should be added. The inception redeemer should include a
signature by `cur_key` over an inception message whose signature is not part of
the AID hash:

```
inc_msg = cbor({
  domain: "cardano-keri/inception/v1",
  network_id,
  registry_policy_id,
  registry_thread_token,
  aid,
  cur_key,
  next_digest
})
```

The script should verify `verify_ed25519_signature(cur_key, inc_msg, sig)`.
This proves control of `cur_key` and prevents third-party public-key imprinting.
It does not by itself prevent a copied mempool transaction from being submitted
unchanged or with unrelated side effects. To prevent altered front-running, the
inception authorization must also bind all security-relevant transaction
effects, or the transaction must be required to carry a non-copyable tx-level
signature from the controller or a designated submitter.

### 8. On-chain vs off-chain boundary

Purely on-chain, the protocol can guarantee the current registry state if all
registry transitions start from the canonical identity UTxO and every update is
validated by the script. For MPFS value writes, the value cage can verify that a
live identity reference input contains an AID whose current digest matches the
signing key, and that one Ed25519 signature authorizes a message for that
snapshot.

The guarantees lost versus a full KERI implementation are substantial:

- no on-chain replay of the full key event log;
- no on-chain verification of witness receipts, duplicity detection, or
  watcher-backed consistency;
- no native threshold, weighted key, or multi-sig establishment semantics;
- no on-chain audit that the current state is portable outside the Cardano
  registry without trusting Cardano's UTxO history;
- no detection of alternate off-chain KELs for the same identifier except where
  they conflict with the single on-chain state;
- no on-chain recovery of historical authority context beyond the current
  key-state snapshot.

That boundary can be acceptable for MPFS if the intended trust root is the
Cardano identity UTxO, not a general KERI verifier. The spec should say this
explicitly: MPFS authorization trusts the live on-chain registry snapshot, while
full KERI-style historical audit remains an off-chain responsibility.

## Op-by-op audit

### Inception

Forgery vectors:

- Missing check: no `verify_ed25519_signature(cur_key, inc_msg, sig)`.
  Strategy: register an inception using a victim's public `cur_key` and an
  attacker-controlled `next_digest`, then rotate to the attacker key.
- Missing domain separation between `AID` and `KeyDigest`.
  Strategy: use equal-looking 32-byte values across fields to confuse tooling,
  logs, or off-chain resolvers.

Replay and front-running vectors:

- Missing check: no controller-bound transaction authorization.
  Strategy: copy a pending inception redeemer and submit first. The state is the
  same, but registration ordering and any side effects are captured.
- Missing check: no explicit current-root anchoring is shown for the absence
  proof.
  Strategy: if an implementation accepts an absence proof not tied to the
  consumed identity root, a stale proof can be replayed against a later trie.

Collision vectors:

- If two different canonical inception events collide under Blake2b-256, the
  same AID can represent different initial states. This is assumed infeasible,
  but the spec should rely on a domain-separated hash input to avoid structural
  cross-protocol collisions.
- If CBOR is malleable, semantically identical events can produce multiple
  AIDs. This is not a hash collision, but it is an identity-level collision of
  meaning.

### Rotation

Forgery vectors:

- The next-key possession check is the key security check and is appropriate:
  `blake2b_256(reveal_key) == current_state.next_digest` plus
  `verify_ed25519_signature(reveal_key, rot_msg, sig)`.
- Missing check: `rot_msg` has no protocol, network, registry, or script
  domain.
  Strategy: replay a signature produced for an identical tuple in a different
  registry, testnet/mainnet context, or protocol that also signs a CBOR map with
  fields `{ aid, seq, new_next }`.

Replay and front-running vectors:

- Same-registry replay after success is blocked by `seq + 1`.
- Same-registry copied front-running is possible.
  Strategy: observe `reveal_key`, `new_next`, and `sig` in the mempool and
  submit an equivalent registry update first. This does not change the key-state
  if the script constrains the output root, but it can grief the honest
  transaction or capture unconstrained side effects.
- Missing check: the spec does not explicitly require the inclusion proof root
  to equal the consumed identity UTxO's root, nor the output root to equal the
  deterministic MPF update result.
  Strategy: in a loose implementation, replay a stale proof or publish an
  output root that does not correspond to the checked update.

Collision vectors:

- A `KeyDigest` collision lets a different pubkey satisfy the pre-committed
  digest. This is assumed infeasible.
- A malicious `new_next` with no known pubkey preimage bricks future rotation.
  This is not a forgery, but it is a liveness failure the spec should call out.

### Value-write

Forgery vectors:

- The current-key signature check is the core security check, but
  `vk_from_tx_signatories` is underspecified. On Cardano, script-visible
  signatories are normally key hashes, not raw Ed25519 verification keys.
  Strategy: exploit implementation ambiguity about which verification key is
  being checked, especially in transactions with multiple signers.
- The redeemer should carry `vk : PubKey`, and the script should check
  `blake2b_256(vk) == keyState.cur_digest` and
  `verify_ed25519_signature(vk, auth_msg, sig)`. If a Cardano tx signer is also
  required, that must be a separate, precisely specified check.

Replay and front-running vectors:

- Missing check: `auth_msg` does not bind the value-cage input root, output
  root, UTxO reference, operation proof hash, validity interval, or nonce.
  Strategy: replay the same signed `op` while `identity_root` is unchanged, or
  apply it to a different compatible value-cage state.
- Missing check: `auth_msg` does not bind a value-cage policy id or thread
  token.
  Strategy: replay the same value-write authorization in another cage that
  interprets `op` the same way.
- Missing check: `auth_msg` does not bind transaction recipients or other
  side-effect outputs.
  Strategy: front-run the signed operation and redirect any unconstrained
  benefits.

Collision vectors:

- An MPF identity-root collision allows authorization replay across different
  key-state snapshots. This is assumed infeasible only if the MPF hash scheme is
  specified with domain-separated canonical node encodings.
- A value-root or operation encoding collision can make the signed `op` mean
  different things to different implementations unless `MpfsOp` serialization
  is canonical and typed.

## Additional findings

1. The spec should not rely on text field names inside signed CBOR maps unless
   it also defines exact canonical map encoding. Fixed arrays with versioned
   domain tags are cheaper and less ambiguous on-chain.

2. `identity_root` in `auth_msg` is an indirect binding to `keyState`. Include
   `seq` and `cur_digest` directly in the signed message as defense in depth
   and to simplify audit logs.

3. Every hash input should be domain-separated: AID hash, key digest, MPF leaf,
   MPF branch, MPF empty node, rotation message hash if introduced, and
   operation/proof hashes.

4. The spec should define whether signatures are over raw CBOR bytes or over a
   Blake2b-256 digest of a canonical message. Ed25519 can sign arbitrary
   messages, but signing a fixed-size digest can reduce on-chain and wallet
   ambiguity if the domain separation is done before hashing.

5. There is no explicit expiry or nonce for value-write authorizations. Without
   one, a valid signature can remain live indefinitely until the next identity
   rotation, which may be much longer than intended.

6. The registry and value-cage scripts must enforce thread-token continuity.
   It is not enough to check that a reference input has the right token; updates
   must also preserve the singleton token and deterministic root transition.

7. The spec should describe compromised-next-key handling. If the next key is
   compromised before rotation, the attacker can rotate as soon as they learn or
   choose `new_next`. KERI-style pre-rotation protects against current-key
   compromise, not next-key compromise.

8. The design should state its non-goals. It is a Cardano-native current-state
   authorization mechanism inspired by KERI, not a full KERI implementation
   unless off-chain KEL replay, witnesses, receipts, and duplicity handling are
   added.

## Prioritized recommendations

1. Add inception self-auth. Require `cur_key` to sign a canonical
   domain-separated inception message containing `aid`, `cur_key`,
   `next_digest`, network id, registry policy id, and registry thread token.

2. Mandate deterministic serialization. Define the exact canonical CBOR or
   Plutus Data encoding for `InceptionEvent`, `rot_msg`, `auth_msg`, `MpfsOp`,
   and MPF node hashes. Reject non-canonical off-chain inputs before signing.

3. Add explicit domain separation everywhere. Separate AID hashes, key digests,
   signature messages, MPF leaves, MPF branches, and value operations with
   fixed protocol/version tags.

4. Strengthen rotation messages:

```
rot_msg = cbor({
  domain: "cardano-keri/rotation/v1",
  network_id,
  registry_policy_id,
  registry_thread_token,
  aid,
  input_identity_root,
  cur_digest,
  old_next_digest,
  seq_from,
  seq_to,
  new_next
})
```

The script should reconstruct this message from the consumed identity state and
the proposed update.

5. Strengthen value-write messages:

```
auth_msg = cbor({
  domain: "cardano-keri/value-write/v1",
  network_id,
  identity_registry_policy_id,
  identity_thread_token,
  value_cage_policy_id,
  value_cage_thread_token,
  aid,
  key_seq,
  cur_digest,
  identity_root,
  value_input_root,
  value_output_root,
  op_hash,
  nonce_or_counter,
  valid_from,
  valid_until
})
```

If binding both roots is too expensive, bind a canonical hash of the exact MPFS
transition proof and all user-visible side effects.

6. Clarify verification-key handling for value writes. Do not use the undefined
   phrase `vk_from_tx_signatories`. Put the raw `vk : PubKey` in the redeemer,
   verify its digest against `keyState.cur_digest`, verify the Ed25519
   signature with that key, and separately specify any required Cardano
   transaction signer checks.

7. Require every MPF proof to be anchored to the actual input root and every MPF
   update to produce the exact output root in the continuing UTxO. Specify
   domain-separated MPF node encodings.

8. Add replay controls for value writes. Use a per-AID or per-value nonce,
   counter, consumed authorization UTxO, or short validity interval. Binding
   only to `identity_root` leaves signatures reusable for too long.

9. Treat copied front-running explicitly. Either prove it is harmless by
   constraining all transaction side effects in the scripts, or bind
   authorizations to the relevant transaction effects and require controller
   tx-level signatures where appropriate.

10. Document the trust boundary: on-chain MPFS authorization trusts the live
    Cardano identity UTxO and does not provide full KERI historical guarantees
    without an off-chain KEL replay and witness layer.
