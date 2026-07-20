# Spec: enforcement wiring — freeze, convict, and mint once (#116)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/116
Epic: https://github.com/lambdasistemi/cardano-keri/issues/24

Registration and advance now cover the honest checkpoint lifecycle. This
ticket makes the same validator react to evidence: a witnessed later event can
freeze a stale checkpoint, a witnessed conflicting event can permanently
convict it, and the registration gate remembers every AID forever so a
convicted identity cannot mint a replacement checkpoint.

Ratified inputs (do not reopen without an epic Q-file):
`specs/106-enforcement/spec.md` (pure enforcement predicates and proof
fixtures), `specs/114-registration/spec.md` (live Register path and gate-room),
`specs/115-advance/spec.md` (live Advance path and O1 full-byte signatures),
and `specs/92-checkpoint-contention/spec.md` (sovereign per-AID state and
status-by-address).

!!! danger "This completes pre-deployment validator surface"
    The role addresses, append-only registration set, Freeze path, Convict
    path, and tombstone dispatch rule all affect the applied checkpoint script
    hash. They must be ratified before implementation. No deployed checkpoint
    exists, so this is the last safe place to amend the V1 script in place.

---

## Technical contract

### Decisions at a glance

1. **Do not recompute the event SAID on Freeze or Convict.** O1 signatures
   already cover the complete `event_bytes`. All predicate-relevant fields are
   slice-bound to those signed bytes. The `d` field is retained as a signed
   audit label, not treated as a second authorization root.
2. **Use an append-only MPFS registration set for mint-once unicity.** A
   singleton registry thread UTxO is consumed atomically with every Register.
   Its root inserts the AID-derived asset name with an absence proof; there is
   no delete/update path. The same combined checkpoint script mints and cages
   the registry thread token, so there is no trusted registry owner.
3. **Encode lifecycle roles on the staking-credential axis.** ACTIVE keeps the
   already-ratified no-stake address. FROZEN, TOMBSTONE, and the internal
   REGISTRY state use distinct deterministic staking **script** credentials
   derived from the checkpoint policy hash. The payment credential remains the
   checkpoint script hash for every role.

These three decisions are spec-checkpoint material.

### Ratification record (2026-07-20)

Epic #24's first design question is resolved here: enforcement-path SAID
recomputation is omitted. O1 signs the full event bytes and EE0–EE9
slice-bind every predicate-relevant field, so recomputing a blanked event
would add no authority boundary. The contemporary measurements below show why
that distinction matters: the historical 1024-byte hash projection consumes
about 71.7% memory, while the binding cell retains 80.34% memory headroom.

This is a dated #116 disposition, not a rewrite of #106 history. #106 F6's
`said_blank` reconstruction is superseded by signature-mutation and
wrong-`d`-slice adversarial vector families because this V1 wire contract has
no `said_blank` input.

## Problem

At `616c630`, `checkpoint.ak` admits Register and Advance but still rejects
Freeze, Convict, and Close. The #106 predicates exist only as decoded schema
functions; the live validator does not bind their fields to a transaction,
does not encode Frozen/Tombstone addresses, and has no terminal tombstone path.
Registration also still permits the same `(policy, aid_asset_name)` to be
minted in separate transactions. That temporary pre-deployment residual makes
conviction reversible by re-registration and therefore must disappear here.

## Scope

**In scope**

1. A live wire-evidence layer that slice-binds KERI `rot` fields to the exact
   bytes signed by controllers and witnesses, then invokes the #106 predicates.
2. ACTIVE → FROZEN, FROZEN → ACTIVE by ordinary Advance, and
   ACTIVE|FROZEN → TOMBSTONE transaction paths.
3. Tombstone terminality and bounty release from the registration deposit.
4. A permanent, permissionless MPFS absence gate coupled atomically to
   Register, including one-shot registry bootstrap.
5. Deterministic full-address role encoding.
6. Haskell/Aiken verdict parity, transaction-boundary adversarial vectors, and
   full-path execution-unit measurements.

