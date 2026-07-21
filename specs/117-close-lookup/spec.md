# Spec: close a checkpoint and resolve ACTIVE state by reference input (#117)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/117
Epic: https://github.com/lambdasistemi/cardano-keri/issues/24

This ticket completes two small edges of the checkpoint lifecycle. A current
controller threshold may close one ACTIVE checkpoint instance, burn its
quantity-one checkpoint token, and direct every remaining asset in that state
input to a signed refund address. A consumer may resolve an authenticated
ACTIVE checkpoint from the transaction's CIP-31 reference inputs without
spending it.

The #116 reversal is load-bearing: Cardano does not own a mint-once or global
unicity decision for a KERI AID. Close retires the checkpoint instance named by
its spent output reference; it does not bar the AID or asset name. The same AID
may register again under the unchanged Register policy when KERI still carries
it. Resolution therefore authenticates a transaction-supplied ACTIVE instance;
it cannot prove that no other live instance was omitted from the transaction.

Ratified inputs (not reopened here): `specs/114-registration/spec.md`,
`specs/115-advance/spec.md`, `specs/116-enforcement/spec.md`, and
`specs/92-checkpoint-contention/spec.md`. The deployed script already has the
generic, deployment-fixed `d_reg` parameter (mechanical floor 5,000,000
lovelace; non-normative fixture value 1,000,000,000) and the exact ACTIVE,
FROZEN, and TOMBSTONE role addresses. This ticket uses those surfaces; it does
not rebuild or reinterpret them.

---

## Decisions at a glance

1. **Close burns; there is no CLOSED role.** Close spends exactly one ACTIVE
   checkpoint, burns its derived quantity-one token, creates no checkpoint
   successor, and refunds the complete remaining input value. Logical Closed
   state is absence after that spend, not a new live UTxO or datum.
2. **Close is ACTIVE-only.** FROZEN is containment, so its controller cannot
   bypass the freeze with Close. It must first use the existing ordinary
   Advance proof to return to ACTIVE. TOMBSTONE remains terminal for its own
   token and admits no Close.
3. **The current controller set authorizes the exact effect.** Distinct valid
   signatures satisfying `OLD.cur_threshold` cover a versioned, canonical-CBOR
   message reconstructed from deployment, the named state input, its datum,
   and the full refund address.
4. **Close is one checkpoint instance per transaction.** The mint branch burns
   exactly the one name derived from the named ACTIVE input. The spend branch
   independently checks the same burn and refund. Register and Close cannot be
   combined under one policy redeemer; re-registration is a later ordinary
   Register transaction.
5. **Lookup reads only ACTIVE.** A public Aiken helper inspects the actual
   `Transaction.reference_inputs`, authenticates the trusted checkpoint policy,
   exact ACTIVE full address, derived token, inline V1 datum, and AID, and
   returns one resolved `(out_ref, datum)` or fails closed.
6. **Reference-input uniqueness is local, not global.** The helper requires
   exactly one matching candidate among the supplied reference inputs. Plutus
   cannot prove that the transaction author included every globally live UTxO.
   No mint-once registry, MPF, shared root, batcher, sequencer, or off-chain
   ordering service is introduced.
7. **O3 and O4 are consumed, not rebuilt.** Close refunds whatever the input
   contains after removing the token. Lookup reuses the already-shipped ACTIVE
   address. No new role byte or `d_reg` rule is in scope.

## Problem

The combined checkpoint validator still has an explicitly fail-closed `Close`
redeemer and no consumer-resolution library. Controllers cannot intentionally
recover the bond from an honest ACTIVE checkpoint. Downstream contracts also
need a small, hard-to-misuse way to authenticate an ACTIVE checkpoint supplied
as a CIP-31 reference input.

The old issue wording predated #116's simplification and can be misread as
requiring a globally terminal AID. That invariant is rejected. A burn removes
the current state instance and its live token, but the existing Register mint
branch may later mint the same `(policy, aid_asset_name)` again. A consumer
must likewise avoid smuggling global uniqueness into its lookup claim.

## Scope

### In scope

1. A versioned Close message and controller-threshold authorization predicate
   with Haskell/Aiken byte and verdict parity.
2. ACTIVE-only live Close handling in both sides of the combined validator:
   exact token burn, no checkpoint successor, and right-address/right-value
   refund.
