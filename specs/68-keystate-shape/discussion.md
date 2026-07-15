# Design discussion — the frozen KeyState / trie_key shape (#68)

Status: **historical discussion, partially superseded**. The external
`cesr_aid` + sovereign per-AID checkpoint decision removed the frozen Cardano
`trie_key` preimage that framed D-A/D-B/D-C. D-D survives: weighted thresholds are
required. D-E is now decided as **independent AIDs only in V1, with no passive
`delegator` field**; see
[delegation-boundary-decision.md](delegation-boundary-decision.md).
Goal: agree, in plain language, on what the identity key commits to — then
formalize the security invariants in Lean, then write the spec.

---

## 1. Why this is a forever-decision (the trap)

Every AID's on-chain identity is a key in the MPF trie:

```
trie_key = blake2b_256( cbor( <inception material> ) )
```

`trie_key` is computed **once, at inception, from the inception material**, and
then **never changes** — not across rotations, not ever. Cages, credentials, and
every reference to the identity point at this 32-byte key.

So: **whatever fields go into `cbor(<inception material>)` are frozen into every
AID for its entire life.** You cannot add a field later — that would change the
hash, i.e. it would be a *different identity*. This is the whole point of a
self-certifying identifier, and it is also the trap: get the shape wrong and
every AID ever registered is malformed, unfixably.

Today the material is two fields — one signing key and one next-key hash:

```
trie_key = blake2b_256(cbor({ cur_pubkey, next_digest }))
```

That encodes **one key controls this identity**. The business cases say that's
wrong for the actors that matter (legal entities, QVIs, SPOs, DAOs): those are
**k-of-n multisig**. If we ship the one-key shape and later need multisig, we
cannot retrofit it. Hence #68 must be resolved before #24 writes the validator.