**Out of scope**

- Close, migration, consumer lookup, and final deposit economics (#117).
- The full cross-path adversarial matrix (#118) and devnet cast (#44).
- A witness-delta/pool-swap-only conviction. It remains fail-closed to Freeze;
  `prev_witnesses_digest` is the named V2 hook.
- Replacing the sovereign per-AID checkpoint with an MPFS current-state store.
  The MPFS structure here remembers registration history only; Advance remains
  per-AID and contention-free across unrelated identities.
- Any `said_blank` reconstruction or BLAKE3 over enforcement event bytes.

## Inherited invariants

1. Controller and witness signatures verify over the complete KERI event
   serialization, never over its SAID (O1).
2. A witnessed conviction needs both the tip controller threshold and at least
   the tip `toad` in distinct valid witness receipts. A witnessless `toad = 0`
   AID remains the explicitly weaker controller-only tier.
3. Freeze needs a strictly later event whose verifying revealed keys satisfy
   the tip's committed `(next_keys, next_threshold)` and whose distinct valid
   receipts meet the tip `toad`.
4. Freeze preserves the complete state value and byte-identical V1 datum. Thaw
   is an ordinary Advance to ACTIVE; there is no separate unfreeze redeemer.
5. Convict leaves the quantity-one checkpoint token in a terminal tombstone,
   records the evidence, and releases the deposit remainder as bounty.
6. Status is derived from the exact full address, not from a status field in
   `CheckpointDatumV1`.
7. Close remains fail-closed. Tombstone is excluded before any current or
   future checkpoint-state redeemer dispatch.
8. Every registration inserts once into the permanent history set. A Frozen,
   Tombstone, advanced, or later closed checkpoint never removes that entry.

## SAID decision — no enforcement-path recomputation

### Decision

Freeze and Convict **MUST NOT recompute** `blake3(said_blank)` and MUST NOT
carry `said_blank`. The validator slice-checks the fields used by the
predicate, and every signature used for authority or witnessing verifies over
the complete `event_bytes`. Changing `i`, `s`, `k`, `kt`, `n`, `nt`, `bt`, or
`d` changes the signature target. An attacker without the required controller
and witness keys cannot substitute any of them; a party with those thresholds
can already produce a correctly self-addressed event, so repeating the SAID
hash adds cost without narrowing the authority boundary.

The `TombstoneV1.evidence_said` field is retained unchanged. It is the
E-code-stripped 32-byte value slice-bound to the signed event's `d` field: an
audit locator for the evidence, **not** a validator-recomputed claim that
`d == blake3(blank(event))`. No acceptance decision depends on it alone.

### Measurement evidence

Mainnet per-transaction limits are 14,000,000 memory and 10,000,000,000 CPU.

- The #106 spike priced a 1024-byte single-chunk SAID BLAKE3 recomputation at
  approximately **10.0M memory, 71.7% of the transaction budget**. The later
  full #114 hash-proof 1024-byte cell corroborates the scale at **10,241,066
  memory (73.15%) and 5,510,621,625 CPU (55.11%)**, including its surrounding
  handler and slice checks.
- A fresh `just measure-enforcement` at `616c630` (2026-07-20) measures the
  binding pure enforcement cell, `freeze_honest7`, at **2,751,945 memory
  (19.66% used, 80.34% headroom)** and **1,551,883,756 CPU (15.52% used,
  84.48% headroom)**. `fork_witnessed_convicts` costs **108,885 memory** and
  **146,649,513 CPU**.
- Even the older #106 pre-encoder-optimization freeze cell was only 4,113,688
  memory (29.38%). Naively adding the roughly 10.0M SAID cost to that cell
  crosses the 14M limit before the transaction shell. Removing the redundant
  hash leaves room for the live address, datum, token, and output checks.

The final live Freeze/Convict cells are still measured in this ticket. These
numbers decide that SAID recomputation is absent; they do not waive the
standing ≥25% live-path headroom gate.

### F6 disposition

#106 F6's proposed `said_blank` outside-span reconstruction is **superseded**:
there is no `said_blank` input to reconstruct. Its security intent is covered
by two executable boundaries:

- mutate any signed `event_bytes` field without replacing its threshold
  signatures/receipts → signature rejection;
- point `off_d` at bytes other than `qb64_aid(said)` or supply a non-32-byte
  `said` → wire-binding rejection.

The validator deliberately does not prove that the signed `d` is the BLAKE3
of a blanked serialization.

## Live enforcement evidence

The existing `EventEvidence` remains the decoded input to the #106 pure
predicates. A new wire type is the redeemer surface:

```text
EnforcementEvidence {
  event_bytes    : ByteArray
  off_t          : Int
  off_i          : Int
  off_s          : Int
  off_d          : Int
  off_k          : List<Int>
  off_kt         : Int
  off_n          : List<Int>
  off_nt         : Int
  off_bt         : Int
  native_sn      : Int
  said           : ByteArray
  revealed_keys  : List<ByteArray>
  next_keys      : List<ByteArray>
  cur_threshold  : Threshold
  next_threshold : Threshold
  toad            : Int
  ctrl_sigs       : List<(Int, ByteArray)>
  wit_sigs        : List<(Int, ByteArray)>
}
```

Offsets locate content; they never define it. Binding runs in this order:

| Check | Signed event slice |
| --- | --- |
| EE0 | `1 <= length(event_bytes) <= 1024` (the V1 single-chunk evidence tier) |
| EE1 | `off_t` equals `"rot"` |
| EE2 | `off_i` equals `qb64_aid(TIP.cesr_aid)` |
| EE3 | `off_s` equals `respell_hex(native_sn)` |
| EE4 | `said` is 32 bytes and `off_d` equals `qb64_aid(said)` |
| EE5 | `off_k` count and slices equal `qb64_verkey(revealed_keys)` positionally |
| EE6 | `off_kt` equals `respell_threshold(cur_threshold)` |
| EE7 | `off_n` count and slices equal `qb64_aid(next_keys)` positionally |
| EE8 | `off_nt` equals `respell_threshold(next_threshold)` |
| EE9 | `off_bt` equals `respell_hex(toad)` |

Only after EE0–EE9 pass is decoded `EventEvidence` constructed and supplied
to `freeze_predicate` or `convict_predicate`. `event_bytes` is used without
copying as every Ed25519 target. KERI `br`/`ba` are not decoded here: a
witness-line-up-only fork remains the named V2 residual.

### Pre-wiring schema corrections

Two corrections are required before the pure #106 predicates may secure a
live transaction:

1. Witness receipt quorum counts **distinct verifying witness indices**,
   matching #115's receipt gate. Repeating one valid `(idx, sig)` never
   satisfies `toad > 1`.
2. Convict's conflict axes are `kt`/`n`/`nt`/`bt`: an event with the same
   revealed keys but a different `cur_threshold` is a conflicting commitment.
   This restores #106 O2's stated `kt` behavior; `br`/`ba` remain excluded.

Both corrections land in Haskell and Aiken with shared negative vectors before
the validator branches open.

## Address roles

Let `h` be the applied checkpoint validator hash (also its token policy id),
and let:

```text
role_hash(h, tag) = blake2b_224(
  "cardano-keri/checkpoint/role/v1" || h || tag
)
```

Tags are one byte: FROZEN `0x00`, TOMBSTONE `0x01`, REGISTRY `0x02`.

| Role | Full address |
| --- | --- |
| ACTIVE | `Address(Script(h), None)` |
| FROZEN | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x00)))))` |
| TOMBSTONE | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x01)))))` |
| REGISTRY | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x02)))))` |

The markers are deterministic protocol labels, not caller parameters and not
verification keys. They grant no spending authority: every output still has
`Script(h)` as payment credential and therefore executes the combined
validator. Including `h` in the derivation prevents role-address aliasing
across validator versions. ACTIVE stays byte-for-byte compatible with #114 and
#115.

Every branch compares the **whole address**. An unknown staking credential
fails closed even when its payment credential is `Script(h)`.

## Mint-once unicity gate

### Registry state

The combined checkpoint validator gains a fifth parameter, a deployment
`registry_seed : OutputReference`, and a second mint redeemer:

```text
MintRedeemer =
  BootstrapRegistry
  | Register {
      evidence       : RegistrationEvidence,
      registry_ref   : OutputReference,
      absence_proof  : Proof
    }

