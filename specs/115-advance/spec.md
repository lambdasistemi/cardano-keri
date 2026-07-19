# Spec: advance path — dual-threshold rotation with incoming-set witness validation (#115)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/115
Epic: https://github.com/lambdasistemi/cardano-keri/issues/24 (V1 checkpoint
validator — the script hash freezes at deployment, so this surface is
co-designed with every sibling path).

Ratified inputs (do not reopen — parent Q-file required):
`specs/68-keystate-shape/spec.md` (frozen `CheckpointDatumV1`, message wire
contract, F10 eq1–eq8, dual-threshold rule, `deriveAidAssetName`),
`specs/92-checkpoint-contention/spec.md` (sovereign per-AID checkpoint,
status-by-address), `specs/106-enforcement/spec.md` (`EventEvidence` slice
discipline, O1/O2), `specs/114-registration/spec.md` (Register branch,
E-slice machinery, A-001 standing conditions, #116 gate-room), and the
**incoming-set witness ruling (epic, 2026-07-18, non-negotiable)** restated
in "Ratified invariants" below.

!!! danger "This document amends frozen protocol surface"
    The `AdvanceMessage` signed preimage changes shape (17 → 18 fields:
    `new_witnesses` is replaced by the `wit_cut`/`wit_add` delta). The
    advance path has never been deployable (every spend fails closed at
    HEAD), so this is a **pre-deployment amendment** — but it is
    frozen-contract material and is submitted for explicit ratification at
    the spec checkpoint before any slice is dispatched.

---

## Problem

`main` at 53837f7 ships the registration path end-to-end (#114), but the
checkpoint is write-once: every spend of the state UTxO fails closed (R10).
The #68 message layer carries an `AdvanceMessage`/`advance_equalities` pair
that predates the epic's witness ruling: it signs a `new_witnesses` full
list, validates no witness receipts at all, and its module docs still
describe the abandoned two-seal handoff. #115 delivers the Advance spend
branch — KERI rotation admission with dual-threshold key proof and
incoming-set witness receipts — and amends the message layer to the ratified
delta schema.

## Scope

**In scope**

1. **`AdvanceMessage` amendment** (both languages, goldens regenerated):
   `new_witnesses : List<Verkey>` → `wit_cut`/`wit_add` deltas in the signed
   preimage; `new_toad` stays; stale two-seal comments fixed.
2. **Witness-delta derivation + validity rules** (W1–W3 below) and the
   amended eq7 (created datum's `witnesses` is the *derived* incoming set).
3. **Advance evidence layer** (`advance.ak` / `Advance.hs`): the rot
   event-binding slice set AE1–AE10, controller dual-threshold signatures
   over the reconstructed preimage, and the incoming-set receipt gate.
4. **`checkpoint.ak` spend branch** (`Advance` redeemer, V1–V7): consume the
   tip, exactly one successor at ACTIVE; Register untouched; Freeze/Convict/
   Close still fail closed; #116 gate-room preserved.
5. keripy-oracle **witness-changing rotation fixture family** (hermetic
   flake extension; existing bundles byte-unchanged) + Haskell/Aiken parity
   (bytes AND verdicts) + measurement cells (2-key, 7-key, witnessed) under
   the A-001 ≥25% headroom STOP gate.

**Out of scope**

- Freeze/convict wiring and the unicity/absence gate (#116); close/
  migration, role encoding O4, deposit economics O3 (#117); adversarial tx
  suite + full budget matrix (#118); devnet cast (#44).
- Delegated rotation (`drt`) admission — rejected in V1 (AE1).
- Interaction (`ixn`) checkpointing — an advance is a rotation by
  definition; non-establishment events never touch the checkpoint.
- Multi-chunk/attested tiers; any blake3 over the rot bytes (none is needed
  — see "No SAID proof on the advance path").

---

## Ratified invariants (inherited — binding)

1. Advance consumes the tip and creates **exactly one** successor at ACTIVE;
   binds network/policy/asset/AID/spent-outref/`seq+1`/strictly increasing
   `native_sn` (F10 eq1–eq5, frozen).
2. KERI pre-rotation dual threshold (eq6a/eq6b, frozen): evidence satisfies
   the rotation's own `new_cur_threshold` over `new_cur_keys` AND the spent
   checkpoint's committed `(next_keys, next_threshold)` via
   `blake3_256(qb64(key))` digests; the spent current set never authorizes;
   partial/reserve rotation (GLEIF 3-of-7) supported.
3. **Incoming-set witness rule (epic, 2026-07-18):** evidence carries KERI's
   delta `br`/`ba`/`bt` only; the validator derives
   `new_set = (old.witnesses − br) ∪ ba` (cuts first, adds appended, order
   preserved) and, when `new_toad > 0`, verifies **≥ `new_toad`** valid
   Ed25519 receipts drawn from `new_set` over the exact anchoring event
   bytes (O1). Bounds `1 ≤ new_toad ≤ |new_set|`, or `0` iff the set is
   empty. A cut/outgoing-only witness receipt MUST NOT count. **NO**
   outgoing-set endorsement; **NO** magnitude bound; `toad → 0` downgrade =
   zero receipts + visible datum.
4. O1: every signature verifies over full serialized bytes, never a SAID.
5. Slice discipline (#106/#114): prover-supplied offsets **locate**, never
   define — every expected slice is computed from validated state.
6. `aid_asset_name == deriveAidAssetName(cesr_aid)`; status is the address;
   frozen #68 shapes are consumed, not re-derived.
7. A-001 standing conditions: adversarial vectors for every new checking
   surface; measurement gate ≥25% headroom with STOP-on-miss (fallback is
   never weakening checks).
8. #116 gate-room: no check may assume a fixed input count or reject
   transactions for carrying inputs beyond those the branch names.

---

## The `AdvanceMessage` amendment (spec-checkpoint material)

### New signed preimage — Constr 0, 18 fields in frozen order

The one structural change: field 14 (`new_witnesses`) is replaced by the
two delta fields, in KERI event order (`br` before `ba`); everything after
shifts by one. `new_toad` stays. Constructor index stays 0.

| # | Field | Data encoding | Status |
|---|---|---|---|
| 1 | `domain` | `B` (the frozen `adv` literal) | unchanged |
| 2 | `network_id` | `I` | unchanged |
| 3 | `checkpoint_policy_id` | `B` | unchanged |
| 4 | `aid_asset_name` | `B` | unchanged |
| 5 | `cesr_aid` | `B` | unchanged |
| 6 | `spent_txid` | `B` | unchanged |
| 7 | `spent_index` | `I` | unchanged |
| 8 | `prior_seq` | `I` | unchanged |
| 9 | `prior_native_sn` | `I` | unchanged |
| 10 | `new_cur_keys` | `List(B)` | unchanged |
| 11 | `new_cur_threshold` | `Threshold` data | unchanged |
| 12 | `new_next_keys` | `List(B)` | unchanged |
| 13 | `new_next_threshold` | `Threshold` data | unchanged |
| 14 | **`wit_cut`** | `List(B)` — raw 32-byte verkeys cut (KERI `br`) | **replaces `new_witnesses`** |
| 15 | **`wit_add`** | `List(B)` — raw 32-byte verkeys added (KERI `ba`) | **new** |
| 16 | `new_toad` | `I` (KERI `bt`) | unchanged (shifted) |
| 17 | `seq_to` | `I` | unchanged (shifted) |
| 18 | `native_sn_to` | `I` | unchanged (shifted) |

The signed preimage stays the canonical-CBOR serialization of the Constr-0
`Data` tree (`cbor.serialise` / `toBuiltinData`), unchanged in mechanism.

**Domain string: unchanged (`cardano-keri/checkpoint/adv/v1`) — ratified by
A-005.** The #68 freeze note says field order changes only by minting a
new version tag; that discipline protects *deployed* artifacts. No advance
artifact has ever been produced outside test goldens (spends fail closed;
nothing is on any chain), so the recommendation is to amend in place under
`/v1` and regenerate the goldens, keeping `/v2` for a genuinely
post-deployment migration. Alternative (bump to `adv/v2` now) costs a dead
version number and implies a v1 that never existed.

**Ratified amendment (2026-07-19, A-005/QA).** The 18-field delta layout is
amended in place under `cardano-keri/checkpoint/adv/v1`. The version-tag
discipline protects deployed surface; no advance artifact has existed outside
test goldens, so minting a dead `adv/v2` would add noise rather than preserve
compatibility. Advance goldens regenerate under `/v1`; `/v2` remains reserved
for a post-deployment migration.

### Why the controller signs the delta, not the list

The delta is what KERI's `rot` event actually carries (`br`/`ba`); signing
the same shape the witnesses receipt keeps one semantic object across both
signature domains. It also makes the datum's witness list a *derived* value
— the validator, not the prover, computes the incoming set, so a signed
message can never smuggle a witness list that disagrees with the event the
witnesses receipted.

### `SpentCheckpoint` gains `witnesses`

The delta derivation needs the spent witness list. `SpentCheckpoint` (a
validation-context type constructed from the spent datum — **not** a wire
type; no golden changes beyond the message) gains
`witnesses : List<Verkey>` after `cesr_aid`, in both languages. The spend
branch fills it from the spent inline datum.

### Witness-delta validity + derivation (W1–W3)

Checked inside `advance_equalities`, between eq5 and eq6 (new `AdvanceError`
constructors `EqW1CutInvalid`, `EqW2AddInvalid`; W3 lands in the amended
eq7). Mirrors keripy's rotation rules exactly:

- **W1 — cuts valid.** `wit_cut` entries are pairwise distinct and every
  entry ∈ `spent.witnesses`. (A dup cut or a cut of a non-member is a
  malformed rotation — keripy rejects it; so do we. Neither is otherwise
  caught: set-wise both are no-ops.)
- **W2 — adds valid.** `wit_add` entries are pairwise distinct,
  `wit_add ∩ wit_cut = ∅` (no cut-then-re-add in one event), and
  `wit_add ∩ (spent.witnesses − wit_cut) = ∅` (no add-already-present).
- **W3 — derived set.** `new_set = (spent.witnesses − wit_cut) ++ wit_add`:
  survivors keep the spent order, adds are appended in `wit_add` order. The
  amended **eq7** requires the created datum's `witnesses` field to equal
  `new_set` exactly (alongside the other new-state fields), and its `toad`
  to equal `new_toad`.
- `new_toad` bounds (`1 ≤ new_toad ≤ |new_set|`, or `0` iff empty) are
  **already enforced** by eq8's `datum_well_formed` rule 14 over the created
  datum — `bt`-out-of-bounds needs no new check, only its adversarial
  vector.

### Stale two-seal comments (fixed with the amendment)

`onchain/lib/cardano_keri/checkpoint/message.ak` ("Advance message
(rotation / two-seal handoff)" section header) and
`offchain/lib/Cardano/KERI/AID/Checkpoint/Message.hs` (export-list and
section headers) still call the advance a "two-seal handoff". The
amendment commit re-titles these to the dual-threshold + incoming-set
model and sweeps any remaining `two-seal` mention in the two files.

### Blast radius (all regenerated in the amendment slice)

`message.ak` + `message_tests.ak` + `vectors.ak` goldens (Aiken),
`Message.hs` + `MessageSpec.hs` + `GenCheckpointVectors.hs` goldens
(Haskell), shared-vector parity (bytes AND verdicts). Registration
artifacts are untouched — `InceptionMessage` does not change.

---

## Transaction shape

Advance is **one transaction** (no hash-proof pre-step: see "No SAID proof
on the advance path"):

```
Tx Advance (spend, redeemer Advance { evidence }):
  input:  the tip checkpoint UTxO at ACTIVE
          (token (checkpoint_policy, aid_asset_name), inline V1 datum OLD)
  output: exactly one successor at ACTIVE
          (same token, inline V1 datum NEW, lovelace >= min_ada + d_reg)
  mint:   nothing under checkpoint_policy (the token moves; no mint/burn)
```

### The `Advance` spend branch (`checkpoint.ak`, V1–V7)

Same validator parameters as #114 (`version`, `hash_proof_policy`,
`network_id`, `d_reg`); the spend handler replaces the unconditional `fail`
with a redeemer sum — `Advance { evidence }` runs V1–V7, every other
constructor still fails closed (#116/#117 land there).

```
AdvanceEvidence {
  event_bytes : ByteArray             -- full keripy rot serialization
  off_t   : Int                       -- offset of the event-type value
  off_i   : Int                       -- offset of the 44-char qb64 AID
  off_s   : Int                       -- offset of the hex sequence-number value
  off_k   : List<Int>                 -- offsets of the 44-char qb64 `k` entries
  off_kt  : Int                       -- offset of the kt JSON value
  off_n   : List<Int>                 -- offsets of the 44-char `n` entries
  off_nt  : Int                       -- offset of the nt JSON value
  off_br  : List<Int>                 -- offsets of the 44-char `br` entries
  off_ba  : List<Int>                 -- offsets of the 44-char `ba` entries
  off_bt  : Int                       -- offset of the bt JSON value
  wit_cut : List<ByteArray>           -- raw 32-byte verkeys cut (KERI br)
  wit_add : List<ByteArray>           -- raw 32-byte verkeys added (KERI ba)
  ctrl_sigs : List<(Int, ByteArray)>  -- (index into new_cur_keys, Ed25519 sig)
                                      --   over the AdvanceMessage preimage
  wit_receipts : List<(Int, ByteArray)> -- (index into DERIVED new_set,
                                      --   Ed25519 sig over event_bytes)
}
```

- **V1 — own input.** The spent `out_ref` resolves to an input at
  `Address(Script(own_hash), None)` carrying
  `(own_policy, deriveAidAssetName(OLD.cesr_aid))` at quantity one, with
  the inline V1 datum `OLD`. Fails closed on any non-V1 datum constructor.
- **V2 — successor output.** Exactly one output at the ACTIVE address; it
  carries the same token at quantity one and inline V1 datum `NEW`
  (one-element filter = the datum-confusion guard, as in R2). No mint under
  `own_policy` (`tokens(mint, own_policy)` is empty — the token moves).
- **V3 — deposit continuity.** The successor's lovelace
  `>= min_ada + d_reg` (mechanism as R8; economics stay O3/#117).
- **V4 — message equalities.** `advance_equalities(spent, M, NEW, signers)
  == AdvanceValid` where `spent` is the `SpentCheckpoint` built from `OLD`
  + the deployment parameters + the spent `out_ref`, and `M` is the
  **reconstructed** `AdvanceMessage`: domain literal, deployment
  parameters, `deriveAidAssetName(NEW.cesr_aid)`, `NEW.cesr_aid`, the spent
  `out_ref`, `OLD.seq`/`OLD.native_sn`, `NEW`'s key-state fields,
  `evidence.wit_cut`/`wit_add`, `NEW.toad`, `NEW.seq`/`NEW.native_sn`.
  Nothing message-shaped is caller-supplied except the delta lists — which
  W1/W2 validate against `OLD.witnesses`, AE8/AE9 pin to the receipted
  bytes, and the controllers sign inside the preimage. This carries
  eq1–eq5, W1/W2, eq6 dual-threshold, amended eq7, eq8.
- **V5 — controller signatures.** `signers` for V4 =
  `RevealedSuccessorSigners` of the keys at distinct positions of
  `evidence.ctrl_sigs` that verify over the canonical-CBOR preimage of `M`
  with `NEW.cur_keys[idx]` (the `verified_positions` convention: bad index
  or bad signature never counts, never aborts).
- **V6 — event binding.** The AE1–AE10 slice set below holds over
  `evidence.event_bytes`.
- **V7 — witness gate.** Let `new_set` be the W3 derivation. If
  `NEW.toad == 0`: no receipts required (`new_set` is empty by rule 14 —
  the downgrade is visible in the datum). Else: the count of **distinct**
  indices in `evidence.wit_receipts` whose `(idx, sig)` verifies with
  `new_set[idx]` over `evidence.event_bytes` is `>= NEW.toad`. Out-of-range
  or non-verifying entries never count; duplicate indices count once. A cut
  witness appears at no `new_set` index, so its receipt can never count —
  structurally, not by filter.

Gate-room (#116): V1 names one input and V2 one output at ACTIVE; nothing
bounds total inputs/reference inputs. `len(event_bytes)` is unbounded by
construction (no blake3 chunk limit exists on this path). **Ratified QD note:**
the registration path's 1024-byte inception cap already bounds the registered
population's board sizes, so advance inherits a practical bound; the
measurement gate covers the remaining execution-budget bound.

### No SAID proof on the advance path (ratified — QC)

Registration needed the hash-proof mint because the AID **is** the blake3
SAID of the inception bytes — an identity claim requiring an in-script
digest. An advance makes no such claim: the identity is already anchored by
the spent token/datum; `event_bytes` only needs to (a) spell exactly the
transition being written — AE1–AE10, computed from validated state — and
(b) carry ≥ `new_toad` incoming-set receipts over those exact bytes (O1).
The rot event's `d` (its own SAID) and `p` (prior-event SAID) spans are
therefore **not checked**: the checkpoint tracks projected key state, not
KEL digests, and no on-chain field exists to check them against. Any
byte-string that spells this transition and is receipted by the incoming
quorum is valid witness evidence. Consequence: no blake3 over `event_bytes`
anywhere (eq6b's per-revealing-key digests are the only blake3 on the
path), and Tx-A-style proof tokens do not exist for advances.

**Ratified QC rationale (A-005).** Spend linearity is the prior-event binding:
the spent outref anchors the identity and checkpoint state, while strict
sequence monotonicity and AE1–AE10 pin the claimed rotation to the transition
being written. A rotation with a wrong `p`, but the correct reveal at the
correct sequence number and receipts from the required incoming threshold, is
witnessed duplicity. That lies inside the same honest-threshold boundary on
which the rest of the design already relies. Accordingly, leaving `d` and `p`
unchecked is deliberate, and #116 inherits this rationale when it resolves the
SAID question for enforcement evidence.

### The advance event-binding slice set (AE1–AE10)

All checks are `slice(event_bytes, off, len) == expected` with expected
bytes computed from the datum/message — the #106/#114 discipline
(`slice_matches`/`slices_match` are reused; the script never parses JSON):

| # | Field | Expected bytes |
|---|---|---|
| AE1 | `t` | `"rot"` at `off_t` (3 bytes; `icp`/`dip`/`drt`/`ixn` all differ ⇒ rejected) |
| AE2 | `i` | `qb64_aid(NEW.cesr_aid)` at `off_i` (44 chars) |
| AE3 | `s` | `respell_hex(NEW.native_sn)` at `off_s` (KERI `s` is the rot's own sn = `native_sn_to`) |
| AE4 | `k` | `len(off_k) == len(NEW.cur_keys)`; each `qb64_verkey(NEW.cur_keys[j])` at `off_k[j]` |
| AE5 | `kt` | canonical re-spelling of `NEW.cur_threshold` at `off_kt` (`respell_threshold`) |
| AE6 | `n` | `len(off_n) == len(NEW.next_keys)`; each E-code spelling of `NEW.next_keys[j]` at `off_n[j]` |
| AE7 | `nt` | re-spelling of `NEW.next_threshold` at `off_nt` |
| AE8 | `br` | `len(off_br) == len(wit_cut)`; each `qb64_witness_verkey(wit_cut[j])` at `off_br[j]` (B code) |
| AE9 | `ba` | `len(off_ba) == len(wit_add)`; each `qb64_witness_verkey(wit_add[j])` at `off_ba[j]` |
| AE10 | `bt` | `respell_hex(NEW.toad)` at `off_bt` |

**Why offset misdirection fails here.** The receipts fix the bytes: a
receipt only counts if an incoming-set witness signed `event_bytes`
verbatim, so the prover cannot invent bytes without the quorum's
cooperation. Within genuinely receipted bytes, every expected value is
derivation-code-prefixed (`D`/`E`/`B`) or an exact re-spelling computed
from the datum, so pointing an offset at a different field compares
differently-coded strings and fails; duplicated `off_k` entries collapse to
duplicate keys and fail rule F18-2 via eq8; spans into `a`/`p`/`d` compare
against code-prefixed expectations and fail. The dedicated misdirection
family (A-001 condition 1) is mandatory acceptance material.

---

## Fixtures — the keripy oracle (hermetic flake extension)

Extend `offchain/test/keri-fixtures/gen_fixtures.py` with a
**witness-changing rotation family**; every honest artifact is
reference-implementation output; existing bundles byte-unchanged;
regeneration byte-stable:

- `adv_wit_2key` — a true 2-key shape: witnessed `icp` (3 witnesses,
  `toad = 2`) → `rot` that cuts one witness and adds one
  (`br = [w0]`, `ba = [w3]`, `bt = 2`), with per-field offsets
  (incl. `br`/`ba` list spans), controller sigs, and **incoming-set witness
  receipts** over `rot.raw` (keripy nontransferable witness signers).
- `adv_wit_7key` — the GLEIF Root shape: 7-key reserve `icp` (witnessed) →
  partial-reveal `rot` (3-of-7, restated `kt`) with a witness cut/add and
  receipts.
- `adv_downgrade` — a `rot` cutting **all** witnesses (`bt = 0`; the
  visible-downgrade positive vector, zero receipts).
- `adv_keep` — a no-delta witnessed `rot` (`br = ba = []`, same set;
  receipts from the unchanged set) — the common steady-state advance.
- The offsets machinery (`_field_spans`) learns the `p`, `br`, `ba` spans;
  seed export covers witness signers (receipts over `event_raw` stay keripy
  output; Cardano-side `AdvanceMessage` signatures are produced in the
  Haskell layer from exported seeds, as in #114).
- Existing `honest_2key`/`honest_7key` rot material is reused where it fits
  (their unwitnessed rotations exercise the `toad = 0` equalities).

Adversarial vectors (delta malformations, receipt games, misdirected
offsets, stolen-quorum rotations) are deterministic constructions over
these honest artifacts in the vector generators — never keripy output,
never mutations of committed bundles.

---

## Acceptance criteria

- [ ] The amended `AdvanceMessage` (18 fields, `wit_cut`/`wit_add`)
      round-trips byte-identically between Haskell and Aiken (goldens
      regenerated once, then frozen; registration bundles byte-unchanged);
      stale two-seal comments gone from both message modules.
- [ ] A real keripy witnessed `rot` fixture advances end-to-end through the
      Aiken spend branch (constructed `ScriptContext`), for `adv_wit_2key`,
      `adv_wit_7key`, `adv_keep`, and `adv_downgrade`.
- [ ] Witnessed 2-of-3 advance accepted with threshold receipts; the same
      advance with 1 receipt, 0 receipts, or `new_toad` duplicate receipts
      from one witness rejected (V7) — **receipt-free advance rejected
      regardless of elapsed time** (no time axis exists in the gate).
- [ ] Witness-changing advance accepted on incoming-set receipts; a
      receipt by a cut witness does not count (V7 structural); an
      outgoing-only quorum (old set, disjoint from `new_set`) rejected.
- [ ] Receipt-index games rejected: out-of-range index, index pointing at a
      different member than the signer, duplicated indices counted once —
      each with an executable vector.
- [ ] Delta malformations rejected: dup cuts, dup adds,
      add-already-present, cut-not-present, cut∩add overlap (W1/W2), datum
      witness list ≠ derived set, wrong survivor order (eq7), `bt` out of
      bounds (eq8) — each with an executable vector.
- [ ] Full stolen current-key quorum cannot rotate (eq6b); partial reserve
      3-of-7 passes (eq6a+eq6b); below-threshold and wrong-preimage
      controller signatures rejected (V5).
- [ ] Slice vectors: each of AE1–AE10 has at least one rejection, plus the
      offset-misdirection family (spans into `a`/`p`/`d`, cross-field
      offsets, code confusion, truncated/overlapping spans, duplicated
      offsets) in both languages (A-001 condition 1).
- [ ] Transaction-shape vectors: second output at ACTIVE, missing/extra
      token, token minted or burned under own policy, non-V1 datum,
      lovelace below `min_ada + d_reg`, `seq` skip, `native_sn`
      non-increase — each rejected (V1–V4).
- [ ] Register branch behavior unchanged at HEAD (its #114 suite green,
      byte-identical goldens); non-`Advance` spend redeemers still fail
      closed.
- [ ] Haskell/Aiken parity: shared generated vectors, byte-identical
      encodings AND identical verdicts; drift check green.
- [ ] **Measurement gate (A-001 condition 2):** the full Advance spend
      context measured at `adv_wit_2key`, `adv_wit_7key`, and `adv_keep`
      shapes meets ≥25% headroom; on a miss the ticket STOPS and Q-files
      the epic owner (fallback is never weakening checks).

## Spec-checkpoint rulings (Q-005 / A-005 — ratified 2026-07-19)

- **QA — APPROVED.** The 18-field `AdvanceMessage` layout above, amended **in place
  under the `adv/v1` domain** (pre-deployment; goldens regenerate; `/v2`
  reserved for post-deployment migration).
- **QB — APPROVED.** `SpentCheckpoint` gains `witnesses` (validation-context type,
  both languages); W1/W2 delta-validity live inside `advance_equalities`
  with new error constructors; eq7 checks against the derived set.
- **QC — APPROVED.** **No SAID/blake3 proof over the rot bytes** (section above): the
  receipts + AE slices + dual-threshold signatures carry the binding; `d`
  and `p` spans remain deliberately unchecked under the ratified rationale.
- **QD — APPROVED.** No structural cap on `len(event_bytes)` (no blake3 chunk bound
  exists on this path; the registration cap and measurement gate supply the
  practical bounds).
- **QE — APPROVED.** Deposit continuity as V3 (`successor lovelace >= min_ada +
  d_reg`, same constant mechanism as R8; economics remain O3/#117).
- **QF — APPROVED.** The slice plan in `plan.md` (S1 fixtures → S2 Haskell amendment
  → S3 Aiken amendment+parity → S4 Haskell advance predicate → S5 Aiken
  predicate+parity → S6 spend branch+measurement STOP gate → S7 report).
