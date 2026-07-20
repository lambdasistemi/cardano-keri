# Plan: enforcement wiring — unicity redesign (#116)

The accepted S1, S2, and S4 commits remain frozen. The delivered S3, S5, and
S6 commits also remain in history, but A-009 supersedes their append-on-Register
and free-bounty behavior. Four corrective, bisect-safe commits land on top:
reference-read registration, conviction-list bootstrap and parameter floor,
the complete Convict-to-cash-out vertical path, then fresh measurements.

Every corrective slice uses the persistent driver/navigator pair and lands one
RED→GREEN commit. No slice rewrites an already-pushed commit. `just ci` remains
the mechanical gate body; `gate.sh` stays present while this redesign is in
flight. The PR remains draft and is not re-finalized by this plan.

## Frozen and superseded history

| Existing slice | Disposition |
| --- | --- |
| S1 `4d8948b` | FROZEN: keripy enforcement offsets and byte preservation |
| S2 `6807096` | FROZEN: EE0–EE9 binding, distinct receipts, `kt` conflict axis |
| S3 `8837f19` | SUPERSEDED: shared registration-write mechanics replaced by S7/S8 |
| S4 `da363e7` | FROZEN: Freeze and ordinary-Advance thaw |
| S5 `5916555` | SUPERSEDED: mint-nothing/free-change Convict replaced by S9 |
| S6 `653bcfb` | SUPERSEDED MEASUREMENTS: retained as historical rows, replaced by S10 |

## Final module map

| Artifact | Redesign fate |
| --- | --- |
| `onchain/patches/mpf-v2.0.0-excludes.patch` | NEW: one-line public `excludes` wrapper over v2.0.0's private traversal |
| `justfile` | AMEND: reproducibly and idempotently apply/assert the pinned MPF patch before every Aiken build/check/vector/measurement path |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Unicity.hs` + spec | AMEND: conviction labels, absence/membership/insert roots, right/claim derivations, floor vectors |
| `offchain/app/GenUnicityVectors.hs` + generated Aiken vectors | AMEND: one source for conviction bootstrap, proofs, roles, rights, and floor boundary |
| `offchain/e2e/Cardano/KERI/AID/E2E/MpfProof.hs` | AMEND only for the required exclusion/inclusion proof roots; do not create a second MPF implementation |
| `onchain/lib/cardano_keri/checkpoint/unicity.ak` + tests | AMEND: read-only absence, permanent-marker insert/membership, conviction thread, bounty claim/right primitives |
| `onchain/lib/cardano_keri/checkpoint/role.ak` + tests | AMEND: retain tags `0x00..0x02`, add BOUNTY `0x03` |
| `onchain/validators/checkpoint.ak` | AMEND: reference-read Register, conviction bootstrap, sovereign Convict, BOUNTY custody, two-mode cash-out |
| `onchain/validators/checkpoint_registry_tests.ak` | AMEND: focused bootstrap, live-root, Finalize/Redeem, and race families |
| `onchain/validators/checkpoint_tests.ak` | AMEND: Convict/custody/terminality and unaffected lifecycle regressions |
| `onchain/validators/checkpoint_measurements.ak` | AMEND in every behavior slice to keep the suite compiling; populate final matrix in S10 |
| `specs/116-enforcement/MEASUREMENTS.md` | AMEND in S10: old write-on-Register rows marked superseded; new complete transaction sums recorded |
| `offchain/cardano-keri.cabal`, `offchain/test/Main.hs` | AMEND only when the existing generated-vector/unit-test wiring requires it |

The MPF dependency remains pinned at `aiken-lang/merkle-patricia-forestry`
v2.0.0. The source-controlled patch changes only visibility by adding:

```text
pub fn excludes(self, key, proof) -> Bool {
  excluding(key, proof) == self.root
}
```

The preparation recipe must fail if the pinned source no longer matches or the
patch is neither already applied nor cleanly applicable. Register calls this
single-traversal helper; discarding the result of `insert` is not the final
implementation.

## Corrective slices

### Slice 7 — reference-read Register and MPF absence (T116-S7)

Convert the delivered S3 Register gate from a consumed registry input to an
authenticated reference read while retaining the current bootstrap labels for
one intermediate green commit. Remove `RecordRegistration` and every
per-registration root successor. Resolve the redeemer's named reference only
from `tx.reference_inputs`, require the exact REGISTRY address, quantity-one
thread token, inline root datum, and prove the AID key absent against that root
with the patched `mpf.excludes` helper.

RED first proves that the delivered handler consumes/writes the singleton.
GREEN covers U1–U3: missing/wrong/stale references, wrong address/token/datum/
root/proof, attempts to spend or continue the list, thread mint/burn, present
AID, and both unrelated and same-AID absent registrations sharing one live
reference without a shared spend. Add `check-unicity-vectors` to the aggregate
`just ci` dependencies so generated-root drift cannot pass `gate.sh`. R1–R8 and
the accepted S2/S4 tests stay green.

Owned files:

- `onchain/patches/mpf-v2.0.0-excludes.patch`
- `justfile`
- `offchain/lib/Cardano/KERI/AID/Checkpoint/Unicity.hs`
- `offchain/test/Cardano/KERI/AID/Checkpoint/UnicitySpec.hs`
- `offchain/app/GenUnicityVectors.hs`
- `offchain/e2e/Cardano/KERI/AID/E2E/MpfProof.hs`
- `offchain/cardano-keri.cabal` and `offchain/test/Main.hs` only if wiring changes
- `onchain/lib/cardano_keri/checkpoint/unicity.ak`
- `onchain/lib/cardano_keri/checkpoint/unicity_tests.ak`
- `onchain/lib/cardano_keri/checkpoint/unicity_vectors.ak`
- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_registry_tests.ak`
- `onchain/validators/checkpoint_tests.ak`
- `onchain/validators/checkpoint_measurements.ak`

