# Spec: enforcement wiring — conviction as penalty and record (#116)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/116
Epic: https://github.com/lambdasistemi/cardano-keri/issues/24

Registration and Advance cover the honest checkpoint lifecycle. This ticket
wires the same validator to react to signed KERI evidence: a witnessed later
event can freeze a stale checkpoint, and an irreconcilable witnessed fork can
sovereignly tombstone that checkpoint and release its locked bond to the
convictor. The tombstone is a permanent record for that token, not a Cardano
decision that the KERI identity is dead.

Ratified inputs (do not reopen without an epic Q-file):
`specs/106-enforcement/spec.md` (pure enforcement predicates and proof
fixtures), `specs/114-registration/spec.md` (live Register path),
`specs/115-advance/spec.md` (live Advance path and O1 full-byte signatures),
and `specs/92-checkpoint-contention/spec.md` (sovereign per-AID state and
status-by-address). A-010 and
`/tmp/keri-24/conviction-final-design.md` supersede A-007/A-009's complete
unicity, bounty-right, and finalization design.

!!! danger "This completes the pre-deployment validator surface"
    Register, Freeze, Advance-from-FROZEN, Convict, role addresses, and the
    dispatch rule all affect the applied checkpoint script hash. No deployed
    checkpoint exists, so V1 can still delete the rejected unicity surface and
    fix the bond parameter before deployment.

---

## Technical contract

### Decisions at a glance

1. **Cardano mirrors KERI.** Conviction is a penalty and a queryable record,
   never permanent execution of an AID. The convicted checkpoint token is
   terminal, but the same KERI AID may register again.
2. **No unicity apparatus exists.** Register has no shared state, reference
   input, MPFS absence proof, thread token, or registry successor. Convict has
   no shared write, right token, claim UTxO, seal, Finalize, or Redeem path.
3. **Every registration locks the deployment-fixed bond.** `d_reg` is one
   validator parameter selected at contract deployment, not a value chosen by
   each controller. Fresh and repeated Register calls both require the same
   fixed minimum. V1 also rejects an applied parameter below the mechanical
   floor of 5,000,000 lovelace.
4. **Conviction stays sovereign and immediate.** The existing #106 predicate
   gates ACTIVE|FROZEN → TOMBSTONE. The tombstone keeps only its min-ADA and
   quantity-one checkpoint token; all locked surplus leaves checkpoint-script
   custody for the convict transaction's payout/change.
5. **Do not recompute the event SAID.** O1 signatures already cover the full
   `event_bytes`, and EE0–EE9 bind every predicate-relevant field. The signed
   `d` value is an audit locator, not a second authorization root.
6. **Lifecycle role is the full address.** ACTIVE remains bare. FROZEN `0x00`
   and TOMBSTONE `0x01` retain the ratified staking-script derivation. The
   rejected REGISTRY `0x02` and proposed BOUNTY `0x03` roles do not exist.

### A-010 simplification record (2026-07-20)

The delivered S3 append-on-Register MPFS singleton serialized registrations
globally. The later reference-read/finalization redesign avoided that hot-path
write but imposed a worse semantic invariant: Cardano would permanently bar an
identity that KERI may still carry after superseding recovery, resolved witness
collusion, or legitimate continuation.

A-010 reverses that invariant. The entire S3 unicity surface is deleted rather
than replaced. Conviction means “this checkpoint fork was convicted here”; it
does not mean “this AID can never appear again.” Freeze/thaw, the #106 `kt`
conflict correction, distinct witness-index counting, and SAID
non-recomputation remain unchanged.

The epic owner owns the corresponding invariant unwind in `docs/` and issues
#106/#92/#91. This ticket changes only #116's specification, implementation,
tests, and measurements.

## Problem

The branch at `e409c38` contains the accepted S1–S6 history, including S3's
registration registry. That registry both consumes one shared UTxO per
registration and claims a permanent Cardano-side unicity decision. Both are
rejected. The final V1 must retain sovereign per-token enforcement while
removing every shared-list dependency and making the fixed bond mandatory on
every fresh or repeated registration.

## Scope

**In scope**

1. EE0–EE9 binding from signed KERI wire evidence to the #106 predicates.
2. ACTIVE → FROZEN, FROZEN → ACTIVE by ordinary Advance, and sovereign
   ACTIVE|FROZEN → TOMBSTONE transaction paths.
