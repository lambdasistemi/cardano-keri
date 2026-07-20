# Spec: enforcement wiring — freeze, sovereign convict, and lazy permanence (#116)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/116
Epic: https://github.com/lambdasistemi/cardano-keri/issues/24

Registration and advance cover the honest checkpoint lifecycle. This ticket
makes the same validator react to evidence: a witnessed later event can freeze
a stale checkpoint, and a witnessed conflicting event can sovereignly
tombstone it without touching shared state. The full registration deposit then
backs a transferable bounty right. Registration only reference-reads a shared
conviction list; the list is written lazily when a right holder cashes out and
makes the conviction permanent.

Ratified inputs (do not reopen without an epic Q-file):
`specs/106-enforcement/spec.md` (pure enforcement predicates and proof
fixtures), `specs/114-registration/spec.md` (live Register path and gate-room),
`specs/115-advance/spec.md` (live Advance path and O1 full-byte signatures),
and `specs/92-checkpoint-contention/spec.md` (sovereign per-AID state and
status-by-address). The 2026-07-20 ruling in
`/tmp/keri-24/unicity-redesign.md` supersedes only A-007 QB's
append-on-registration registry; the other A-007 rulings remain binding.

!!! danger "This completes pre-deployment validator surface"
    The role addresses, conviction-list bootstrap, Freeze path, sovereign
    Convict path, bounty-right custody, Finalize/Redeem path, and tombstone
    dispatch rule all affect the applied checkpoint script hash. They must be
    ratified before reimplementation. No deployed checkpoint exists, so this
    remains a safe place to amend the V1 script in place.

---

## Technical contract

### Decisions at a glance

1. **Do not recompute the event SAID on Freeze or Convict.** O1 signatures
   already cover the complete `event_bytes`. All predicate-relevant fields are
   slice-bound to those signed bytes. The `d` field is retained as a signed
   audit label, not treated as a second authorization root.
2. **Separate sovereign containment from lazy permanence.** Register
   reference-reads an append-only MPFS conviction list and proves the AID is
   absent; it never consumes or updates the list. Convict immediately
   tombstones only the named per-AID checkpoint and converts its whole deposit
   into a uniquely named bearer bounty right backed by a claim UTxO; it also
   performs no shared write. The first cash-out inserts the AID into the
   conviction list, while later rights redeem against the already-present
   marker. Duplicate fresh mint and pre-finalization re-registration are an
   explicit, deposit-backed residual rather than a claimed mint-once property.
3. **Encode lifecycle roles on the staking-credential axis.** ACTIVE keeps the
   already-ratified no-stake address. FROZEN, TOMBSTONE, and the internal
   REGISTRY state retain their deterministic staking **script** credentials;
   the proposed BOUNTY claim extends the same derivation with a new tag. The
   payment credential remains the checkpoint script hash for every role.

The replacement unicity mechanics, bounty custody, cash-out modes, race
semantics, and `D_reg` security role are new spec-checkpoint material. SAID,
existing role derivation, Freeze/thaw, and the two #106 corrections are not
reopened.

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

### Unicity redesign record (2026-07-20)

The epic owner rejected A-007 QB after the delivered implementation exposed
its ledger-level throughput consequence: consuming one singleton MPFS UTxO on
every Register serializes all registrations globally, roughly one AID per
block, and creates a griefing surface. This spec therefore supersedes the
append-on-registration design. The shared MPFS now stores only permanent
convictions and is read-only on Register, untouched on Convict, and written at
most once per identity during economically motivated cash-out.

## Problem

The draft branch at `78009a1` wires Freeze and Convict, but its unicity path
consumes and advances one singleton MPFS root on every Register. That turns a
permissionless admission path into a global serialization point and is
rejected. The redesign must preserve the already-proved enforcement binding,
roles, and Freeze/thaw behavior while replacing S3/S5 with contention-free
registration, sovereign conviction, deposit-backed rights, and lazy permanent
finalization.

## Scope

**In scope**

1. A live wire-evidence layer that slice-binds KERI `rot` fields to the exact
   bytes signed by controllers and witnesses, then invokes the #106 predicates.