Exact commit: `feat(116): make registration read the conviction root` with
exactly `Tasks: T116-S7`.

### Slice 8 — conviction-list bootstrap and parameter floor (T116-S8)

Replace the intermediate registration-era labels with the ratified V1
conviction contract: applied `conviction_seed`, `BootstrapConvictionList`,
`ConvictionListDatumV1`, conviction-thread/marker domains, and an empty,
single, permanently caged REGISTRY state. There is no RecordRegistration,
delete, update, split, merge, burn, Close, or migration path.

Add the BOUNTY `0x03` role and shared Haskell/Aiken derivations for
`BountyClaimDatumV1` and the unique right name over
`(domain, cesr_aid, checkpoint_ref)`. Preserve the existing role domain and
tags byte-for-byte. Apply the validator with generic `d_reg`; every entry point
fails when `d_reg < 5_000_000`, while all deposit equations use the applied
parameter rather than a security constant. Boundary fixtures use 5,000,000
only for the mechanical floor and retain the 4,999,999 negative; ordinary
behavior fixtures use the non-normative 1,000 ADA reference.

RED covers U4, old-domain/constructor acceptance, second bootstrap, non-empty
root, wrong seed/address/thread quantity, thread escape, and the one-below
parameter. GREEN proves the one-shot empty bootstrap, exact roles/domains,
cross-language vectors, and unchanged reference-read registration.

Owned files:

- `offchain/lib/Cardano/KERI/AID/Checkpoint/Unicity.hs`
- `offchain/test/Cardano/KERI/AID/Checkpoint/UnicitySpec.hs`
- `offchain/app/GenUnicityVectors.hs`
- `offchain/cardano-keri.cabal` and `offchain/test/Main.hs` only if wiring changes
- `onchain/lib/cardano_keri/checkpoint/unicity.ak`
- `onchain/lib/cardano_keri/checkpoint/unicity_tests.ak`
- `onchain/lib/cardano_keri/checkpoint/unicity_vectors.ak`
- `onchain/lib/cardano_keri/checkpoint/role.ak`
- `onchain/lib/cardano_keri/checkpoint/role_tests.ak`
- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_registry_tests.ak`
- `onchain/validators/checkpoint_tests.ak`
- `onchain/validators/checkpoint_measurements.ak`

Exact commit: `feat(116): bootstrap the parameterized conviction list` with
exactly `Tasks: T116-S8`.

### Slice 9 — sovereign Convict plus Finalize/Redeem (T116-S9)

Land the complete bounty lifecycle as one usable vertical commit; do not leave
claims locked at an intermediate HEAD. Convict remains sovereign and never
touches the conviction list. It admits ACTIVE|FROZEN, receives the applied
`d_reg`, keeps the exact F11-terminal tombstone, mints one unique bearer right,
and creates one dedicated BOUNTY claim holding
`bounty_claim_min_ada + seized_lovelace`, where `seized_lovelace` is the whole
checkpoint surplus and is at least the applied `d_reg`. Tombstone floor,
claim min-ADA, fees, and ordinary change are separately funded; no seized
lovelace is retained, burned, paid as free change, or used as a fee haircut.

Add both cash-out modes in the same commit. Absent mode consumes the live
singleton, proves exclusion, inserts the exact convicted marker, creates one
byte-value-preserving REGISTRY successor, burns all paired same-AID rights,
spends their claims, and pays each complete seized amount to the address of the
input carrying that right. Present mode binds the current singleton as an
exact reference input, proves `mpf.has`, creates no root successor, and performs
the same burns/claim payouts. The mint/burn policy, REGISTRY spend, BOUNTY
spends, proofs, and payout sums are bidirectionally welded. Claim single-spend
plus right burn makes redemption one-time.

RED covers B1/B2, P1–P3, X1/X2, F11, and F13-L, including right misnaming,
claim mismatch, free-change release, fee haircut, missing separate funding,
unwelded root update/payout, stale root, mixed-AID aggregation, wrong bearer
payout, replay, two first-finalizer retry, and multi-cycle rights after the
first insertion. GREEN keeps Freeze/thaw, role encoding, R1–R8, distinct
receipts, and the `kt` conflict axis unchanged.

Owned files:

- `offchain/lib/Cardano/KERI/AID/Checkpoint/Unicity.hs`
- `offchain/test/Cardano/KERI/AID/Checkpoint/UnicitySpec.hs`
- `offchain/app/GenUnicityVectors.hs`
- `offchain/cardano-keri.cabal` and `offchain/test/Main.hs` only if wiring changes
- `onchain/lib/cardano_keri/checkpoint/unicity.ak`
- `onchain/lib/cardano_keri/checkpoint/unicity_tests.ak`
- `onchain/lib/cardano_keri/checkpoint/unicity_vectors.ak`
- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_registry_tests.ak`
- `onchain/validators/checkpoint_tests.ak`
- `onchain/validators/checkpoint_measurements.ak`

