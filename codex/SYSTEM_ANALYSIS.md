# System Analysis: KERI + cardano-aid + MPFS Value Cages

## Executive summary

The composed system should be described as a Cardano-consumable checkpoint of
KERI key-state, not as KERI on-chain. Cardano can give MPFS scripts a cheap,
deterministic authorization snapshot, but it does not by itself inherit KERI's
witness-backed duplicity detection, CESR semantics, delegation semantics, or
watcher gossip.

The main architectural risk is the bridge invariant. The controller self-relays
KERI rotations to Cardano, but the current documents do not define a mandatory
binding between a Cardano registry update and a specific KERI key event. Without
that binding, a Cardano key-state can be valid under the cardano-aid script while
still being unaudited, stale, or divergent from the KERI witness pool. Smart
contracts will follow the Cardano state; KERI-aware verifiers may reject it.

Anchoring on Cardano neither solves nor fundamentally worsens KERI equivocation
detection. It adds a single public checkpoint branch and a Cardano-final order
for MPFS consumers. That helps only if off-chain monitors compare each Cardano
checkpoint to the witnessed KEL. If users treat the Cardano registry as a
replacement for witnesses, it can hide duplicity from the data plane by making
one branch look canonical to contracts.

The stale-checkpoint window is the most important safety/liveness trade-off.
When the KEL rotates but the Cardano registry lags, MPFS scripts continue to
authorize the old on-chain key-state. That is acceptable only for applications
that explicitly tolerate old-key authority during bridge delay. For compromise
recovery, the maximum cryptographically safe lag is zero: until the Cardano
rotation is confirmed at the application's settlement depth, a stolen current key
can continue writing to value cages.

The docs have already absorbed much of the earlier crypto vetting in
`architecture/*` and `design/*`, but `docs/aid-ops.md` remains an older spec with
the rejected `vk_from_tx_signatories` path, weak `auth_msg`, no inception
self-auth, and an under-bound rotation message. The project needs one canonical
spec before implementation or review.

## 1. Equivocation surface

KERI detects equivocation by observing conflicting KEL events for the same AID,
normally through witnesses, watchers, and duplicity evidence. A Cardano singleton
identity UTxO has a different property: it serializes one accepted on-chain
state per Cardano chain fork. That serialization is useful for contracts, but it
is not KERI duplicity detection.

Cardano anchoring can help off-chain detection if every on-chain checkpoint is
bound to a KERI event identifier and is monitored by KERI-aware watchers. In
that mode, Cardano acts like an additional public witness of "this branch was
used for the data plane at this slot." A verifier can replay the KEL, verify
witness receipts, recompute the event identifier, and check that the Cardano
checkpoint matches.

Cardano anchoring has no useful effect on equivocation detection if the registry
stores only `{cur_digest, next_digest, seq}` with no KERI event binding. The same
key-state can be reached, represented, or claimed outside the witnessed KEL
context. The chain will show that some valid cardano-aid rotation occurred; it
will not show that the rotation is the witnessed KERI event.

It can hinder the composed trust model socially and operationally if the data
plane treats Cardano as canonical and stops paying attention to KERI duplicity.
For example, a compromised controller that can produce conflicting KERI events
can publish branch A to a witness pool while submitting branch B to Cardano.
Cardano will not reject branch B merely because branch A exists. MPFS scripts
will authorize branch B until an off-chain monitor detects and escalates the
divergence.

The correct claim is therefore narrow: Cardano gives one globally ordered branch
for Cardano consumers; KERI witnesses detect whether that branch is the only
valid KEL branch.

## 2. Bridge trust

The bridge is currently a self-relay: after each KERI rotation, the controller is
expected to submit a Cardano transaction updating the registry. That relay is a
live trust boundary.

If the controller does not submit the Cardano transaction, the on-chain key-state
does not change. KERI-aware off-chain verifiers may consider the new key current,
but MPFS contracts will still accept the old key-state. The system has no oracle
or automatic propagation mechanism to close that gap.

