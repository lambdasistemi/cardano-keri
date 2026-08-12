# Implementation plan — #271 enforcement bounty entitlement

Artifact ceiling: 12,000 bytes and 240 lines.

## Strategy

Add a dedicated bounty-commitment validator/policy and integrate it into the
versioned checkpoint family delivered by #254. An authenticated commitment
marker proves creation-time checks ran. Its datum exposes scope, payee, and
time bounds but hides the evidence digest and nonce behind a canonical hash.
Freeze and Convict consume a mature matching commitment while the enforcement
observer derives the digest from the actual evidence it already validates.

The split checkpoint remains thin: state/value dispatch and observer coupling
stay in `checkpoint_register`; evidence plus entitlement matching stays in the
enforcement observer/shared protocol. The combined `checkpoint` program and
M8 artifact receive the same rule so no dormant or formal target preserves the
defect. Offchain wire/build paths construct commitments and required signers;
they never manufacture an entitlement only at reveal time.

## Protocol decisions

| Question | Decision and reason |
| --- | --- |
| Minimum age | One complete network slot. Reveal lower bound is at least `commit_upper + commit_min_age`; same-slot/same-block commit+reveal is impossible while latency remains minimal. |
| Expiry | 10,000 slots after `commit_upper`. This matches the existing enforcement horizon scale, bounds stale state, and gives a claimant hours rather than seconds to reveal. |
| Garbage collection | After expiry anyone may burn the unique marker and take the exact commitment lovelace to a signer-controlled sweep output. This removes abandoned state without a privileged collector. |
| Grinding price | Exact marker plus `max(5 ADA, ledger min-ADA)` per commitment. Valid reveal refunds it; expiry exposes it to sweep, pricing broad speculation in locked capital and loss risk. |
| Competing commitments | First valid reveal wins; ledger order breaks ties. First-commit-wins is rejected because global exclusion lets speculative commits block genuine evidence. |
| Payee consent | Payee signs commitment creation and reveal/refund when directly participating. Stored entitlement is durable consent for later Claim and ARMED hunter payment; no fresh signature may create a hunter veto. |
| Evidence meaning | Unchanged. The commitment binds the complete evidence digest but does not alter KERI verification or make payee data identity state. |

## Ordered slices inside #254

### S271-1 — commitment protocol and parity

Add versioned commitment/preimage/reveal types, canonical Haskell/Aiken parity,
unique marker minting, opening, valid reveal, and expired sweep. Freeze a
parameter set containing commitment policy, one-slot age, 10,000-slot lifetime,
and deposit floor. Demonstrate RED for counterfeit output, missing signer,
same-slot reveal, post-expiry reveal, premature sweep, retained/duplicated
marker, changed refund, and changed preimage scope.

Bisect condition: commitment lifecycle and generated vectors are complete,
but no checkpoint action claims entitlement protection yet.

### S271-2 — enforcement integration

Require mature commitments in Freeze and all Convict roles; record commitment
identity in the new ARMED datum; preserve fixed-beneficiary Claim and ARMED
hunter payout without a fresh-signature veto. Update the split validator,
enforcement observer, combined mirror, transaction builders, measurements,
and focused/live properties together.

Bisect condition: every exposure row rejects a substituted/no-commitment payee,
all exact payout and lifecycle behavior remains valid, and source/mirror verdicts
agree.

### S271-3 — release registry and migration composition

Register the commitment script/reference/parameters and entitlement-aware
checkpoint family in #254's append-only version registry. Extend migration and
deployment packages without treating immutable v0 as repaired. Reconcile the
cutover family with #163/#164 prerequisites and M8's exact compiled target.

Bisect condition: the family can be built, located, migrated to, and consumed
without a single-address or ambient-script assumption; no live cutover occurs
before #254 acceptance.

## Verification contract

- **Entitlement RED:** start from valid Freeze/Convict evidence and exact value,
  substitute the payee plus output and sign as the attacker. It must fail for
  lack of a matching aged commitment. The old signer-only mutant must be shown
  to pass against the pre-fix rule, proving the test distinguishes consent from
  entitlement.
- **Age RED:** a commit and reveal valid in one slot/block package fails; the
  same reveal after the one-slot boundary passes.