Exact commit: `feat(116): weld conviction bounties to finalization` with
exactly `Tasks: T116-S9`.

### Slice 10 — replacement measurements and report (T116-S10)

Measure the settled live ACCEPT paths and replace the acceptance evidence in
`MEASUREMENTS.md` without deleting the old S6 history. Rows cover Freeze,
sovereign Convict with right plus claim, conviction bootstrap, reference-read
Register at absence depths 0/8/16, absent-mode Finalize at depths 0/8/16 for
one and multiple same-AID rights, and present-mode Redeem at inclusion depths
0/8/16 for one and multiple rights.

Every transaction row sums every live script execution in that transaction,
reports raw memory/CPU, percentages, headroom, and distinguishes typed handler
costs from ledger deserialization. Any cell below 25.00% headroom on either axis
stops before commit and opens an epic Q-file; fixture weakening, depth
substitution, or calling a summed estimate a live-node measurement is forbidden.
All rows apply `d_reg = 1_000_000_000` lovelace as the reference measurement
parameter; the validator remains generic and the report labels it non-normative.
Retain the existing SAID non-recomputation comparison and rationale when the
old S6 rows are marked superseded.

Owned files:

- `onchain/validators/checkpoint_measurements.ak`
- proof/vector sources above only if needed to materialize the declared depths
- `specs/116-enforcement/MEASUREMENTS.md`
- `justfile` only if the measurement recipe itself is incomplete

Exact commit: `test(116): remeasure lazy conviction enforcement` with exactly
`Tasks: T116-S10`.

## Slice ordering and bisect safety

S7 first removes the rejected hot-path shared write while keeping the current
bootstrap surface, so its HEAD already permits concurrent Register. S8 then
renames and freezes the deployment topology and parameter floor without
opening a spendable claim. S9 opens Convict custody and both cash-out modes
together, so no committed HEAD creates an unredeemable bounty. S10 measures
only the settled script and cannot weaken earlier checks. Each intermediate
HEAD builds, runs the full gate, and retains all unaffected accepted behavior.

## Review and gate obligations

- Driver writes RED, publishes `red.diff`, waits for navigator RED approval,
  writes GREEN, publishes `green.diff`, and waits for GREEN approval before the
  one commit. Navigator verifies the committed diff after commit.
- Workers never edit `specs/116-enforcement/{spec,plan,tasks}.md`, `gate.sh`, PR
  metadata, or sibling protocol files; workers never push.
- The ticket owner reviews every changed file and commit message, reruns a fresh
  `./gate.sh`, checks only that slice's task boxes, amends the same commit, and
  pushes with force-with-lease. A pushed slice is frozen.
- Generated vectors are Haskell-sourced and drift-stable. The MPF patch is
  pinned, minimal, idempotent, and part of every Aiken gate path;
  `check-unicity-vectors` is an aggregate `just ci` dependency.
- `d_reg = 5_000_000` appears only in mechanical boundary tests. Ordinary
  fixtures and measurements use the non-normative 1,000 ADA reference; no code
  or report may call either value the deployed security choice, which is made
  when the contract is deployed.
- Any measurement miss, patch/pin ambiguity, payout-accounting ambiguity,
  analyzer surprise, or cross-slice scope change is a Q-file blocker.
- Finalization is outside this execution pass. `gate.sh` remains present, PR
  #121 remains draft, and neither `gh pr ready` nor merge may run.

## Risks

- **Dependency patch drift.** The one-line public wrapper is load-bearing. The
  preparation recipe must prove the v2.0.0 source and fail loudly on drift.
- **Live-root substitution.** Exact REGISTRY address plus quantity-one thread
  token and inline-datum root are inseparable; accepting a caller root is a
  permanent-conviction bypass.
- **Multi-script weld.** Policy mint/burn, REGISTRY and BOUNTY spends, claim
  sums, and bearer-input destinations must agree in both directions.
- **Intermediate usability.** S9 is intentionally larger than the other
  slices because Convict custody without Finalize/Redeem would strand claims.
- **Economics language.** The 5 ADA floor is mechanical and the 1,000 ADA
  fixture is a reference/expected value. Only contract deployment pins the
  actual validator parameter; honest Close recovery remains #117.