If the controller delays, the data plane runs under stale authority for the delay
plus the chosen Cardano settlement depth. This is mostly a liveness issue during
routine rotations: the new key cannot authorize MPFS writes yet, and the old key
still can. It becomes a safety issue during compromise recovery: the stolen
current key remains valid for value-writes until the Cardano checkpoint advances.

If Cardano and KERI operations are out of order, consumers can disagree. A
Cardano rotation submitted before the corresponding KERI event is witnessed gives
contracts an unaudited key-state. A KERI rotation witnessed before the Cardano
transaction confirms gives KERI-aware clients the new state while contracts still
use the old state. A Cardano update that is never matched by a valid KERI event
is a bridge failure unless the architecture explicitly allows Cardano-native
identity independent of KERI.

Without on-chain CESR parsing, the system can still prove correspondence, but
only by anchoring a digest of the KERI event. Each Cardano registry update should
carry or store a bridge record such as:

```text
KeriCheckpoint {
  registry_domain
  keri_aid_canonical
  keri_event_said
  keri_sequence_number
  prior_keri_event_said
  current_key_digest_canonical
  next_key_digest_canonical
  cardano_registry_key
}
```

The on-chain script can cheaply enforce internal consistency over fixed byte
strings and signatures, while off-chain verifiers do the KERI work: parse CESR,
verify the event SAID, replay the KEL, check witness receipts, and compare the
result to the Cardano checkpoint. Without this event-level commitment, equality
of a current public key digest is not a proof that the Cardano state corresponds
to a specific KERI KEL event.

## 3. AID format compatibility

KERI AIDs and the current cardano-aid identifiers are not the same object.
KERI AIDs are CESR-qualified identifiers with derivation codes, often rendered
as qb64 text such as `EKYLUMm...`. The current cardano-aid AID is a raw
`blake2b_256(canonical_cbor(InceptionEvent))` value. Treating these as
interchangeable 32-byte identifiers would lose type information and can create
ambiguous registry keys.

The bridge needs an explicit canonical mapping. A reasonable pattern is:

```text
cardano_registry_key =
  blake2b_256(
    "cardano-aid/keri-registry-key/v1" ||
    canonical_cesr_identifier_bytes
  )
```

The canonical CESR identifier bytes must include the KERI derivation/type code,
not only the raw digest payload. If the implementation uses qb64 text as the
canonical input, it must define normalization exactly. Prefer a CESR canonical
binary representation if the KERI tooling exposes one.

The registry should keep the original KERI AID available to off-chain tooling,
either in a checkpoint datum, event record, or indexed metadata. The 32-byte
Cardano trie key is an index; it is not a substitute for the KERI identifier.

Key digest mapping also needs a decision. If MPFS uses value-authorization
Option B, the current key digest becomes a Cardano payment key hash
(`blake2b_224(PubKey)`), which is not a KERI key digest. That is simple for
Cardano scripts but couples KERI control keys to Cardano signing keys. If the
system must support general KERI keys and CESR key material, use Option A with a
redeemer-carried public key and a domain-separated digest over the canonical KERI
public key representation. Do not mix KERI digests, Cardano key hashes, and
cardano-aid `KeyDigest` under one unqualified field name.

## 4. Threat model completeness

The composed system adds new failure modes because KERI finality, Cardano
settlement, and MPFS data authority can diverge.

