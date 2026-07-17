# Spec: freeze the sovereign per-AID `CheckpointDatumV1` wire contract (#68)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/68
Epic: https://github.com/lambdasistemi/cardano-keri/issues/21
Absorbs: #77 (rotation/successor binding — F10), #79 (freshness/currentness —
F12), #81 (delegator removal / independent-only).
Downstream consumer: #24 (checkpoint validator + permissionless pre-rotation).

Ratified design inputs (do not reopen — see "Ratified invariants"):
`specs/92-checkpoint-contention/{spec.md,DECISION.md}` (sovereign per-AID
checkpoint, Candidate A), `specs/68-keystate-shape/identity-model.md`
(§6 checkpoint state, §6a two-seal handoff, §11 loss/fork),
`specs/68-keystate-shape/delegation-boundary-decision.md` (#81),
`specs/24-keystate/spec.md` ("frozen surface" KERI alignment — reused),
`docs/architecture/identity-ops.md`, `docs/design/aid-model.md`,
`docs/vetting/canonical-model-findings.md` (F10/F12/F18/F30).

!!! danger "This document is protocol surface (constitution principle III)"
    Everything under **The frozen surface**, **Threshold well-formedness and
    evaluation**, and **Signed message domains** is a versioned wire contract. It
    changes only by minting a **new version tag** (`CheckpointDatumV2`, new domain
    strings) alongside regenerated golden vectors; v1 stays resolvable under v1
    rules forever. #24 must implement exactly this shape.

---

## Problem

#92 selected the **sovereign per-AID checkpoint** (Candidate A): each KERI AID's
current authority lives in its **own** quantity-one, uniquely-tokenized checkpoint
UTxO, discovered generically by `(checkpoint_policy_id, aid_asset_name)` and read
as a CIP-31 reference input. #92 fixed only the **conceptual** checkpoint fields
(`identity-model.md` §6) and explicitly deferred the exact CBOR/wire layout to
this ticket (`specs/92-checkpoint-contention/spec.md`, "Where the current key
lives": *"#68 (not #92) freezes the exact CBOR/wire layout"*).

Until that layout is frozen, #24 cannot implement registration or rotation without
inventing schema, and Aiken/Haskell cannot share byte-identical vectors. The
canonical-model vetting also left four findings that gate #24 and are facets of
this freeze:

- **F18** — weighted-threshold well-formedness (zero weights, `threshold > sum`,
  empty sets, duplicate keys) entirely unspecified.
- **F30** — the CBOR preimage is not pinned byte-for-byte to the Aiken builtin.
- **F10 (#77)** — the rotation message does not bind the signed successor state
  (`new_next`/successor/`seq_to`), so a naive wiring lets a public reveal be
  replayed to capture the identity at `seq+2`.
- **F12 (#79)** — `identity_root` is used in two irreconcilable senses (single
  value vs sliding window); inception stales under concurrency; typed
  inconsistently.

The frozen `trie_key` preimage that framed the original #68 (F1) is **dissolved**
by Candidate A: the identity handle is the external qualified KERI AID and the
state lives in the versioned checkpoint datum, not a derived Cardano preimage
(#68 comment, 2026-07-09; `identity-model.md` §8). What survives is the **key
material + threshold + witness + message contract** — this document.

---

## Scope

**In scope — freeze + validator-free schema support:**

1. The exact versioned `CheckpointDatumV1` PlutusData/CBOR shape: constructor
   tags, field order, byte widths/domains, canonical CBOR rules (F30).
2. Current keys (`k`) + current threshold (`kt`); the next-key commitment over
   `n`+`nt`; witness set (`b`) + `toad` (`bt`); `seq`; the KERI native sequence
   (`native_sn`) and external CESR AID binding.
3. Both KERI **integer** and **fractionally weighted (multi-clause)** thresholds,
   with one deterministic normalization/evaluation and a complete rejection
   predicate (F18). 1-of-1 is the degenerate instance of the same schema.
4. Signed **inception (`icp`)** and **advance (rotation / two-seal)** message
   domains and their bindings; #77 (F10) successor-substitution/replay resistance.
5. Cardano **freshness/currentness** semantics against the per-AID UTxO
   architecture (F12/#79): uniqueness, concurrency, off-chain KERI lag,
   fail-closed evidence — no revived global sliding root.
6. The **delegation boundary** (#81): independent-AID `icp` only, `dip`/`drt`
   rejected, no passive `delegator`/`di` field.
7. **Executable** byte-identical Aiken/Haskell golden **and** negative vectors for
   a pure schema-support codec (types + canonical CBOR + threshold arithmetic +
   message-byte builders).

**Out of scope — belongs to #24 and beyond:**

- The checkpoint **spend/mint validator**, redeemers, and state-machine
  transitions (registration, normal rotation, migration, close/burn).
- **Witness-receipt** (`Ed25519.verify(witness_pk, seal_bytes, sig)`) verification
  wiring, seal **parsing**, and the two-seal handoff **enforcement** in a
  validator (this document fixes the message/commitment **bytes** those checks run
  over, not the transaction-level checks).
- MPFS absence/unicity proofs, genesis BLAKE3 byte-binding, CIP-31 reference-input
  resolution, min-ADA/exec-unit measurement, live-boundary smoke.
- Recursive **delegated-AID** proof verification, ACDC/TEL credential chains,
  emergency freeze (R-FRZ), superwatcher fraud-proof mechanics.

The boundary is deliberate: #68 supplies the **data layer** (what the bytes are
and what makes a threshold/message well-formed); #24 supplies the **transaction
layer** (which UTxOs are spent/created and which signatures are checked) that
consumes it.

---

## Ratified invariants (cross-ticket — do not reopen without a parent Q-file)

1. One quantity-one identity asset + one current script-locked checkpoint UTxO per
   AID; consumers discover it generically by `(policy_id, asset_name)` and verify
   it against the ledger; indexers affect availability only.
2. The KERI AID is the sole identity state machine. Cardano **mirrors** the
   currently accepted key state; it does not invent an old/current key separate
   from KERI. The checkpoint is a spend-linearized projection that can lag, never
   fork (`identity-model.md` §11).
3. V1 supports sovereign **independent** AIDs only: accept `icp`; reject `dip` and
   `drt`; no passive `di`/`delegator`. Recursive KERI delegation is a versioned M5
   extension (`delegation-boundary-decision.md`).
4. ACDC/TEL credential-authority chains are **not** KERI event delegation.
   Historical issuer evidence does not require a live current checkpoint; an AID
   authorizing a **new** Cardano action does.
5. Rotation/new authorization must consume or reference the unique current
   checkpoint and bind the exact successor state. Replaying, substituting the next
   commitment, changing sequence, or crossing network/policy/AID domains must fail.
6. An unseen off-chain KERI event cannot be known by a Cardano script. The contract
   states the honest staleness/fail-closed boundary and the permissionless
   evidence-bound superwatcher/freeze role; it does not recreate a global sliding
   root.

---

## The frozen surface

All multi-byte structured values are serialized by **the script's own canonical
CBOR encoding of a structured value** — never accepted as caller-supplied opaque
bytes (kills encoding-malleability, #24 attack A8). "Canonical CBOR" is pinned in
"Canonical PlutusData / CBOR rules" below and enforced byte-for-byte by the golden
vectors (F30).

### Primitive widths and domains

| Name | Type | Domain |
|---|---|---|
| `KeyDigest` | `ByteArray` | exactly 32 bytes; `= blake3_256(qb64(verkey))` — the KERI `n` entry byte-for-byte (E-native, see below) |
| `Verkey` | `ByteArray` | exactly 32 bytes; raw Ed25519 public key (current keys and witnesses) |
| `Digest32` | `ByteArray` | exactly 32 bytes; a hash output |
| `CesrAid` | `ByteArray` | exactly 32 bytes; raw E-code-stripped Blake3-256 AID digest — production KERI AIDs as-is |
| `Int` fields | `Int` | non-negative unless stated; canonical minimal-width CBOR integer |

### `CheckpointDatum` — the versioned datum

`CheckpointDatum` is a **version sum**. `V1` is **constructor index 0**
(PlutusData `Constr` tag `121`). Future versions add new constructors; a validator
that only understands v1 fails closed on an unknown constructor.

```
CheckpointDatum =
  | V1 (CheckpointDatumV1)        -- constructor index 0

CheckpointDatumV1 { -- Constr 0 of the inner record; fields in EXACTLY this order:
  0  cesr_aid       : CesrAid                 -- external AID; the identity binding (KERI `i`)
  1  cur_keys       : List<Verkey>            -- current establishment RAW verkeys (KERI `k`, decoded), positional
  2  cur_threshold  : Threshold               -- current signing threshold (KERI `kt`)
  3  next_keys      : List<KeyDigest>         -- pre-rotation next-key digests (KERI `n`), positional
  4  next_threshold : Threshold               -- pre-rotation next threshold (KERI `nt`)
  5  witnesses      : List<Verkey>            -- current witness verkeys (KERI `b`), positional
  6  toad           : Int                     -- witness threshold (KERI `bt`); 0 iff no witnesses, else 1 <= toad <= len(witnesses)
  7  seq            : Int                     -- Cardano checkpoint projection counter; starts 0, +1 per advance
  8  native_sn      : Int                     -- KERI native sequence number `s` of the reflected est. event
}
```

Field notes (nothing here is retrofittable):

- **`cesr_aid`** — the AID binding. Stored, and bound inside every message (below),
  so a checkpoint cannot be re-pointed at a different identity. Never itself
  "verified" — the qb64/derivation-code correspondence to on-chain material is the
  hybrid-genesis concern (`identity-model.md` §7c), not this schema.
- **`cur_keys`** — **raw** verkeys, not digests: authorization signature checks
  verify Ed25519 directly against the datum with **zero hashing on the hot
  path**; the KEL `k` entries are recoverable byte-for-byte by decoding the
  qb64. Positional: `cur_threshold`'s weights and clauses index into this list
  by position. Non-empty, no duplicate key.
- **`cur_threshold`** — see "Threshold". Carries the KERI `kt` faithfully
  (integer **or** fractionally weighted multi-clause), so real GLEIF/QVI configs
  round-trip byte-identically.
- **`next_keys` / `next_threshold`** — the **explicit** pre-rotation commitment:
  the KERI `n` digest list and `nt` threshold, stored as-is (each entry is a
  `KeyDigest`, so raw next keys stay secret until reveal). Storing the pair
  explicitly — instead of an aggregate hash over it — is what makes KERI
  **partial (reserve) rotation** representable: an advance may reveal any
  satisfiable subset of the committed digests and restate its own current
  threshold, exactly the KERI dual-threshold rotation rule (GLEIF's production
  Root AID rotates this way: 7 committed digests at `nt = ["1/3"×7]`, revealing
  3 with `kt = ["1/3"×3]`, carrying unexposed reserves forward). Byte-for-byte
  equal to the `n` lists of **real production KELs** — E-code Blake3, no
  Cardano-specific KEL flavor.
- **`witnesses`** — current witness **verkeys** (raw 32-byte Ed25519), because
  Cardano verifies receipts as `Ed25519.verify(witness_pk, seal_bytes, sig)`
  directly over seal bytes (`identity-model.md` §5). A non-transferable KERI
  witness AID's verkey is recoverable from its `B`-prefixed qb64; store the raw
  verkey. Positional. May be empty only if `toad = 0`.
- **`toad`** — integer witness threshold (KERI `bt`). KERI-faithful bounds
  (keripy `Kever` enforcement): `toad == 0` iff `witnesses` is empty, else
  `1 <= toad <= len(witnesses)`. A witnessed state with `toad = 0` is not a
  reachable KERI state and is rejected.
- **`seq`** — the **projection** counter. Starts at `0` at inception; each accepted
  advance sets `new.seq = old.seq + 1` (`delta = 0`; `specs/92-checkpoint-contention/spec.md`).
  This is the anti-replay/monotonic key #24 A11 and #77 bind.
- **`native_sn`** — the KERI **native** sequence number `s` of the establishment
  event whose key-state this checkpoint reflects. Distinct from `seq`: KERI
  interaction events advance `s` without changing keys, so a single Cardano advance
  may cross more than one native `s`. Bound in messages and in the §7b
  correspondence/duplicity proof so a seal at one native event cannot be replayed
  to project a different state. Strictly increasing across advances.

There is deliberately **no** `delegator`/`di` field (#81), **no** `identity_root`,
**no** `root_window`, and **no** `deposit`/`status` in the datum: status/lifecycle
is carried by the token's mint/spend lineage and the designated script address
(`specs/92-checkpoint-contention/spec.md`), not by a datum enum, and the sliding
window is dissolved (see "Freshness").

### `KeyDigest` — KERI alignment (E-native, normative)

Verified against the ToIP KERI specification and keripy
(`Diger(ser=verfer.qb64b)`, default code `E` = Blake3-256 — the production
KERI default):

```
qb64(k)   = "D" ++ b64url(0x00 ++ k)[1..]     -- 44 ASCII chars, transferable code "D"
KeyDigest = blake3_256(qb64(k))               -- 32 bytes; equals the KEL `n`-entry digest value
```

The stored `next_keys` entries equal the `n` list of **real production KELs**
(GLEIF, Veridian) byte-for-byte from public KEL data at seq 0 — no digest-agility
mandate, no Cardano-specific KEL flavor. `cur_keys` hold the **raw** verkeys
(the KEL `k` entries decoded), so authorization signature checks never hash;
blake3 runs only on the rare paths: at rotation, one single-block
`blake3(qb64(raw_key))` per revealing key (measured: **3.6% cpu / 4.5% mem**
of the mainnet per-tx budget each, spike #88 lane-packed core, vendored as
`onchain/lib/cardano_keri/blake3.ak`), and at genesis over the inception event
bytes (#24/#91's transaction layer, see "Genesis binding" below). #68 fixes
the digest **definition** and its width; the qb64 reconstruction is a fixed
33-byte → 44-char Base64url encoding shared by both codebases.

### AID asset-name derivation (locator binding — the #92→#68 pin)

`specs/92-checkpoint-contention/spec.md` fixes that the per-AID checkpoint token is
`(checkpoint_policy_id, aid_asset_name)` with
`aid_asset_name = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ canonical_qualified_aid_bytes)`
but **explicitly defers the exact `CHECKPOINT_ASSET_DOMAIN_TAG` and
`canonical_qualified_aid_bytes` encoding to #68**. This is that freeze — without it
the locator asset cannot be reproduced byte-for-byte:

```
CHECKPOINT_ASSET_DOMAIN_TAG   = UTF8("cardano-keri/checkpoint-asset/v1")   -- 32 bytes, constant
   = 0x 63617264616e6f2d 6b6572692f636865 636b706f696e742d 61737365742f7631
canonical_qualified_aid_bytes = 0x45 ‖ cesr_aid                            -- 33 bytes
   -- 0x45 = ASCII 'E', the V1 E-native (Blake3-256) derivation code — the
   -- production KERI AID default; cesr_aid is the complete 32-byte raw digest
   -- (E-code-stripped, as stored in the datum).
aid_asset_name = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ canonical_qualified_aid_bytes)
   -- blake2b_256 over the fixed 65-byte (32+1+32) preimage → 32-byte asset name
```

Rationale: minimal and **cheap on-chain** — a single native `blake2b_256` Plutus
builtin over a fixed 65-byte preimage. The outer hash is deliberately
`blake2b_256` even though the AID itself is Blake3: the asset name is a
Cardano-internal **label of** the AID (#91), never a KERI artifact, so the
cheap native builtin is correct here and blake3 stays confined to genesis and
rotation. Because the preimage is fully determined by `cesr_aid`, the asset
name is deterministic, never an independent identifier. Changing either
constant requires a new version tag.

### Genesis binding (E-native) — the hash-proof minter

`cesr_aid = blake3_256(icp bytes)` for an E-code AID. The on-chain binding
check (`blake3(icp_bytes) == cesr_aid`, plus keys-in-event equality) is
#24/#91's **transaction layer**, wired as a **hash-proof minter**: a dedicated
minting policy verifies the blake3 relation in its own transaction — using the
lane-packed single-chunk core measured in spike #88 (17.1% cpu at 300 bytes,
54.3% cpu / 71.7% mem at the 1024-byte single-chunk boundary; vendored at
`onchain/lib/cardano_keri/blake3.ak`) — and mints a proof token named
`blake2b_256(icp_bytes ‖ cesr_aid)`. Registration then recomputes that one
cheap native blake2b over the event bytes it already carries and requires the
token: no inline blake3 in the registration validator, no oracle trust.

V1 verifiable genesis is **capped at 1024 bytes** (one blake3 chunk). Measured
against production KELs, this covers the entire V1 target population: a
GEDA-scale 5-key, 5-witness inception is 966–1017 bytes; single-sig and
QVI-shaped 2-key groups are 550–660 bytes. The only real event observed above
the cap is GLEIF's own 7-key Root inception (1181 bytes) — issuer
infrastructure that never registers (and `dip` besides). Boards of 6+ keys
with a full witness pool wait for the chunk-token extension (the #97
multi-transaction lineage: chunk proofs composed by a cheap parent-node mint)
or a native `blake3` builtin CIP. #68 freezes the `cesr_aid` definition and
width; the minter is a #24 obligation.

`deriveAidAssetName(cesr_aid) -> aid_asset_name` is part of the **executable
schema-support** scope (Haskell + Aiken), with a fixed golden and adversarial
coverage (wrong derivation code, truncated/over-long `cesr_aid`, mutated AID,
substituted asset name). Any message or validator that carries `aid_asset_name` MUST
require `aid_asset_name == deriveAidAssetName(cesr_aid)` — **copying a caller-provided
asset name is insufficient**; the equality ties the locator token to the AID.

### `Threshold` — integer and fractionally weighted (KERI `kt`/`nt`)

`Threshold` is a sum; constructor indices are frozen:

```
Threshold =
  | Unweighted (m : Int)                       -- constructor 0: KERI hex-integer "m"-of-n
  | Weighted   (clauses : List<Clause>)        -- constructor 1: KERI fractionally weighted

Clause   = List<Weight>                        -- one weighted clause, positional over its key partition
Weight   = { 0 num : Int, 1 den : Int }        -- Constr 0; an exact rational in reduced canonical form
```

Semantics (KERI-faithful):

- **`Unweighted(m)`** — satisfied when the number of distinct valid signer
  positions is `>= m`. All keys carry implicit weight 1.
- **`Weighted(clauses)`** — the clauses **partition `cur_keys` positionally**:
  clause 0 covers positions `[0, len(c0))`, clause 1 covers
  `[len(c0), len(c0)+len(c1))`, and so on. Each clause is satisfied when the sum of
  the `Weight`s at its satisfied positions is `>= 1` (exact rational comparison, no
  rounding). The threshold is satisfied iff **every** clause is satisfied (clauses
  are logically ANDed). A single-clause `Weighted([[w0..wn]])` is the common vLEI
  form; multi-clause `Weighted([[..],[..]])` is the KERI "fractionally weighted
  threshold with multiple clauses".

`Weight` **canonical form** (enforced by `fromData`, see F18): `den > 0`, `num >= 0`,
`num <= den` (weight in `[0, 1]`), and `gcd(num, den) = 1` (reduced). Zero weights
are **legal KERI** — keripy's `Tholder` accepts `0 <= w <= 1` and the spec's
reserve/custodial-rotation examples use them — and the gcd rule makes `0/1` the
unique canonical zero spelling (`0/2` is rejected as unreduced). An unreduced
input (`2/4`) is **rejected**, not silently normalized — canonicalization is the
caller's obligation before constructing a typed V1 value. What is canonical is the
**reduced rational spelling** only: `1/2` and `2/4` cannot both be present because
the latter is rejected, so equal weights have one byte representation.

**Order is positional and security-significant.** `cur_keys` and the weights/clauses
of a `Weighted` threshold are aligned by position; reordering the key list, the
weights within a clause, or the clauses themselves is **not** a no-op — it changes
the datum bytes and the authority. The one KERI-mandated exception: the
dual-threshold advance maps signer evidence into `next_keys` by **digest
membership**, so a revealed subset need not preserve the committed order (the
KERI spec explicitly allows reordering between the prior-next and current key
lists).

This **supersedes** the `specs/24-keystate/spec.md` v1 restriction ("multi-clause,
nested, or zero weights — out of v1 scope"): #68 supports multi-clause weighted
thresholds directly, because every production GLEIF/QVI AID uses them
(`specs/68-keystate-shape/acdc-zoo.md` §A/B). Nested weights (a weight that is
itself a weighted list) remain **out of scope** and are rejected (F18 rule 13); no
current AID requires them and they are a genuine v2 shape.

`toad` (witness threshold) is always `Unweighted`-style integer arithmetic and is
stored as a bare `Int`; KERI `bt` has no weighted form.

### The explicit pre-rotation pair (KERI `n` + `nt`)

The pre-rotation commitment is the **explicit** `(next_keys, next_threshold)`
pair inside the datum — no aggregate `keyset_commit` hash. Each `next_keys`
entry is a `KeyDigest` (the production KEL `n` entry byte-for-byte), so
raw next keys remain secret until reveal, while the structure supports the KERI
**dual-threshold rotation rule**: at advance time the signer evidence must
satisfy the rotation's own `(new_cur_keys, new_cur_threshold)` **and** the
spent checkpoint's committed `(next_keys, next_threshold)`. This admits partial
(reserve) rotation, augmented rotation (new keys that were never pre-committed
count only toward the current threshold), and a restated current threshold —
all normative KERI. The pair must itself be F18-well-formed at every write
(inception and advance), so an AID can never commit to an unsatisfiable next
state.

### Canonical PlutusData / CBOR rules (F30)

The datum and every message preimage are **PlutusData** values
serialized with the **deterministic Plutus `Data` encoding** that both the Cardano
ledger's canonical encoder (Haskell) and Aiken's `aiken/cbor` `serialise` builtin
emit. The pinned rules:

- **Constr**: constructor index `0..6` → CBOR tag `121..127`; `7..127` →
  `1280 + (i-7)`; otherwise the `(102, [i, fields])` general form. Fields follow as
  a CBOR array.
- **Int** (`I`): minimal-width major-type 0/1 encoding; integers with
  `|n| > 2^64-1` use the bignum tags `2`/`3`.
- **ByteString** (`B`): definite-length byte string; a value longer than 64 bytes
  is split into 64-byte chunks under an indefinite-length wrapper. Every `ByteArray`
  field in this contract is `<= 32` bytes, so each is a single definite chunk.
- **List**: a CBOR array using Plutus `Data`-list conventions (definite-length
  empty list `0x80`; non-empty lists as the ledger/`cbor.serialise` produce them).
- **Map**: not used by this contract (all records are `Constr`, not `Map`), which
  removes CBOR map key-ordering ambiguity entirely.

Because both encoders are deterministic Plutus `Data` serializers, byte-identity is
a **testable property**, not a hand-transcribed byte table: the golden vectors are
the byte-for-byte pin, and a parity/drift check (below) fails if the Aiken and
Haskell encodings ever diverge. The repository already relies on this equivalence
(`onchain/validators/cage_boundary.ak`: assembled per-field CBOR is *"byte-identical
to the `cbor.serialise` of the equivalent typed"* value).

---

## Threshold well-formedness and evaluation (F18)

A `Threshold` is evaluated only against a **well-formed** `(cur_keys, threshold)`
pair. The well-formedness predicate is total and deterministic; every rejection
rule below has a negative golden vector.

Let `n = len(keys)`.

| # | Rule | Rejects |
|---|---|---|
| 1 | `n >= 1` | empty key set |
| 2 | `keys` has no duplicate `KeyDigest` | duplicate keys (weight double-count) |
| 3 | every `KeyDigest` is exactly 32 bytes | malformed key width |
| 4 | `Unweighted(m)`: `1 <= m <= n` | `m < 1` (trivially-true) and `m > n` (impossible) |
| 5 | `Weighted`: `clauses` non-empty; each clause non-empty | empty clause set / empty clause |
| 6 | `Weighted`: `sum(len(clause_i)) == n` (partition covers keys exactly, once) | clause-structure/partition mismatch |
| 7 | every `Weight`: `den > 0` | zero/negative denominator (invalid fraction) |
| 8 | every `Weight`: `num >= 0` | negative weight (zero is legal KERI — reserve pattern) |
| 9 | every `Weight`: `num <= den` (weight `<= 1`) | over-unity weight |
| 10 | every `Weight`: `gcd(num, den) == 1` | non-canonical (unreduced) rational |
| 11 | every `Weight`: `1 <= num <= den <= MAX_WEIGHT_DENOM` | out-of-bound / grief-sized rational magnitude |
| 12 | every clause: `sum(all weights in clause) >= 1` | impossible threshold (unsatisfiable even if all sign) |
| 13 | no `Weight` is itself a nested weighted list | nested weighted threshold (v2 shape) |
| 14 | `toad == 0` iff `witnesses` empty, else `1 <= toad <= len(witnesses)`; no duplicate `Verkey`; the `(next_keys, next_threshold)` pair passes rules 1–13 | malformed witness threshold / set; ill-formed next pair |

`MAX_WEIGHT_DENOM` is a **frozen V1 constant = `4294967296` (`2^32`)**. Rationale:
real GLEIF/QVI weights use tiny denominators (`/2`, `/3`, `/5`, `/12`); `2^32` is
far above any plausible weight while keeping every cross-multiplication a
single-word-scale integer op, so per-weight evaluation cost is bounded and
deterministic. Changing it requires a new version tag. Rule 12 is the "impossible
threshold" guard; rules 4/12 together guarantee an AID is never incepted into an
unsatisfiable (bricked) state.

Rule 11 bounds each rational's **magnitude only**. It does **not** by itself make
threshold evaluation DoS-proof: total cost also depends on the **key/clause/witness
list lengths**, which V1 does not cap here. Measured `max_keys` / `max_clauses` /
`max_witnesses` limits (frozen in the validator against the exec-unit budget) are a
**#24 obligation** (Q2); this schema layer bounds each element, #24 bounds the
counts.

**Evaluation** (`evaluate : Threshold × cur_keys × SignerPositions -> Bool`, where
`SignerPositions` is the set of positions whose raw key verified a signature and
whose raw key equals `cur_keys[pos]` — no hashing):

- `Unweighted(m)`: `|SignerPositions| >= m`.
- `Weighted(clauses)`: for each clause `c_j` over partition `P_j`,
  `sum_{pos in P_j ∩ SignerPositions} weight(pos) >= 1` (compared exactly via
  cross-multiplication of the running rational sum; no floating point); the result
  is the **AND** over all clauses.

Determinism: the running-sum comparison is `num_acc * 1 >= den_acc` reduced by
cross-multiplication against `1/1`; because weights are canonical and bounded
(rules 10/11) the accumulation is exact and order-independent. The 1-of-1 vector,
integer m-of-n vectors, single-clause and multi-clause weighted vectors, and every
rule-1..14 rejection are exercised as executable vectors.

---

## Signed message domains

Two domain-separated message preimages are frozen. Each is a PlutusData `Constr`
serialized by the canonical rules above; the leading `domain` field makes the two
non-interchangeable (a signature over one can never satisfy the other). On-chain,
#24 **reconstructs** each message from the redeemer + the spent/created datum —
it is **never** taken as caller-supplied bytes.

### Inception message (`icp`) — registration

```
InceptionMessage { -- Constr 0; fields in EXACTLY this order:
  0  domain               : ByteArray      -- literal "cardano-keri/checkpoint/icp/v1"
  1  network_id           : Int            -- Cardano network id (0 = testnet, 1 = mainnet); binds the deployment
  2  checkpoint_policy_id  : ByteArray[28]  -- checkpoint token minting-policy id (Plutus script hash)
  3  aid_asset_name        : ByteArray[32]  -- = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ canonical_qualified_aid_bytes)
  4  cesr_aid              : CesrAid
  5  cur_keys              : List<KeyDigest>
  6  cur_threshold         : Threshold
  7  next_keys             : List<KeyDigest>  -- KERI `n`
  8  next_threshold        : Threshold        -- KERI `nt`
  9  witnesses             : List<Verkey>
  10 toad                  : Int
  11 native_sn             : Int            -- MUST be 0 (a KERI icp always has s = 0)
}
```

Bound at registration; `seq` is implicitly `0` (an inception may only mint the
genesis checkpoint) and `native_sn` MUST be `0` — a KERI `icp` always has
`s = 0`, so a non-zero value is rejected. Registration is accepted iff the
supplied signatures satisfy `(cur_keys, cur_threshold)` over
`InceptionMessage` — an `icp` is self-signed by its own establishment keys —
**and** the attested inception event type is a non-delegated `icp` **and** the
implied genesis datum (the message's key-state fields at `seq = 0`) passes the
full datum well-formedness predicate (F18 rules 1–13 on both the current and
next pairs, plus rule 14). A `dip` (delegated inception) is **rejected**:
accepting it would silently discard the delegator's establishment authority
(`delegation-boundary-decision.md`). There is no `delegator` field to populate.

`network_id`, `checkpoint_policy_id`, and `aid_asset_name` bind the **deployment
and token**: a signed inception cannot be replayed on another network or under a
different checkpoint policy, and cannot be bound to a different identity asset.
Registration additionally requires `aid_asset_name == deriveAidAssetName(cesr_aid)`
(above) — the genesis token minted for the AID is the AID's own derived locator, not
a caller-chosen name. The
fuller #91 oracle-gated registration package (OOBI-style signed package + the
transient inception-cage token) is #24/#91's transaction-level binding; #68 freezes
these deployment/token context fields in the signed preimage.

### Advance message (rotation / two-seal handoff) — F10 / #77

```
AdvanceMessage { -- Constr 0; fields in EXACTLY this order:
  0  domain               : ByteArray      -- literal "cardano-keri/checkpoint/adv/v1"
  1  network_id           : Int            -- MUST equal the deployment network id
  2  checkpoint_policy_id  : ByteArray[28]  -- MUST equal the checkpoint token policy id
  3  aid_asset_name        : ByteArray[32]  -- MUST equal the spent checkpoint's identity-asset name
  4  cesr_aid              : CesrAid        -- MUST equal the spent checkpoint's cesr_aid (AID invariant)
  5  spent_txid           : ByteArray[32]  -- tx id of the exact spent checkpoint UTxO (its TxOutRef)
  6  spent_index          : Int            -- output index of the exact spent checkpoint UTxO (its TxOutRef)
  7  prior_seq            : Int            -- = spent.seq
  8  prior_native_sn      : Int            -- = spent.native_sn
  9  new_cur_keys         : List<KeyDigest>  -- the revealed keys (any satisfiable subset of spent.next_keys, plus optional augmented keys)
  10 new_cur_threshold    : Threshold        -- the rotation's own kt (may differ from spent.next_threshold)
  11 new_next_keys        : List<KeyDigest>  -- the new pre-rotation commitment (KERI `n`)
  12 new_next_threshold   : Threshold        -- the new pre-rotation threshold (KERI `nt`)
  13 new_witnesses        : List<Verkey>
  14 new_toad             : Int
  15 seq_to               : Int            -- MUST equal prior_seq + 1
  16 native_sn_to         : Int            -- MUST be > prior_native_sn
}
```

The pre-rotation binding is the KERI **dual-threshold rule** (check 6 below): the
signer evidence must satisfy the spent checkpoint's committed
`(next_keys, next_threshold)` — evidence is mapped onto committed positions by
**digest membership** (`blake3_256(qb64(key))`, one single-block hash per revealing key — measured 3.6% cpu / 4.5% mem each), and only keys revealed in `new_cur_keys` count, mirroring
keripy's index/ondex signature validation. A party holding no pre-committed key
cannot substitute a successor set: their evidence maps to no committed position.
Partial (reserve) rotation, augmented keys, and a restated current threshold are
all admitted, exactly as the KERI spec's rotation-validation rule requires.

The checks #24 MUST enforce on the **reconstructed** message (F10 fix — the
signed message binds the successor, defeating "capture the identity at `seq+2`"):

1. `network_id` equals the deployment network id and `checkpoint_policy_id` equals
   the checkpoint token policy id — a cross-network or cross-policy replay fails.
2. `aid_asset_name == deriveAidAssetName(cesr_aid)` **and** `aid_asset_name ==
   spent.identity_asset_name`, and `cesr_aid == spent.cesr_aid` — the locator token
   is the AID's **own derived** asset (not a copied name), so a cross-asset replay, a
   substituted asset name, or a crossed AID all fail; the AID cannot cross
   checkpoints.
3. `(spent_txid, spent_index)` equals the `TxOutRef` of the exact checkpoint UTxO
   being spent — binds THIS unspent tip, not a stale sibling; a wrong-outref fails.
   This is the #68 acceptance target that the signature binds the spent
   checkpoint/token.
4. `prior_seq == spent.seq` and `prior_native_sn == spent.native_sn` — the message
   binds the exact prior projection state.
5. `seq_to == spent.seq + 1` (exact successor sequence; no skips, no `seq+2`) and
   `native_sn_to > spent.native_sn` (KERI events advance).
6. **The dual-threshold rule (KERI pre-rotation; parent #21 invariant).** The
   signer evidence MUST satisfy **both** (a) the rotation's own
   `(new_cur_keys, new_cur_threshold)` and (b) the spent checkpoint's committed
   `(next_keys, next_threshold)`, where for (b) only evidence from keys revealed
   in `new_cur_keys` counts and positions are found by `blake3_256(qb64(key))` digest membership in
   `spent.next_keys`. Theft of every raw *current* key contributes no committed
   next position, so a full spent-current quorum signing an advance is
   **rejected** (negative vector) — whether it signs the honest message or an
   attacker-crafted one. Partial reveal holds: only the members that actually
   sign reveal their raw keys; unexposed reserves stay digest-committed and may
   be carried forward into `new_next_keys` (the GLEIF production Root pattern —
   positive vector).
7. The created checkpoint datum equals `V1{ cesr_aid, new_cur_keys,
   new_cur_threshold, new_next_keys, new_next_threshold, new_witnesses,
   new_toad, seq_to, native_sn_to }` (message ≡ resulting state; nothing written
   that was not signed).
8. The created datum passes the full datum well-formedness predicate (F18 rules
   1–13 on both pairs + rule 14) — nothing ill-formed can be written, so the
   next tip is always advanceable and never bricked.

**Witness rotation (two-seal handoff, `identity-model.md` §6a).** When
`new_witnesses/new_toad` differ from the spent set, #24 additionally requires the
outgoing set to have endorsed `(new_witnesses, new_toad)` (Seal W, receipted by the
outgoing set) before the incoming set's Seal K is accepted. #68 fixes the
**message bytes** that carry `new_witnesses/new_toad`; the seal-receipt verification
is #24's transaction-level check over these bytes. V1 has **no Δ-windowed or other
signature-only fallback**: when the spent checkpoint has `toad > 0`, no controller-only
advance is valid. A transition to `toad = 0` still needs the outgoing set's threshold
receipts over the explicit handoff; an already witnessless checkpoint is the only V1 state
that can advance without witness receipts.

Domain separation and the reconstruct-don't-trust rule together give the F10/#77
guarantee: replaying a captured reveal, substituting `new_next`, changing `seq`,
crossing network/policy/asset/AID domains, or re-pointing at a different spent UTxO
all fail because each such field is inside the signed, reconstructed preimage — and
the rotation is authorized by the pre-committed successor keys, not the (possibly
stolen) current keys.

---

## Freshness / currentness semantics (F12 / #79)

Under the sovereign per-AID UTxO (Candidate A) the F12/#79 confusion is resolved by
**removal**, not reinterpretation:

- **No `identity_root`, no `root_window`, no sliding window.** The checkpoint datum
  **is** the tip. There is no windowed root to be "single value vs sliding" about;
  the two irreconcilable senses are both deleted. All formerly root-typed fields are
  gone, so the "typed inconsistently" facet is closed by construction.
- **Currentness = unspent tip.** An AID's current authority is the unique unspent
  UTxO holding quantity-one `(checkpoint_policy_id, aid_asset_name)` at the
  designated script address. A consumer resolves it generically and re-validates it
  against the ledger; a stale index answer yields retry/failure, never forged
  authority (`specs/92-checkpoint-contention/spec.md` C9).
- **Concurrency.** Inception concurrency no longer stales a signed root (there is no
  root): the genesis checkpoint is minted once behind the #91 oracle gate + MPFS
  unicity proof; racing inception attempts use distinct transient cage tokens and
  cannot consume one another. A rotation consumes the tip and produces exactly one
  successor; any authorization still referencing the spent tip is **stale** and must
  re-resolve and re-sign under the successor (universal re-authorization).
- **Off-chain KERI lag is a real safety window, not a fork.** KERI rotates
  immediately; Cardano enforcement changes only when a successor checkpoint, an
  applicable freeze, or valid evidence reaches the ledger (`identity-model.md` §11).
  A Cardano-only consumer may still accept the old key during the lag.
- **Fail-closed evidence.** High-security consumers **fail closed** once a later
  witnessed event, an active freeze, or a valid duplicity/correspondence proof is
  presented, and MUST publish an anchoring-freshness policy/SLA. #68 invents **no**
  universal numeric timeout and **no** validity bound in the datum; validity bounds,
  if any, are a consumer-side policy, not a wire field.
- **Typing unified.** `cesr_aid`, all key/witness/digest fields are fixed-width
  `ByteArray` (32 bytes); `seq`/`native_sn`/`toad`/threshold integers are `Int`.
  No field is typed two ways.

---

## Delegation boundary (#81)

Frozen by `specs/68-keystate-shape/delegation-boundary-decision.md`:

- `CheckpointDatumV1` has **no** `delegator`/`di` field (removed, not reserved).
- Registration accepts a non-delegated `icp`; `dip` is rejected.
- Advancement has no `drt` / cooperative-delegation / superseding-delegation /
  delegated-recovery path.
- A future delegated-AID protocol is a **new explicitly versioned** validator + proof
  surface (`CheckpointDatumV2`), not an optional byte string in a v1 datum, because
  `di` is one-hop data with recursively-defined validity.
- ACDC/TEL authority chaining and Cardano stake delegation are distinct
  relationships and must not be presented as interchangeable with KERI `di`.

The three-relationship distinction (KERI cooperative delegation / ACDC authority
chaining / Cardano stake delegation) is documented in the reconciled canonical
material (pair-owned doc slices).

---

## The 1-of-1 degenerate vector

A solo user is **not** a special path: `cur_keys = [d0]` (one key digest),
`cur_threshold = Unweighted(1)`, and a one-entry
`(next_keys, next_threshold)` pair. The equivalent single-clause weighted form
`Weighted([[ {num:1,den:1} ]])` evaluates identically. Both are shipped as golden
vectors and asserted byte-identical across Aiken and Haskell, proving the degenerate
case is a true instance of the general schema.

---

## Executable acceptance — schema-support codec + vectors

This ticket ships **executable** proof, not design-only prose, because the pure
schema layer compiles before #24. Two independent encoders and a shared vector set:

- **Haskell** (`offchain`) — a validator-free library: the `CheckpointDatumV1`,
  `Threshold`, and message types with `toData`/`fromData`
  (PlutusData) + canonical CBOR serialization; the F18 well-formedness predicate +
  `evaluate` + the datum-level predicate; `deriveAidAssetName`; the
  `InceptionMessage`/`AdvanceMessage` preimage
  builders. Hspec suites assert each golden vector's bytes and each negative
  vector's rejection.
- **Aiken** (`onchain/lib`) — the mirrored `CheckpointDatumV1`/`Threshold`/message
  types compiling to the same PlutusData, with `cbor.serialise` producing the same
  bytes; the same F18 predicate + `evaluate` + `deriveAidAssetName`. `aiken check`
  tests assert `cbor.serialise(value) == <fixture bytes>`, the same derived asset
  name, and identical threshold verdicts / rejections.
- **Shared vectors + parity** — one Haskell generator emits (a) the canonical golden
  + negative vectors and (b) the Aiken fixture literals from a single computation;
  both are committed. A **drift check** regenerates and asserts no diff
  (`git diff --exit-code`), and the Aiken suite asserts its **independent** encoder
  reproduces the generated bytes. Together these give **byte-identical
  Aiken/Haskell parity with executable evidence** — the epic invariant "one
  canonical CBOR schema with Haskell/Aiken golden parity".

Vector families (each positive + adversarial):

1. `CheckpointDatumV1` datum: 1-of-1; integer m-of-n; single-clause weighted;
   multi-clause weighted; witnessed (non-empty `witnesses`/`toad`); witnessless
   (`toad=0`).
2. Threshold well-formedness: one negative vector per F18 rule 1–14, including the
   exact `MAX_WEIGHT_DENOM` bound (rule 11) and unreduced-rational rejection (rule
   10).
3. **Positional-order sensitivity**: reordering keys, reordering weights within
   a clause, and reordering clauses each yield **different** datum bytes (a
   positive equal-spelling pair `1/1` vs a rejected `2/2` covers the
   reduced-spelling rule; zero weights get a positive vector and a rejected
   non-canonical `0/2`).
4. `InceptionMessage` bytes: accept `icp` (positive); negatives = `dip`-typed
   attested inception, wrong `network_id`, wrong `checkpoint_policy_id`, crossed
   `aid_asset_name`, non-zero `native_sn`, ill-formed genesis state.
5. `AdvanceMessage` bytes + the checks: valid full-reveal succession (positive);
   valid **partial (reserve) rotation** on the GLEIF production Root shape —
   3-of-7 subset reveal, restated `kt`, carried-forward reserves — plus an
   augmented-key acceptance (positives); negatives = **full spent-current quorum
   (stolen-quorum rejection, on both the honest and an attacker-crafted
   message)**, substituted never-committed successor set, insufficient subset
   reveal, `seq_to != prior_seq+1`, substituted `new_next_keys`, wrong
   `prior_seq`/`prior_native_sn`, crossed `cesr_aid`, cross-`network_id`,
   cross-`checkpoint_policy_id`, cross-`aid_asset_name`, **wrong
   `(spent_txid, spent_index)`**, non-increasing `native_sn`, and an ill-formed
   created state (eq8).
6. `deriveAidAssetName(cesr_aid)` — one fixed derivation golden (a known `cesr_aid`
   → its exact 32-byte `aid_asset_name`, byte-identical Aiken/Haskell); negatives =
   wrong derivation code (`0x46`, not `0x45`), truncated / over-long `cesr_aid` (≠ 32 bytes),
   mutated AID (one-bit flip ⇒ different asset name), and a message carrying a
   substituted `aid_asset_name ≠ deriveAidAssetName(cesr_aid)`.

The invocation of these suites lives in the ticket `accept.sh` (a **pair-owned**
harness, written RED→GREEN) and in `just ci` via `./gate.sh`; the required
assertions are enumerated in `plan.md`/`tasks.md`. The ticket owner specifies them;
a driver+navigator pair implements every codec module, test, generator, and
`accept.sh` target.

---

## Downstream obligation for #24 (the recut)

#24 must be re-cut onto this frozen contract and this document is the schema it
implements:

- Import the `CheckpointDatumV1`/`Threshold`/message types, `evaluate`, and
  `deriveAidAssetName` from the #68 schema-support layer; do **not** re-derive the
  shape. Mint the genesis token under `aid_asset_name = deriveAidAssetName(cesr_aid)`
  and enforce `aid_asset_name == deriveAidAssetName(cesr_aid)` on every advance —
  never trust a caller-provided asset name.
- Implement the checkpoint mint/spend validator: genesis registration (mint
  quantity-one token, `seq=0`, `icp` only, `dip`/`drt` rejected), normal rotation
  (`delta=0`, `seq+1`, the eight F10 checks incl. the dual-threshold rule, two-seal witness handoff),
  migration (#99 predecessor binding), and close (#99 `validateEnd` `-1` burn) with
  a closed/tombstone discovery story.
- Wire witness-receipt verification (`Ed25519.verify(witness_pk, seal_bytes, sig)`) over
  the frozen witness/message bytes. Reject missing, insufficient, wrong-set, replayed, or
  wrong-seal receipts. **Do not implement a time-based signature-only fallback in V1.**
- Resolve the current checkpoint as a CIP-31 reference input; enforce
  uniqueness/currentness; publish per-use-case anchoring-freshness policy.
- Delete the standalone MPF identity-registry / `identity_root` / `root_window` /
  depth-10 `trie_key` path from `specs/24-keystate/spec.md` (the rejected
  Candidate-B lineage) as part of the recut.
- Carry the measurement + live-boundary smoke gate that #68 does not perform.

---

## Acceptance criteria

- [ ] The exact `CheckpointDatumV1` PlutusData shape — constructor tags, field
      order, byte widths/domains, canonical CBOR rules — is frozen and unambiguous
      for #24.
- [ ] Current keys/threshold, the explicit pre-rotation pair (`n`+`nt` as
      `next_keys`/`next_threshold`), witnesses/`toad`,
      `seq`, `native_sn`, and `cesr_aid` are each represented and bound.
- [ ] Integer **and** fractionally-weighted multi-clause thresholds are supported
      with one deterministic normalization/evaluation; zero weights are accepted
      (KERI reserve pattern); the F18 predicate rejects
      empty sets, duplicate keys, negative/invalid fractions, over-unity/non-canonical
      rationals, overflow, unsatisfied clause structure, nested weights, and
      impossible thresholds — one negative vector each.
- [ ] The 1-of-1 vector is the degenerate instance of the same schema (not a
      separate path), shipped and byte-identical across languages.
- [ ] `InceptionMessage` and `AdvanceMessage` domains are frozen; the advance
      message binds the successor state and the eight checks; #77 is translated
      from `trie_key` wording into successor-substitution/replay resistance.
- [ ] **Pre-rotation authorization (parent #21):** the advance satisfies the KERI
      **dual-threshold rule** — the rotation's own `(new_cur_keys,
      new_cur_threshold)` **and** the spent checkpoint's committed `(next_keys,
      next_threshold)`; a full stolen current quorum is rejected — negative
      vectors on both the honest and an attacker-crafted message.
- [ ] **Partial (reserve) rotation (KERI-faithful):** a satisfiable subset reveal
      with a restated current threshold and carried-forward reserves — the GLEIF
      production Root pattern — is accepted; an insufficient reveal is rejected;
      augmented keys count only toward the current threshold — positive and
      negative vectors.
- [ ] **Witness-gated V1 advance:** when the spent checkpoint has `toad > 0`, #24
      requires the applicable threshold witness receipts over the KEL anchoring evidence;
      valid controller/dual-threshold signatures without those receipts are rejected, and
      elapsed time never changes that verdict. Witness-set changes use the two-seal handoff;
      only an already witnessless (`toad = 0`) checkpoint has no receipt requirement.
- [ ] **Deployment/token binding:** both messages bind `network_id`,
      `checkpoint_policy_id`, and `aid_asset_name`, and the advance binds the exact
      spent `TxOutRef` (`spent_txid`/`spent_index`); cross-network, cross-policy,
      cross-asset, and wrong-outref replays are each rejected — negative vectors. No
      replay boundary is claimed that is absent from the signed bytes.
- [ ] **Locator asset-name pinned:** `CHECKPOINT_ASSET_DOMAIN_TAG` and
      `canonical_qualified_aid_bytes` (= `0x45 ‖ cesr_aid`) are frozen with exact
      bytes; `deriveAidAssetName` is executable Aiken+Haskell with a byte-identical
      golden and wrong-code / truncated / mutated-AID / substituted-asset negatives;
      messages require `aid_asset_name == deriveAidAssetName(cesr_aid)`.
- [ ] Weighted semantics are **positional**: reordering keys/weights/clauses changes
      the commitment and authority; unreduced rationals are rejected (not
      normalized); `MAX_WEIGHT_DENOM` is a single ratified value — order-sensitivity
      and the exact bound are tested.
- [ ] Freshness semantics are resolved against the per-AID UTxO (F12/#79): no
      sliding root / `identity_root`; currentness = unspent tip; concurrency,
      off-chain lag, and fail-closed evidence stated; validity bounds are consumer
      policy, not a wire field.
- [ ] #81 fully reflected: no `delegator`/`di`; `icp` accepted; `dip`/`drt`
      rejected — in the datum, messages, and reconciled docs.
- [ ] Byte-identical Aiken/Haskell golden **and** negative vectors are executable
      (both encoders + a drift/parity check under `just ci` / `./gate.sh`); no
      cross-language parity is claimed without executable evidence.
- [ ] Architecture/user-story/roadmap material is reconciled to the frozen contract
      (pair-owned doc slices), and the #24 recut obligation is stated precisely.

---

## Open questions

- **Q1 — `MAX_WEIGHT_DENOM` — RESOLVED for V1.** Ratified `4294967296` (`2^32`);
  frozen in the F18 table. A larger real GLEIF/QVI denominator would move it behind
  a new version tag; V1 does not leave it open.
- **Q2 — `max_keys` / `max_clauses` / `max_witnesses` list-size bounds.** Not fixed
  by this schema layer; needs the #24 exec-unit measurement, frozen in the validator
  so an over-long set cannot brick rotation or grief the budget. F18 rule 11 bounds
  each rational's magnitude; these bounds cap the counts. #24 obligation.
- **Q3 — witness identifier form.** V1 stores raw witness **verkeys** (receipts are
  verified over seal bytes with the verkey). If a future witness set needs
  transferable (rotatable) witness AIDs, that is a v2 witness shape.
- **Q4 — `native_sn` vs `seq` exposure.** Both are stored; a consumer that only
  needs current authority reads keys/threshold and ignores `native_sn`. If #24
  finds `native_sn` is only needed inside the correspondence proof (not for
  consumers), it may move to the seal payload in a v2 datum — recorded, not
  reopened here.
