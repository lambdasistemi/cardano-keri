# Feature specification — #271 enforcement bounty entitlement

Artifact ceiling: 12,000 bytes and 220 lines.

## Outcome

An observer cannot copy pending Freeze or Convict evidence, substitute its
payment key hash, and steal the reward. Before revealing evidence, a claimant
must settle a priced commitment for the exact checkpoint/action. It binds the
payee and evidence through a hidden nonce; only that payee can receive value.

Required-signer membership proves consent, not entitlement: a thief can sign
for a thief-selected payee. The former small `extra_signatories` patch is
rejected; theft prevention needs commitment state and a versioned datum.

## Exposure inventory at `35970a6`

The preproduction manifest selects the split
`checkpoint_register.checkpoint_register` program. The combined
`checkpoint.checkpoint` remains the source-level and compiled-UPLC mirror; it
must not retain a second, weaker rule.

| Edge | Deployed split source | Current binding | Mempool substitution |
| --- | --- | --- | --- |
| Freeze records the future hunter | `checkpoint_register.ak:43-52,100-115,524-560` | **Unbound.** Caller `hunter_pkh` enters `ArmedV1`; checkpoint paths ignore `extra_signatories`. | Copy evidence, replace hunter/ARMED datum, preserve value/deadline, outbid. An attacker signer still passes a signer-only repair. |
| ClaimFreeze pays `B` | `checkpoint_register.ak:563-602` | **Bound after Freeze**, but a stolen Freeze may have poisoned the stored hunter. | Direct output swap rejects; steal Freeze first, then claim as its recorded attacker. |
| Convict ACTIVE pays `min-ADA + D_reg + B` | `checkpoint_register.ak:361-370,619-657` | **Unbound.** Redeemer `convictor_pkh` is checked only for width/output equality. | Copy evidence; replace convictor, indexed output, fee inputs, and witnesses. |
| Convict ARMED pays `min-ADA + D_reg` to convictor | `checkpoint_register.ak:371-375,619-667` | **Unbound.** Convictor is caller-selected. | Replace convictor/output; preserve evidence and hunter output. |
| Convict ARMED pays `B` to hunter | `checkpoint_register.ak:371-375,658-673` | **Bound after Freeze**, but Freeze may have installed the thief. | No direct swap; poisoning Freeze redirects this share. |
| Convict FROZEN pays `min-ADA + D_reg` | `checkpoint_register.ak:376-378,619-657` | **Unbound.** Same caller-selected shape as ACTIVE. | Copy evidence, substitute convictor/output, and win the spend. |

The combined mirror has the same exposures at `checkpoint.ak:78-87,141-191,
348-424,427-505,548-558`. Production transaction construction also names the
uncommitted payees and sets no required signer in
`CheckpointTxBuilder.hs:3110-3215,3337-3477,3624-3690`.

Positive control: board update/retire read `extra_signatories` at
`endpoint_board.ak:107-108,129-130`. Comparator `close.ak:20-64,77-100` binds
refund address, policy, AID, outref, and prior state in a preimage authorized by
datum-fixed keys. Enforcement lacks equivalent pre-existing entitlement.

## Entitlement protocol

### Commit before reveal

A claimant opens **DAT-271-COMMITMENT** under a dedicated commitment
validator/policy. It is authenticated by a unique marker derived from a
consumed seed outref; an arbitrary output sent to the script address is not a
commitment.

The output fixes checkpoint policy/outref, action, payee, timing, and opaque
hash. The hash binds domain/version, network, exact checkpoint, action,
complete-evidence digest, payee, marker, timing, and a 32-byte-or-longer nonce.
Digest and nonce stay hidden. Opening requires the payee signer, recording
consent independently of a later submitter.

### Aging, expiry, deposit, and races

- **Age:** the opening transaction stores its finite validity upper endpoint.
  Reveal requires a finite lower endpoint at least one network slot after it.
  The applied `commit_min_age` is exactly one slot in ledger validity units.
  A commitment and reveal cannot settle in the same slot or same-block package.
- **Expiry:** reveal requires a finite upper endpoint no later than
  `commit_upper + 10,000 slots`. After that point it cannot reveal.
- **Grinding price:** a commitment locks exactly the marker plus
  `D_commit = max(5,000,000 lovelace, the current ledger minimum for the
  output)`. A valid reveal returns it to the committed payee. After expiry,
  anyone may burn the marker and take exactly that lovelace by naming and
  signing for the sweep output. Abandoned speculative commitments therefore
  become garbage-collection rewards rather than permanent UTxOs.
- **Race rule:** first valid reveal wins. Multiple independently prepared
  commitments may coexist; the first ledger-ordered transaction spending the
  unique checkpoint input settles. All losing commitments become stale and
  remain sweepable after expiry. “First commit wins” is rejected because it
  needs global per-checkpoint exclusion and lets a speculative commitment
  block genuine evidence. Same-block ties are ledger transaction order.

Copying an opaque commitment cannot change its payee or hidden nonce. Once
reveal exposes the nonce, the age rule makes a reactive commitment too young.
Independent pre-reveal commitment is legitimate competition, not mempool theft.

## Enforcement-path fix

- **Freeze:** consumes one mature unexpired Freeze commitment for the exact
  ACTIVE checkpoint and actual observer evidence. The committed payee must
  equal `hunter_pkh`; the marker burns and deposit refunds exactly. `ArmedV2`
  records both hunter and commitment identity, making the later entitlement
  provenance durable.
- **ClaimFreeze:** pays only the hunter and entitlement recorded by `ArmedV2`.
  It needs no new caller-selected payee. The payee consented when opening the
  commitment, so requiring a fresh hunter signature here is forbidden: an
  absent hunter must not permanently veto Claim or a later conviction.
