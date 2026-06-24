# Cryptographic Vetting — AID Operations on Cardano

**Scope:** `docs/aid-ops.md` (Inception, Rotation, Value-write).
**Threat model used:** a well-resourced adversary with full mempool visibility, the
ability to bribe a block producer for ordering, and the capacity to force shallow
chain reorgs. Off-chain key storage compromise is considered only where the spec
claims it is survivable (pre-rotation).

---

## Executive summary

The **identity layer is sound**: AID self-certification, pre-rotation, and
monotonic sequencing are correctly constructed, and the use of a single global
trie *prevents* (rather than merely *detects*) duplicity, which is stronger than
stock KERI. Front-running cannot steal an AID, and a stolen *current* key cannot
advance the sequence. Those core claims hold.

The **value-write layer is where the protocol is weak**, and it is the layer the
MPFS use case actually depends on. Two of the findings are high severity:

1. The anti-replay binding for value-writes is the *global* `identity_root`. That
   value is simultaneously **too coarse** (constant for the entire lifetime of a
   key-state → signatures are replayable for as long as nobody rotates) and
   **too shared** (it changes on *any* unrelated inception/rotation → an in-flight
   value-write is invalidated by activity it has nothing to do with). A single
   field cannot be both a per-operation nonce and a key-state pin; here it is
   neither well.

2. The value-write authorization mechanism does not type-check against Cardano.
   `cur_digest = blake2b_256(PubKey)` (32 bytes) can never equal a Cardano
   signatory key hash `blake2b_224(PubKey)` (28 bytes), so
   `blake2b_256(vk_from_tx_signatories) == cur_digest` is unsatisfiable as
   written. The full verification key cannot come "from tx signatories"; it must
   be supplied in the (attacker-controlled) redeemer, which collapses all
   value-write security onto the single Ed25519 signature over `auth_msg` — the
   very object that has no fresh nonce (finding V1).

| # | Finding | Severity | Op |
|---|---|---|---|
| V1 | `auth_msg` anti-replay relies on global `identity_root`; no per-transition nonce | **High** | Value-write |
| V2 | Signer-resolution is hash-size-inconsistent; security collapses onto the redeemer sig | **High** | Value-write |
| V3 | Single global identity UTxO → contention DoS; one inception-or-rotation per block; stale proofs | **Medium** | Inception / Rotation |
| V4 | Inception is unauthenticated (no signature) → griefing + no liveness/possession proof | **Medium** | Inception |
| V5 | No revocation / death; trie grows unboundedly | **Medium** | All |
| V6 | Reorg replay of value-writes (and rotations) when `identity_root` recurs | **Medium** | Value-write / Rotation |
| V7 | CBOR non-canonicalization → AID and signed-message ambiguity | **Low** | All |
| V8 | No domain separation between `rot_msg` and `auth_msg` | **Low** | Rotation / Value-write |
| V9 | Ed25519 signature malleability not addressed (canonical-S) | **Low** | Rotation / Value-write |
| V10 | Identity thread token must be a *verified* one-shot NFT; datum must be inline | **Medium** | Value-write |

Recommendation in one line: **make value-writes carry their own monotonic,
locally-scoped nonce (bind to the value-cage pre-state, not the global identity
root) — or drop the app-level signature entirely and require the AID key to be a
native required-signer of the transaction, letting the ledger's UTxO-uniqueness
provide replay protection for free.**

---

## 1. Op-by-op audit

### 1.1 Inception

**Claimed guarantee — self-certification.** `AID = blake2b_256(cbor(InceptionEvent))`,
verified on-chain by check 1. This is correct and the central strength of the
design: to register AID `X` you must exhibit an inception event that hashes to `X`,
and that event embeds `cur_key`. Pre-image resistance of blake2b-256 means an
adversary cannot manufacture a *different* event hashing to a *chosen* AID. The
"no signature required" claim is defensible **for the binding** — the AID is the
proof of pre-image knowledge.

