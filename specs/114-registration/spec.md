# Spec: registration path — `icp` admission and checkpoint genesis (#114)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/114
Epic: https://github.com/lambdasistemi/cardano-keri/issues/24 (V1 checkpoint
validator — the script hash freezes at deployment, so this surface is
co-designed with every sibling path).

Ratified inputs (do not reopen — parent Q-file required):
`specs/68-keystate-shape/spec.md` (frozen `CheckpointDatumV1` / message wire
contract, `deriveAidAssetName`, genesis-binding sketch),
`specs/68-keystate-shape/identity-model.md` (§6a, §7a/§7c hybrid genesis),
`specs/92-checkpoint-contention/spec.md` (sovereign per-AID checkpoint,
combined script, status-by-address), `specs/106-enforcement/spec.md`
(address-role lifecycle, `EventEvidence` slice machinery, O1/O3/O4),
`specs/91-genesis-registration/` + PR #95 (hybrid genesis decision).

!!! danger "This document extends protocol surface"
    The hash-proof minting policy, the registration mint branch, and the
    event-binding slice set below become part of the V1 validator surface.
    Nothing in the frozen #68 datum/message contract is modified.

---

## Problem

The #68 schema layer ships `validate_inception`, `inception_datum`,
`deriveAidAssetName`, the F18 predicate, and `evaluate` in both languages with
byte parity — but no transaction can register an AID: there is no hash-proof
minter (the #97 machinery is spike code under `spikes/97-blake3-multitx/`),
no checkpoint minting policy, and no on-chain binding between the datum's
key-state and the actual inception event bytes. #114 delivers that
transaction layer for genesis: the registration path of the V1 checkpoint
validator.

## Scope

**In scope**

1. The **hash-proof minting policy** (`hash_proof.ak`): a single-transaction
   in-script `blake3(icp_bytes) == cesr_aid` check over the lane-packed
   single-chunk core, minting the proof token named
   `blake2b_256(icp_bytes ‖ cesr_aid)`.
2. The **checkpoint combined validator scaffold** (#92/#99 pattern: policy id
   = script hash) with the **`Register` mint branch**; every spend redeemer
   fails closed (placeholders for #115–#117).
3. The **event-binding slice set** (keys-must-match gate): datum key-state ==
   the inception event's own `k`/`kt`/`n`/`nt`/`b`/`bt` fields, by
   prover-supplied offsets and slice equality — the script never parses CESR.
4. **Registration signatures**: the #68 `InceptionMessage` preimage
   (reconstructed, never caller-supplied) signed to the event's own
   `(cur_keys, cur_threshold)`.
5. **Deposit mechanism**: `D_reg` locked above min-ADA as a validator
   parameter (economics = O3, deferred to #117).
6. keripy-oracle **registration fixture family** (hermetic flake extension;
   existing bundles byte-unchanged) + Haskell/Aiken **parity (bytes AND
   verdicts)** + measurement cells for the registration context.

**Out of scope**

- Advance/rotation (#115), freeze/convict wiring (#116), close/migration/
  CIP-31 resolution/role-encoding decision O4 and deposit economics O3 (#117),
  adversarial tx suite + full #109 budget matrix (#118), devnet cast (#44).
- The #91 oracle projection attestation and MPFS absence/unicity gate (see
  "Unicity residual" — decision requested at the spec checkpoint).
- `> 1024 B` (multi-chunk) inceptions: rejected in V1 (see below).
- Multi-transaction Step/Finish blake3 chains and their cage confinement (no
  intermediate state exists in the single-tx design below).

---

## Ratified invariants (inherited — binding)

1. Registration admits independent `icp` only; `dip`/`drt` rejected (#81,
   epic fact).
2. The registration validator itself never computes Blake3; it consumes the
   hash-proof mint token (epic fact).
3. Keys-must-match gate: checkpoint keys equal the event's own `k`; the
   registration message is signed to the event's own `kt`. Squatting
   collapses to key theft; front-running is harmless (the package is fully
   signed and registers the owner).
4. Frozen #68 shapes are consumed, not re-derived: `CheckpointDatumV1`,
   `InceptionMessage`, `deriveAidAssetName`, F18, `evaluate`.
5. `aid_asset_name == deriveAidAssetName(cesr_aid)` — never a caller-copied
   name.
6. O1: every signature verifies over full serialized bytes, never a SAID.
7. Status is the address (#92/#106): the genesis output sits at the ACTIVE
   address; datum carries no status enum.
8. One quantity-one token, minted into exactly one checkpoint state output
   (single-`Pair` mint check, #99).

---

## Transaction shapes

Registration is **two transactions** (budget separation — the blake3 check
alone measures 54.3% cpu / 71.7% mem at the 1024-byte boundary and cannot
share a transaction with threshold Ed25519 + output checks at ≥25% headroom):

```
Tx A — hash-proof mint (permissionless):
  mint: (hash_proof_policy, blake2b_256(icp_bytes ‖ cesr_aid), +1)
  redeemer: { icp_bytes, cesr_aid, off_i, off_d }
  → proof token paid anywhere the submitter likes

Tx B — registration (permissionless, replay-safe):
  input:  the proof-token UTxO (burned: hash_proof −1)
  mint:   (checkpoint_policy, deriveAidAssetName(cesr_aid), +1)
  redeemer (Register): { evidence : RegistrationEvidence }
  output: the genesis checkpoint state output at the ACTIVE address
```

### The hash-proof minting policy (`hash_proof.ak`)

Parameter-free. Checks, on mint (H2 corrected 2026-07-18, slice-4 Q-001: a
KERI `E`-code AID is the blake3 digest of the **SAID-dummied**
serialization — keripy dresses the 44-char `i` and `d` value spans with
`"#"×44` before digesting — never of the final bytes; #106's shared checks
already state this mechanism, and the empirical proof against the committed
`reg_witnessed`/`honest_2key` fixtures is recorded in the Q/A files):

- **H1** — redeemer carries `(icp_bytes, cesr_aid, off_i, off_d)`;
  `len(icp_bytes) <= 1024` (one blake3 chunk), `len(cesr_aid) == 32`, and
  the two 44-char spans at `off_i`/`off_d` are disjoint and lie inside
  `icp_bytes`.
- **H2** — the said-blank binding, two parts:
  (a) `slice(icp_bytes, off_i, 44) == qb64_aid(cesr_aid)` and the same at
  `off_d` (an `icp` is self-addressing: `d == i`);
  (b) `blake3.verify(splice_dummies(icp_bytes, off_i, off_d), cesr_aid)`
  (the vendored lane-packed single-chunk core), where `splice_dummies`
  overwrites both spans with `"#"×44` — equality outside the spans holds by
  construction of the splice.
- **H3** — the policy mints exactly
  `[Pair(blake2b_256(icp_bytes ‖ cesr_aid), 1)]` over the **final** bytes
  (single-name, quantity-one; inspects the full `tokens(mint, policy)`
  map). Naming over the final bytes is what makes Tx A compose with R5,
  which recomputes the same name from the final `evidence.event_bytes`.
- **H4** — burn branch: every entry under the policy is strictly negative —
  burning is always permitted (the registration tx burns the proof).

Trust note: with prover-supplied spans the policy proves "`cesr_aid` is the
SAID of `icp_bytes` **under the claimed spans**". Fake spans over
self-authored bytes buy an attacker nothing beyond honest self-registration:
Tx B's admission still requires E1–E9 + R4 + R7 threshold signatures with
the datum keys over the same bytes — the #106 two-slice-comparison
discipline. (Optionally S5 may additionally pin Tx B's `off_i` to Tx A's;
recorded as optional hardening, not required — both already independently
compare against `qb64_aid(D.cesr_aid)`.)

The token name binds the **pair** (bytes, AID): a proof for one AID can never
satisfy a registration carrying different bytes or a different AID, because
the registration branch recomputes the name with one cheap native blake2b
over material it independently checks. No placement constraint: the token is
pure existence evidence; whoever holds it may use it.

### The registration mint branch (`checkpoint.ak`, `Register`)

Validator parameters (following `mpfCage(version, predecessorPolicy)`):
`checkpoint(version : Int, hash_proof_policy : PolicyId, network_id : Int,
d_reg : Int)`. The applied script's hash is BOTH the checkpoint token policy
id and the payment credential of the state output (#92).

```
RegistrationEvidence {
  event_bytes : ByteArray                  -- full keripy icp serialization (≤ 1024 B)
  off_t   : Int                            -- offset of the event-type value
  off_i   : Int                            -- offset of the 44-char qb64 AID
  off_s   : Int                            -- offset of the hex sequence-number value
  off_k   : List<Int>                      -- offsets of the 44-char qb64 `k` entries
  off_kt  : Int                            -- offset of the kt JSON value
  off_n   : List<Int>                      -- offsets of the 44-char qb64 `n` entries
  off_nt  : Int                            -- offset of the nt JSON value
  off_b   : List<Int>                      -- offsets of the 44-char qb64 `b` entries
  off_bt  : Int                            -- offset of the bt JSON value
  ctrl_sigs : List<(Int, ByteArray)>       -- (index into cur_keys, Ed25519 sig)
                                           --   over the InceptionMessage preimage
}
```

Checks (R1–R10), over the transaction and the inline datum `D` of the
continuing output:

- **R1 — mint shape.** `tokens(mint, own_policy)` is exactly
  `[Pair(deriveAidAssetName(D.cesr_aid), 1)]`.
- **R2 — state output.** Exactly one output at
  `Address(Script(own_policy), None)` (the ACTIVE address — see "Address
  role") carries the minted token; it holds inline datum `D` and no other
  output at that address exists in the transaction (datum-confusion guard,
  #92 boundary hygiene).
- **R3 — genesis datum.** `D.seq == 0` and `D == inception_datum(M)` where
  `M` is the **reconstructed** `InceptionMessage` — built from the deployment
  parameters (`network_id`, `own_policy`), `deriveAidAssetName(D.cesr_aid)`,
  and `D`'s own key-state fields. Nothing message-shaped is caller-supplied.
- **R4 — schema predicate.** `validate_inception(event_type, M) ==
  InceptionValid`, where `event_type` is derived from the `off_t` slice
  (E1). This carries the #68 obligations: domain, 32-byte AID width, derived
  asset name, `native_sn == 0`, and full F18 well-formedness of both pairs +
  rule 14.
- **R5 — hash-proof consumption.** Some input carries
  `(hash_proof_policy, blake2b_256(evidence.event_bytes ‖ D.cesr_aid))` at
  quantity one, and the transaction burns it (`hash_proof_policy` mints
  exactly `[Pair(name, -1)]`). This is the only bytes↔AID binding the branch
  needs — no blake3 on this path.
- **R6 — event binding (the keys-must-match gate).** The slice set E1–E9
  below holds over `evidence.event_bytes`.
- **R7 — signatures.** Each `(idx, sig)` in `ctrl_sigs` verifies with
  `D.cur_keys[idx]` over the canonical-CBOR serialization of `M` (the #68
  preimage), and the distinct verified positions satisfy
  `evaluate(D.cur_threshold, positions)` — the event's own `kt`, which E5
  pins to `D.cur_threshold`.
- **R8 — deposit.** The state output's lovelace `>= min_ada + d_reg`
  (mechanism here; `d_reg` economics = O3, #117).
- **R9 — no witness receipts required at genesis.** Documented, not checked:
  genesis receipts are circular (§7c — the set verified against is the set
  being asserted); the KEL carries the icp's own KERI signatures and receipts
  for off-chain audit. On-chain, key possession + byte binding + slice
  binding carry the admission.
- **R10 — spend paths fail closed.** The scaffold's spend handler rejects
  every redeemer (`fail`); #115–#117 add Advance/Freeze/Convict/Close before
  the deployment freeze.

### The event-binding slice set (E1–E9)

All checks are `slice(event_bytes, off, len) == expected` with the expected
bytes **computed from the datum** — prover-supplied offsets locate, never
define, content (#106 `EventEvidence` discipline; the script never parses
CESR/JSON):

| # | Field | Expected bytes |
|---|---|---|
| E1 | `t` | `"icp"` at `off_t` (3 bytes; `dip`/`drt`/`rot` all differ ⇒ rejected; feeds R4's `event_type`) |
| E2 | `i` | `qb64_aid(D.cesr_aid)` at `off_i` (44 chars; belt-and-braces over H2's whole-bytes binding) |
| E3 | `s` | `"0"` at `off_s` (a KERI `icp` always has `s = 0`) |
| E4 | `k` | `len(off_k) == len(D.cur_keys)`; each `qb64_verkey(D.cur_keys[j])` at `off_k[j]` (44 chars, `D` code) — **the gate** |
| E5 | `kt` | the canonical KERI JSON re-spelling of `D.cur_threshold` at `off_kt` (hex string for `Unweighted`, fraction-string array for `Weighted` — #106 O2's canonical re-spelling, owned here for `icp`) |
| E6 | `n` | `len(off_n) == len(D.next_keys)`; each `qb64_aid`-style `E`-code spelling of `D.next_keys[j]` at `off_n[j]` |
| E7 | `nt` | re-spelling of `D.next_threshold` at `off_nt` |
| E8 | `b` | `len(off_b) == len(D.witnesses)`; each `B`-code qb64 of `D.witnesses[j]` at `off_b[j]` (non-transferable witness code) |
| E9 | `bt` | hex re-spelling of `D.toad` at `off_bt` |

**Why offset misdirection fails.** The bytes are fixed (H2 binds them to the
AID via the said-blank splice, with the `i`/`d` spans themselves
slice-checked against `qb64_aid(cesr_aid)`). Every expected value is derivation-code-prefixed (`D`/`E`/`B`) or an
exact re-spelling, so pointing an offset at a different field of the genuine
event compares differently-coded 44-char strings and fails; pointing two
`off_k` entries at one slice duplicates a key and fails F18 rule 2 (via R4).
An attacker cannot place chosen 44-char strings inside a victim's genuine
inception bytes.

**Consequence — ratified supersession (2026-07-18, A-001).** E1–E9 make the
semantic projection of a `<= 1024 B` inception **fully on-chain-checked** —
the §7c "attested, challengeable projection" and the #91 oracle activation
gate are not wired in this path. Registration in V1 is permissionless and
trustless for the single-chunk tier; `> 1024 B` inceptions are rejected
outright (H1), not admitted via an attested tier. **This formally
supersedes #91 decision 1 (oracle-gated registration) for V1** — ratified
at the epic spec checkpoint (A-001): it removes a trusted role rather than
adding one, and reuses the slice-binding machinery the enforcement layer
already relies on. It does not touch the `> 1-chunk` attested story, which
simply waits (with the chunk-token extension or a native blake3 builtin)
behind a version bump. Two **binding conditions** ride with the
supersession:

1. **Offset-misdirection adversarial vectors are mandatory** — a dedicated
   negative-vector family (wrong offsets, overlapping spans, spans pointing
   into `a`/other fields, derivation-code prefix confusion, truncated
   slices), in both languages, before the slice landing E1–E9 is accepted.
2. **Measurement gate** — the full registration Tx B (E1–E9 + the blake2b
   proof-name recompute + R7 signatures) measured at the 2-key and 7-key
   shapes against the epic's ≥25% headroom target; **on a miss, STOP and
   Q-file the epic owner** — the fallback is re-introducing the attested
   tier, never weakening checks.

### Address role (O4 non-foreclosure)

The genesis output's address is `Address(Script(own_policy), None)` — payment
credential = the combined script's own hash (#92), **no staking credential**.
This is the V1 ACTIVE address. Frozen/Tombstone role encoding stays open for
#116/#117 (O4): distinguishing roles by staking credential (same payment
script, so every spend still runs the V1 validator and `policy id ==
payment hash` everywhere) remains fully available; nothing here forecloses
address-per-role.

### Unicity — temporary pre-deployment residual (gate = #116 scope)

Ruled at the spec checkpoint (A-001): mint-once unicity is a ratified epic
invariant, **not** a permanent residual. Nothing in this path prevents
minting the **same** `(policy, aid_asset_name)` twice; that window is
accepted **only pre-deployment** (the script hash freezes at deployment,
not per-child — a later child amends the script). The unicity/absence gate
is **explicit #116 scope** (the same invariant as tombstone terminality;
mechanism — MPFS absence proof vs alternative — is decided there). #114's
obligation is structural: the `Register` transaction shape **leaves room
for one additional reference or consumed input** (the future gate input) —
no check in the branch may assume a fixed input count or reject
transactions for carrying inputs beyond those R5 names. Bounding the
interim harm:

- A duplicate's datum is forced (keys-must-match) to the same key-state as
  the genuine token — the attacker registers the *victim*, at the
  attacker's own deposit expense.
- The duplicate cannot advance: an advance needs the controller's committed
  next keys (dual-threshold) — and a captured honest advance package cannot
  be replayed onto the duplicate because `AdvanceMessage` binds the exact
  spent `TxOutRef`.
- Residual harms: a stale-read confusion surface (a consumer shown the
  seq-0 duplicate as "current"), and — material for #116 — **post-conviction
  re-registration**, which would undermine tombstone terminality ("with
  mint-once unicity the AID can never re-register", #106).

Decided (A-001): the gate ships with #116 (issue updated by the epic
owner); #114 documents the window as temporary and keeps the `Register`
shape gate-ready as above.

---

## Fixtures — the keripy oracle (hermetic flake extension)

Extend `offchain/test/keri-fixtures/gen_fixtures.py` with a **registration
family**; every honest artifact is reference-implementation output; existing
bundles stay byte-unchanged; regeneration stays byte-stable:

- `reg_witnessed` — a 3-witness, `toad = 2` `icp` (the parent-acceptance
  2-of-3 shape) with per-field offsets and KERI signatures.
- `reg_weighted` — a fractionally-weighted `kt` `icp` (exercises E5's
  weighted re-spelling).
- `reg_dip` / `reg_drt` — a real keripy delegated inception (`dip`) and
  delegated rotation (`drt`) (E1 rejection material).
- `reg_oversize` — a `> 1024 B` inception (GLEIF-Root-shaped board) (H1
  rejection material).
- **Signer-seed export** — the registration family exports each fixture
  identity's Ed25519 seeds: `InceptionMessage` preimages depend on
  deployment parameters chosen at test time, so Cardano-side signatures are
  produced in the Haskell layer from exported keys (keripy stays the oracle
  for KERI artifacts: events, sigs over `event_raw`, digests). Offsets per
  field are emitted by the generator (ground truth from keripy's own
  serialization), not reverse-engineered in consumers.
- Existing `honest_2key` / `honest_7key` / `fork*` icp material is reused
  where it fits (their `icp`/`icp_sigs` already carry O1 evidence).

Adversarial vectors (squats, crossed AIDs, mutated offsets, substituted
names) are deterministic constructions over these honest artifacts in the
vector generator — not keripy output, and never mutations of committed
bundles.

---

## Acceptance criteria

- [ ] A real keripy `icp` fixture registers end-to-end through the Aiken
      validator entry point (constructed `ScriptContext`: hash-proof mint Tx A
      shape + registration Tx B shape), for the unwitnessed 2-key, the
      GLEIF-shaped 7-key, and the witnessed 2-of-3 fixtures.
- [ ] Foreign-`icp` squat rejected: attacker-keyed datum over the victim's
      bytes fails E4 (and R7); attacker-signed message over victim keys fails
      R7. Replay of the owner's complete package registers the owner
      correctly (positive vector).
- [ ] `dip` and `drt` rejected (E1/R4), each as an executable vector from
      real keripy events.
- [ ] `> 1024 B` inception rejected (H1); wrong-AID bytes rejected (H2b);
      wrong/overlapping/out-of-range `off_i`/`off_d` spans rejected
      (H1/H2a); proof-name mismatch (wrong bytes, wrong AID, crossed pair)
      rejected (R5); missing/unburned proof token rejected (R5).
- [ ] Mint-shape vectors: extra asset name, quantity ≠ 1, token to a foreign
      address, second output at the checkpoint address, missing token — each
      rejected (R1/R2).
- [ ] Datum vectors: `seq ≠ 0`, message/datum field mismatch, ill-formed F18
      state, caller-copied asset name, `native_sn ≠ 0` — each rejected
      (R3/R4).
- [ ] Signature vectors: below-threshold, non-signer index, signature over
      the wrong preimage (KERI `event_raw` instead of the `InceptionMessage`
      preimage), crossed `network_id`/policy — each rejected (R7).
- [ ] Slice vectors: each of E1–E9 has at least one rejection (mismatched
      slice or count), **plus the dedicated offset-misdirection family
      (A-001 QB condition 1)**: wrong offsets, overlapping spans, spans
      pointing into `a`/other fields (incl. off_k → `n`, off_k → `b`),
      derivation-code prefix confusion, truncated slices, duplicated
      offsets — executable in both languages, landed with the E1–E9 slice.
- [ ] Deposit vector: state output below `min_ada + d_reg` rejected (R8).
- [ ] Haskell/Aiken parity: shared generated vectors, byte-identical
      encodings AND identical verdicts in both implementations; drift check
      green; existing fixture bundles byte-unchanged.
- [ ] Measurement cells for the hash-proof mint (300 B, 966 B, 1024 B)
      reported against the mainnet per-tx budget (rationale recorded if the
      1024 B boundary cell runs tight — known 71.7% mem from spike #88).
- [ ] **Measurement gate (A-001 QB condition 2):** the full registration
      Tx B context (E1–E9 + blake2b proof-name recompute + R7 signatures)
      measured at the 2-key and 7-key shapes meets the epic's ≥25% headroom
      target; on a miss the ticket STOPS and Q-files the epic owner (the
      fallback is re-introducing the attested tier, never weakening checks).
- [ ] Spend paths fail closed at HEAD (R10 vector).

## Spec-checkpoint rulings (Q-001 → A-001, 2026-07-18 — all resolved)

- **QA — APPROVED.** Single-tx lane-packed hash-proof mint; no Step/Finish
  chain, no intermediate chaining value, §7c cage confinement vacuous for
  this path.
- **QB — APPROVED WITH CONDITIONS.** Oracle-less trustless registration for
  the ≤1-chunk tier formally supersedes #91 decision 1 for V1 (dated note
  above). Binding conditions: the offset-misdirection vector family and the
  Tx B measurement gate with STOP-on-miss (folded into the acceptance
  criteria).
- **QC — MODIFIED.** Duplicate-mint is a **temporary pre-deployment
  residual**; the unicity/absence gate is **#116 scope**; the `Register`
  shape leaves room for the gate input (section above).
- **QD — APPROVED.** ACTIVE = `Address(Script(own_hash), None)`; role
  encoding stays open on the staking-credential axis for #116/#117 (O4).
- **QE — APPROVED.** `> 1024 B` inceptions hard-rejected in V1 — the
  documented M1 limit; larger boards wait behind a version bump.
- **QF — APPROVED (R7-only), considered-and-rejected.** On-chain
  re-verification of the icp's indexed KERI self-signatures adds no security
  against squat: the registration message is already signed by the event's
  own keys to the event's own threshold, so possession is proven; the KEL
  carries the self-signatures for off-chain audit.