- **Convict ACTIVE/FROZEN:** consumes one mature unexpired Convict commitment
  for the exact source and evidence. The committed payee is the convictor; the
  marker burns, deposit refunds, and the existing source-specific bounty goes
  only to that key.
- **Convict ARMED:** applies the same commitment rule to the convictor share.
  The hunter share remains fixed by `ArmedV2`; its earlier signed commitment is
  durable consent, so the hunter cannot veto terminal conviction by withholding
  a fresh signature.

No enforcement-evidence predicate changes. Entitlement authenticates economic
context; KERI evidence continues to prove only later event or witnessed fork.

## Requirements

- **RQ-271-01:** Every Freeze/Claim/Convict exposure in the inventory is
  covered in the deployed split validator, transaction builders, and combined
  compiled mirror.
- **RQ-271-02:** Only an authenticated marker output created by the commitment
  policy can establish entitlement; script-address deposits alone reject.
- **RQ-271-03:** Reveal derives the evidence digest from the actual observer
  payload and matches the opaque commitment using the supplied nonce.
- **RQ-271-04:** Commitment scope binds network, checkpoint policy/outref,
  action, marker, payee, evidence, and timing. Cross-input/action/evidence use
  rejects.
- **RQ-271-05:** Commit and reveal validity ranges enforce the one-slot minimum
  age and 10,000-slot maximum lifetime at the ledger boundary.
- **RQ-271-06:** Open, reveal, and expired sweep conserve exactly one marker and
  `D_commit`; no duplicate mint, retained marker, alternate refund, or
  unsignatured caller-selected recipient is admitted.
- **RQ-271-07:** Multiple valid commitments use first-valid-reveal semantics;
  transaction order is the only tie-break and a losing commitment cannot spend
  or redirect the winner's checkpoint.
- **RQ-271-08:** Freeze records only the payee and commitment identity proven by
  the consumed entitlement; Claim cannot choose another beneficiary.
- **RQ-271-09:** Every Convict role pays the committed convictor amount exactly;
  ARMED also pays the already committed hunter exactly, without giving that
  hunter a fresh-signature veto.
- **RQ-271-10:** Required-signer checks certify consent when a payee or sweep
  recipient is first selected. They never substitute for the entitlement
  preimage and never make a fixed later beneficiary a liveness dependency.
- **RQ-271-11:** Wire changes are versioned and mirrored in Haskell/Aiken from
  generated vectors; frozen constructor layouts are not silently edited.
- **RQ-271-12:** The commitment validator identity, parameters, reference, and
  checkpoint-family dependency are published in the #254 version registry.
- **RQ-271-13:** Existing v0 scripts are not described as patched. #163/#164
  remain blocked until migration to the entitlement-aware family is complete.
- **RQ-271-14:** M8 continues to target the exact changed compiled family and
  demonstrates entitlement, age, replay, and payout mutants can fail.

## Declared invariants

All rows are `BLOCKING`: each constrains chain state, money, or signatures.
Passing examples alone leave a row OPEN.

| Invariant | Severity | Failure meaning | Success meaning |
| --- | --- | --- | --- |
| `INV-271-ENTITLEMENT` | BLOCKING | Valid public evidence can pay a key without a pre-existing authentic commitment to that key. | A substituted-payee/no-marker mutant is rejected; the committed payee settles. |
| `INV-271-AGE` | BLOCKING | A commitment created after observing the reveal can settle in the same slot/block package. | A same-slot package mutant fails while a one-slot-aged reveal passes. |
| `INV-271-SCOPE` | BLOCKING | A commitment replays across checkpoint input, policy, action, evidence, marker, or network. | A named mutation of each scope class rejects permanently. |
| `INV-271-CONSENT` | BLOCKING | A caller-selected payee/sweeper is recorded or paid without its consent, or a fixed beneficiary gains a signature veto. | Missing selection-time signer rejects; Claim and ARMED conviction remain executable from stored consent. |
| `INV-271-VALUE` | BLOCKING | Marker, commitment deposit, hunter bond, or convictor reserve is duplicated, retained, redirected, or miscounted. | Named token/deposit/payout mutants reject for every source role. |
| `INV-271-LIFETIME` | BLOCKING | Premature sweep, post-expiry reveal, or an unsweepable expired commitment is accepted. | Boundary mutants fail and a permissionless signed sweep removes the expired output. |
| `INV-271-RACE` | BLOCKING | Two reveals settle one checkpoint, ordering is caller-asserted, or a loser redirects winner value. | Single-spend/transaction order selects one winner and stale commitments affect no payout. |
| `INV-271-PARITY` | BLOCKING | Split/mirror/offchain encodings or verdicts disagree, or source tests pass while compiled UPLC admits a bypass. | Generated parity and named compiled mutants fail against the announced family. |

Campaign ledger:
`/tmp/ms-keri-1/e274/cardano-keri-271/evidence/mutation-campaign.md`.
The build-denominated stopping contract is fixed in `plan.md`.

## Shipping recommendation

Batch implementation into #254's checkpoint-family migration, as a distinct
entitlement slice before its checkpoint-family acceptance. #254 already changes
the checkpoint dispatch, datum version, applied parameters, registry, reference
scripts, M8 target, and preproduction cutover that this protocol necessarily
changes. #253 touches only the board. A standalone implementation would still
depend on #254 to move immutable v0 checkpoints and would create a second
validator-version/cutover event. The extra commitment transaction adds latency
and capital lock, but one slot and a refundable 5 ADA floor are bounded costs;
duplicating the migration vehicle would cost more and delay #163/#164 further.
