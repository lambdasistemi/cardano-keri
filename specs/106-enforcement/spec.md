# Spec: convict (burn) and freeze spend paths — on-chain enforcement of KERI↔Cardano divergence (#106)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/106
Blocks: #24 (the checkpoint validator — these spend paths must ship inside the
V1 script; a script hash cannot grow paths after deployment).
Ratified inputs: the three-mode enforcement ruling (2026-07-17, documented in
`specs/68-keystate-shape/identity-model.md` §11b and
`docs/design/trust-model.md`), the frozen E-native wire contract
(`specs/68-keystate-shape/spec.md`, merged in #105), status-by-address
(`specs/92-checkpoint-contention/spec.md`: lifecycle is carried by the token's
lineage and the designated script address, never a datum enum).

!!! danger "This document extends protocol surface"
    The proof formats, conviction/freeze predicates, and the address-role
    lifecycle below become part of the V1 validator surface. They change only
    with a new script (a migration), so every predicate here must be right the
    first time. Nothing in the frozen #68 datum/message contract is modified.

---

## Problem

The checkpoint is a projection of a KERI identity. The ratified ruling gives
each divergence mode a consequence: **fork → nullified**, **Cardano behind →
frozen**, **Cardano ahead → not in-script provable** (prevented structurally,
resolved when the KEL moves). #24 cannot freeze the validator until the
convict/freeze proof formats and predicates are exact — that is this spec.

## Scope

**In scope**

1. The **address-role lifecycle**: active / frozen / tombstone script
   addresses and the legal transitions between them.
2. The **`Convict` spend path**: proof format, the conviction predicate, the
   tombstone output shape, and the bounty payout.
3. The **`Freeze` spend path**: proof format, the freeze predicate, the frozen
   output shape, and the (advance-only) thaw.
4. **Framing resistance** requirements and their negative vectors.
5. **Measurement obligations** (delegated to the #109 matrix).

**Out of scope**

- Proving the *absence* of a KERI event (Cardano-ahead) — structurally
  prevented by witness receipts at advance; not a spend path.
- Punishing lag itself — lag is honest operation; only evidence triggers.
- Semantic correspondence fraud beyond the double-sign conflict (the freeze
  path plus fail-closed consumers cover it; superwatcher duties are #10).
- R-TEL mirror policing (#30 consumer policy).
- The rest of the #24 validator (registration, rotation, close, migration).

---

## Ratified invariants

1. **Attribution or nothing.** A conviction requires signatures that satisfy
   the checkpoint's own recorded threshold under the controller's keys.
   Witness signatures alone MUST NOT be able to convict — witnesses receipt
   events, they do not own identities. Framing collapses to key theft.
2. **Permissionless both ways.** Any party may submit either proof; neither
   path requires registration, stake, or identity.
3. **Tombstone is terminal.** No spend path exits the tombstone address. With
   #91 mint-once unicity the AID can never re-register.
4. **Freeze is exactly advance-shaped.** The only spend of a frozen checkpoint
   is a valid #68 advance (dual-threshold, eq1–eq8) whose continuing output
   returns to the active address. No unfreeze-without-catching-up.
5. **Status is the address.** Datum bytes are identical across active and
   frozen states; consumers read status from where the token sits (per #92).
   The tombstone is the only state with a distinct datum (the conviction
   record).
6. **No truth-choosing.** Both predicates verify presented cryptographic
   evidence; neither embeds any oracle, committee, or timeout.

---

## The address-role lifecycle

Three script addresses share the V1 validator (parameterized by role, or one
validator with a role datum tag — plan.md decides the encoding; the roles are
protocol surface, the encoding is not):

```
            genesis (#91 mint + hash-proof)
                      │
                      ▼
                ┌──────────┐  advance (eq1–eq8)   ┌──────────┐
                │  ACTIVE  │◄────────────────────►│  FROZEN  │
                └──────────┘   Freeze(proof)      └──────────┘
                      │                                 │
                      │ Convict(proof)                  │ Convict(proof)
                      ▼                                 ▼
                ┌────────────────────────────────────────────┐
                │                 TOMBSTONE                  │   (terminal)
                └────────────────────────────────────────────┘
```

- ACTIVE → ACTIVE: the #68 advance (unchanged by this spec).
- ACTIVE → FROZEN: `Freeze` with a valid lag proof; token + datum unchanged.
- FROZEN → ACTIVE: a valid #68 advance (the thaw *is* the catch-up).
- ACTIVE|FROZEN → TOMBSTONE: `Convict` with a valid conviction proof.
- TOMBSTONE: no spend path. Holds the token, the conviction record datum, and
  min-ADA forever.

## KERI event evidence — shared proof machinery

Both proofs carry a serialized KERI establishment event and locate fields in
it by **prover-supplied offsets checked with slice equality** — the script
never parses CESR/JSON:

```
EventEvidence {
  event_bytes   : ByteArray            -- the full serialized KERI event (≤ 1024 B, one blake3 chunk)
  off_t         : Int                  -- offset of the event-type value ("rot" / "ixn" / "icp")
  off_s         : Int                  -- offset of the hex sequence-number value
  off_i         : Int                  -- offset of the 44-char qb64 AID
  off_k         : List<Int>            -- offsets of the 44-char qb64 entries of `k`
  off_n         : List<Int>            -- offsets of the 44-char qb64 entries of `n`
  said_blank    : ByteArray            -- event_bytes with the SAID span dressed (for SAID recomputation)
  ctrl_sigs     : List<(Int, ByteArray)>   -- (key index into k, Ed25519 signature)
  wit_sigs      : List<(Int, ByteArray)>   -- (witness index into the checkpoint's stored set, signature)
}
```

Checks shared by both predicates (over tip datum `D`):

- `slice(event_bytes, off_i, 44) == qb64_aid(D.cesr_aid)` — the event is for
  this AID (`qb64_aid` = `'E' ‖ b64url(0x00 ‖ digest)[1..]`, mirroring the
  existing `qb64_verkey`).
- `slice(event_bytes, off_t, 3) == "rot"` (Convict/Freeze evidence is an
  establishment event; `icp` is excluded — genesis conflicts are impossible
  under mint-once + the #91 keys-in-event gate).
- The sequence-number slice equals the hex spelling of the predicate's target
  sn (hex spelling supplied by the prover, checked by re-encoding).
- SAID (AID binding): `blake3(said_blank) == slice(event_bytes, off_d, 44-decoded)`
  via the #24 hash-proof machinery, where `said_blank` is `event_bytes` with the
  `i`/`d` spans dummied; `said_blank` must equal `event_bytes` outside those
  spans (two slice comparisons). This binds the event bytes to the AID —
  anti-substitution — and is the *only* use of the SAID.
- `ctrl_sigs`: each `(idx, sig)` verifies with the raw key decoded from
  `k[idx]`'s qb64 slice, **over `event_bytes` (the full serialization)** — NOT
  over the SAID. (O1 RESOLVED empirically against keripy 1.3.5, 2026-07-17: both
  controller indexed signatures and witness receipts verify over `serder.raw`;
  verification against the SAID bytes fails. So the carried event bytes are the
  signature target directly — no SAID-isolation needed for signature checks.)

## The `Convict` predicate (fork → tombstone)

Given tip datum `D` at either role address and `EventEvidence` `E`:

1. Shared checks pass with target sn = `D.native_sn`.
2. **Same reveal**: the decoded raw keys at `E.off_k` equal `D.cur_keys` as a
   positional list. (The conflicting event and the checkpoint claim the same
   revealed key set at the same sn — this is what makes the conflict a
   double-sign of one commitment rather than two unrelated events.)
3. **Controller attribution**: `E.ctrl_sigs` satisfy `D.cur_threshold` over
   positions in `D.cur_keys` (exact rational evaluation, reusing #68
   `evaluate`).
4. **Conflict**: the qb64-decoded digests at `E.off_n` differ from
   `D.next_keys` (as positional lists), OR the event's `nt`/`kt`/`b`/`bt`
   slices differ from `D`'s recorded values (any single material mismatch
   suffices; equality of everything = no conflict = reject).
5. **Output shape**: the continuing output sits at the tombstone address,
   carries the quantity-one token, min-ADA, and the conviction record datum:

   ```
   TombstoneV1 { cesr_aid, convicted_at_native_sn : Int, evidence_said : ByteArray }
   ```

6. **Bounty**: the remaining value (registration deposit) pays the transaction
   as the prover directs. No controller signature is required anywhere.

Witness receipts (`wit_sigs`) are **not required** for conviction (invariant
1: attribution comes from controller signatures). If present they are ignored
by the predicate — the plan may log them for off-chain analytics only.

## The `Freeze` predicate (lag → frozen)

Given tip datum `D` at the ACTIVE address and `EventEvidence` `E`:

1. Shared checks pass with target sn strictly `> D.native_sn`.
2. **Committed reveal**: for each `ctrl_sigs` index, `blake3(qb64(k[idx]))`
   (one single-block hash per signing key, the #68 `next_key_digest`) is
   located in `D.next_keys`; the located positions satisfy
   `D.next_threshold`. (The event provably spends this checkpoint's own
   pre-rotation commitment — it is *this* identity's future, not noise.)
3. **Witnessed**: `E.wit_sigs` verify against `D.witnesses` (raw keys, native
   Ed25519, **over `event_bytes`** — per O1, witness receipts sign the full
   serialization, not the SAID) and count `≥ D.toad`. A `toad = 0` checkpoint
   is freezable with controller-signature evidence alone (a documented weaker
   tier — consistent with #68's witnessless stance).
4. **Output shape**: the continuing output sits at the FROZEN address with
   byte-identical datum and the token; all other value is preserved. No
   bounty (freezing is cheap, reversible, and must not be grief-profitable;
   the submitter pays fees).
5. FROZEN → ACTIVE is not part of this predicate: it is the ordinary #68
   advance, accepted from the frozen address, with its continuing output
   required at the ACTIVE address.

### Griefing analysis (why freeze needs no bounty and no cooldown)

A freeze requires a *real* witnessed successor event revealing the committed
next keys — only the controller can mint that evidence. So a third party can
only freeze a checkpoint whose controller has in fact rotated in KERI: the
"grief" is forcing the projection to tell the truth. The controller thaws by
advancing — which they must do anyway. A freeze submitted with fabricated
evidence fails signature/receipt checks; a freeze replayed after the thaw
fails check 1 (its sn is no longer `> D.native_sn` once the advance lands…
if it still is, the freeze is legitimate again).

## Deposit and bounty mechanics

- Registration (#24/#91) locks a fixed deposit `D_reg` in the checkpoint UTxO
  above min-ADA. Its size is a #24 parameter (open question O3 records the
  trade-off: large enough to fund a conviction bounty that pays a watcher's
  costs, small enough not to gate registration).
- `Convict` releases everything except tombstone min-ADA to the prover.
- Ordinary advances and freezes must preserve the deposit (value-preservation
  checks in those paths — #24 obligation, restated here because Convict's
  economics depend on it).
- Close (#24) returns the deposit to the controller (a closed identity has no
  conviction surface left; its tombstone-on-close shape is #24's).

## Framing resistance — the negative-vector contract

Each of these MUST be a rejected vector in both implementations:

| # | Attack | Rejected by |
|---|---|---|
| F1 | Witness-signatures-only conviction (no controller sigs) | Convict 3 |
| F2 | Conviction with sigs below threshold | Convict 3 |
| F3 | Conviction where the event matches `D` exactly (no conflict) | Convict 4 |
| F4 | Conviction at sn ≠ `D.native_sn` | shared sn check |
| F5 | Conviction with another AID's event (i-field mismatch) | shared AID check |
| F6 | Conviction whose `said_blank` diverges outside the SAID span | #24 slice reconstruction (see note) |
| F7 | Conviction with revealed keys ≠ `D.cur_keys` (two unrelated events) | Convict 2 |
| F8 | Freeze with unwitnessed event (receipts < toad) | Freeze 3 |
| F9 | Freeze whose signing keys are not committed in `D.next_keys` | Freeze 2 |
| F10 | Freeze at sn ≤ `D.native_sn` (stale/replay) | Freeze 1 |
| F11 | Spend of a tombstone output by any redeemer | lifecycle (no path) |
| F12 | Freeze output at any address other than FROZEN / datum mutated | Freeze 4 |
| F13 | Convict output missing token or conviction record | Convict 5 |

**F6 and F11 — the two validator-boundary vectors.** F6 (the `said_blank`
anti-substitution) is the on-chain **slice reconstruction** the schema layer
out-of-scopes to #24: the schema predicates already verify every signature over
the exact `event_bytes`, so no signature can be moved onto different bytes, and
the SAID-dummy reconstruction is precisely the CESR slicing #24 owns. F11 (a
tombstone is unspendable) is a **validator "no path" property**, not a pure
predicate — the schema layer encodes it as *terminality*: `TombstoneV1` carries
no advance/convict/freeze continuation, and #24's validator ships no spending
redeemer for the tombstone address. Both are covered by #24; the schema layer
delivers F1–F5, F7–F10, F12, F13 as executable rejected vectors and documents
F6/F11 as the #24 obligation.

Positive vectors: one conviction from ACTIVE and one from FROZEN (GLEIF-shaped
7-key fixture with a conflicting `n'`); one freeze with a 3-of-7 reserve-shaped
witnessed successor; one thaw-by-advance.

## Measurement obligations

Two layers, two owners:

- **Schema-layer predicate cost (this ticket, Slice 6):** the ex-units of
  `convict_predicate` and `freeze_predicate` as executed by the Aiken schema
  layer — per-signature `verify_ed25519_signature`, per-revealed-key
  `next_key_digest` (blake3, freeze only), threshold `evaluate`, and the list
  comparisons — measured on the 2-key and the GLEIF-shaped 7-key fixtures via
  `aiken check --plain-numbers`, reported against the mainnet per-tx budget.
- **Full-spend-context cost (#24 / #109):** SAID recomputation over the event
  bytes (≤ 1024 B) + CESR slice extraction + the transaction-level checks that
  wrap these predicates. This is the on-chain layer the schema predicates do NOT
  perform (they take decoded evidence), so it extends the #109 matrix under #24,
  not here.

Budget target: the schema-layer predicate cost leaves ample room (the SAID
recomputation is the dominant #24 cost, measured separately); Slice 6 reports the
predicate cells and confirms they are a small fraction of budget.

!!! important "#24 design question surfaced by the Slice-6 measurement (2026-07-17)"
    The Slice-6 cells show the 7-key GLEIF freeze schema predicate at **29.38%
    mem** (the binding cell; convict is < 1%). The naive full-spend estimate adds
    #24's SAID recomputation (~71.7% mem at 1024 B, spike #88), which would exceed
    budget for a 7-key freeze. **But O1 likely makes the SAID recomputation
    redundant:** every signature verifies over the full `event_bytes` (not the
    SAID), so the controller signatures (convict) and witness receipts (freeze)
    already bind `event_bytes` — including the `i`/AID field and the conflicting
    `n` — to the AID. An attacker can neither alter `i` nor forge a signature over
    the altered bytes. #24's **first enforcement design question** is therefore:
    *does the on-chain path need the SAID recomputation at all, or do the
    O1-over-`event_bytes` signatures suffice?* If the latter (expected), the
    dominant projected cost disappears and every enforcement path — including
    large-board freezes — fits one transaction with wide headroom.

## Open questions

- **O1 — witness/controller signing target — RESOLVED (2026-07-17).** Pinned
  empirically against keripy 1.3.5: both controller indexed signatures and
  witness receipts verify over the **full event serialization** (`serder.raw`),
  not over the SAID. The predicate text and shared checks above are updated
  accordingly; the SAID is used only for the AID-binding hash. Evidence is the
  `signing_target` field recorded per signature in every fixture manifest
  (Slice 1), which the generator sets by re-verifying each signature against
  both candidate byte strings.
- **O2 — `kt`/`bt` conflict encoding — RESOLVED (2026-07-17).** The schema-layer
  predicates compare the **decoded structured** `Threshold` (kt/nt) and the raw
  witness list (b) and integer toad (bt) directly (Slice 3/4), so a kt/nt/bt-only
  conflict IS detected — strictly stronger than the n/b-only fallback. The
  on-chain path re-derives the structured `Threshold` from the event's slices
  (canonical re-spelling), which is #24's CESR-slicing obligation; the schema
  contract fixes the comparison semantics.
- **O3 — deposit size — DEFERRED to #24 (validator parameter).** `D_reg` is a
  #24 registration/close parameter, not a #106 schema concern: large enough that
  a conviction bounty pays a watcher's costs, small enough not to gate
  registration. Recorded here as a #24 obligation.
- **O4 — role encoding — DEFERRED to #24 (address layout).** Address-per-role
  (Active/Frozen/Tombstone) vs one address with a role datum tag; address-per-role
  keeps consumer reads status-blind (#92 style) and is preferred. Decided with
  #24's address layout; the schema layer fixes the roles, #24 fixes the encoding.

## Acceptance criteria

- [ ] Convict and Freeze predicates implemented in both languages as pure
      schema-support functions (validator wiring in #24), byte- and
      verdict-parity tested like the #68 layer.
- [ ] All F1–F13 negative vectors and the three positive vectors executable in
      both implementations.
- [ ] Attribution invariant proven: no vector convicts without controller
      signatures satisfying the recorded threshold.
- [ ] Lifecycle documented for consumers (address roles, tombstone datum) in
      the architecture docs.
- [ ] O1 and O2 resolved with evidence (keripy cross-check committed as a
      fixture note); O3/O4 recorded as #24 parameters.
- [ ] #109 matrix extended with both proof contexts; ≥ 25% headroom shown.
