# Spec: detached-signature authorization envelope (Option A)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/39
Epic: https://github.com/lambdasistemi/cardano-keri/issues/34

Status: Draft — design-only. Decided items are stated as decisions;
everything still open is under [Open questions](#open-questions).

## Problem

The entity being authorized often never signs the executing transaction:
batcher-executed DEX orders, ceremony assemblers, oracle-submitted cage
writes (`docs/design/business-cases/index.md`, factored-core item 4;
`docs/design/business-cases/regulated-defi.md` §2). Required-signer checking
(Option B) has nothing to find in those transactions. Authorization must
travel *inside the data* as a detached Ed25519 signature envelope, verified
on-chain against the Layer-1 identity registry.

`docs/architecture/value-auth.md` already defines a value-write `auth_msg`
for the singleton-key illustration. This spec generalizes it into **one
envelope layout for every gated purpose** (value writes, orders, contract
transitions, admission-cage operations, override verbs), threshold-aware per
the list-shaped `KeyState` of #24, and states the replay, freshness, and
uniqueness rules that `value-auth.md` leaves implicit. Where the two
documents disagree, this spec wins and `value-auth.md` is reconciled in the
same PR that implements it.

## Scope

- Normative envelope layout (fields, canonical encoding, signing procedure).
- Normative Aiken verification **contract** (inputs, checks, failure modes)
  — no implementation in this PR.
- Domain-tag registry extension (`docs/design/aid-model.md` table).
- Option B documented as the optimization with its decision criterion.
- Uniqueness (anti-replay) enforcement patterns per consumer class.

Out of scope: the per-case payload schemas (order terms, transition bodies —
last-mile adapters, M5), the bridge implementation that produces envelopes
(#41), and the scoped-override verb semantics (#40, which *consumes* this
envelope).

## Envelope

### Fields

```
Envelope {
  domain        : ByteArray        -- purpose tag, "cardano-keri/<purpose>/v1"
  network_id    : Int              -- Cardano network magic discriminator
  consumer      : (PolicyId, AssetName)
                                   -- thread token of the gate/cage that may
                                   -- accept this envelope
  trie_key      : ByteArray[32]    -- signer identity (stable, from inception)
  key_seq       : Int              -- KeyState.seq the signers claim (freshness)
  payload_digest: ByteArray[32]    -- blake2b_256(purpose-specific payload)
  nonce         : ByteArray        -- uniqueness material, semantics per
                                   -- consumer class (see Uniqueness)
  valid_from    : POSIXTime
  valid_until   : POSIXTime
}
```

Why each field exists:

| Field | Attack it kills |
|---|---|
| `domain` | cross-purpose confusion: an order signature replayed as a cage write, a ceremony transition replayed as an override verb |
| `network_id` | cross-network replay: a preprod test envelope executed on mainnet |
| `consumer` | cross-cage replay: the same order executed on a second venue; the same authorization consumed by an unrelated gate |
| `trie_key` | signer substitution: binding to the stable identity handle, not to a key that rotates |
| `key_seq` | stale-key replay across rotation — see [Freshness rule](#freshness-rule-decided) |
| `payload_digest` | payload substitution: batcher executes different terms than signed |
| `nonce` | same-consumer replay — see [Uniqueness](#uniqueness-decided-per-consumer-class) |
| `valid_from`/`valid_until` | unbounded shelf life of captured envelopes |

**Signer key-state reference — decided: `trie_key + key_seq`, not
`identity_root`.** Binding the identity MPF root would pin the envelope to
one registry snapshot; roots advance on every inception/rotation/close, so
ordinary pending envelopes would go stale through no action of the signer
(the fragility argument already recorded in
`docs/vetting/analysis-codex.md`). `key_seq` binds exactly the fact the
signer must vouch for — "these signatures come from key state N" — and the
verifier resolves that leaf against any root in the registry reference
window at execution time (`docs/architecture/value-auth.md`, window root
selection).

### Canonical encoding and what is signed

```
env_bytes  = canonical_cbor(Envelope)          -- RFC 8949 §4.2, per the CBOR
                                               -- determinism rules in
                                               -- docs/design/aid-model.md
env_digest = blake2b_256(env_bytes)
sig_i      = Ed25519.sign(sk_i, env_digest)    -- each signer, same digest
```

Every signer signs the **same 32-byte `env_digest`**. Rationale: the digest
is small enough to move through wallet/hardware signing channels and
multi-party collection flows; the semantic protection against blind-signing
is the `IntentTranscript` display requirement
(`docs/architecture/veridian-bridge.md`), which the bridge MUST extend to
envelope production — the transcript shows the decoded envelope fields, not
the digest.

On-chain, the verifier does **not parse** attacker-supplied CBOR. The
redeemer carries the envelope as typed fields; the script *constructs*
`env_bytes` with a fixed serialization function and hashes it. That
serializer is protocol surface under constitution III: its byte layout is
frozen at v1 and changes only with a new `/v2` domain tag plus regenerated
cross-layer vectors (constitution II — `gen-vectors` is the single source;
the off-chain Haskell encoder and the Aiken encoder must agree byte-for-byte
on the vectors).

### Domain tags

The envelope reserves the `cardano-keri/<purpose>/v1` namespace already
established in `docs/design/aid-model.md`. Existing tag
`cardano-keri/value-write/v1` becomes the first envelope instance. New tags
this spec reserves (payload schemas defined by their consumers):

| Purpose | Tag | Consumer class |
|---|---|---|
| Value write | `cardano-keri/value-write/v1` | cage `Modify` (exists) |
| Order intent | `cardano-keri/order/v1` | order/pool gate (M5 adapter) |
| Contract transition | `cardano-keri/transition/v1` | state-machine validators (M4 pilot) |
| Cage admission | `cardano-keri/admission/v1` | admission cage (#38) |
| Scoped override | `cardano-keri/override/v1` | override knob (#40) |

A verifier instance accepts exactly one tag. Tags are compared as full byte
strings, not prefixes.

## Verification contract (Aiken)

One library function, no local state, usable from any validator:

```
verify_envelope(
  registry_ref   : ReferenceInput,   -- identity registry UTxO (CIP-31)
  freeze_ref     : ReferenceInput,   -- freeze registry UTxO
  expected_domain: ByteArray,        -- the consumer's own tag
  expected_consumer: (PolicyId, AssetName),  -- the consumer's own token
  payload_digest : ByteArray[32],    -- recomputed by the CALLER from the
                                     -- action actually being performed
  tx_validity    : ValidityRange,
  proof          : EnvelopeProof,
) -> Bool                            -- True or fail
```

```
EnvelopeProof {
  envelope        : Envelope          -- typed fields, serialized on-chain
  key_list        : WeightedKeyList   -- revealed: [(vk, weight)] + threshold,
                                      -- per the list-shaped KeyState of #24
  sigs            : [(Int, ByteArray[64])]  -- (index into key_list, sig)
  inclusion_proof : Proof             -- trie_key → leaf, registry root window
  root_used       : ByteArray         -- which window root the proof targets
  freeze_proof    : Proof             -- absence of active FreezeMarker
}
```

Checks, in order — each is a distinct failure mode:

1. **Domain**: `envelope.domain == expected_domain`.
2. **Network**: `envelope.network_id` matches the verifier's compiled-in
   network parameter.
3. **Consumer**: `envelope.consumer == expected_consumer`.
4. **Registry resolution**: `root_used ∈ registry_datum.roots`;
   `inclusion_proof` proves `envelope.trie_key → leaf` at `root_used`
   (no-op-update inclusion, as in `specs/23-identity-auth/spec.md`).
5. **Status**: `leaf.status == Active`; `freeze_proof` shows no active
   `FreezeMarker` for `trie_key` (`marker.seq == key_state.seq` semantics
   per `docs/architecture/identity-ops.md`).
6. **Freshness**: `envelope.key_seq == leaf.key_state.seq` — strict, see
   below.
7. **Key list binding**: `blake2b_256(canonical_cbor(key_list)) ==
   leaf.key_state.cur_digest` (the k-of-n commitment of #24; a single key is
   the 1-of-1 degenerate case).
8. **Threshold**: indices in `sigs` are strictly increasing (no duplicate
   key counted twice); `Σ weight(key_list[i]) ≥ key_list.threshold`; every
   `Ed25519.verify(key_list[i].vk, env_digest, sig_i)` holds, where
   `env_digest` is computed on-chain from `envelope` (serializer above).
9. **Payload**: `envelope.payload_digest == payload_digest` (the caller
   recomputes it from the action it is actually about to permit — the
   verifier never trusts a digest the submitter merely asserts *about* the
   action).
10. **Validity**: `tx_validity` has finite bounds and
    `tx_validity ⊆ [valid_from, valid_until]`. An unbounded transaction
    validity range fails.
11. **Uniqueness**: delegated to the consumer class — the function itself is
    stateless; see next section. Callers MUST implement exactly one of the
    three patterns.

The function is O(key_list size + proof depth), independent of how many
leaves the identity owns; exec-unit budgeting per batch size is measured at
implementation time (as `specs/23-identity-auth/spec.md` does).

### Freshness rule (decided)

**An envelope is valid only at the exact `key_seq` it names. Rotation
invalidates all outstanding envelopes of that identity.**

Defense of the decision: rotation is the owner's only self-service kill
switch against a stolen *current* key — the pre-rotation property
(`docs/design/trust-model.md`). Any grace rule ("seq N or N+1") lets a
thief's envelopes survive the victim's recovery rotation, which inverts the
recovery story precisely in the emergency it exists for. The cost falls on
the honest path: a routine rotation kills in-flight orders and
partially-collected ceremony signatures, and the bridge must re-sign. That
cost is bounded and visible; the alternative's cost is a silent security
hole. Consequence for consumers: rotation frequency is an operational
choice, and the bridge (#41) MUST surface "outstanding envelopes will be
invalidated" at rotation time.

### Uniqueness (decided: per consumer class)

There is no global spent-nonce set on-chain and this spec does not invent
one — tracking spent nonces in a shared UTxO would serialize all envelope
consumers through a single state cell, which is exactly the contention MPFS
exists to avoid. Uniqueness is always derived from state the consumer
already owns. Three patterns, fixed per domain tag:

1. **Carrier consumption** (`order/v1`): the envelope rides in the datum of
   a carrier UTxO (the order); the carrier is spent exactly once, so the
   envelope executes at most once *per carrier*. `nonce` is a random 32-byte
   value chosen at signing; it discriminates otherwise-identical orders in
   audit trails but is not checked on-chain. Residual accepted risk: a third
   party can copy a captured envelope into a *second* self-funded carrier
   whose terms hash to the same `payload_digest` — since payout address and
   amounts are inside the digest, the duplicate pays the original signer
   from the copier's funds. Recorded as attributed-flow noise, not a fund
   loss; per-case adapters that cannot accept it must escalate to pattern 2.
2. **Per-leaf monotonic counter** (`value-write/v1`, `admission/v1`,
   `override/v1`): `nonce` encodes a big-endian counter; the consumer's leaf
   stores the last accepted counter and the validator checks
   `counter == last + 1` and writes it back. State lives where the write
   already happens; no extra cell. This serializes envelopes *per identity
   per consumer*, which matches these flows (registry writes are serialized
   by the cage UTxO anyway).
3. **State-machine progression** (`transition/v1`): the payload itself names
   the contract state being left (`payload = {state_id, transition, ...}`);
   the state UTxO is consumed, so replaying the envelope has nothing left to
   transition. `nonce` is unused (zero-length).

### Validity-bound semantics

Bounds are POSIXTime, compared against the transaction validity interval as
the ledger presents it to Plutus (slot-to-time conversion is the ledger's;
the envelope never mentions slots). The check is interval containment
`tx_validity ⊆ [valid_from, valid_until]`, so the envelope bound holds at
*every* moment the transaction could validate. Consumers SHOULD reject
`valid_until - valid_from` above a per-purpose ceiling (venue policy); the
library enforces only containment and finiteness.

## Attack list

| # | Attack | Stopped by | Residual / open |
|---|---|---|---|
| 1 | Replay same envelope in a different tx, same consumer | uniqueness pattern of the domain tag (checks 11) | pattern-1 duplicate-carrier noise, accepted above |
| 2 | Replay across cages/venues | `consumer` binding (check 3) | — |
| 3 | Replay across networks (preprod → mainnet) | `network_id` (check 2) | — |
| 4 | Cross-purpose confusion (order bytes accepted as override) | `domain` full-string match (check 1); one tag per verifier instance | — |
| 5 | Stale key-state: envelope signed at seq N, executed after rotation to N+1 (incl. thief racing the victim's recovery rotation) | strict `key_seq` equality (check 6) | honest in-flight envelopes die at rotation — accepted; ceremony ergonomics in open Q2 |
| 6 | Batcher executes different terms than signed | `payload_digest` recomputed by the caller from the actual action (check 9) | everything *outside* the digest is batcher-controlled by construction: batch composition, ordering, MEV. Adapters MUST enumerate what their payload digest covers; ordering fairness is out of scope here (case-local problem per `docs/roadmap.md`) |
| 7 | Threshold splicing: combine partial signatures from two different envelopes to fake a quorum | every signature is over the full `env_digest`; signatures from different envelopes verify against different digests (check 8) | — |
| 8 | Duplicate-signer inflation: same key counted twice toward the threshold | strictly increasing index rule (check 8) | — |
| 9 | Key-list substitution: attacker supplies a friendlier key list | `cur_digest` commitment binding (check 7); the list is committed at inception/rotation, frozen into `trie_key` lineage per #24 | — |
| 10 | Frozen/closed identity keeps acting | status + freeze-marker checks (check 5) | freshness of the freeze root is window-bounded — minutes-grade floor per factored-core item 5, never sanctions-grade |
| 11 | Unbounded validity: captured envelope executed months later | finite-bounds requirement (check 10) | wide bounds are venue policy; library cannot know the right ceiling |
| 12 | Non-canonical CBOR second preimage on `env_digest` | on-chain serializer constructs the bytes; attacker-supplied encodings are never hashed (encoding section) | off-chain producers must use the vector-tested encoder (constitution II) |
| 13 | Asserted-digest laziness: verifier trusts `payload_digest` without recomputation | contract requires the *caller* to pass its own recomputed digest (check 9 wording) | adapter-review item; cannot be enforced by the library signature alone |

## Option B — required-signer (the optimization)

Documented per `docs/architecture/value-auth.md`, unchanged in substance:
when the AID owner signs the executing transaction, the consumer checks
`blake2b_224(vk) ∈ tx.extra_signatories` for enough keys of the revealed
list to meet the threshold, after the same registry resolution, status,
freeze, and key-list-binding checks (steps 4, 5, 7). No envelope, no nonce,
no validity bounds: transaction uniqueness and lifetime are ledger-native.

**Decision criterion for a gate**: Option B is permitted iff the authorized
party's keys sign the executing transaction *in every flow the gate serves*.
One batcher-shaped flow anywhere in the gate's surface forces Option A for
that gate (a gate accepting both modes for the same action doubles its
attack surface for no user benefit). Hardware/custody isolation of KERI keys
from Cardano payment flows is an additional reason to force Option A even
where B is technically possible.

## Consumers and freeze order

The Layer-4 bridge (#41) produces envelopes; every case consumes them
(factored core item 4). M3 starts as soon as the producer-facing surface of
this spec is frozen — it does not wait for all of M2 (`docs/roadmap.md`).

**Freezes first (M3 blocker, constitution III surface):**

1. Envelope field list and canonical serialization (`env_bytes` layout).
2. `env_digest` construction and "sign the digest" procedure.
3. Domain-tag registry rows above.
4. Uniqueness pattern assignment per tag (the bridge must know whether to
   generate counters or random nonces).
5. Cross-layer test vectors for encoder parity (`gen-vectors`).

**May move later without breaking the bridge:** verifier-internal proof
shapes (`EnvelopeProof` field order, window-root selection details),
exec-unit budgets, Option-B plumbing — all verification-side.

The bridge inherits two obligations from this spec: extend
`IntentTranscript` to display decoded envelope fields before Signify signs,
and warn on rotation that outstanding envelopes die.

## Acceptance criteria

Contract-level; they become executable tests when #39's implementation
slice lands, and the M2 vertical demo (#45) exercises the full path.

- A 2-of-3 threshold identity produces an envelope; verification passes with
  any two valid signatures and fails with one, with a duplicated signer, or
  with signatures over a different envelope's digest.
- The same envelope is rejected by: a consumer with a different thread
  token, a verifier with a different domain tag, a network with a different
  id.
- After the identity rotates, the envelope is rejected (seq mismatch);
  after re-signing at the new seq, it passes.
- A frozen identity's envelope is rejected while `marker.seq ==
  key_state.seq` and accepted after a rotation clears the marker (per
  identity-ops semantics).
- Transaction validity ranges outside the envelope window — and unbounded
  ranges — are rejected.
- Pattern-2 consumers reject `counter != last + 1`; pattern-3 replays find
  no state to transition.
- Off-chain (Haskell) and on-chain (Aiken) serializers agree on the
  `gen-vectors` corpus byte-for-byte.

## Open questions

1. **Signify raw-signature capability (riskiest).**
   `docs/architecture/veridian-bridge.md` asserts Signify "exposes signing
   operations: sign a message with the current key". Whether signify-ts can
   produce a *bare* Ed25519 signature over an arbitrary 32-byte digest — as
   opposed to an indexed, CESR-framed signature over CESR-framed material —
   is not verifiable from the docs bundled in this repo or the plugin corpus
   (no KERI/Signify sources bundled). If CESR framing is unavoidable, the
   on-chain verifier must reproduce the framing bytes around `env_digest`,
   which changes the frozen signing procedure. Must be settled by a
   spike against signify-ts before the M3 freeze — it sits exactly on the
   items that freeze first.
2. **Ceremony envelopes across rotation.** Strict seq binding means a
   multi-party ceremony whose signature collection straddles a routine
   rotation of *any* signer must re-collect. Is re-collection acceptable
   ceremony UX (institutional-contracts pilot #37), or do ceremonies need a
   "no rotations during collection" convention — and if so, whose tooling
   enforces it?
3. **Pattern-1 residual: attributed-flow noise.** Duplicate self-funded
   carriers replaying an order envelope pay the original signer but create
   order flow attributed to an identity that placed it once. For a regulated
   venue, is externally-injected attributed flow a compliance problem
   (spoofing-shaped) even when economically harmless? If yes, `order/v1`
   escalates to pattern 2 and serializes each trader's concurrent orders —
   a real UX cost that should be decided with the DeFi adapter owner, not
   defaulted here.
4. **Weighted-list reveal size.** Check 7 reveals the full key list in the
   redeemer on every verification. For large n (board-custody QVI/LE AIDs),
   is the exec-unit and size cost acceptable, or does v1 need a capped n
   (e.g. n ≤ 8) stated in #24's KeyState spec?
5. **`valid_from` necessity.** Post-dated envelopes (valid_from in the
   future) enable "authorize now, execute in tomorrow's window" flows but
   also widen the captured-envelope surface. Keep both bounds, or is
   `valid_until` alone enough for v1 consumers?
