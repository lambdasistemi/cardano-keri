# Design analysis: KERI-AID-owned MPFS leaves (claude)

> Read-only analysis. Repos inspected: `cardano-mpfs-onchain`
> (`validators/cage.ak`, `types.ak`, `lib.ak`, `docs/architecture/proofs.md`),
> `cardano-mpfs-offchain` (`cardano-mpfs-cage-tx`, `cardano-mpfs-client`,
> `cardano-mpfs-verify`), `cardano-mpfs-offchain-issue-258`,
> `cardano-mpfs-cage`. The brief names `state.ak / request.ak / shared.ak`;
> the live on-chain repo has consolidated these into `cage.ak` (spend+mint),
> `types.ak` (datums/redeemers), `lib.ak` (token helpers). The older split
> survives only in a `dist-newstyle` cache. Citations below use the live files.

## Executive summary (5 lines)

1. Today the oracle has **unilateral write authority over every leaf**: `Modify`
   only checks an MPF proof + the *oracle's* signature; the `requestOwner` field
   is never bound to leaf content at fold time (`cage.ak:517-605`), and request
   UTxOs are permissionlessly creatable, so the oracle fabricates any `(key,value)`.
2. The hard constraint holds: PlutusV3/Aiken can do **one Ed25519 verify + blake2b
   per touched leaf**, but cannot replay a KEL — so on-chain ownership must reduce
   to *one sig against an on-chain-anchored current key-state*, KEL replay staying
   off-chain in the pure verifier.
3. **Recommendation: Design B, in its strongest form** — a second MPF (`identityRoot`)
   mapping `AID → keyStateAnchor`, with **value-keys namespaced under their owner AID**
   (`key = H(AID ‖ subkey)`) so ownership is implicit in the key and a *single*
   identity entry covers all of an AID's leaves. This gives **O(1) rotation**;
   the naive B1 (`key → keyState`) and Design A (owner embedded in each leaf) both
   degrade to **O(leaves-owned) rotation** and are rejected.
4. Refinement: put `identityRoot` in its **own UTxO/thread token**, referenced
   read-only by data `Modify` and mutated by *permissionless, self-authorizing*
   rotation — otherwise the single oracle-signed State UTxO lets the oracle censor
   rotations and thereby keep a stolen key alive (the one residual that quietly
   breaks KERI recovery).
5. Biggest risk is not on-chain cost — it is a **wasm/js-portable Ed25519 + CESR**
   in `cardano-mpfs-verify` (its crypto today is `cardano-crypto-class`, whose
   Ed25519 is libsodium-FFI and a known wasm blocker). Prototype that build first.

---

## 0. What the code actually does today (basis for everything below)

**Datum** (`types.ak:205-222`): a single State per cage —
```aiken
State { owner: VerificationKeyHash, root: ByteArray /*32B value-MPF root*/,
        tip: Int, process_time: Int, retract_time: Int }
```
One root, one owner (a Cardano payment-key hash).

**Modify** (`cage.ak:250-277, 639-687`): `expect StateDatum(state)`, `validateOwnership`
(= oracle VKH in `extra_signatories`, `cage.ak:366-371`), then `foldl` over `tx.inputs`
with `mkAction` (`cage.ak:517-605`). For each input that is a `RequestDatum` whose
`requestToken == tokenId`, it pops one `RequestAction` and applies
`mpf.insert/delete/update(root, requestKey, …, proof)`. Final root must equal the
output datum's root (`cage.ak:675`).

**The forgery vector, precisely.** In `mkAction`, `requestOwner` is read **only** to
build the lovelace-refund list (`cage.ak:589-595`); it is **never** used to authorize
the `(requestKey, requestValue)` transition. Request UTxOs are created permissionlessly
(`Contribute` is signature-free, `cage.ak:243-249, 416-437`). Therefore the oracle can:
mint a request UTxO with `requestOwner = anyone`, `requestKey = K`, `requestValue =
Insert/Update/Delete(V)`, supply a valid MPF proof, sign as `state.owner`, and write any
leaf to any value. **`requestOwner` is a refund address + retract authorizer, not an
integrity binding.** This is the trust the brief wants the contract to remove.

**Leaf bytes** (confirmed both sides): MPF hashes key and value with **blake2b-256**;
off-chain `mkMPFHash = blake2b256` matches `blake2b_256(key)/blake2b_256(value)` in the
Aiken MPF lib. Conceptually `leaf = (blake2b(key), blake2b(value))`. Off-chain `Fact{key,
value}` are raw bytes; root is `Root ByteString` (32B).