**Front-running / MEV.** The inception event is fully public in the redeemer, so a
mempool adversary can copy it verbatim and submit a competing transaction.
*Crucially, this does not transfer control*: to register AID `X` the attacker must
reuse the victim's exact event, which embeds the victim's `cur_key` and
`next_digest`. The resulting key-state therefore still points at the victim's keys.
Self-certification neutralizes takeover. What remains:

- **Registration griefing.** The attacker's copy registers first; the victim's own
  inception then fails the absence proof (check 2), wasting fees and creating
  operational confusion. The victim can still *use* the AID (it resolves to their
  keys), but did not create the UTxO.
- **UTxO-attribute capture.** The inception event commits only to
  `{cur_key, next_digest}`. It does *not* commit to the UTxO address, staking part,
  min-ADA, or any auxiliary datum. Whoever lands the registration chooses those.
  If the identity registry is a single global trie this is mostly moot, but any
  per-AID UTxO attribute that matters off-chain is attacker-selectable on a
  front-run. (See V4.)

**Replay.** Re-submitting the same inception after confirmation fails the absence
proof. Submitting it in the same block as a competitor: both spend the single
identity UTxO, so they serialize and only one lands with identical state — no
double-registration of the same AID is possible. Inception replay is *prevented
on-chain*; only the front-run-to-grief residue remains.

**Signature malleability / CBOR.** None in the signature sense (no signature). But
the AID is a hash of a CBOR encoding, so encoding non-determinism is a correctness
hazard — see V7.

### 1.2 Rotation

**Claimed guarantee — pre-rotation.** Correct and well-constructed. Rotation is
authorized by `reveal_key` (the *next* key), not by `cur_key`. Check 1 forces
`blake2b_256(reveal_key) == next_digest`, i.e. the revealed key is exactly the one
pre-committed; check 2 proves possession of its private half. A thief of `cur_key`
is *never* consulted in rotation and therefore cannot advance the sequence. This
matches KERI's model (the `rot` event is signed by the keys being rotated *to*).

**Front-running / "what if the attacker learns `reveal_key` early".** When the
rotation is broadcast, `reveal_key` (public) and a signature over
`rot_msg = cbor({aid, seq+1, new_next})` become visible before confirmation. The
adversary can:

- **Replay the rotation verbatim** (copy the redeemer, race it in). This succeeds
  but produces *the victim's intended end-state* — `cur_digest` becomes
  `blake2b_256(reveal_key)`, whose private key the victim holds; the attacker only
  ever saw the *public* `reveal_key`. Net effect: griefing (stolen fee, lost race),
  not takeover.
- **Substitute a different `new_next`? No.** That would change `rot_msg` and
  invalidate the signature; the attacker cannot forge under `reveal_key`.

The pre-rotation commitment is therefore **binding tight enough** in the sense the
brief asks: revealing the *public* `reveal_key` plus a signature does not leak its
private key (Ed25519 is not private-key-leaking) and does not compromise the *next*
rotation, whose security rests on the still-secret pre-image of `new_next`. The
commitment is only as *hiding* as the next keypair is random — a deterministically
derivable next key would break hiding, but that is a key-management property, not a
protocol flaw. (Full discussion in §2.)

**Replay across reorg.** If a rotation `seq 4→5` is rolled back, the key-state
returns to `seq 4` with `next_digest = blake2b_256(reveal_key)`, and the captured
rotation tx is valid again. Re-applying it reproduces the same end-state — harmless
in isolation. It becomes relevant only combined with value-write replay (V6).

**`new_next` grinding (spec Q6).** The rotator may set `new_next` to any 32-byte
value, including one equal to an existing AID. This does **not** pollute the AID
namespace: AIDs are `blake2b_256(cbor(event))` while `next_digest` is
`blake2b_256(pubkey)` — different pre-image domains, and `next_digest` is never
re-interpreted as an AID. Setting `new_next` to a value with no known key pre-image
only **bricks the rotator's own next rotation**. Self-harming, not an attack on
others. (This is, incidentally, the only "death" mechanism available — see V5.)