2. ACTIVE → FROZEN, FROZEN → ACTIVE by ordinary Advance, and sovereign
   ACTIVE|FROZEN → TOMBSTONE transaction paths.
3. Tombstone terminality plus seizure of the whole registration deposit into a
   bearer bounty-right claim, with no fee haircut.
4. A one-shot-bootstrapped append-only MPFS conviction list: read-only absence
   proof on Register, no shared touch on Convict, first-redemption insertion,
   and already-finalized redemption without another write.
5. Unique repeatable bounty rights, claim custody, one-time burn, multi-right
   cash-out, and the Register/Convict/Finalize race matrix.
6. Deterministic full-address role encoding.
7. Haskell/Aiken verdict parity, transaction-boundary adversarial vectors, and
   full-path execution-unit measurements.

**Out of scope**

- Close, migration, and consumer lookup (#117). `D_reg` is pulled forward from
  #117 as this design's primary deterrence and bounty parameter; production
  calibration remains a spec-checkpoint decision rather than an implicit
  constant.
- The full cross-path adversarial matrix (#118) and devnet cast (#44).
- A witness-delta/pool-swap-only conviction. It remains fail-closed to Freeze;
  `prev_witnesses_digest` is the named V2 hook.
- Replacing the sovereign per-AID checkpoint with an MPFS current-state store.
  The MPFS structure here remembers permanent convictions only; Advance,
  Freeze, and Convict remain per-AID and contention-free across unrelated
  identities.
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
   records the evidence, and backs a unique bearer right with **all** lovelace
   above the checkpoint min-ADA floor. Fees and claim min-ADA are funded
   separately; the seized deposit cannot be burned, retained, or haircut.
6. Status is derived from the exact full address, not from a status field in
   `CheckpointDatumV1`.
7. Close remains fail-closed. Tombstone is excluded before any current or
   future checkpoint-state redeemer dispatch.
8. Register proves absence against a named current conviction-list reference
   input but does not write it. Multiple registrations may reference-read the
   same root concurrently.
9. The first valid bounty cash-out for an absent AID inserts one permanent
   conviction marker. Later rights prove membership and redeem without another
   root update. There is no delete path.
10. Until that first finalization lands, duplicate fresh mint and
    re-registration are permitted. Every later evidenced fork remains
    sovereignly containable and seizes another full deposit.

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

The ratified tags remain FROZEN `0x00`, TOMBSTONE `0x01`, and REGISTRY
`0x02`. This redesign proposes BOUNTY `0x03` for deposit-claim custody; adding
that tag does not change the domain or any existing role encoding.

| Role | Full address |
| --- | --- |
| ACTIVE | `Address(Script(h), None)` |
| FROZEN | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x00)))))` |
| TOMBSTONE | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x01)))))` |
| REGISTRY | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x02)))))` |
| BOUNTY | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x03)))))` |

The markers are deterministic protocol labels, not caller parameters and not
verification keys. They grant no spending authority: every output still has
`Script(h)` as payment credential and therefore executes the combined
validator. Including `h` in the derivation prevents role-address aliasing
across validator versions. ACTIVE stays byte-for-byte compatible with #114 and
#115.

Every branch compares the **whole address**. An unknown staking credential
fails closed even when its payment credential is `Script(h)`.

## Conviction-list unicity and lazy permanence

### State, labels, and bootstrap

The fifth applied parameter remains a one-shot deployment seed, renamed
`conviction_seed : OutputReference`. The shared state stores **only permanent
convictions**:

```text
ConvictionListDatumV1 { root : ByteArray }

BountyClaimDatumV1 {
  aid_asset_name   : ByteArray,
  right_asset_name : ByteArray,
  seized_lovelace  : Int
}
```

The thread token and fixed set value are domain-separated:

```text
conviction_thread_name(seed) = blake2b_256(
  "cardano-keri/checkpoint/conviction-thread/v1"
  || cbor.serialise(seed)
)

convicted_marker = blake2b_256(
  "cardano-keri/checkpoint/convicted/v1"
)
```