| Actor | Added capability in the composed system |
|---|---|
| Passive eavesdropper | Can correlate public Cardano registry updates, MPFS value writes, timing, fees, UTxOs, and AIDs. KERI logs may already be public, but the Cardano data plane adds economic and application metadata. Mempool observation also exposes pending bridge and value-write transactions before settlement. |
| Active network attacker | Can delay or partition KERI traffic and Cardano submission differently, creating stale-checkpoint windows. Can feed clients different views: a fresh witnessed KEL off-chain and a stale Cardano registry on-chain, or the reverse. |
| Compromised current key | Cannot rotate under the pre-rotation rule, but can authorize MPFS writes for as long as Cardano still lists that key. After an off-chain KERI recovery rotation, the attacker still has data-plane authority until the Cardano checkpoint confirms. |
| Compromised next key | Can race or perform the next Cardano rotation if the on-chain script accepts the reveal key without requiring a witnessed KERI-event binding. This can make MPFS follow an attacker branch even while KERI witnesses eventually report duplicity. |
| Compromised witness, 1-of-N | Usually cannot forge KERI consensus alone, but can contribute to asymmetric views, missing receipts, or false reassurance if the bridge or monitors do not require the configured witness threshold before treating a KERI event as eligible for Cardano anchoring. |
| Compromised watcher | Cannot change KERI or Cardano state directly, but can fail to report divergence between the witnessed KEL and Cardano checkpoints. Clients depending on that watcher may accept stale or divergent data-plane authority. |
| Compromised bridge / relay | Can omit, delay, reorder, or selectively submit checkpoints. If the bridge also controls signing keys, it can submit Cardano-valid states that do not correspond to witnessed KERI events. KERI alone has no equivalent data-plane desynchronization layer. |
| Cardano block producer / MEV actor | Can order, censor, or delay registry and value-cage transactions. A rotation that spends the identity UTxO can be ordered before a value-write that references the old UTxO, invalidating the value-write. This ordering surface does not exist in plain KERI. |
| Cardano chain reorg | Can roll back a checkpoint or value-write that off-chain systems already observed. KERI witnesses may consider a rotation final while Cardano rolls back the corresponding checkpoint, or vice versa. Applications need a settlement-depth rule. |

The docs name most of these pieces, but they do not yet state the full composed
threat model or define what MPFS should do when KERI and Cardano disagree.

## 5. Liveness vs safety trade-off

During bridge lag, MPFS scripts see stale key-state. There is no cryptographic
way for a Cardano script to know that an off-chain KERI rotation has happened
unless the rotation has been checkpointed into the registry UTxO that the script
reads.

For routine rotations, bounded lag may be operationally acceptable. It means the
old key remains the MPFS authority and the new key is not yet active on the data
plane. The system should document this as delayed activation, not as immediate
KERI/Cardano synchronization.

For compromise recovery, stale authority is a safety break. If `cur_key` is
stolen and the controller rotates in KERI, the attacker can keep writing to MPFS
until the Cardano rotation confirms. Under a strict "revocation should stop
writes" requirement, the maximum safe lag is zero confirmed Cardano blocks: the
data plane is not safe until the registry state has advanced and settled.

In practice the architecture must choose a policy:

- Treat Cardano as the authority for MPFS and state that KERI rotations do not
  affect value cages until Cardano settlement.
- Pause or quarantine value writes for an AID when monitors see a KERI rotation
  that is not yet checkpointed.
- Require bridge submission within an explicit SLA and alert or suspend on
  missed deadlines.
- Include short validity intervals for detached value authorizations if Option A
  remains supported.
- Define a settlement depth for registry updates and value writes before
  off-chain systems act on them as final.

The current docs say settlement depth is application-specific. That is not enough
for the composed security claim; the MPFS integration needs at least a default
depth and a stale-checkpoint handling rule.

## 6. What Cardano adds vs plain KERI

cardano-aid does not strengthen KERI's core identity guarantees by default. It
does not verify CESR, replay KELs, validate witness receipts, or detect
duplicity. Those remain off-chain KERI responsibilities.

What it adds is a bridge for Cardano-native enforcement:

- MPFS scripts can authorize writes using a reference input instead of an oracle.
- Cardano consensus gives one ordered checkpoint branch for smart contracts.
- Value writes and identity snapshots can be composed atomically under the UTxO
  rules that Cardano scripts can see.
- After settlement, Cardano gives public evidence that a particular checkpoint
  was accepted by the ledger at a particular point in chain history.

There are scenarios where this is stronger than a witness pool alone for Cardano
applications. A KERI witness pool can tell an off-chain verifier what the
controller's key-state should be, but a Plutus script cannot call that pool or
parse an unbounded KEL. A settled Cardano checkpoint gives contracts a local
predicate they can enforce. That is an enforcement and composability guarantee,
not a stronger KERI duplicity guarantee.

The most accurate positioning is: KERI remains the identity-event audit layer;
Cardano is the smart-contract authorization projection of that audit layer.