3. A public Aiken CIP-31 resolution helper over the transaction's real
   reference-input collection, plus a shared pure Haskell/Aiken candidate
   model for generated vectors.
4. Full-context adversarial tests for close, burn/refund welding, role
   exclusion, resolver authentication, ambiguity among supplied references,
   and post-close re-registration.
5. Full close-transaction and lookup execution-unit measurements at ordinary
   two-key and GLEIF seven-key shapes, with the standing 25% headroom gate.

### Out of scope

- Any mint-once, AID-wide terminality, unicity registry, MPF membership or
  absence proof, mutable root, global scan, or shared state.
- Any CLOSED, REGISTRY, or BOUNTY role; ACTIVE `bare`, FROZEN `0x00`, and
  TOMBSTONE `0x01` are unchanged.
- Any change to the `d_reg` parameter, its 5,000,000-lovelace deployment floor,
  the 1,000,000,000-lovelace reference fixture, or Register/Advance/Convict
  bond rules.
- Closing FROZEN or TOMBSTONE state, a separate thaw/close shortcut, or a
  witness-authorized close.
- Off-chain node queries, chain-index selection, transaction construction,
  wallet UX, deployment selection, or a live-node demonstration. Those belong
  to downstream #44 and integration work.
- The cross-path adversarial matrix in #118, migration, and documentation.
- Changes to old specifications or `docs/`.

## Existing invariants retained

1. The full address is the lifecycle role: ACTIVE is
   `Address(Script(checkpoint_policy_id), None)`; FROZEN and TOMBSTONE use the
   already-ratified staking-script tags.
2. A checkpoint token name is
   `deriveAidAssetName(cesr_aid)` under the checkpoint validator/policy hash.
3. V1 datums are inline, well formed, and bind the same raw 32-byte KERI AID as
   the derived token name.
4. Advance and Freeze preserve their current behavior. Convict remains
   permissionless and sovereign, retains the terminal token in TOMBSTONE, and
   releases its bond according to #116.
5. Tombstone terminality is token-instance-scoped. Close adds no AID-wide bar,
   and post-close or post-conviction re-registration remains accepted.
6. `d_reg` validity is checked before mint/spend dispatch by the existing
   applied validator. #117 does not add a controller-selected deposit field.
7. Unknown role addresses, role/datum mismatches, datum versions other than V1,
   and malformed values fail closed.

---

## Close protocol

### C1 — signed Close message

The frozen domain is:

```text
UTF8("cardano-keri/checkpoint/close/v1")
```

`CloseMessage` is Plutus Data constructor 0 with the following fields in exact
order, serialized as canonical Plutus-Data CBOR before Ed25519 verification:

```text
CloseMessage {
  domain                : ByteArray
  network_id            : Int
  checkpoint_policy_id  : ByteArray
  aid_asset_name        : ByteArray
  cesr_aid              : ByteArray
  spent_txid            : ByteArray
  spent_index           : Int
  prior_seq             : Int
  prior_native_sn       : Int
  refund_address        : Address
}
```

The live validator reconstructs every field. The redeemer supplies only the
full `refund_address` and indexed signatures:

```text
CloseEvidence {
  refund_address : Address
  ctrl_sigs       : List<(Int, ByteArray)>
}
```

`checkpoint_policy_id` comes from the named input's payment script hash;
`aid_asset_name` is derived from `OLD.cesr_aid`; transaction id/index come from
the named `own_ref`; and sequence fields and authority come from the named
inline V1 datum. The applied `network_id` is included to prevent cross-network
replay. The spent outref prevents replay after either close or re-registration,
and the signed full refund address prevents a submitter from redirecting the
bond.

### C2 — controller authorization

Close accepts only when all of the following hold:

1. `OLD` is well formed and its AID is exactly 32 bytes.
2. The message domain, deployment, derived asset name, AID, named outref,
   sequence fields, and full refund address equal the reconstructed values.
3. Each signature index is in range of `OLD.cur_keys` and the signature
   verifies over the exact canonical-CBOR `CloseMessage` bytes.
4. Duplicate indices count once. The set of distinct valid indices satisfies
   `OLD.cur_threshold` with the shared threshold evaluator.

Close uses the current keys, not `next_keys`, witnesses, or a KERI event. A
bad-index, duplicate-inflated, wrong-key, wrong-message, or below-threshold set
rejects.

### C3 — spend-side transaction shape