`BootstrapConvictionList` consumes the parameterized seed once, mints exactly
one thread token under the checkpoint policy, and cages it in exactly one
REGISTRY output with inline `ConvictionListDatumV1 { root = root(empty) }`.
The thread has no burn, split, merge, close, or migration branch in V1. The set
key is the frozen 32-byte `deriveAidAssetName(cesr_aid)`; presence means
permanent conviction, not historical registration.

### Register is a reference-read

Register keeps #114 R1–R8 and adds a named **reference input**, never a normal
input or continuing output:

```text
Tx Register:
  inputs:
    hash-proof token input (existing R5)
    fee/funding inputs as needed
  reference_inputs:
    conviction_ref at REGISTRY, carrying thread token + current root
  outputs:
    one ACTIVE checkpoint state output (existing R2)
  checkpoint mint:
    exactly +1 deriveAidAssetName(D.cesr_aid)
  hash-proof mint:
    exactly -1 proof token
  checkpoint redeemer:
    Register { evidence, conviction_ref, absence_proof }
```

The mint branch:

1. resolves exactly the named `conviction_ref` from `reference_inputs` at the
   exact REGISTRY address, with inline `ConvictionListDatumV1` and the derived
   thread token at quantity one;
2. verifies `absence_proof` for the AID key against that datum's exact root;
3. requires no thread-token mint/burn and no REGISTRY spend or successor;
4. runs unchanged R1–R8 controller authorization, event binding, hash-proof
   consumption, output, and deposit checks.

An old root cannot be named after it has been consumed: its output reference is
no longer in the UTxO set. Multiple Register transactions may, however,
reference-read the same current root concurrently, including two registrations
of the same absent AID. This is intentional. An AID already present in the
conviction list fails its absence proof forever.

### Bearer bounty right and deposit custody

Each sovereign Convict names the checkpoint input it consumes and derives a
fresh right name:

```text
bounty_right_name(checkpoint_ref, aid_asset_name) = blake2b_256(
  "cardano-keri/checkpoint/bounty-right/v1"
  || cbor.serialise(checkpoint_ref)
  || aid_asset_name
)
```

Because an output reference is consumed at most once, repeated conviction
cycles for one AID produce distinct rights. The combined checkpoint policy
mints exactly one such token in the Convict transaction and requires the token
to leave checkpoint-script custody so its holder may transfer it like any
bearer asset.

The deposit is not left on the terminal tombstone. Convict creates exactly one
BOUNTY claim output with inline `BountyClaimDatumV1` and no unrelated native
assets. Let:

```text
seized_lovelace = checkpoint_input.lovelace - checkpoint_min_ada
```

The claim output contains exactly `claim_min_ada + seized_lovelace`, while the
tombstone contains exactly `checkpoint_min_ada` plus the AID token. The claim's
min-ADA and all transaction fees require separate funding. Thus every lovelace
above the checkpoint floor—including any amount above the minimum `D_reg`—is
backed for the right holder; Convict cannot fund fees from it or apply a
haircut. The checkpoint input must already satisfy
`seized_lovelace >= D_reg`.

This BOUNTY-role claim is the checkpoint proposal for the soundness pass. It
preserves F11 because TOMBSTONE remains unspendable. The epic checkpoint may
replace the custody shape if it supplies an equally exact whole-deposit and
one-time-redemption proof.

### Finalize first; redeem later rights

A cash-out consumes one or more BOUNTY claims for exactly one AID, consumes and
burns each matching bearer right at quantity `-1`, and releases each complete
`seized_lovelace` amount to the exact address of the input that carried that
right. Dedicated payout accounting must prevent fees from reducing the seized
amount; the precise ledger-level sum check is part of the checkpoint ruling.
There is no claim successor, so the claim plus right burn is one-time.

Cash-out has two modes:

1. **Finalize absent.** If the AID is absent, the transaction consumes the
   current REGISTRY thread UTxO, verifies the absence proof, creates exactly one
   byte-value-preserving REGISTRY successor whose root inserts
   `(aid_asset_name, convicted_marker)`, and then releases the claims. This is
   the only V1 root-write path. Payout without that insertion fails.