RegistryDatumV1 { root : ByteArray }
```

The registry thread asset name is:

```text
blake2b_256(
  "cardano-keri/checkpoint/registry-thread/v1"
  || cbor.serialise(registry_seed)
)
```

It is under the checkpoint policy itself. `BootstrapRegistry` consumes the
parameterized seed once, mints exactly one thread token, and places it in
exactly one REGISTRY output with inline `RegistryDatumV1 { root =
root(empty) }`. There is no burn redeemer for the thread token.

The set key is the already-frozen 32-byte
`deriveAidAssetName(D.cesr_aid)`. Its value is the fixed V1 registered marker
`blake2b_256("cardano-keri/checkpoint/registered/v1")`. The value never
changes; only presence matters.

### Atomic Register shape

Register adds one input and one continuing output to #114's transaction:

```text
Tx Register:
  inputs:
    hash-proof token input (existing R5)
    registry_ref at REGISTRY, carrying thread token + old root
    fee/funding inputs as needed
  outputs:
    one ACTIVE checkpoint state output (existing R2)
    one REGISTRY successor, same thread token/value + new root
  checkpoint mint:
    exactly +1 deriveAidAssetName(D.cesr_aid)
  hash-proof mint:
    exactly -1 proof token
  checkpoint redeemers:
    mint  = Register { evidence, registry_ref, absence_proof }
    spend = RecordRegistration