- **Scope RED:** independently mutate checkpoint ref, policy, network, action,
  evidence digest, marker, payee, and nonce.
- **Lifetime RED:** test exact age/expiry boundaries, premature sweep, expired
  reveal, and successful post-expiry sweep.
- **Value RED:** mutate every source-specific bounty, commitment refund,
  marker mint/burn, output index, datum, and extra asset.
- **Liveness:** stored hunter consent permits Claim and ARMED Convict without a
  new hunter witness; a mutation demanding that witness must fail the property.
- **Parity/compiled:** generated vectors drive Haskell, split Aiken, combined
  Aiken, and the named M8 compiled program; no hand-written duplicate vectors.
- **Full:** the focused entitlement gate precedes repository CI and #254's
  migration/registry/cutover gates.

## Campaign termination and build budget

Ledger path:
`/tmp/ms-keri-1/e274/cardano-keri-271/evidence/mutation-campaign.md`.

- Initialize all eight declared rows OPEN with `builds_spent=0` and
  `builds_budget=3`.
- A row becomes KILLED only after a named mutant is observed RED and a permanent
  property keeps it RED. These BLOCKING rows can end only KILLED or BLOCKED,
  never RESIDUAL.
- The intended stop is set-point: every row terminal.
- A tail round with no new class and no blocking finding may close advisory
  work only; it cannot close any OPEN row in this all-BLOCKING set.
- At three build checkpoints, any OPEN row causes
  `MUTATION-CAMPAIGN-OVERRUN`; further building work requires an explicit
  higher-scope budget decision. Reading/typecheck/interpreted work does not
  spend this build budget.
- Every build receipt records candidate identity, command, exit, evidence hash,
  and free space before/after. Reproducible build trees are retired after their
  evidence is frozen; source, receipts, reports, ledger, and instruments remain.

## Dependencies and shipping

| Dependency | Contract |
| --- | --- |
| #254 | **Selected vehicle.** Add S271-1/S271-2 before checkpoint-family acceptance and carry S271-3 in its registry/cutover slice. #254's versioned datum provides `ArmedV2`; its migration moves v0 state to the protected family. |
| #253 | No implementation dependency; it changes the endpoint board, not enforcement state. Share only #254 registry/cutover mechanics. |
| #163/#164 | Remain blocked until the entitlement-aware family is deployed; a specs-only or source-green state does not restore hunter incentives. |
| M8 | Register the new commitment and checkpoint compiled targets at acceptance and cutover; entitlement/age mutants are part of the proof surface. |
| Preproduction | Existing v0 remains exposed until #254's desk-gated migration. Preserve old manifest history and announce the protection boundary honestly. |

## Risks and controls

- **Commitment copied from the mempool:** marker/hash still bind the original
  payee and hidden nonce; copied commitment cannot pay the copier.
- **Attacker opens after seeing reveal:** one-slot age makes the reactive
  commitment too young.
- **Broad speculative commitments:** deposit lock, expiry sweep, exact input
  scope, and first-valid-reveal make speculation costly without granting a
  blocking first-commit right.
- **Hunter veto:** selection-time consent is stored; later fixed payments do
  not demand a new witness.
- **Counterfeit script output:** authenticated unique marker and policy checks
  distinguish a real commitment from value merely sent to the address.
- **Validator-size pressure:** heavy evidence/hash matching remains in the
  enforcement observer/shared layer; measure both applied programs and split
  further before weakening any invariant.
- **Version drift:** frozen v0 bytes stay historical; new constructors and
  parameters enter only the #254 successor registry.

## Artifact measurements

Provider-reported token counts are unavailable for local files. Actual
byte/line counts are filled from the committed mandate before publication.

| Artifact | Ceiling bytes / lines | Actual bytes / lines |
| --- | ---: | ---: |
| `spec.md` | 12,000 / 220 | 11,961 / 176 |
| `plan.md` | 12,000 / 240 | 9,010 / 154 |
| `modules-model.md` | 8,000 / 160 | 5,064 / 102 |
| `data-model.md` | 10,000 / 200 | 6,367 / 163 |
| `functions-model.md` | 8,000 / 160 | 5,384 / 105 |
| `tasks.md` | 8,000 / 180 | 4,740 / 88 |