**Verifier** (`cardano-mpfs-verify`, pure, cross-target): replays CSMT (UTxO) and MPF
(facts) inclusion/exclusion proofs against a trusted snapshot root; **no Ed25519 anywhere**
(deps: `cardano-crypto-class` for blake2b, `cborg`, `mts:{csmt-verify,mpf-write}`). No
KERI/AID/owner/per-leaf-signature/second-trie concept exists anywhere in either repo.

**Constraint check (done myself).** Aiken/PlutusV3 exposes `verify_ed25519_signature` +
`blake2b_256` and the secp256k1/BLS verifies — all single-shot, cheap enough for a handful
per tx. There is no primitive to parse CESR, iterate an unbounded event list, or walk a
pre-rotation hash-chain within budget. So the constraint in the brief is real: **on-chain
= one sig vs anchored key-state; KEL replay = off-chain.** Accepted as a hard boundary.

---

## 1. On-chain enforcement at Update, per design

### Design A — owner embedded in the leaf
Self-contained leaf: `value = encode(payload, curKeyDigest, nextKeyDigest, seq)`.
At Update of key `K`:
1. `mpf` inclusion proof of old leaf `K → oldValue` (gives the validator `curKeyDigest`,
   `nextKeyDigest`, `seq` for free — they are *inside* the proven value).
2. Redeemer carries `ownerKey` (pre-image); check `blake2b(ownerKey) == curKeyDigest`.
3. `verify_ed25519(ownerKey, msg, sig)`, `msg = H(tokenId ‖ K ‖ oldPayload ‖ newPayload ‖ seq)`.
4. `mpf.update(root, K, proof, oldValue, newValue)` writes the new leaf (with `seq+1`,
   possibly a rotated `curKeyDigest`/`nextKeyDigest`).

No second root is referenced — ownership rides *in-band*. Redeemer per leaf:
`{ proof, ownerKey, sig }`. Cheap to reference (nothing external), but see §2/§5 for why
this in-band coupling is fatal for rotation.

### Design B — parallel identity MPF (recommended; shown in its strong form)
Datum gains a root; redeemer gains an identity proof + sig per touched leaf.