2. **Redeem present.** If an earlier cash-out already inserted the AID, the
   transaction reference-reads the current REGISTRY UTxO, verifies inclusion,
   writes no successor, burns the remaining matching rights, and releases their
   claims. This avoids a second shared write for the same identity.

The registry spend and BOUNTY spend handlers, plus the checkpoint-policy
mint/burn handler, must be welded: no claim may leave script custody unless the
same transaction proves one of the two modes, and no absent-mode root update
may occur without at least one matching right burn and claim payout. A holder
may aggregate multiple rights for the same AID in one cash-out. Rights for
different AIDs use separate proofs and transactions in V1.

Therefore “get paid if and only if permanent” means: an absent AID is made
permanent in the payout transaction; a present AID is proved already permanent
in the payout transaction. No third claim-spend mode exists.

### Race semantics

The required outcomes are explicit:

- Register vs Register: both reference-read; unrelated and same-AID absent
  registrations may validate concurrently. There is no shared write.
- Convict vs Register: Convict touches only its named per-AID checkpoint and
  claim outputs. A pre-finalization re-registration may land; a later fork is
  independently convictable and creates another backed right.
- Register vs first Finalize: if Finalize consumes the referenced root first,
  Register's old reference disappears and it must retry against the convicted
  root, where absence fails. If Register validates first, or precedes Finalize
  in ledger order, its ACTIVE output may exist during the documented
  resurrection window; Finalize blocks registrations after that point but does
  not retroactively spend that output.
- Finalize vs Finalize: two absent-mode cash-outs serialize on the thread. One
  inserts; the loser retries in present mode and can still redeem without
  another root write.
- Redeem-present transactions are reference-read only and may run concurrently.

The epic-owner soundness pass must confirm these outcomes against actual
CIP-31/reference-input and MPF proof semantics before implementation dispatch.

### Contention boundary

The singleton list is never consumed by Register, Advance, Freeze, Convict, or
present-mode redemption. It is consumed only by the first cash-out for an AID,
at most once per identity and at the bounty holder's timing. Those rare
finalizations serialize, but registration throughput and sovereign containment
do not. V1 therefore keeps one unsharded list unless the checkpoint answer
finds a ledger or proof reason to shard it.

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
  outputs:
          exactly one TOMBSTONE output containing:
            value = checkpoint_min_ada + the same quantity-one AID token
            datum = TombstoneV1 {
              cesr_aid = TIP.cesr_aid,
              convicted_at_native_sn = TIP.native_sn,
              evidence_said = evidence.said
            }
          exactly one BOUNTY claim output containing:
            value = claim_min_ada + all checkpoint lovelace above
                    checkpoint_min_ada
            datum = BountyClaimDatumV1 {
              aid_asset_name,
              right_asset_name,
              seized_lovelace
            }
  checkpoint mint:
          exactly +1 bounty_right_name(checkpoint_ref, aid_asset_name)
          and no AID-token/thread mint or burn
  conviction list: no input, reference input, output, or root proof