The design already committed to the *intent* ("list-shaped, threshold-capable,
1-of-1 is the degenerate case") but **never wrote down the
actual bytes**. That gap is the finding. This doc fills it.

---

## 2. The reference: what KERI itself commits to

KERI (which we are bridging) already solved "what does an establishment event
commit to." Every establishment event carries four things:

| KERI field | Meaning |
|---|---|
| `k`  | **current** signing public keys — a *list* |
| `kt` | **current** threshold — how many/how much weight must sign (k-of-n, possibly weighted/fractional) |
| `n`  | **next** key *digests* — a list of hashes; the pre-rotation commitment to the next key set |
| `nt` | **next** threshold |

Two things worth internalizing:

- KERI pre-rotation commits to the **next keys _and_ the next threshold** (`n`
  *and* `nt`), not just the keys. (See §3 for why that matters.)
- The single-key identity is literally `k = [one key]`, `kt = 1`. There is no
  separate "singleton type" — the solo user is `n = 1` of the list shape. That
  is the property we want on Cardano too, so "1-of-1 degenerate case" is real
  rather than a slogan.

Our on-chain `trie_key` is the Cardano analogue of KERI's inception commitment.
The natural, low-surprise choice is to mirror `k / kt / n / nt`.

---

## 3. The one security invariant we must not break

Pre-rotation is the entire reason this system is interesting:

> **A thief who holds the _current_ keys cannot rotate the identity.**

For one key that's obvious: rotation requires revealing `next_pubkey`, and the
thief only knows its hash. For **k-of-n it's subtler**, and this is exactly where
a careless shape leaks:

- The thief might steal a *quorum* of current keys (k of them). Pre-rotation must
  still stop them, because rotation authority comes from the **next** set, not the
  current set.
- **Threshold downgrade attack.** Suppose we pre-commit only the next *keys* but
  not the next *threshold*. A thief with the current quorum rotates to the same
  next keys but sets the new threshold to `1-of-n`, then only needs one of those
  keys going forward. Committing `nt` alongside `n` (KERI's choice) closes this.

So the invariant we will hand to Lean is roughly:

```
rotation is authorized only by signatures from the NEXT key set meeting the
NEXT threshold, both of which were committed (as digests) before any current
key was ever used — for all n, all weightings, all thresholds.
```

Everything in §4 is chosen to make that invariant true and provable.

---

## 4. The decisions (each stands alone)

Five choices. For each: what's being chosen, the options, the trade-off, a
recommendation, and whether it's reversible. Read them independently — you don't
have to hold all five at once.

### D-A. What fields are frozen into `trie_key`
**Choice:** which parts of the establishment config are "identity DNA" (in the
frozen preimage) vs mutable state (in the leaf value, changeable at rotation).

- Frozen (historical candidate): current keys+weights, current threshold, and
  next commitment.
- Mutable (in the leaf value, not the key): `seq`, `cesr_aid`, `deposit`, status.

**Trade-off:** more in the frozen preimage = more bound to identity but less
flexibility. Note current keys/threshold *do* change at rotation — so they are
frozen **only as the inception snapshot** that seeds `trie_key`; the live values
live in the mutable leaf. `trie_key` is "who you were at birth," the leaf is "who
you are now."
**Recommendation:** freeze the inception snapshot of {keys+weights, threshold,
next-commitment}; keep seq/cesr_aid/deposit/status mutable. Reversible? **No.**

### D-B. Inline the config, or hash a digest of it (structural)
**Choice:** two ways to get the same identity binding:

- **Flat/inline:** `trie_key = blake2b_256(cbor({keys, threshold, next}))`
  — the whole config is the preimage.
- **Two-level:** `config_digest = blake2b_256(cbor({keys, threshold}))`;
  `trie_key = blake2b_256(cbor({config_digest, next_digest}))` — trie_key stays a
  fixed two-field preimage; the config lives in the leaf value, checked against
  the digest on-chain.

**Trade-off:** this is *not* a security choice — both bind the same data. It's
cost/ergonomics: flat means the inception redeemer carries the full list and the
script re-encodes it (bigger redeemer, one hash); two-level keeps a tiny fixed
preimage and moves the list into the value (extra indirection, two hashes). On
Cardano, redeemer size and script CPU both cost budget.
**Recommendation:** decide with a rough exec-budget sanity check (ties to finding
F15). Mild lean toward **flat** for legibility (what you sign is what you see),
unless budget says otherwise. Reversible? **No** (it's in the hash).

### D-C. How the next-set is committed
**Choice:** the pre-rotation commitment `next`:

- **Single digest:** `next = blake2b_256(cbor(next_public_config))` — one hash over
  the whole next {keys, weights, threshold}. Rotation reveals the entire next
  config at once.
- **Per-key digests (KERI `n`):** `next = [hash(nextkey_1), …]` + committed `nt`.
  Allows partial/weighted reveal and staggered custody.

**Trade-off:** single digest is simpler and cheaper and is enough if rotation is
always all-keys-at-once. Per-key digests match KERI exactly and support advanced
custody (rotate a subset), at more on-chain cost and complexity.
**Recommendation:** **single digest over {next keys+weights+threshold}** for v1
— simplest thing that still commits `nt` (closes the §3 downgrade attack). Revisit
per-key only if a case needs partial rotation. Reversible? **No.**

### D-D. Weighted threshold, or plain m-of-n
**Choice:** KERI allows *fractional weighted* thresholds (e.g. weights
`[1/2,1/2,1/2,1/2]`, satisfy if signed weight ≥ 1). Do we need weights, or is a
plain count `m-of-n` enough?

- **Weighted:** matches KERI/vLEI board structures exactly; needs rational
  arithmetic and a well-formedness predicate on-chain (finding F18).
- **Plain m-of-n:** integers only, trivial to validate; can't express "the CEO's
  key counts double."

**Trade-off:** weights add real on-chain complexity and edge cases (zero weights,
`threshold > sum`, unsatisfiable configs that brick an AID). Plain m-of-n covers
most orgs and is far easier to get provably right.
**DECIDED BY FACTS → weighted REQUIRED.** The vLEI EGF *mandates* fractionally
weighted thresholds and real GLEIF/QVI AIDs use them (`isith: ["1/2","1/2"]`, with
non-uniform `1/5` weights in the tooling) — see [acdc-zoo.md](acdc-zoo.md) §B.
Integer-only would reject production GLEIF/QVI AIDs. So `kt`/`nt` support **both**
KERI forms: an integer count `"2"` **or** a fraction-weight list `["1/2","1/2"]`
(satisfied when signed weights sum ≥ 1). This pulls in on-chain rational-weight
arithmetic and the F18 well-formedness predicate. Reversible? **No.**

### D-E. KERI delegation in V1

**DECIDED — independent AIDs only; no passive `delegator` field.** The vLEI
credential chain uses ACDC edges and does not require the acting LE/OOR/ECR AIDs in
the four Cardano use cases to be KERI-delegated. QVI infrastructure is commonly
delegated, but validating it requires the parent's anchor and recursively valid KEL,
not merely a stored `di`.

Candidate A also dissolved the frozen Cardano `trie_key`; the qualified KERI AID is
the identity handle and the checkpoint datum is versioned. V1 therefore rejects
`dip`/`drt`. A future delegated-AID version must carry and verify the cooperative
delegation proof described in
[delegation-boundary-decision.md](delegation-boundary-decision.md).

---

## 5. The shape these recommendations assemble to (straw man, now fact-grounded)

The historical straw man below took the evidence-based threshold decisions (flat;
single next-digest covering `nt`; **weighted-or-integer** threshold per the vLEI
mandate). Candidate A later removed this `trie_key` object entirely:

```
inception_config = {
  0: [ pk_1, pk_2, ... ],   -- current establishment keys (KERI k), positional list of raw Ed25519 keys
  1: kt,                    -- current threshold (KERI kt): integer "2"  OR  weight list ["1/2","1/2"]
  2: next_digest,           -- blake2b_256(cbor({ 0: next_keys, 1: next_kt })): commits next keys AND next threshold
}
trie_key = blake2b_256(cbor(inception_config))     -- integer map keys, canonical CBOR (F30)

-- solo user, 1-of-1 (genuinely n=1 of the same shape):
--   { 0: [pk], 1: "1", 2: next_digest }
```

Weights live in `kt` positionally (KERI-faithful: a key's weight is its entry in
the `kt` list), not as `[pk,weight]` pairs. `next_digest` is a single hash over the
*next* {keys, kt} so a stolen current quorum can neither reveal the next keys nor
lower the next threshold (§3). This is a **straw man to react to**, not a decision.

---

## 6. What Lean will then prove (so we don't have to trust prose)

Once the shape is agreed, formalize as a state machine and prove:

- **P1 pre-rotation (the big one):** for all n, weights, thresholds — a rotation
  is accepted only if signed by the committed *next* set meeting the committed
  *next* threshold; a holder of any subset of *current* keys cannot produce an
  accepted rotation. (Kills threshold-downgrade too.)
- **P2 well-formedness:** an inception with a malformed config (empty keys, dup
  keys, `threshold=0`, `threshold>sum(weights)`) is rejected — so no AID can be
  born bricked (finding F18).
- **P3 determinism:** the on-chain re-encoding of `inception_config` is
  byte-identical to the off-chain one for all inputs (finding F30 / CBOR pin).
- **P4 1-of-1 equivalence:** the solo-key instance is exactly `n=1` of the list
  shape — no separate code path.

These are the invariants the docs will then cite by predicate name.

---

## 7. Status after the zoo (both scope calls now answered by facts)

- **D-D — weighted thresholds: REQUIRED** (vLEI EGF mandate; real GLEIF/QVI configs).
- **D-E — KERI delegation: V1 independent-only, no passive field.** Full
  cooperative delegation is a versioned extension because `di` alone is not proof.

So there is **no remaining product-scope question** — the evidence settled both.
What's left is engineering, which the design loop drives:

1. **D-B (flat vs two-level)** — decide with a rough Plutus exec-budget check for
   the k-of-n inception/rotation redeemer (finding F15). Not a scope call.
2. **Lean formalization** — prove P1–P4 (§6), especially pre-rotation for the
   *weighted* k-of-n case (the new complexity D-D introduced), before anything
   freezes.
3. **CBOR pin** — fix the exact canonical encoding to the Aiken builtin (F30).

Recommended next step: open the design PR with this discussion + zoo, then start the
Lean model of the weighted-threshold pre-rotation invariant. The straw-man shape in
§5 is the working proposal.