**Signature malleability.** See V9; not exploitable for takeover because
`reveal_key` is pinned by `next_digest` (a small-order/substitute key would fail
the digest check).

### 1.3 Value-write

This is the operation that fails. The claimed guarantee — *"`identity_root` in
`auth_msg` ties the authorization to the exact key-state snapshot; a replayed
signature from a previous rotation cannot be reused because `identity_root` would
have changed"* — is **false in both directions** of the timing it cares about.

- **`identity_root` is constant between trie mutations.** It changes only on an
  inception or rotation of *some* AID. During the (potentially long) life of a
  key-state, `auth_msg = cbor({aid, op, identity_root})` is a **constant**. The
  signature over it is therefore replayable in every block until the next trie
  mutation. For an `Update`, replay re-imposes a stale value `V` onto a leaf the
  owner may have since moved to `V'` (a value-rollback attack). The binding to the
  key-state snapshot is real, but a snapshot can authorize *unboundedly many*
  operations, which is exactly what an anti-replay nonce is supposed to prevent.

- **The same coarseness is also a liveness bug.** Because the root is *global*, any
  unrelated inception/rotation between sign-time and inclusion changes
  `identity_root` and **invalidates an honest in-flight value-write**. In a busy
  system a value-write can be perpetually invalidated by other people's identity
  activity. So the single field is *too coarse* for replay protection and *too
  volatile* for liveness at the same time. (V1.)

**Signer resolution does not type-check (V2).** Check 3 is
`blake2b_256(vk_from_tx_signatories) == keyState.cur_digest`. On Cardano,
`tx.extra_signatories` yields `VerificationKeyHash = blake2b_224(PubKey)` (28
bytes), not full keys; and `cur_digest = blake2b_256(PubKey)` (32 bytes). The two
can never be equal, and you cannot recover a full `vk` from a signatory list. So
`vk` must be passed in the redeemer (attacker-controlled), and the only real check
is `verify_ed25519_signature(vk, auth_msg, sig)` with `vk` pinned by check 3's
digest comparison. The Cardano transaction-level witness contributes **nothing** to
authorization as specified. All value-write security thus rests on a single
signature over a nonce-free message — compounding V1.

**Anti-replay within one block (brief 3a).** Multiple identical value-write txs in
the same block all carry the same valid `(vk, sig, op)` and the same constant
`identity_root`; each is independently valid. The only thing stopping duplicates is
the *value cage's own* state machine (e.g. "leaf already exists"), which is outside
this spec. Nothing in `auth_msg` prevents intra-block replay.

**Reorg replay (brief 3b/3c, V6).** A reorg that restores a prior `identity_root`
re-validates every signature bound to it. If the rollback also restores a
pre-rotation (e.g. compromised) key-state, captured value-write signatures *and*
the compromised current key are re-enabled together. UTxO re-registration with an
identical root is the same class. The spec documents no settlement-depth assumption
for treating a key-state as final.

**Thread-token / datum trust (V10).** Check 1 requires the reference input to carry
the identity thread token. This is only sound if (a) the minting policy is a
verified **one-shot NFT** (otherwise an attacker mints a second "identity UTxO" with
an attacker-chosen root and arbitrary key-states → total break), and (b) the
`identity_root` is read from an **inline datum** (CIP-32). If a datum *hash* is used,
the root is not directly readable on-chain and resolution can be griefed. Neither
property is stated.

---

## 2. Pre-rotation binding strength (brief 2)

`blake2b_256(reveal_key) == next_digest` is a hash commitment to a 32-byte Ed25519
public key. Assessed on the three axes that matter:

- **Binding:** strong. blake2b-256 is collision-resistant (~128-bit); the committer
  cannot later open `next_digest` to a *different* key. ✔