`SpendRedeemer.Close { evidence }` is admitted only for the named
`ActiveCheckpoint`. The spend branch MUST require:

1. `own_ref` resolves to exactly the named ACTIVE input, with inline V1 `OLD`.
2. Its payment credential is the applied checkpoint script hash and its full
   address is the exact ACTIVE address.
3. It carries exactly one token at
   `(own_hash, deriveAidAssetName(OLD.cesr_aid))`.
4. It is the only transaction spending input that carries a nonzero quantity
   of that exact policy/name. This prevents a fungible sibling instance from
   being mixed into the named close.
5. Close authorization C1–C2 passes against the named input and evidence.
6. The complete mint map under `own_hash` is exactly one pair:
   `(deriveAidAssetName(OLD.cesr_aid), -1)`.
7. No transaction output carries that exact policy/name at a nonzero quantity.
   There is no ACTIVE, FROZEN, TOMBSTONE, ordinary-address, or disguised
   successor for the burned instance.
8. Exactly one output at the signed refund address has value equal to the
   complete named input value plus the `-1` checkpoint-token adjustment. This
   returns all lovelace (`checkpoint_min_ada + d_reg` and any surplus) and any
   unrelated assets; transaction fees are funded from ordinary other inputs.
9. The signed refund address's payment credential is not `Script(own_hash)`,
   so the refunded value leaves checkpoint-script custody.

The exact matching refund output is deliberately dedicated: unrelated
transaction change cannot be used to underpay it, and other inputs cannot be
used to disguise a missing checkpoint asset. Extra ordinary inputs and outputs
remain allowed.

### C4 — mint-side burn shape

`MintRedeemer` gains `CloseBurn { checkpoint_ref }`. The mint handler MUST
independently require:

1. `checkpoint_ref` resolves among transaction spending inputs to the exact
   ACTIVE address for this policy.
2. That input has inline V1 `OLD` and exactly one derived checkpoint token.
3. No other transaction spending input carries that exact policy/name.
4. The complete mint map under this policy is exactly the derived name at
   quantity `-1`.

The policy handler does not accept controller evidence; the spending handler
for the named script input performs C1–C3. The dual check welds the burn to the
same state input without duplicating signature work. A burn without the named
ACTIVE spend, the wrong asset name, multiple names, quantity other than `-1`,
or a FROZEN/TOMBSTONE input rejects.

One policy redeemer cannot be both `Register` and `CloseBurn`, so atomic
close-and-re-register is intentionally absent. A later Register remains valid
and mints the same derived asset name into a fresh ACTIVE checkpoint.

### C5 — lifecycle and races

```text
ACTIVE --Close/current controller threshold--> no live checkpoint instance
ACTIVE --Freeze/later witnessed KERI event----> FROZEN
ACTIVE|FROZEN --Convict/fork evidence---------> TOMBSTONE
FROZEN --ordinary Advance proof--------------> ACTIVE
no live checkpoint --ordinary Register-------> ACTIVE (same AID allowed)
```

Close, Advance, Freeze, and Convict all spend the same named state UTxO, so
normal ledger contention serializes races. If Close wins, competitors see a
spent input. If Freeze wins, Close fails because the old input is gone and the
new role is FROZEN; a controller must prove an ordinary Advance before closing.
If Convict wins, its tombstone admits no Close. A later independent Register is
not a race continuation and is never barred.

### C6 — Close negative matrix

The shared predicate and full-context tests MUST include at least:

| ID | Mutation | Verdict |
| --- | --- | --- |
| C-N1 | FROZEN input with otherwise valid close evidence | REJECT |
| C-N2 | TOMBSTONE input | REJECT |
| C-N3 | wrong/unknown role or non-V1 datum | REJECT |
| C-N4 | token absent or quantity two on named input | REJECT |
| C-N5 | no burn, wrong name, `-2`, or a second own-policy mint entry | REJECT |
| C-N6 | burn names an ACTIVE input other than `checkpoint_ref` | REJECT |
| C-N7 | any reconstructed message field changed | REJECT |
| C-N8 | bad/out-of-range signature index or below-threshold signatures | REJECT |
| C-N9 | duplicate signature index used to inflate threshold | REJECT |
| C-N10 | refund address differs from the signed full address | REJECT |
| C-N11 | refund value one lovelace or one unrelated asset short | REJECT |
| C-N12 | refund stays under the checkpoint payment credential | REJECT |
| C-N13 | a second target-token input or any output carries the target token | REJECT |
| C-N14 | old Close signature replayed against a re-registration outref | REJECT |
| C-P1 | extra ordinary fee input/change output, exact dedicated refund | ACCEPT |
| C-P2 | close succeeds, then ordinary same-AID Register succeeds | ACCEPT |