```

No unrelated native asset may remain in either script output. The minted right
must be paid outside checkpoint-script custody to the transaction submitter's
chosen bearer address. The tombstone and claim equations account for the whole
checkpoint input: its floor remains with the tombstone, while every excess
lovelace backs the right. Claim min-ADA, fees, and ordinary change come from
separate funding inputs.

The branch binds EE0–EE9 and requires
`convict_predicate(TIP, decoded) == ConvictValid` before checking the exact
tombstone, claim, right-name, mint-map, and custody shapes. It MUST NOT inspect,
spend, reference, or update the conviction list. No controller signature over
the Cardano spend is required.

## Tombstone terminality (F11)

Spend dispatch first classifies the named own input by exact role and datum:

- ACTIVE V1: Advance, Freeze, or Convict;
- FROZEN V1: Advance or Convict;
- REGISTRY `ConvictionListDatumV1`: FinalizeConviction only;
- BOUNTY `BountyClaimDatumV1`: RedeemBounty only;
- TOMBSTONE `TombstoneV1`: **no redeemer**;
- unknown role/datum pairing: fail.

This is stronger than leaving a `Tombstone` constructor out of a datum sum:
every current `SpendRedeemer` is tried against a real tombstone input in the
validator-level F11 family and fails. #117 must add Close beneath the same
pre-dispatch role gate; it cannot make TOMBSTONE spendable accidentally.

The tombstoned token is terminal immediately. Mint-history permanence is
separate: until a right is redeemed, another Register may create another token
for the same AID; after first-redemption insertion, the reference-read absence
gate rejects all later registration. Any checkpoint created during the window
is still subject to sovereign Freeze/Convict and can lose another full deposit.

## Required adversarial vectors

Existing #106 F1/F1b/F2–F5/F7–F10/F12/F13 remain executable. This ticket adds
or promotes these transaction-boundary families:

| ID | Required boundary |
| --- | --- |
| W1 | any EE offset points at different bytes; count mismatch; truncated or negative span |
| W2 | `said` is wrong width or `off_d` does not name its E-code spelling |
| W3 | one valid witness receipt duplicated to fake `toad = 2` |
| W4 | same reveal and `n`/`nt`/`bt`, but different `kt`, is accepted as a conflict only when the tip controller threshold still attributes it |
| U1 | Register without the named REGISTRY reference input, or with wrong thread token/address/datum/root |
| U2 | stale/wrong absence proof or present AID; any Register attempt to spend the list, create a successor, or mint/burn the thread |
| U3 | two unrelated or same-AID absent registrations reference-read one root concurrently without a shared spend |
| U4 | second Bootstrap, thread-token escape/burn/mint, split list, non-empty bootstrap root, or wrong seed |
| B1 | Convict touches the conviction list, omits/duplicates the unique right, misnames it, leaves it in script custody, or mints/burns an AID/thread token |
| B2 | claim datum/right/AID mismatch, claim value below `claim_min_ada + seized_lovelace`, fee haircut, retained deposit, unrelated claim asset, or missing separate funding |
| P1 | absent-AID claim payout without consuming the current thread and inserting the exact convicted marker, or root update without a matching claim + right burn |
| P2 | already-present redemption without a current REGISTRY reference + inclusion proof, with a REGISTRY successor, or with a second root write |
| P3 | right/claim replay, burn count mismatch, duplicate claim, mixed-AID aggregation, payout to an address other than the right-bearing input, or incomplete seized amount |
| X1 | Register-before-Finalize window accepts; Finalize-before-Register invalidates the old reference and retry rejects on presence |
| X2 | two first Finalizers: one inserts; the loser can retry present-mode without losing its claim; present-mode redemptions coexist |
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
2. Sovereign Convict from ACTIVE and FROZEN, including `fork_witnessed`, the
   unique right mint, and the fully backed claim output.
3. Conviction-list bootstrap.
4. Reference-read Register at 2-key, witnessed, and 7-key registration shapes,
   with MPFS absence proofs at depths 0, 8, and 16. There is no registry spend
   execution to add.
5. First Finalize at proof depths 0, 8, and 16, for one right and a faithful
   multi-right same-AID aggregate.
6. Present-mode Redeem at inclusion-proof depths 0, 8, and 16, likewise covering
   one and multiple same-AID rights without a root write.

Each cell must retain at least 25.00% headroom on both axes. A miss is a hard
STOP: no weakened check, reduced signer fixture, or depth-0-only claim may be
substituted. The orchestrator opens an epic Q-file with raw numbers and the
smallest faithful remediation.

Every transaction row reports the sum of all script executions in that
transaction (checkpoint spend, checkpoint-policy mint/burn, REGISTRY/BOUNTY
spends, and any other live handler). The report must distinguish typed-handler
numbers from ledger `Data` deserialization and must not call a summed estimate
a live-node measurement. The old append-on-registration rows are retained only
as superseded history. #118 owns the final cross-path matrix; #44 owns devnet
corroboration.

## Residuals

- Witness-line-up-only/pool-swap conviction remains fail-closed to Freeze;
  `prev_witnesses_digest` is the V2 hook.
- Duplicate fresh mint and re-registration after Convict but before first
  Finalize are explicitly allowed. They preserve a stale-read/confusion window;
  cryptographic fork evidence still contains each offending checkpoint and
  every repeated cycle loses another full deposit.
- A right holder can delay permanence by declining to cash out. The system owes
  no payout until the right is redeemed, the offending checkpoint is already
  tombstoned, and the locked claim remains fully backed.
- First Finalize transactions for different AIDs share one list and may need to
  retry. Register, Advance, Freeze, Convict, and present-mode Redeem do not share
  that write bottleneck.
- `D_reg` is the primary deterrence/reward knob. Its production value and the
  claimed bleed/milk/finalize equilibrium require epic-level ratification in
  this ticket, not silent deferral to #117.
- `evidence_said` is a signed event field, not a recomputed digest.
- Close/migration discovery semantics remain #117.
- Proof production, current-tip discovery, and right/claim discovery are
  off-chain liveness work; every referenced root, proof, transition, burn, and
  payout weld is verified on-chain.

## Acceptance criteria

- [ ] Freeze and Convict consume real #106 fixture evidence at the full
      transaction boundary; Haskell and Aiken agree on every wire/predicate
      verdict.
- [ ] Freeze→Advance round-trip returns to ACTIVE, with no other thaw path.
- [ ] A witnessed fork convicts from ACTIVE and FROZEN; controller-only or
      duplicate-receipt framing fails.
- [ ] A tombstone cannot be spent by any redeemer and holds the exact terminal
      record/token/min-ADA shape; Convict creates a unique bearer right and a
      separate claim backing the whole seized deposit with no fee haircut.
- [ ] Bootstrap creates one permanent conviction-list thread. Register only
      reference-reads it and proves absence; concurrent absent registrations do
      not consume shared state.
- [ ] First cash-out burns matching rights, pays every complete claim, and
      inserts the AID exactly once; later rights redeem on inclusion without
      another root write or replay.
- [ ] The full Register/Convict/Finalize race matrix has the outcomes specified
      above; pre-finalization re-registration accepts and post-finalization
      registration rejects.
- [ ] Role addresses use the exact deterministic staking-script encoding above.
- [ ] SAID non-recomputation and its measurement rationale remain recorded.
- [ ] All new adversarial families pass and all live measurement cells retain
      ≥25% memory and CPU headroom.
- [ ] Register and Advance regressions remain green; Close remains fail-closed.

## Spec-checkpoint questions

The epic owner is asked to fold the parallel Cardano-mechanics soundness pass
into a ruling on these replacement questions:

1. **Mutable-root reference read and races.** Confirm that a named CIP-31
   reference input carrying the singleton thread makes an MPF absence proof
   current under ledger semantics, and ratify the Register-before-Finalize,
   Finalize-before-Register, and two-Finalizer outcomes stated above.
2. **Bearer right and custody.** Ratify or correct the proposed unique right
   name, mint under the combined checkpoint policy, BOUNTY role `0x03`, separate
   claim UTxO, whole-surplus seizure equation, and payout-to-right-input-address
   accounting. Any correction must preserve repeatability, transferability,
   exact full-deposit backing, fee separation, and one-time redemption.
3. **Finalize/Redeem weld.** Ratify absent-mode consume+insert and present-mode
   reference-read+inclusion, including multi-right same-AID aggregation,
   rights held by different bearers, retry after a competing insertion, exact
   burns, and the rule that an absent claim cannot pay without permanence.
4. **Bootstrap and topology.** Ratify the renamed conviction domains, one-shot
   thread, unchanged REGISTRY role encoding, no deletion, and a single
   unsharded list whose only write is first cash-out per identity.
5. **Economics.** Pull O3 forward: state the V1 `D_reg` requirement or
   calibration rule needed for the claimed bleed/milk/finalize equilibrium,
   and identify any perverse incentive the implementation vectors must exclude.

The following A-007 decisions remain ratified and are not reopened: SAID
non-recomputation; ACTIVE/FROZEN/TOMBSTONE/REGISTRY role derivation; Freeze and
ordinary-Advance thaw; distinct witness-index counting; and `kt` as a Convict
conflict axis.