3. Exact ACTIVE/FROZEN/TOMBSTONE role-address classification and fail-closed
   tombstone dispatch.
4. Deletion of the registry bootstrap, thread token, MPFS unicity model,
   Register/RecordRegistration coupling, registry role, vectors, and build
   wiring.
5. One deployment-fixed `d_reg` minimum on Register and re-register, including
   the mechanical parameter floor and underfunded-output negatives.
6. Haskell/Aiken evidence parity, full-context transaction adversarial tests,
   and replacement live-path execution-unit measurements.

**Out of scope**

- The cross-issue/docs invariant unwind named by A-010; the epic owner owns it.
- Close, migration, and consumer lookup (#117), including honest recovery of
  the refundable bond. This ticket fixes the parameter and enforcement shape;
  deployment selects the concrete security value.
- The full cross-path adversarial matrix (#118) and devnet cast (#44).
- Witness-delta/pool-swap-only conviction. It remains fail-closed to Freeze;
  `prev_witnesses_digest` is the named V2 hook.
- Any global list, mint-once guarantee, batcher, sequencer, finalizer, reward
  claim, or off-chain ordering service.
- Any `said_blank` reconstruction or BLAKE3 over enforcement event bytes.

## Inherited invariants

1. Controller and witness signatures verify over the complete KERI event
   serialization, never over its SAID (O1).
2. A witnessed conviction needs both the tip controller threshold and at least
   the tip `toad` in distinct valid witness receipts. A witnessless
   `toad = 0` AID remains the explicitly weaker controller-only tier.
3. Convict conflict axes include `kt`, `n`, `nt`, and `bt`; duplicate receipt
   indices never inflate a quorum.
4. Freeze needs a strictly later event whose revealed keys satisfy the tip's
   committed `(next_keys, next_threshold)` and whose distinct receipts meet
   the tip `toad`.
5. Freeze preserves the complete state value and byte-identical V1 datum.
   Thaw is an ordinary Advance to ACTIVE; no separate unfreeze redeemer exists.
6. Convict leaves the quantity-one checkpoint token and exact evidence record
   in a terminal tombstone, while no registration bond remains there.
7. Status is derived from the exact full address, not a datum field.
8. Close stays fail-closed. Tombstone is excluded before every current or
   future checkpoint-state redeemer dispatch.
9. Tombstone terminality applies to that token only. It never bars a later
   Register for the same AID.

## SAID decision — no enforcement-path recomputation

### Decision

Freeze and Convict MUST NOT recompute `blake3(said_blank)` and MUST NOT carry
`said_blank`. The validator slice-checks the fields used by the predicate, and
every authority or witness signature verifies over the complete
`event_bytes`. Changing `i`, `s`, `k`, `kt`, `n`, `nt`, `bt`, or `d` changes
the signature target. A party able to replace the required signatures already
has the relevant threshold, so a second SAID hash adds cost without narrowing
authority.

`TombstoneV1.evidence_said` is retained. It is the E-code-stripped 32-byte
value slice-bound to the signed event's `d` field: an audit locator, not a
validator-recomputed claim that `d == blake3(blank(event))`.

### Measurement evidence

Mainnet per-transaction limits are 14,000,000 memory and 10,000,000,000 CPU.

- The #106 spike priced a 1024-byte single-chunk SAID BLAKE3 recomputation at
  about 10.0M memory, 71.7% of the transaction budget. The full #114 1024-byte
  hash-proof cell measured 10,241,066 memory (73.15%) and 5,510,621,625 CPU
  (55.11%), including its surrounding handler.
- A fresh binding-predicate measurement at `616c630` measured
  `freeze_honest7` at 2,751,945 memory and 1,551,883,756 CPU, leaving 80.34%
  and 84.48% headroom respectively. `fork_witnessed_convicts` used 108,885
  memory and 146,649,513 CPU.
- Adding the roughly 10.0M SAID cost to the older full Freeze cell crosses the
  memory limit before the transaction shell. Omitting the redundant hash
  preserves room for live address, datum, token, and output checks.

The final Register/Freeze/Convict paths are remeasured after unicity deletion.
The comparison decides SAID non-recomputation; it does not waive the standing
25% headroom gate.

### F6 disposition

#106 F6's proposed `said_blank` reconstruction is superseded for this V1 wire
contract. Its security intent is covered by executable boundaries:

- mutating any signed event field without replacing its threshold signatures
  and receipts rejects; and
- pointing `off_d` elsewhere or supplying a non-32-byte `said` rejects.

## Live enforcement evidence

The decoded #106 `EventEvidence` remains internal to the pure predicates. The
live redeemer carries signed bytes plus positions and decoded candidates:

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
  toad           : Int
  ctrl_sigs      : List<(Int, ByteArray)>
  wit_sigs       : List<(Int, ByteArray)>
}
```

Offsets locate content; they never define it. Binding precedes either pure
predicate:

| Check | Signed event slice |
| --- | --- |
| EE0 | `1 <= length(event_bytes) <= 1024` |
| EE1 | `off_t` equals `"rot"` |
| EE2 | `off_i` equals `qb64_aid(TIP.cesr_aid)` |
| EE3 | `off_s` equals `respell_hex(native_sn)` |
| EE4 | `said` is 32 bytes and `off_d` equals `qb64_aid(said)` |
| EE5 | `off_k` and slices equal `qb64_verkey(revealed_keys)` positionally |
| EE6 | `off_kt` equals `respell_threshold(cur_threshold)` |
| EE7 | `off_n` and slices equal `qb64_aid(next_keys)` positionally |
| EE8 | `off_nt` equals `respell_threshold(next_threshold)` |
| EE9 | `off_bt` equals `respell_hex(toad)` |

Only after EE0–EE9 pass is decoded evidence supplied to `freeze_predicate` or
`convict_predicate`. `event_bytes` is every Ed25519 verification target.
KERI `br`/`ba` are not decoded; a witness-line-up-only fork stays the named V2
residual.

### Pre-wiring schema corrections

The accepted S2 corrections remain load-bearing:

1. witness quorum counts distinct verifying witness indices; and
2. Convict conflict axes include `kt` as well as `n`, `nt`, and `bt`.

Both remain shared Haskell/Aiken vector verdicts. This ticket does not edit
#106's historical specification.

## Address roles

Let `h` be the applied checkpoint validator hash and token policy id:

```text
role_hash(h, tag) = blake2b_224(
  "cardano-keri/checkpoint/role/v1" || h || tag
)
```

| Role | Full address |
| --- | --- |
| ACTIVE | `Address(Script(h), None)` |
| FROZEN | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x00)))))` |
| TOMBSTONE | `Address(Script(h), Some(Inline(Script(role_hash(h, 0x01)))))` |

The payment credential is always `Script(h)`; staking credentials are status
markers, never authority. The retained domain and tag bytes are unchanged.
REGISTRY `0x02` and BOUNTY `0x03` are removed pre-deployment. An unknown staking
credential or wrong role/datum pairing fails closed.

## Registration and fixed bond

The applied validator has one `d_reg : Int` supplied at contract deployment.
It is absent from every redeemer and cannot vary by controller or transaction.
The rejected `registry_seed` applied parameter and all Register proof/reference
fields are removed:

```text
Tx Register / re-register:
  inputs:  hash-proof token input plus ordinary funding inputs
  outputs: exactly one ACTIVE V1 checkpoint output
  checkpoint mint: exactly +1 deriveAidAssetName(D.cesr_aid)
  hash-proof mint: exactly -1 proof_token_name(event_bytes, cesr_aid)
  checkpoint redeemer: Register { evidence }
  shared state: none
```

The branch keeps #114 R1–R8. In particular, the ACTIVE output must hold at
least:

```text
checkpoint_min_ada + d_reg
```

`d_reg` is a fixed minimum, not an exact-output cap: any extra lovelace is also
inside checkpoint custody and leaves that custody on Convict. Fresh and repeat
registration execute the identical branch, so a repeated registration cannot
post a smaller bond.

V1 additionally requires the applied parameter itself to satisfy:

```text
d_reg >= 5_000_000 lovelace
```

The guard is applied before both mint and spend dispatch, so a mechanically
invalid script application cannot Register, Advance, Freeze, Convict, or use a
future Close branch selectively.

The floor predicate and its `5_000_000`/`4_999_999` boundary values are shared
Haskell/Aiken registration-model outputs; the combined validator reuses that
predicate rather than defining a second transaction-only constant.

The 5,000,000-lovelace value is only a mechanical hard floor. The expected
fixture and measurement value is 1,000 ADA (`1_000_000_000` lovelace), while
the operator chooses the deployed security magnitude pre-mainnet. Neither
value is a controller choice or a compiled replacement for the parameter.

Register deliberately does not inspect existing ACTIVE or TOMBSTONE outputs.
Duplicate active mint and post-conviction re-registration are allowed.

## Freeze transaction

```text
Tx Freeze:
  input:  one ACTIVE V1 checkpoint, quantity-one AID token and bond
  output: exactly one FROZEN output, byte-identical datum and complete value
  mint:   nothing under the checkpoint policy
```

The branch binds EE0–EE9, requires `freeze_predicate == FreezeValid`, and
preserves value and datum exactly. There is no controller transaction
signature requirement; evidence signatures carry attribution.

Advance admits its named input from ACTIVE or FROZEN and always creates one
ACTIVE successor satisfying the same fixed `d_reg` minimum. That is the entire
thaw path. Advance from TOMBSTONE or an unknown role fails before its predicate.

## Convict transaction

```text
Tx Convict:
  input:  one ACTIVE or FROZEN V1 checkpoint, token + locked bond
  output: exactly one TOMBSTONE output containing:
            checkpoint_min_ada
            the same quantity-one AID token
            TombstoneV1 {
              cesr_aid = TIP.cesr_aid,
              convicted_at_native_sn = TIP.native_sn,
              evidence_said = evidence.said
            }
  checkpoint mint: nothing
  shared state / claim / right / finalize: none
```

The branch binds EE0–EE9 and requires
`convict_predicate(TIP, decoded) == ConvictValid`. The exact tombstone leaves
all lovelace above `checkpoint_min_ada` outside checkpoint-script custody; the
convict transaction pays that seized value through its own ordinary
output/change shape. No reward identity, bearer token, claim script, burn,
finalizer, or later actor is introduced. Transaction construction owns the
off-script payout; the validator's enforceable boundary is that none of the
bond remains on the tombstone and no checkpoint-policy asset is minted or
burned.

Convict is permissionless and sovereign across identities. It touches only
the named checkpoint. An ACTIVE or FROZEN fork can be contained even during a
mass compromise without contending on shared state.

## Tombstone: terminal token, permanent record, no AID bar

Spend dispatch classifies the named input before any branch predicate:

- ACTIVE V1: Advance, Freeze, or Convict;
- FROZEN V1: Advance or Convict;
- TOMBSTONE `TombstoneV1`: no redeemer; and
- unknown role/datum pairing: fail.

Every current spend redeemer against a real tombstone fails (F11). The token
and evidence record therefore remain queryable forever. This terminality is
token-scoped: a later Register may mint another checkpoint token with the same
AID-derived asset name. Multiple tombstones for repeated convicted copies are
valid historical records and bar nothing.

## Required adversarial vectors

Existing #106 F1/F1b/F2–F5/F7–F10/F12/F13 remain executable. This ticket adds
or promotes these live boundaries:

| ID | Required boundary |
| --- | --- |
| W1 | any EE offset points at different bytes; count mismatch; truncated or negative span |
| W2 | `said` is wrong width or `off_d` does not name its E-code spelling |
| W3 | one valid witness receipt duplicated to fake `toad = 2` |
| W4 | same reveal and `n`/`nt`/`bt`, but different `kt`, convicts only with tip-threshold attribution |
| D1 | applied `d_reg = 4_999_999` rejects on mint and spend dispatch; the validator remains generic above the floor |
| D2 | fresh or repeated Register output one lovelace below `checkpoint_min_ada + d_reg` rejects |
| U1 | Register succeeds with no registry/reference input and post-conviction same-AID re-registration succeeds |
| U2 | duplicate same-AID ACTIVE registration is admitted as the documented self-harm residual |
| R1 | role marker mutation, unknown staking credential, or wrong role/datum pairing rejects |
| F11 | every spend redeemer against TOMBSTONE rejects while another Register for that AID is admitted |
| F12-L | Freeze changes datum/value, omits token, mints/burns, or targets a non-FROZEN address |
| F13-L | Convict from wrong role, wrong tombstone record/value/address, missing token, retained bond, or own-policy mint/burn rejects |
| T1 | Advance from FROZEN succeeds only with the ordinary full proof and returns ACTIVE |

Wire/schema verdicts stay generated and shared between Haskell and Aiken.
Transaction shape, address, deposit, duplicate registration, and terminality
are full-context Aiken tests.

## Measurement gate

Every final ACCEPT path is measured with the pinned Aiken toolchain against
14,000,000 memory and 10,000,000,000 CPU:

1. Register at 2-key, witnessed, and GLEIF 7-key shapes, without any registry
   spend or MPFS proof component.
2. Freeze at lag, 2-key, and GLEIF 7-key shapes.
3. Convict from ACTIVE and FROZEN, including witnessed-fork evidence and the
   exact tombstone/direct-release transaction shape.
4. Advance-from-FROZEN thaw as the already accepted ordinary Advance path.

Every row uses reference `d_reg = 1_000_000_000` lovelace and must retain at
least 25.00% headroom on both axes. A miss is a hard STOP: no weakened check,
reduced signer fixture, or partial transaction may substitute. Rows report raw
units, percentages, headroom, and whether they are typed-handler rather than
ledger-deserialization measurements. Historical S6 registry rows are marked
superseded; no registry/bootstrap/finalization row remains in final acceptance.

## Residuals

- **Duplicate active mint.** Only the controller can authorize it. Two
  identical checkpoints add no authority; divergent copies are convictable.
  Consumers fail closed on a checkpoint count other than one, so duplication
  makes the controller's identity unusable and is self-harm, not an escalation.
- **Self-conviction.** A forker may submit their own public evidence and reclaim
  the released bond. Fast self-conviction contains the fork before harm; delay
  gives an honest hunter time to convict first and take the bond. There is no
  on-chain party attribution, half-burn, attestation, or other mechanism.
- **Re-registration.** A KERI identity may legitimately continue after a
  convicted checkpoint. Every new copy locks the full fixed bond and every
  divergent copy remains independently convictable.
- Witness-line-up-only/pool-swap conviction remains fail-closed to Freeze.
- `evidence_said` is signed event data, not a recomputed digest.
- Close/migration and consumer discovery remain #117.

## Acceptance criteria

- [ ] The complete #116 unicity surface is absent from code, build wiring,
      validator parameters/redeemers, tests, and final measurements.
- [ ] Fresh and repeated Register preserve #114 R1–R8 and lock the same applied
      fixed `d_reg`; below-parameter and below-mechanical-floor cases reject.
- [ ] Same-AID duplicate ACTIVE mint and post-conviction re-registration are
      explicitly accepted, with no shared input or ordering service.
- [ ] Freeze and Convict consume real #106 fixture evidence at the full
      transaction boundary; Haskell and Aiken agree on wire/predicate verdicts.
- [ ] Freeze→Advance returns to ACTIVE with no other thaw path.
- [ ] A witnessed fork convicts from ACTIVE and FROZEN; controller-only or
      duplicate-receipt framing fails, and `kt` remains a conflict axis.
- [ ] Convict creates the exact token-scoped tombstone, leaves no bond there,
      mints/burns nothing, and depends on no later finalization.
- [ ] Every spend redeemer fails against a tombstone, while the tombstone does
      not prevent another same-AID Register.
- [ ] Only ACTIVE/FROZEN/TOMBSTONE roles remain, with retained bytes unchanged.
- [ ] SAID non-recomputation and both benign residuals are documented.
- [ ] All live measurement rows retain at least 25% memory and CPU headroom;
      Register/Advance regressions stay green and Close stays fail-closed.

## Spec-checkpoint disposition

A-010 is the controlling design ruling and supersedes A-009 in full:

1. conviction is penalty plus per-token record, never permanent AID execution;
2. Register/re-register has a mandatory deployment-fixed bond and no unicity
   read or write;
3. Convict keeps the already-delivered sovereign tombstone/direct-release
   shape and adds no bounty/finalization machinery;
4. tombstone remains unspendable but does not bar same-AID reappearance; and
5. duplicate active mint and self-conviction are benign documented residuals
   with zero added mechanism.

The epic owner separately owns the design-of-record unwind outside #116.