```

The Register mint branch keeps R1–R8 and additionally:

1. resolves exactly the named `registry_ref` at the exact REGISTRY address;
2. requires its inline registry datum and the derived thread token at quantity
   one;
3. requires exactly one REGISTRY successor with byte-identical value and the
   same thread token, inline new-root datum, and no mint/burn of the thread;
4. computes
   `new = mpf.insert(from_root(old.root), aid_asset_name,
   registered_marker, absence_proof)` and requires
   `root(new) == successor.root`.

`mpf.insert` verifies both absence at the old root and inclusion at the new
root. An existing key therefore rejects forever. Two racing registrations
serialize on the registry UTxO: at most one consumes the current tip; after a
retry the loser faces a present key and fails.

The REGISTRY `RecordRegistration` spend branch accepts only when the
transaction mints exactly one non-registry asset at quantity `+1` under the
same checkpoint policy. That forces the paired Register mint handler to run;
the mint handler performs controller authorization, event binding, proof-token
consumption, and the MPFS transition. Conversely, Register requires the
registry input, so neither half can execute alone.

This coupling prevents reservation griefing: inserting a victim AID is only
possible in the same transaction that passes the victim's full #114 Register
authorization. The set is permissionless and has no owner key, delete,
update, close, or migration branch in V1.

### Contention boundary

The singleton registry serializes **registration only**, a one-time operation.
It never participates in Advance, Freeze, Convict, consumer reads, or
per-AID lookup. The #92 sovereignty invariant therefore stands: an unrelated
AID cannot contend for another AID's ongoing checkpoint UTxO. Global
registration contention is an explicit liveness residual of the logically
fixed MPFS absence gate: two people registering at once may need to retry, but
they cannot delay each other's already-registered identities or lifecycle
transactions.

### Registry-lineage adversarial acceptance

The live vectors MUST reject registry-token smuggling, a duplicate or missing
registry successor, root rollback, an absence proof checked against a stale
root, and bootstrap replay (the seed cannot be consumed a second time). The
final measurement matrix includes aggregate Register plus RecordRegistration
rows at MPFS depths 0, 8, and 16; any row below 25% memory or CPU headroom
stops the ticket and opens an epic Q-file.

## Freeze transaction

`SpendRedeemer.Freeze` gains `EnforcementEvidence`.

```text
Tx Freeze:
  input:  one ACTIVE checkpoint tip, inline V1(TIP), quantity-one AID token
  output: exactly one FROZEN output, same complete value, inline V1(TIP)
  mint:   nothing under the checkpoint policy