## 7. Revocation and the data plane

The current system has no complete revocation operation. The docs correctly note
that a tombstone rotation with `new_next = 0x00...00` freezes future rotations
but leaves `cur_digest` live. Any cage script that checks only `cur_digest` will
continue to authorize value-writes for the tombstoned AID.

A real data-plane revocation needs an on-chain state bit or status enum:

```text
KeyState {
  cur_digest
  next_digest
  seq
  status : Active | Suspended | Revoked | Retired
  last_keri_event_said
}
```

All MPFS cage scripts must reject writes unless `status == Active`. If this check
is optional per cage, revocation is not system-wide.

Who can submit revocation depends on the intended KERI semantics:

- Deliberate retirement can be authorized by the current key or next/recovery key
  and submitted by anyone carrying the valid authorization.
- Current-key compromise should not rely only on the compromised current key. It
  needs authorization by the pre-rotated next key, a KERI recovery event, a
  delegator event, or another explicitly registered recovery authority.
- Delegatee revocation requires the delegator relationship to exist in the
  Cardano checkpoint model. The current `KeyState` has no delegation field, so
  the chain cannot enforce delegated revocation without a new representation.
- If revocation is represented only in the off-chain KEL, the same bridge-lag
  problem applies: MPFS keeps accepting writes until the revocation checkpoint is
  submitted and settled.

Without on-chain CESR parsing, the revocation transaction can still bind to the
KERI revocation event by storing its SAID and requiring the relevant key
authorization on-chain. Full semantic validation of "this KERI event revokes that
AID under the KERI rules" remains an off-chain monitor responsibility unless the
Cardano model is extended to encode those KERI rules.

## Prioritized gaps and changes needed

1. **Define the KERI-to-Cardano checkpoint invariant.** Every Cardano registry
   update that claims to represent KERI should bind to a specific KERI event
   SAID, KERI sequence number, prior event SAID, canonical KERI AID, and
   canonical key digest mapping. Off-chain verifiers must have a deterministic
   procedure to replay the KEL and compare it to the checkpoint.

2. **Specify canonical AID and key mappings.** Do not treat KERI qb64 AIDs,
   cardano-aid self-certifying hashes, Cardano payment key hashes, and KERI key
   digests as interchangeable byte strings. Define domain-separated registry
   keys and preserve enough CESR information for audit.

3. **Add real revocation for the data plane.** Add a `status` field and a
   revocation operation, define who can authorize each revocation class, and
   require every MPFS cage to reject revoked or suspended AIDs.

4. **State the stale-checkpoint policy.** Define bridge submission expectations,
   settlement depth, maximum tolerated lag, and what value cages or off-chain
   monitors do while a KERI event is witnessed but not yet checkpointed.

5. **Document equivocation handling explicitly.** Cardano does not detect KERI
   duplicity. The architecture should specify the monitor that compares KEL
   branches to Cardano checkpoints, the evidence it emits, and whether divergence
   suspends MPFS authority.

6. **Unify the documentation.** `docs/aid-ops.md` still describes the older
   weak value-write and signer model, while `architecture/value-auth.md` and
   `design/*` contain the corrected options. Keep one normative spec and mark
   replaced material as historical.

7. **Choose one value-write signer model.** Option B is simpler and fits Cardano
   scripts, but it couples KERI authority to Cardano payment keys. Option A
   preserves detached KERI-style signatures but requires the fully-bound
   `auth_msg`, counter, validity interval, and public key in the redeemer.

8. **Make the reference-input trust root normative.** Require a verified
   one-shot registry thread NFT, inline datum for the root, thread-token
   continuity, consumed-root proof anchoring, deterministic output roots, and
   domain-separated MPF node encodings.

9. **Promote the composed threat model into the design docs.** Include current
   key, next key, witness, watcher, bridge, Cardano block producer, and reorg
   actors, with concrete effects on MPFS value authority.

10. **Resolve single-UTxO operational limits.** Sharding, batching, or an
    explicit low-throughput assumption is needed before claiming production
    suitability for a global identity registry.