- **Hiding:** strong **iff** the next keypair is sampled with full entropy. A
  high-entropy Ed25519 public key makes the digest a hiding commitment. The risk is
  not cryptographic but operational: if next keys are derived deterministically from
  a low-entropy seed or a predictable KDF path, the digest stops hiding and an
  observer could pre-compute `reveal_key`. **Recommend the spec mandate independent,
  full-entropy generation of each pre-committed key**, since the whole forward
  security argument depends on it.
- **"Attacker learns `reveal_key` before confirmation":** the only thing revealed
  on-chain at rotation is the *public* `reveal_key` and a signature. Neither leaks
  the private key. So an early-learning adversary can at most replay the victim's
  own rotation (→ victim's intended state) — **the binding holds**. The forward
  guarantee for the *next* hop rests entirely on `new_next`'s pre-image remaining
  secret, which it does.

**Where the binding is genuinely *not* tight: the message, not the commitment.**
`rot_msg = cbor({aid, seq+1, new_next})` omits any binding to the *current* key
being rotated out beyond what `seq` implies. This is acceptable because `(aid, seq)`
uniquely identifies one transition on a single-trie chain, *but* there is no domain
tag separating `rot_msg` from `auth_msg` (V8), and no explicit settlement assumption
(V6). The commitment is tight; the **signed envelope around it is under-bound**.

Bottom line: pre-rotation is correctly designed and survives the specific attack the
brief raises. Harden the *envelope* (domain separation, settlement depth) and the
*key generation discipline* (entropy), not the commitment primitive.

---

## 3. Value-write anti-replay via `identity_root` (brief 3)

Covered in §1.3; summarized against the three sub-cases:

| Sub-case | Prevented by `identity_root` binding? | Why |
|---|---|---|
| Same sig, same block, multiple txs | **No** | `identity_root` is constant; every copy is valid. Only the value cage's own state machine may reject duplicates. |
| Replay after a reorg restoring the old root | **No** | Restored root re-validates all sigs bound to it; pairs dangerously with a restored compromised key-state. |
| Replay after UTxO re-registration with same root | **No** | Identical-root re-creation re-validates captured sigs. |

> *"What if an MPF root collides or is predictable?"* (spec Q3) — Collision is
> infeasible (blake2b-256). Predictability is the wrong worry: the root is **public
> and read directly** from the reference input, so it is fully known by design. The
> problem is not that it is guessable but that it is **insufficiently frequent and
> non-local** — it is a property of the whole trie, not of the specific operation
> being authorized. Replay protection needs a nonce that advances **once per
> value-write**, scoped to **this AID's** state, which `identity_root` is not.

The correct anti-replay object is the **pre-state of the thing being mutated**: the
value cage's root (or a per-AID/per-leaf monotonic counter held in the value cage,
which the value-write spends and updates anyway). Binding `auth_msg` to that gives
tight, local, single-use authorization with no global coupling. See Recommendation R1.

---

## 4. Inception front-running (brief 4)

Answered in §1.1. The decisive point: **a copied redeemer registers the same AID,
and the same AID is self-certifying to the victim's keys.** An adversary cannot
"claim a known AID" in any sense that grants control — control is determined by the
hash pre-image, which embeds the victim's `cur_key`. The residual harms are
griefing (failed victim tx, wasted fees), UTxO-attribute capture, and the deeper
structural issue that **inception is unauthenticated**: because no signature is
required, *anyone* who observes an inception event can register it, and nothing
proves the registrant actually possesses `cur_key`'s private half (liveness). KERI
inception events are signed by the inception keys; this spec drops that. See V4 / R3.

---

## 5. Key-compromise recovery (brief 5)

**If `cur_key` is stolen, the attacker CAN:**
- Perform arbitrary **value-writes** (insert/delete/update) until the victim
  rotates — value-writes are authorized by the *current* key. This is full
  data-plane control for the compromise window.