```

The branch resolves the named own input, requires exact ACTIVE, binds EE0–EE9,
requires `freeze_predicate(TIP, decoded) == FreezeValid`, and then enforces
the output shape above. There is no bounty and no controller transaction
signature requirement; the evidence signatures carry attribution.

`Advance` is amended to admit its named input from ACTIVE **or FROZEN** and
still creates exactly one ACTIVE successor. That is the entire thaw path.
Advance from TOMBSTONE, REGISTRY, or an unknown role fails before its predicate.

## Convict transaction

`SpendRedeemer.Convict` gains `EnforcementEvidence`.

```text
Tx Convict:
  input:  one ACTIVE or FROZEN checkpoint tip, inline V1(TIP), token + deposit
  output: exactly one TOMBSTONE output containing:
            value = checkpoint_min_ada + the same quantity-one AID token
            datum = TombstoneV1 {
              cesr_aid = TIP.cesr_aid,
              convicted_at_native_sn = TIP.native_sn,
              evidence_said = evidence.said
            }
  mint:   nothing under the checkpoint policy
```

No other native asset may remain in the tombstone. The input's remaining
lovelace and any other value leave the state output and are available for fees
and the prover's bounty/change. The validator does not prescribe a prover
address; ledger value conservation guarantees the residual cannot disappear
or remain trapped in the tombstone.

The branch binds EE0–EE9 and requires
`convict_predicate(TIP, decoded) == ConvictValid` before checking the exact
tombstone output. No controller signature over the Cardano spend is required.

## Tombstone terminality (F11)

Spend dispatch first classifies the named own input by exact role and datum:

- ACTIVE V1: Advance, Freeze, or Convict;
- FROZEN V1: Advance or Convict;
- REGISTRY `RegistryDatumV1`: RecordRegistration only;
- TOMBSTONE `TombstoneV1`: **no redeemer**;
- unknown role/datum pairing: fail.

This is stronger than leaving a `Tombstone` constructor out of a datum sum:
every current `SpendRedeemer` is tried against a real tombstone input in the
validator-level F11 family and fails. #117 must add Close beneath the same
pre-dispatch role gate; it cannot make TOMBSTONE spendable accidentally.

The append-only registry independently prevents a second Register mint for the
tombstoned AID. Terminality therefore holds both for the old token and for the
AID's mint history.

## Required adversarial vectors

Existing #106 F1/F1b/F2–F5/F7–F10/F12/F13 remain executable. This ticket adds
or promotes these transaction-boundary families:

| ID | Required boundary |
| --- | --- |
| W1 | any EE offset points at different bytes; count mismatch; truncated or negative span |
| W2 | `said` is wrong width or `off_d` does not name its E-code spelling |
| W3 | one valid witness receipt duplicated to fake `toad = 2` |
| W4 | same reveal and `n`/`nt`/`bt`, but different `kt`, is accepted as a conflict only when the tip controller threshold still attributes it |
| U1 | Register without registry input or with wrong thread token/address/datum |
| U2 | stale/wrong MPFS proof, existing-key insert, wrong new root, or changed registry value |
| U3 | RecordRegistration without the paired exact `+1` Register mint; Register without RecordRegistration |
| U4 | second Bootstrap, thread-token burn/mint, duplicate registry successor, registry delete/update attempt |
| U5 | two same-AID registrations from one root cannot both validate; post-conviction re-register rejects |
| R1 | role marker mutation, unknown staking credential, or wrong role/datum pairing |
| F11 | every spend redeemer against TOMBSTONE fails |
| F12-L | Freeze changes datum/value, omits token, mints/burns, or targets a non-FROZEN address |
| F13-L | Convict from wrong role, wrong tombstone record/value/address, missing token, or retained bounty |
| T1 | Advance from FROZEN succeeds only with the ordinary full Advance proof and returns ACTIVE; no standalone thaw exists |

All wire and schema verdicts are shared Haskell/Aiken vectors. Transaction
shape, exact address, terminality, and mint/spend coupling are Aiken
full-context tests because they are ledger-boundary properties.

## Measurement gate

Every final ACCEPT path is measured with the pinned Aiken toolchain against
14,000,000 memory / 10,000,000,000 CPU:

1. Freeze at `lag`, 2-key, and GLEIF 7-key shapes.
2. Convict from ACTIVE and FROZEN, including `fork_witnessed`.
3. Registry bootstrap.
4. Registration plus the registry spend, reported as the **sum of all script
   executions in the same transaction**, at 2-key, witnessed, and 7-key
   registration shapes, with MPFS absence proofs at depth 0, 8, and 16.

Each cell must retain at least 25.00% headroom on both axes. A miss is a hard
STOP: no weakened check, reduced signer fixture, or depth-0-only claim may be
substituted. The orchestrator opens an epic Q-file with raw numbers and the
smallest faithful remediation.

The report must distinguish typed-handler numbers from ledger `Data`
deserialization and must not call a summed estimate a live-node measurement.
#118 owns the final cross-path matrix; #44 owns devnet corroboration.

## Residuals

- Witness-line-up-only/pool-swap conviction remains fail-closed to Freeze;
  `prev_witnesses_digest` is the V2 hook.
- The registration-history UTxO is globally contended and can delay new
  registrations. It cannot delay an existing AID's Advance/Freeze/Convict.
- `evidence_said` is a signed event field, not a recomputed digest.
- Close/migration discovery semantics and deposit amount are #117.
- Proof production and registry-tip discovery are off-chain liveness work;
  the proof and root transition are verified on-chain.

## Acceptance criteria

- [ ] Freeze and Convict consume real #106 fixture evidence at the full
      transaction boundary; Haskell and Aiken agree on every wire/predicate
      verdict.
- [ ] Freeze→Advance round-trip returns to ACTIVE, with no other thaw path.
- [ ] A witnessed fork convicts from ACTIVE and FROZEN; controller-only or
      duplicate-receipt framing fails.
- [ ] A tombstone cannot be spent by any redeemer and holds the exact terminal
      record/token/min-ADA shape.
- [ ] Bootstrap creates one permanent registry thread; Register atomically
      inserts absence into the MPFS set; duplicate and post-conviction Register
      fail.
- [ ] Role addresses use the exact deterministic staking-script encoding above.
- [ ] SAID non-recomputation and its measurement rationale remain recorded.
- [ ] All new adversarial families pass and all live measurement cells retain
      ≥25% memory and CPU headroom.
- [ ] Register and Advance regressions remain green; Close remains fail-closed.

## Spec-checkpoint questions

The epic owner is asked to ratify:

1. **SAID:** no enforcement-path recomputation; signed `d` retained only as
   `TombstoneV1` audit evidence, with the measured cost rationale above.
2. **Unicity:** a one-shot bootstrapped, append-only MPFS registration set in a
   singleton REGISTRY UTxO, atomically paired with Register and never consulted
   on steady per-AID paths.
3. **Roles:** ACTIVE = no stake credential; FROZEN/TOMBSTONE/REGISTRY =
   deterministic domain-separated staking script markers derived from the
   checkpoint hash.
4. **Schema corrections:** distinct witness-receipt indices and restoration of
   `kt` as a Convict conflict axis before live wiring.