---

## CIP-31 ACTIVE resolution

### L1 — trust anchor and public API

The consumer knows the trusted deployed `checkpoint_policy_id` and target raw
`cesr_aid`. The library derives the asset name rather than accepting it from
the caller. The public Aiken API is equivalent to:

```text
resolve_active_checkpoint(
  checkpoint_policy_id : PolicyId,
  cesr_aid             : ByteArray,
  tx                   : Transaction,
) -> Option<ResolvedCheckpoint>

ResolvedCheckpoint {
  out_ref : OutputReference
  datum   : CheckpointDatumV1
}
```

It operates on `tx.reference_inputs`, not ordinary spending inputs and not a
caller-supplied decoded datum. The policy id is a deployment trust anchor; the
helper does not discover or bless a policy.

### L2 — candidate authentication

The helper rejects a target AID whose width is not 32 bytes. It derives
`aid_name = deriveAidAssetName(cesr_aid)` and selects supplied reference inputs
whose outputs satisfy both:

1. full address equals
   `Address(Script(checkpoint_policy_id), None)` (the exact ACTIVE role); and
2. value holds exactly one `(checkpoint_policy_id, aid_name)` token.

There MUST be exactly one such candidate among the supplied reference inputs.
For that candidate the helper then requires:

1. an inline datum, decoded as `CheckpointDatum.V1(datum)`;
2. `datum_well_formed(datum)` succeeds;
3. `datum.cesr_aid == cesr_aid`; and
4. re-deriving the datum's asset name yields the same selected token name.

Success returns the candidate's actual output reference and decoded V1 datum.
Every failure returns `None`; consumers never receive a partially authenticated
datum.

Filtering address+token before datum decoding makes ambiguity fail closed even
when one of two same-token ACTIVE references has a malformed datum. Additional
unrelated reference inputs are allowed.

### L3 — role behavior

FROZEN and TOMBSTONE outputs use different full addresses and therefore never
become candidates. A closed checkpoint has been spent and burned and therefore
has no live reference output. The resolver needs no status flag or branch per
inactive role: exact ACTIVE-address equality makes each case resolve to
`None`. A historical same-AID TOMBSTONE may coexist with one ACTIVE
re-registration without making the ACTIVE lookup ambiguous.

### L4 — CIP-31 ledger boundary

CIP-31 reference inputs are visible to Plutus separately from spending inputs,
and their outputs are not consumed. The ledger requires a referenced output to
exist and remain unspent; a transaction attempting to reference a checkpoint
that another transaction spends loses the race and must be rebuilt. The
referenced output's own validator is not executed, which is why L2 explicitly
re-authenticates its address, policy token, inline datum, AID, and shape.

The Aiken unit/full-transaction tests prove the helper's behavior over real
`Transaction.reference_inputs` values. They do not claim to test node query,
ledger deserialization, mempool races, or transaction submission. A live
boundary demonstration belongs to #44.

### L5 — explicit non-unicity boundary

The helper proves:

> exactly one authentic ACTIVE candidate for this trusted policy and AID was
> supplied as a reference input to this transaction.

It does **not** prove:

> exactly one ACTIVE checkpoint for this AID exists globally on Cardano.

Plutus cannot inspect UTxOs omitted by the transaction author, and #116
deliberately admits duplicate/re-registration minting without shared state. An
off-chain query/indexer preparing a consumer transaction SHOULD scan the exact
ACTIVE address for the target policy/name and fail when it sees zero or more
than one live candidate. That scan is an integration responsibility, not a
consensus guarantee and not an ordering service. A consumer protocol that
requires global AID uniqueness needs a separately specified trust/admission
rule; this ticket must not silently recreate one.

### L6 — resolution vector matrix

The shared model and the live Aiken helper MUST include at least:

| ID | Supplied reference inputs | Verdict |
| --- | --- | --- |
| L-P1 | one exact ACTIVE, quantity-one token, matching well-formed V1 | RESOLVE |
| L-P2 | L-P1 plus unrelated references | RESOLVE |
| L-P3 | one ACTIVE plus same-AID historical TOMBSTONE | RESOLVE ACTIVE |
| L-N1 | no matching reference | NONE |
| L-N2 | FROZEN candidate only | NONE |
| L-N3 | TOMBSTONE candidate only | NONE |
| L-N4 | ordinary spending input only, no reference input | NONE |
| L-N5 | wrong policy, wrong token name, absent token, or quantity two | NONE |
| L-N6 | wrong/unknown full address | NONE |
| L-N7 | datum hash/no datum/non-V1/malformed V1 | NONE |
| L-N8 | datum AID differs from target | NONE |
| L-N9 | two supplied ACTIVE candidates for the same policy/AID | NONE |
| L-N10 | one valid plus one malformed same-token ACTIVE candidate | NONE |
| L-N11 | malformed target AID width | NONE |

---

## Shared Haskell/Aiken parity

Close and resolution each have a validator-free Haskell model and Aiken model.
Haskell generators own canonical fixtures; committed Aiken vector modules are
generated and drift-checked.

Close parity covers:

- exact domain bytes, constructor index, field order, full-address Plutus Data,
  and canonical-CBOR message bytes;
- reconstruction from named spent context and evidence;
- distinct-index current-threshold evaluation and Ed25519 verdicts; and
- every C6 pure authorization mutation that does not require a full transaction.

Resolution parity covers a small `ReferenceInputView` model containing outref,
full address, value, and datum shape. The production Aiken adapter MUST build
that decision from the actual `Transaction.reference_inputs`; it must not
accept a prefiltered candidate or caller-decoded datum. L6 vectors cover the
same candidate verdict and, on success, exact returned outref/datum.

Generated fixtures are full-strength ordinary two-key and GLEIF seven-key
states. Tests may add hand-built transaction mutations but may not replace the
shared parity gate with reduced keys, thresholds, or datum placeholders.

## Measurements and hard gate

Mainnet per-transaction limits remain 14,000,000 memory and 10,000,000,000 CPU.
Every final row MUST retain at least 25.00% headroom on both axes:

```text
memory <= 10,500,000
cpu    <= 7,500,000,000
```

All ordinary checkpoint fixtures use the non-normative reference
`d_reg = 1,000,000,000` lovelace while validator logic remains generic over the
already-shipped parameter.

Required rows:

| Row | Measured execution |
| --- | --- |
| `close_spend_2key` | ACTIVE Close spend handler, ordinary two-key threshold |
| `close_burn_2key` | matching CloseBurn mint handler |
| `close_tx_sum_2key` | mechanical raw-unit sum of both scripts in one transaction |
| `close_spend_gleif7` | ACTIVE Close spend handler, full seven-key fixture |
| `close_burn_gleif7` | matching CloseBurn mint handler |
| `close_tx_sum_gleif7` | mechanical raw-unit sum of both scripts in one transaction |
| `resolve_active_2key` | public helper over a full transaction reference-input fixture |
| `resolve_active_gleif7` | same helper over the full seven-key datum fixture |

Each row records raw memory/CPU, percent used, and percent headroom. The close
acceptance gate is the summed spend+mint cost because both scripts execute in
one ledger transaction; separate rows remain diagnostic. Resolver numbers are
library execution over a full Aiken transaction fixture, not a claim about
ledger deserialization or live-node query costs.

Use a #117-specific `just measure-close-lookup` target and report so the exact
nine-row #116 `measure-checkpoint` acceptance set remains unchanged. Any row
below 25.00% headroom, failure to sum both close scripts, reduced fixture, or
unexplained cost regression is a hard STOP and an epic-owner Q-file before
commit.

## Functional requirements

- **FR-001**: Close MUST be admitted only from the exact ACTIVE full address.
- **FR-002**: Close MUST reconstruct the frozen C1 message and require distinct
  current-controller signatures satisfying `OLD.cur_threshold`.
- **FR-003**: The signed message MUST bind network, policy, derived token name,
  AID, exact spent outref, old sequence fields, and full refund address.
- **FR-004**: Close MUST isolate the named quantity-one token from sibling
  transaction inputs, burn it under the combined policy, and leave that exact
  policy/name in no output.
- **FR-005**: Close MUST pay the complete named input value minus that token to
  exactly one output at the signed non-checkpoint refund address.