- **Replay** any value-write signatures they capture, and (via V1) keep replaying
  them for as long as `identity_root` is unchanged — i.e. the damage can outlive a
  naive "just stop signing" response.

**The attacker CANNOT:**
- **Rotate.** Rotation needs `reveal_key` (the next key), whose private half the
  attacker does not hold. They cannot lock the victim out by rotating to attacker
  keys. ✔ (This is the property that makes the design worth using.)
- **Forge a fresh value-write** under a *new* `op` they did not capture, since they
  cannot produce a signature under `cur_key` for a message they haven't seen signed.
  (They have arbitrary `op` choice only by *replaying* captured signatures, which are
  pinned to the captured `op`.)

**Is the damage bounded?** In *time* — yes, by rotation. In *effect* — only
partially. Two leaks widen the bound beyond what the spec implies:
1. The compromise window allows *unbounded* writes, and for MPFS leaves with
   economic meaning that is real loss, not just nuisance.
2. Because value-write signatures lack a fresh nonce (V1) and reorgs can restore a
   root (V6), captured signatures can be **replayed after** the victim rotates,
   under a reorg that restores the pre-rotation root. So rotation is not a clean
   cut-off as long as V1/V6 stand. **Fixing V1 (per-transition nonce) is what makes
   rotation a true recovery boundary.**

Recovery also assumes the victim can *win the rotation race* — see V3: the attacker
cannot forge a rotation, but can spam the single identity UTxO to delay the victim's
rotation from landing. The spec should guarantee the identity UTxO is spendable
**only** by a valid rotation (reveal_key-authorized), so a stolen `cur_key` cannot
even consume it to grief.

---

## 6. Missing revocation / death (brief 6)

There is no revocation, retirement, or death operation. Consequences for MPFS:

- **Lost-key bricking.** If the next key is lost, the AID can never rotate and never
  be retired; its leaves are frozen forever with no GC path.
- **No clean kill on compromise.** The only "stop future rotation" trick is to
  rotate to a `new_next` with no known pre-image (a tombstone digest). But that does
  **not** stop value-writes — the just-rotated-to current key still authorizes them.
  So even the tombstone trick leaves the data plane live. There is genuinely no way
  to disable an AID's authority.
- **Unbounded trie growth.** AIDs are never removed, so the identity trie grows
  monotonically; MPF proof sizes are `O(log N)`, so everyone's per-tx verification
  cost creeps up over time with no archival/eviction story.

For the MPFS use case this is a real gap: registries usually need both an
"abandon/retire" semantic and a way to reclaim or tombstone the state owned by a
dead identity. **Recommend an explicit revocation op** (a final key-state flag that
makes the trie entry reject all future rotations *and* value-writes), plus a
documented policy for leaves owned by a revoked AID. See R4.

---

## 7. Cardano-specific risks (brief 7)

- **Single-UTxO contention / double-spend (V3).** Every inception and every rotation
  spends-and-recreates the one identity UTxO. At most **one inception-or-rotation
  per block** can succeed; competing txs that referenced the now-spent UTxO become
  invalid (not merely reordered). A griefer can spam cheap self-rotations/inceptions
  to invalidate everyone else's pending identity ops, and can race a victim's
  recovery rotation. Their MPF absence/inclusion proofs also go **stale** the moment
  the root moves, so honest ops must be rebuilt against the latest root. This is a
  practical scaling and griefing bottleneck. *Mitigations:* shard the identity trie
  across multiple UTxOs/threads (keyed by AID prefix), or adopt a batched/relayed
  submission model. Document the chosen settlement depth.
- **Value-writes use the identity UTxO as a CIP-31 reference input** — good, they do
  not contend on it. But a rotation that spends the identity UTxO in the same block
  as a value-write that references it creates an **ordering coupling**: if the
  rotation is sequenced first, the reference input no longer exists and the
  value-write is invalid. Within-block ordering is the block producer's choice → a
  producer can selectively invalidate value-writes by ordering a rotation ahead of
  them (MEV/grief).