```aiken
State { owner, valueRoot, identityRoot, tip, process_time, retract_time }
//                         ^ NEW: MPF root of  AID -> keyStateAnchor

RequestAction =
  | UpdateAction { valueProof: Proof          // K: oldV->V in valueRoot (existing)
                 , identityProof: Proof        // AID -> keyState in identityRoot
                 , ownerKey: ByteArray          // ed25519 pubkey pre-image (32B)
                 , ownerSig: ByteArray }        // 64B over the transition
  | Rejected                                    // unchanged (oracle GC)
```
On-chain check per touched value-leaf `K` owned by `AID`:
1. **Derive/locate owner.** *Namespaced variant (preferred):* recompute `AID` as the
   declared prefix of `K` and require `K == H(AID ‖ subkey)` (or `K`'s leading 32B == AID);
   the oracle cannot place a leaf under a prefix it can't sign for. *General variant:* read
   `ownersRoot[K] = AID` via an extra inclusion proof (a third root — see §2).
2. **Resolve key-state**: `mpf` inclusion of `AID → keyState=(curDigest,nextDigest,seq)`
   against `identityRoot` (the datum's trusted root).
3. `blake2b(ownerKey) == curDigest`.
4. `verify_ed25519(ownerKey, msg, ownerSig)` with `msg` binding `tokenId, K, op, oldV,
   newV` **and** an anti-replay term (see §0/§3 binding discussion).
5. Existing `mpf.insert/delete/update` against `valueRoot`.
6. Oracle sig still required (liveness/fee/ordering) but is **necessary-not-sufficient**.

Cost per leaf: `+1 blake2b`, `+1 MPF inclusion verify` (identity), `+1 ed25519`, on top of
the existing value-MPF op. For a batch of `m` leaves: `m` sigs + `≈2m` MPF verifies. PV3
budget makes `m ≈ 10–20` realistic; large batches must shard across txs (they are already
proof-bounded). The identity proof is `O(log |AIDs|)`; value proof unchanged.

**Why B references the owner the way it does.** The chain trusts exactly one thing it can
read locally: a root in its own input datum. So the *anchor* (identityRoot) lives in the
datum; the *proof* that `AID`'s key-state is what the KEL says is off-chain. The validator
verifies the **local step** (sig by the key whose digest the anchored state commits); it
does **not** verify the global KEL.

---

## 2. Data structures, proof composition, claiming a new key

**Roots.**
- A: one root (`valueRoot`), identity in-band → datum unchanged, *redeemer* grows. Zero new
  roots but O(n) rotation (§5).
- B-namespaced: **two** roots — `valueRoot`, `identityRoot (AID→keyState)`. Ownership is
  implicit in the key, so no `key→AID` map is needed.
- B-general (arbitrary keys): **three** roots — add `ownersRoot (K→AID)`. Each value write
  composes three inclusion proofs (`valueRoot` op, `ownersRoot[K]=AID`, `identityRoot[AID]`).

**identityRoot leaf:** `key = AID` (32B self-certifying prefix), `value =
serialize(curDigest ‖ nextDigest ‖ seq ‖ threshold-meta)`. MPF hashes both as usual.

**Proof composition (B-namespaced Update):**
`snapshot → datum(valueRoot, identityRoot)` ⟹ verify `identityRoot[AID]` (inclusion) ⟹
`blake2b(ownerKey)=curDigest` ⟹ `ed25519(ownerKey, msg, sig)` ⟹ `valueRoot` op. All four
are independent single-shot checks; none requires iteration.

**Establishing ownership of a NEW key — the genuinely hard sub-problem.** Insert proves
*absence*, and absence binds no one. Options, with honest trust assessment:
- **Self-namespacing (best).** Require `K` under `AID`'s prefix and a sig by `AID`'s current
  key. Then "owner of `K` is necessarily `AID`" is *cryptographic*, not assigned: the oracle
  cannot squat `AID`'s namespace, and there is no land-grab for *known* AIDs. Unowned space
  outside any prefix can be oracle-assigned or forbidden.
- **First-claim (race-prone).** First request to insert `K` sets `K→AID`. The oracle orders
  txs, so it always wins the race and can squat. Weak.
- **Oracle-assigned.** Oracle writes `ownersRoot[K]=AID` once; thereafter cannot alter
  content (needs `AID` sig). Trust shrinks from "forge forever" to "assign correctly once" —
  a real reduction, acceptable as a transitional/hybrid policy, but still trust.
- **Bonded.** Claim requires a deposit; slashable on dispute. Adds an oracle/court. Heavy.

**AID inception** must itself be bound: require the AID to be **self-certifying**
(`AID == H(inception event embedding curKeys + nextDigest)`, i.e. KERI's own derivation), so
`InceptIdentity` can be permissionless (absence proof on `identityRoot` + self-cert check)
yet unforgeable — the oracle can mint *its own* AIDs freely (fine) but cannot fabricate an
AID prefix matching an externally-known identity.

---

## 3. Operation model

| Op | Today | Under B-namespaced |
|----|-------|--------------------|
| **Boot/Mint** | empty `valueRoot`, owner=oracle | also empty `identityRoot` |
| **InceptIdentity** | — | permissionless insert `AID→keyState`; absence proof + self-cert |
| **Insert (claim K)** | oracle-only | sig by `AID` (identity inclusion) + `K` under `AID` prefix |
| **Update/Delete** | oracle-only | identity inclusion + **owner sig** over transition; oracle sig still needed for liveness |
| **Rotate** | — | reveal pre-rotated key (`blake2b==nextDigest`), new `nextDigest`, sig by revealed key; `mpf.update identityRoot[AID]`, `seq+1` |
| **Retract** | requestOwner VKH (`cage.ak:214-242`) | unchanged; request now also carries owner sig so it is foldable |
| **Reject/GC** | oracle, Phase-3 (`cage.ak:578-587`) | unchanged — oracle can decline, **cannot forge** |
| **End** | oracle sig + burn (`cage.ak:269-271, 336-341`) | unchanged |

**Who authorizes a leaf mutation:** *both* — the leaf owner's Ed25519 sig authorizes the
*content*; the oracle's sig authorizes *inclusion/ordering/fee*. Clean separation: forgery
needs the owner key; liveness/GC stays with the oracle.

**How the request carries the sig:** extend the off-chain `Request`/`RequestAction` to carry
`ownerKey + ownerSig` (the `Modify` builder in
`cardano-mpfs-cage-tx/.../Cage/Update.hs` and the `Request` builder in `.../Cage/Request.hs`
already thread proofs/datums; this is an additive field + hand-written `ToData` in
`.../Cage/Serialize.hs` to keep byte-parity with Aiken).

**Anti-replay binding (subtle, prototype this).** `msg` must pin the transition to *this*
cage and *this* state so a captured sig can't be reapplied. Three candidates:
- **per-leaf `seq`** in the value/owner-meta — O(1), but turns every write into a counter bump
  and pollutes the value;
- **bind to pre-state `valueRoot`** — no counter, sig valid only against the exact snapshot
  the owner saw (oracle reorder invalidates it — a feature), but multi-owner batches fold the
  root between steps, so all owners must sign vs the *initial* batch root and the validator
  must check sigs against the pre-fold root;
- **bind to `(AID, seq)` from identityRoot** — robust but serializes all of an AID's writes on
  its identity entry (contention).
Recommendation: pre-state-root binding + batch atomicity, fall back to per-leaf nonce if
concurrency demands it. **Same-batch rotate-then-write of one AID** must be ordered or
forbidden (sign against old or new key?).

---

## 4. Forgery resistance (adversarial enumeration)

**Design B-namespaced.** Oracle **CAN**: order/batch, set fee/timing, Reject/GC expired
requests, censor (refuse any write), create its *own* AIDs and own leaves under them, End the
cage. Oracle **CANNOT**: write/alter/delete a leaf under an AID whose key it does not hold;
rotate an AID it does not control; forge an AID prefix matching a known external AID
(collision-resistance); replay an owner sig onto a different transition/state (if §3 binding
holds). **Residual trust:** (a) **censorship/liveness** — mediated, not forgeable; (b)
inception/claim self-cert rests on hash collision-resistance; (c) **anchor-freshness gap**, see §5.

**Design A.** Same *content* forgery-resistance for *existing* leaves (sig vs leaf-embedded
key). But: worse first-claim (no namespacing structure to lean on), O(n) rotation, and the
data plane is polluted with identity material (every reader must parse keys out of values).
A buys the same headline guarantee at structurally worse cost.

**The residual that quietly matters (both designs, sharpened for B):** every datum mutation
spends the single State UTxO, which `validateOwnership` ties to the **oracle's** signature
(`cage.ak:260, 366-371`). If rotations also flow through that UTxO, **the oracle can censor a
rotation** and thereby keep a *stolen current key* usable for data writes. KERI's "rotate to
lock out the thief" then depends on oracle liveness — a real weakening. Fix in §5/§8
(separate identity UTxO, permissionless rotation).

---

## 5. Key rotation / compromise

**Rotation step (O(1) in B, the decisive advantage):**
`identityRoot[AID]: (curDigest, nextDigest, seq)` →
`(blake2b(revealedNextKey), newNextDigest, seq+1)` where the redeemer supplies
`revealedNextKey` with `blake2b(revealedNextKey) == nextDigest` (proves pre-rotation),
`newNextDigest`, and `rotSig = ed25519(revealedNextKey, H(AID ‖ newCurDigest ‖ newNextDigest
‖ seq+1 ‖ binding))`. Validator: identity inclusion (old) → pre-image check → sig by revealed
key → `mpf.update identityRoot`. **One Ed25519, one `mpf.update`, regardless of how many leaves
the AID owns.** In A the same rotation must rewrite every leaf carrying the key-state →
O(leaves-owned); this is the single most important reason to prefer B.

**Pre-rotation preserved.** Because rotation requires the *pre-committed next* key (not the
current one), theft of the *current signing* key does **not** enable rotation — the standard
KERI guarantee, reproduced on-chain with one hash + one verify.

**Recursion (off-chain KEL ↔ on-chain anchor).** The on-chain `(curDigest, nextDigest, seq)`
is a *checkpoint*. The full KEL — every interaction/rotation event, witness receipts,
pre-rotation chain, duplicity checks — is replayed **off-chain** to prove the checkpoint is
AID's legitimate current projection. The chain enforces only the *local* monotonic step (each
on-chain rotation signed by the revealed pre-rotated key, `seq` strictly +1); the off-chain
verifier proves *global* legitimacy and that the anchored digest equals the replayed
key-state. This is exactly the on-chain-anchor / off-chain-replay split the brief asks for.

**Compromise race + the censorship caveat.** With the current key stolen but un-rotated, the
thief can solicit *data writes* (current key still valid) until the holder lands a rotation.
If rotations are oracle-mediated, the oracle can stall the holder's rotation and extend the
thief's window. **Therefore make rotation permissionless and self-authorizing, on a UTxO the
oracle does not gate** (§8). Then the holder can always self-rotate; the worst the oracle does
is censor *data* (freeze), never *forge* and never *block recovery*.

---

## 6. Off-chain pure verifier (wasm/js)

**Chain enforces:** local step — one sig vs anchored key-state, one membership proof, root
transition. **Reader verifies (off-chain, pure):** snapshot anchor → value-MPF inclusion
(data) → identity-MPF inclusion (`AID→keyState`) → **full KEL replay** proving that key-state
is AID's true current state → (for write-receipts) the owner sig over the transition. The
verifier is the only place the *global* KERI guarantee is checked.

**Purity is preserved** — KEL replay is deterministic (parse CESR, verify per-event Ed25519,
check pre-rotation digests, detect duplicity). **But the new primitives are the portability
risk:** a CESR parser and **Ed25519 verify must compile to wasm32-wasi and GHC-JS**. Today
`cardano-mpfs-verify` carries no Ed25519, and its `cardano-crypto-class` Ed25519 is
libsodium-FFI — a known wasm blocker (consistent with this repo's documented Haskell-wasm dep
pain). A pure/wasm-friendly Ed25519 (and a minimal CESR reader) must be admitted *before* the
design is, per the constitution's verifier-portability rule. The write path (off-chain tx
builder, native) may keep using libsodium; only the *verifier* must be portable.

---

## 7. Migration / compat

- **Datum is breaking:** `identityRoot` (and, for B-general, `ownersRoot`) added to `State`.
  The existing `Migrating` path (`cage.ak:792-818`, carries root over) extends to initialise
  the new root(s) to `empty`. New script hash → new policy id → tokens migrate via atomic
  burn+mint.
- **Legacy leaves:** pre-migration leaves have no owner. Policy needed: grandfather them as
  oracle-owned (oracle retains trust over legacy data only) **or** require owners to re-claim
  via inception+claim. A hybrid (oracle-trusted legacy + KERI-owned new) shrinks trust
  incrementally without a flag-day.
- **Redeemer is breaking:** `RequestAction` grows `ownerKey/ownerSig`; new `Rotate`/`Incept`
  actions; clients must upgrade. Hand-written `ToData` in `…/Cage/Serialize.hs` keeps Aiken
  parity.
- **Budget/size:** +1 MPF verify +1 Ed25519 per touched leaf → batch sizes ~halve; script
  size grows modestly (Ed25519 + extra MPF calls are stdlib). Proof-bearing responses grow by
  one identity proof per leaf (+ owners proof in B-general).

---

## 8. Recommendation

**Adopt Design B, namespaced, with identity in its own UTxO. Reject A and reject B1.**

- **B over A:** identical content-forgery resistance, but B gives **O(1) rotation**, a single
  source of truth per identity, and a clean data plane. A's in-band key-state forces
  O(leaves-owned) rotation and pollutes values — disqualifying at scale.
- **Namespaced (`key = H(AID ‖ subkey)`) over key→keyState (B1):** B1 duplicates an AID's
  key-state per key and re-incurs O(n) rotation; namespacing makes ownership cryptographic,
  needs only one identity entry per AID, and kills squatting of known AIDs.
- **Identity in its own UTxO/thread token, referenced read-only by data `Modify`, rotated by
  permissionless self-authorizing txs:** decouples KERI recovery from oracle liveness (§4/§5),
  at the cost of one extra UTxO and serialization on the identity UTxO (shard by AID later if
  contended). If a single-UTxO design is kept for v1, document the censorship-of-rotation
  residual explicitly.

**Decisive trade-offs:** O(1) vs O(n) rotation (the swing factor); data-plane hygiene; one
extra UTxO + cross-UTxO reference (the cost of censorship-resistant rotation).

**Biggest risk:** wasm/js-portable Ed25519 + CESR in the pure verifier — a toolchain/portability
problem, not a contract one. It can sink the whole approach if it can't be built; everything
else is incremental.

**Prototype first, in this order:**
1. **wasm32-wasi + GHC-JS build of Ed25519 verify** (and a stub CESR reader) inside
   `cardano-mpfs-verify`. If this can't be made portable, stop — re-scope to a trusted-verifier
   model. *(highest-risk, cheapest to falsify)*
2. **On-chain `Modify` with identity-inclusion + per-leaf Ed25519**, measure PV3 exec units to
   fix the real max batch size.
3. **Rotation redeemer with pre-rotation reveal** on a standalone identity UTxO; prove
   O(1)-rotation + permissionless recovery.
4. **Pin the anti-replay binding** (pre-state-root vs per-leaf nonce vs identity-seq) under a
   concurrent multi-owner batch — the subtlest correctness question.

**Hybrid worth keeping:** oracle-assigned/legacy leaves coexisting with KERI-namespaced leaves
during migration — narrows trust monotonically without a flag-day, and lets steps 1–4 ship
behind real usage rather than all at once.