- **FR-006**: The mint and spend handlers MUST independently weld the burn to
  the same named ACTIVE input and enforce the same transaction-local isolation.
- **FR-007**: Close MUST NOT create an AID-wide bar, CLOSED role, permanent
  record, shared state, or mint-once check.
- **FR-008**: Same-AID Register after Close MUST remain accepted and must still
  enforce the already-shipped deployment-fixed bond.
- **FR-009**: The public resolver MUST inspect actual transaction reference
  inputs and authenticate exact ACTIVE address, trusted policy/name, quantity,
  inline V1 datum, well-formedness, and AID.
- **FR-010**: Resolver success MUST require exactly one matching candidate
  among supplied references and return its actual outref and datum.
- **FR-011**: FROZEN, TOMBSTONE, closed/absent, malformed, wrong-policy,
  wrong-address, and supplied-reference ambiguity cases MUST fail closed.
- **FR-012**: Resolver documentation and tests MUST NOT claim global uniqueness
  or inspect state outside the supplied transaction.
- **FR-013**: Haskell and Aiken MUST agree on Close message bytes and shared
  Close/lookup vector verdicts; generated vectors MUST be drift-stable.
- **FR-014**: Full-context negatives MUST cover C6 and L6 without weakening
  inherited Register, Advance, Freeze, or Convict behavior.
- **FR-015**: The final full gate and every required measurement row MUST pass,
  with at least 25.00% memory and CPU headroom.

## Acceptance scenarios

### A1 — honest close and refund

Given a well-formed ACTIVE checkpoint with the reference 1,000-ADA bond, when
distinct current controllers satisfy the threshold over the reconstructed
Close message and the transaction burns the named token, then the close
succeeds, no checkpoint successor exists, and the exact input value minus the
token appears at the signed refund address.

### A2 — containment cannot be bypassed

Given the same state at FROZEN, the identical controller evidence fails. After
an ordinary valid Advance returns the state to ACTIVE, a fresh Close signature
over that new outref may succeed.

### A3 — reversed invariant survives close

Given a successful close, a later ordinary Register for the same raw AID and
derived asset name remains accepted when it satisfies existing registration
and fixed-bond rules. No close artifact is consulted.

### A4 — ACTIVE reference read

Given one authentic ACTIVE reference input under the configured policy, the
helper returns its actual outref and complete well-formed V1 datum without
spending it. Adding unrelated references changes no result.

### A5 — inactive and ambiguous references fail closed

Given only FROZEN/TOMBSTONE references, no live post-close output, or two
same-policy/name ACTIVE candidates supplied to the transaction, the helper
returns `None` without exposing a datum.

### A6 — omitted-global-state limitation remains explicit

Given a transaction that supplies one authentic ACTIVE reference while another
duplicate ACTIVE exists elsewhere on chain, the helper can resolve the supplied
instance because the omitted UTxO is invisible to Plutus. The specification,
API docs, and tests identify this as a non-unicity boundary, not a safety proof
of global uniqueness.

## Success criteria

1. The fail-closed Close stub is replaced by the C1–C5 ACTIVE-only burn/refund
   protocol, with all C6 positives/negatives green.
2. Post-close same-AID re-registration is executable and no mint-once,
   registry, MPF, CLOSED role, or AID-wide bar appears in the diff.
3. The public Aiken resolver meets L1–L6 over real transaction reference-input
   fixtures and the shared Haskell/Aiken vectors do not drift.
4. Existing #116 `d_reg` and ACTIVE/FROZEN/TOMBSTONE encoding remain byte- and
   behavior-identical outside the new paths.
5. `./gate.sh` passes and all eight measurement rows retain at least 25.00%
   headroom, including the mechanically summed full close transaction.

## Open ratification points for Q-013

1. Ratify burn/no-CLOSED-role and the precise statement that a later Register
   may remint the same policy/name for a fresh checkpoint instance.
2. Ratify ACTIVE-only Close; FROZEN must ordinary-Advance before closing.
3. Ratify the C1 message fields, current-controller threshold, and exact
   whole-input-minus-token refund to a signed non-checkpoint address.
4. Ratify that the on-chain resolver's uniqueness boundary is exactly the
   supplied CIP-31 reference inputs, while exhaustive off-chain discovery is an
   integration recommendation rather than a consensus property.
5. Ratify four implementation slices: Close parity, live Close, resolver
   parity/live adapter, then hard-gated measurements.