- **Ordering within a block.** Because of single-UTxO consumption, the *first*
  spender of the identity UTxO wins any inception/rotation race outright; a block
  producer (or a briber) decides the winner. Self-certification still prevents
  takeover, but ordering decides *who pays/creates* and *whose recovery lands first*.
- **Datums vs inline datums (V10).** The identity UTxO **must** use an inline datum
  (CIP-32) so `identity_root` is directly and trustlessly readable from the
  reference input. A datum-hash design forces the root to be supplied in the witness
  set and griefs reference-input resolution. Mandate inline.
- **Thread-token uniqueness (V10).** Reference-input trust hinges on the thread token
  being a genuine one-shot NFT. The minting policy must be a verified single-mint
  policy; otherwise the whole value-write authorization is forgeable by minting a
  rogue identity UTxO.

---

## 8. Additional findings

- **V7 — CBOR canonicalization.** `AID`, `rot_msg`, and `auth_msg` are all
  `cbor(...)` then hashed/signed. If the encoding is not pinned to a single
  canonical form, (a) off-chain AID derivation can disagree with the on-chain
  recomputation (registration fails / wrong AID), and (b) an off-chain signer and
  the on-chain verifier can disagree on the message bytes (signature fails or,
  worse, a second valid encoding exists). The on-chain side should standardize on
  Plutus `serialiseData` semantics and **off-chain tooling must reproduce those exact
  bytes**. Mandate canonical CBOR explicitly (spec Q5 answered: *yes, canonical CBOR
  must be required*).
- **V8 — domain separation.** `rot_msg` and `auth_msg` are positional-looking CBOR
  records sharing the `aid` field and signed by Ed25519 keys whose roles transition
  (a `reveal_key` that signs a rotation *becomes* the `cur_key` that signs
  value-writes). A live cross-protocol replay is currently **blocked** by the digest
  pinning (a value-write verifies under the *current* key, a rotation under the
  *next* key, and those never coincide) and by `identity_root` being non-attacker-
  chosen — so this is hardening, not an open exploit. Still, add a distinct type tag
  / prefix to each signed message; it is nearly free and removes a whole class of
  future footguns.
- **V9 — Ed25519 malleability.** Confirm `verify_ed25519_signature` enforces
  canonical `S < L` (RFC 8032 strict). If not, a second valid signature exists for
  the same message — irrelevant to the replay findings (which do not key on signature
  bytes) but relevant to any off-chain dedup that does. Small-order / substituted
  public keys are **not** a threat here because every verification key is pinned by a
  digest (`cur_digest` / `next_digest`), so a rogue key fails the hash check before
  signature verification.
- **On-chain vs off-chain boundary (spec Q8).** The chain stores only the *current*
  key-state in the trie, not the full KEL — but because every event is an on-chain tx
  redeemer, the KEL is fully reconstructible by indexing chain history; no trust in
  an off-chain log is required. More importantly, the single global trie **prevents
  duplicity** rather than merely detecting it, which is stronger than KERI's
  eventual-consistency model. The boundary is drawn correctly for identity. It is
  drawn *incorrectly for value-writes*: a bare signature is treated as a one-time
  authorization on-chain, but without a fresh nonce (V1) consumers cannot rely on
  that on-chain — they would have to track freshness off-chain, which defeats the
  point. Fixing V1 pulls the value-write boundary back on-chain where it belongs.

---

## 9. Prioritized recommendations (concrete edits to `docs/aid-ops.md`)

**R1 — [High] Give value-writes a real, local, single-use nonce.** Replace the
`auth_msg` definition so it binds to the *pre-state of the value cage being mutated*
(plus a per-AID monotonic counter), not the global identity root:

```
auth_msg = cbor({ tag: "aid/auth/v1",
                  aid,
                  seq,                 -- key-state seq: pins the rotation epoch locally
                  op,
                  cage_root_pre,       -- MPF root of the VALUE cage BEFORE this op
                  counter })           -- per-AID monotonic, stored in the value cage
```

`cage_root_pre` makes each signature valid for exactly one value-cage transition;
`seq` pins the key epoch without coupling to *other* AIDs' activity (fixes the V1
liveness half — unrelated rotations no longer invalidate you); `counter` defends
against the case where two ops have the same pre-root. Keep `identity_root` *out* of
the anti-replay role.

**R2 — [High] Fix signer resolution (and consider deleting the app-level sig).**
State whether `vk` is supplied in the redeemer (then say so, and note check 3 only
pins it to `cur_digest`) — or, preferred, **redefine `cur_digest` as the Cardano key
hash `blake2b_224(PubKey)` and require the AID's current key to be a real
`extra_signatories` entry of the value-write transaction.** Then the ledger's native
UTxO-uniqueness gives replay protection for free (every tx body is unique), and the
bespoke `auth_msg` signature can be dropped entirely. Pick one model and make the
hash sizes consistent; the current text is unsatisfiable as written.

**R3 — [Medium] Authenticate inception.** Add `sig = Ed25519(cur_key, cbor(InceptionEvent))`
to `IncRedeemer` and verify it on-chain. This proves possession/liveness of
`cur_key`, prevents anyone from registering an observed event, and binds the
registrant. (Self-cert already prevents takeover; this closes the griefing/liveness
gap.)

**R4 — [Medium] Add revocation/death.** Define a terminal key-state flag (e.g.
`revoked: Bool`, set by a `Revoke` op signed by the current key) that makes the trie
entry reject **all** future rotations and value-writes. Document the GC/tombstone
policy for value-cage leaves owned by a revoked AID. Note explicitly that a
tombstone `new_next` stops rotation but not value-writes, so it is *not* revocation.

**R5 — [Medium] Document settlement depth and harden against reorg/UTxO replay.**
State the minimum confirmation depth at which a key-state (and a consumed
value-write nonce) is treated as final, so V6 replays are out of the trusted window.
With R1's `cage_root_pre`/`counter`, a restored root no longer re-validates a spent
value-write.

**R6 — [Medium] Address single-UTxO contention.** Either shard the identity trie by
AID prefix across independent thread UTxOs, or specify a batched/relayed inception &
rotation path, so one global UTxO is not a per-block bottleneck and a griefer cannot
stall everyone's identity ops (and the victim's recovery rotation). Require that the
identity UTxO is spendable **only** by a valid rotation, so a stolen `cur_key` cannot
consume it to grief.

**R7 — [Low/Medium] Pin the trust assumptions.** Mandate (a) canonical CBOR matching
Plutus `serialiseData`, with off-chain tooling reproducing the exact bytes (V7);
(b) an **inline** datum (CIP-32) for the identity UTxO (V10); (c) a verified one-shot
NFT minting policy for the identity thread token (V10); (d) a distinct domain tag in
every signed message (V8); (e) canonical-`S` Ed25519 verification and full-entropy
generation of each pre-committed next key (V9 / §2).

---

### Appendix — what is *correct* and should not be changed

- AID self-certification via `blake2b_256(cbor(InceptionEvent))` — sound; do not add
  a signature *to the AID derivation* (it would break the self-certifying property).
  R3's inception signature is a *separate* authorization, not part of the AID.
- Pre-rotation (`blake2b_256(reveal_key) == next_digest`, rotation signed by the next
  key) — sound; survives the early-reveal attack; gives clean separation between a
  compromised current key and the ability to advance the sequence.
- Monotonic `seq` + single-trie duplicity prevention — stronger than stock KERI; keep
  it (only sharding under R6 would reintroduce a cross-shard duplicity question to
  handle).
