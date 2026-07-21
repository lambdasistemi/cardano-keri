# Plan: close a checkpoint and resolve ACTIVE state (#117)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/117
Draft PR: https://github.com/lambdasistemi/cardano-keri/pull/123

The implementation is four ordered, bisect-safe RED→GREEN commits. Slice 1
freezes Close message bytes and the pure controller predicate. Slice 2 opens the
live combined-validator Close path. Slice 3 adds the CIP-31 resolver and shared
candidate vectors. Slice 4 measures the final script/library shape and applies
the hard headroom gate.

This plan stops at Q-013 before any implementation or driver/navigator
dispatch. `gate.sh` remains present and PR #123 remains draft.

## Non-negotiable boundary

- There is no mint-once or global unicity invariant. Close burns one named
  checkpoint instance; the same AID and derived policy/name may Register later.
- #116 already delivered the generic deployment-fixed `d_reg`, its mechanical
  floor, and ACTIVE/FROZEN/TOMBSTONE roles. No slice edits those rules or adds a
  role.
- Close is ACTIVE-only and uses burn, not a CLOSED UTxO.
- Resolution authenticates exactly one candidate among the transaction's
  supplied reference inputs. It cannot prove an omitted UTxO does not exist.
- No registry, MPF, shared root, batcher, sequencer, or off-chain ordering
  service may enter the design.
- No slice touches `docs/` or any old specification.

## Technical context

### Existing validator surface

`onchain/validators/checkpoint.ak` is one applied script with mint and spend
handlers. The script hash is both the checkpoint policy id and the payment
credential of state outputs. `MintRedeemer.Register` is live;
`SpendRedeemer.Close` is currently fail-closed. Spend classification already
recognizes exact ACTIVE/FROZEN/TOMBSTONE role+datum pairs before dispatch.

The validator already checks `valid_registration_deposit(d_reg)` before both
mint and spend dispatch. That remains untouched except for ordinary compilation
around the new redeemer branches. The 1,000,000,000-lovelace fixture is
non-normative and the code remains generic over the deployment parameter.

### Close composition

The combined script executes twice in one Close transaction:

```text
MintRedeemer.CloseBurn(checkpoint_ref)
                 │
                 ├── authenticate named ACTIVE input + exact -1 own-policy burn
                 │
ACTIVE input ────┼── SpendRedeemer.Close(CloseEvidence)
                 │      ├── reconstruct signed CloseMessage
                 │      ├── current-controller threshold
                 │      ├── repeat exact -1 own-policy burn check
                 │      └── exact whole-input-minus-token refund
                 │
                 └── no checkpoint successor; ordinary fee inputs stay allowed
```

The spend-side check prevents unauthorized state release; the mint-side check
prevents the policy from burning an unrelated name without its named ACTIVE
state. The named input must be the transaction's only input carrying that
policy/name, and no output may carry it. Exact one-pair own-policy mint maps
make Close one checkpoint per policy per transaction and exclude
Register+Close composition.

### Resolution composition

The trusted caller supplies `checkpoint_policy_id` and raw `cesr_aid`. The
public Aiken adapter reads `Transaction.reference_inputs`, derives the asset
name, filters exact ACTIVE-address + quantity-one-token candidates, requires
exactly one, then decodes and validates inline V1 data. It returns the actual
outref+datum or `None`.

The pure shared model uses a `ReferenceInputView` so Haskell can generate the
same decision vectors without importing a transaction builder. The Aiken live
adapter, not the caller, projects actual reference inputs into that model. It
must filter on address+token before datum decoding so a malformed sibling
candidate cannot be ignored.

## Project structure

### Slice 1 additions

```text
offchain/lib/Cardano/KERI/AID/Checkpoint/Close.hs
offchain/test/Cardano/KERI/AID/Checkpoint/CloseSpec.hs
offchain/app/GenCloseVectors.hs
onchain/lib/cardano_keri/checkpoint/close.ak
onchain/lib/cardano_keri/checkpoint/close_tests.ak
onchain/lib/cardano_keri/checkpoint/close_vectors.ak       (generated)
```

Build/test/generator wiring changes in:

```text
offchain/cardano-keri.cabal
offchain/test/Main.hs
justfile
```

### Slice 2 changes

```text
onchain/validators/checkpoint.ak
onchain/validators/checkpoint_tests.ak
```

### Slice 3 additions

```text
offchain/lib/Cardano/KERI/AID/Checkpoint/Resolution.hs
offchain/test/Cardano/KERI/AID/Checkpoint/ResolutionSpec.hs
offchain/app/GenResolutionVectors.hs
onchain/lib/cardano_keri/checkpoint/resolution.ak
onchain/lib/cardano_keri/checkpoint/resolution_tests.ak
onchain/lib/cardano_keri/checkpoint/resolution_vectors.ak  (generated)
```

Build/test/generator wiring changes again in:

```text
offchain/cardano-keri.cabal
offchain/test/Main.hs
justfile
```

### Slice 4 additions/changes

```text
onchain/validators/checkpoint_close_lookup_measurements.ak
specs/117-close-lookup/MEASUREMENTS.md
justfile
```

`onchain/validators/checkpoint_measurements.ak` and the existing exact
`measure-checkpoint` row set remain unchanged unless compilation forces a
strictly mechanical import repair. Any semantic edit to the #116 measurement
matrix is a STOP/Q-file.

## Slice 1 — Close message and controller predicate (T117-S1)

### RED

Add failing Haskell and Aiken tests/vectors for:

- the exact `cardano-keri/checkpoint/close/v1` domain, constructor 0, ten-field
  order, canonical-CBOR bytes, and full refund-address encoding;
- reconstruction from deployment, named outref, OLD datum, and evidence;
- valid two-key and GLEIF seven-key current-controller thresholds;
- below-threshold, bad/out-of-range, duplicate-inflated, wrong-key, and mutated
  message fields, including refund address and spent outref; and
- replay of an otherwise-valid signature against a fresh outref.

RED must fail because no Close model, message, generator, or drift recipe
exists. The navigator reviews `red.diff` before production work.

### GREEN

Implement one validator-free Close model in each language. Reuse the existing
canonical Plutus-Data CBOR, Ed25519 verification, distinct-index handling, and
threshold evaluator; do not introduce a second threshold algorithm. Define an
explicit Haskell full-address Plutus-Data representation that is byte-identical
to Aiken `Address`, and freeze it with generated bytes.

`CloseEvidence` contains only the full refund address and indexed controller
signatures. Reconstruct all other message fields from trusted context. The pure
predicate returns a typed rejection/verdict suitable for shared vectors.

Add generator and drift recipes following the existing registration/advance
idiom. Run focused Haskell/Aiken tests, generation twice, drift checks, and the
full gate.

### Owned files

- `offchain/lib/Cardano/KERI/AID/Checkpoint/Close.hs` (new)
- `offchain/test/Cardano/KERI/AID/Checkpoint/CloseSpec.hs` (new)
- `offchain/app/GenCloseVectors.hs` (new)
- `offchain/cardano-keri.cabal`
- `offchain/test/Main.hs`
- `onchain/lib/cardano_keri/checkpoint/close.ak` (new)
- `onchain/lib/cardano_keri/checkpoint/close_tests.ak` (new)
- `onchain/lib/cardano_keri/checkpoint/close_vectors.ak` (generated)
- `justfile`

Exact commit: `feat(117): define controller-authorized close` with exactly
`Tasks: T117-S1`.

## Slice 2 — live ACTIVE Close burn and refund (T117-S2)

### RED

Add full-context Aiken tests that exercise both the combined script's mint and
spend sides. The honest ACTIVE close must initially fail because Close is not
dispatched and no burn redeemer exists. Add the C6 adversarial cases before
GREEN, including ACTIVE-only classification, exact one-pair burn, wrong named
input, signature/refund mutation, under-refund by lovelace or unrelated asset,
refund remaining at the checkpoint payment credential, a second input carrying
the same policy/name, and any output carrying that burned name.

Add an executable close-then-register scenario demonstrating that the next
ordinary Register for the same AID/name still passes existing R1–R8 and fixed
bond checks. This is a regression guard against mint-once drift, not a new
Register implementation.

### GREEN

Change `MintRedeemer` to add `CloseBurn { checkpoint_ref }` and change
`SpendRedeemer.Close` to carry `CloseEvidence`. The mint branch resolves and
authenticates the exact ACTIVE input and its single derived token, then accepts
only the exact `-1` map and no sibling input carrying the same policy/name. The
spend dispatch admits Close only from `ActiveCheckpoint`; FROZEN/TOMBSTONE
remain rejected.

The spend handler runs the S1 predicate, repeats the exact own-policy burn, and
requires one dedicated output at the signed non-checkpoint address with value
equal to the complete input minus the burned token. It permits unrelated fee
inputs/change but no other target-token input and no output carrying the target
token. Reuse role/address, datum,
asset-name, and value helpers already in the repository.

Run focused full-context tests and the complete gate. Audit the diff for any
new role, `d_reg` change, shared state, MPF, or Register admission check.

### Owned files

- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_tests.ak`

Exact commit: `feat(117): close active checkpoints by burn` with exactly
`Tasks: T117-S2`.

## Slice 3 — CIP-31 ACTIVE resolver and parity (T117-S3)

### RED

Add shared Haskell/Aiken L6 vectors and live Aiken transaction tests. RED must
show that no public helper can yet resolve an exact ACTIVE reference input.
Cover success with unrelated refs and a historical same-AID TOMBSTONE, plus
absence, ordinary-input-only, FROZEN, TOMBSTONE, wrong policy/name/address,
quantity errors, datum-hash/no-datum/non-V1/malformed/mismatched-AID cases,
two matching candidates, and valid+malformed same-token ambiguity.

The Aiken tests must construct complete `Transaction` values and populate
`reference_inputs`; a prefiltered list-only test does not satisfy the live
adapter boundary.

### GREEN

Implement the small shared candidate model and generated vectors. Add public
Aiken `resolve_active_checkpoint(policy, aid, tx)` returning
`Option<ResolvedCheckpoint>`. Derive the token name internally; filter exact
full ACTIVE address and token quantity before datum parsing; require exactly
one supplied candidate; decode inline V1; run datum well-formedness; bind AID;
return actual outref+datum.

Keep the API explicitly local to supplied reference inputs. Comments/tests may
recommend an exhaustive off-chain address query but must not claim the helper
detects omitted global duplicates. Add no indexer, builder, batcher, service,
or new role.

Generate twice, prove Haskell/Aiken drift stability, run focused tests, and run
the full gate.

### Owned files

- `offchain/lib/Cardano/KERI/AID/Checkpoint/Resolution.hs` (new)
- `offchain/test/Cardano/KERI/AID/Checkpoint/ResolutionSpec.hs` (new)
- `offchain/app/GenResolutionVectors.hs` (new)
- `offchain/cardano-keri.cabal`
- `offchain/test/Main.hs`
- `onchain/lib/cardano_keri/checkpoint/resolution.ak` (new)
- `onchain/lib/cardano_keri/checkpoint/resolution_tests.ak` (new)
- `onchain/lib/cardano_keri/checkpoint/resolution_vectors.ak` (generated)
- `justfile`

Exact commit: `feat(117): resolve active checkpoint references` with exactly
`Tasks: T117-S3`.

## Slice 4 — close/lookup measurements and acceptance gate (T117-S4)

### RED

Add a #117-specific measurement module, exact title-set recipe, and report
expecting the eight rows from the specification. RED fails on missing rows or
placeholder values. The full close transaction acceptance rows must be raw
spend+mint sums, not either script in isolation.

### GREEN

Measure:

- two-key and GLEIF seven-key Close spend handlers;
- their matching CloseBurn mint handlers;
- mechanical raw memory/CPU sums for each complete Close transaction; and
- two-key and GLEIF seven-key resolver calls over full transaction reference
  fixtures.

Record raw units, percent used, and headroom in `MEASUREMENTS.md`. All fixtures
use the non-normative 1,000,000,000-lovelace `d_reg`. Add
`just measure-close-lookup` without modifying the existing #116 exact-nine
acceptance matrix.

Any memory result above 10,500,000, CPU result above 7,500,000,000, missing
full-transaction sum, weakened fixture, or unexpected #116 measurement change
is a hard STOP before commit and opens the next epic Q-file. If green, run the
full aggregate gate once more.

### Owned files

- `onchain/validators/checkpoint_close_lookup_measurements.ak` (new)
- `specs/117-close-lookup/MEASUREMENTS.md` (new)
- `justfile`

Exact commit: `test(117): measure close and reference lookup` with exactly
`Tasks: T117-S4`.

## Slice ordering and bisect safety

1. S1 adds unused pure/library surfaces and vector gates; existing live paths
   are unchanged.
2. S2 consumes the already-green S1 predicate and changes mint+spend together,
   so no commit exposes a burn policy without controller-authorized custody
   release or vice versa.
3. S3 is an independent read-only library addition over the final address/datum
   shapes. It never mutates checkpoint state.
4. S4 changes only measurement fixtures/reporting and their recipe after the
   implementation shape is final.

Every slice ends at a buildable, full-gate-green HEAD. Generated code and its
generator land in the same commit. No intermediate commit changes O3/O4,
introduces CLOSED, or bars re-registration.

## Pair and review protocol after Q-013

- Persistent driver: pane `%2921`, Codex `gpt-5.6-sol/high`, bypass flags.
- Persistent navigator: pane `%2894`, Claude Sonnet, bypass flags.
- Each slice receives a written brief naming its exact task id, owned files,
  RED command, GREEN acceptance, forbidden scope, and commit subject/trailer.
- Driver writes RED, publishes `red.diff`, and waits for navigator approval;
  then writes GREEN, publishes `green.diff`, and waits again before one commit.
- Navigator vetoes skipped RED, weakened fixtures, broad edits, parity drift,
  mint-once language/mechanism, or a commit without the exact task trailer.
- Workers never edit planning artifacts, `gate.sh`, PR metadata, `docs/`, or old
  specifications; they never push.
- The ticket owner reviews every changed file and the actual commit, runs a
  fresh focused gate plus `./gate.sh`, checks only accepted slice tasks, amends
  that same slice commit, and pushes with force-with-lease.

## Verification commands

Exact focused recipe names may be added by the owning slice, but the acceptance
shape is fixed:

```text
./gate.sh
just check-onchain
just unit
just gen-close-vectors
just check-close-vectors
just gen-resolution-vectors
just check-resolution-vectors
just measure-close-lookup
```

The driver must use repository-provided Nix/just tooling rather than ambient
unpinned compilers. Generator drift checks compare committed output after two
runs. The final aggregate remains the root `just ci` through `gate.sh`.

## Live-boundary disposition

The delivered boundary is an on-chain helper reading the actual Aiken
`Transaction.reference_inputs`, so complete transaction fixtures are mandatory
inside S3. #117 does not ship a node-query client, UTxO indexer, wallet builder,
or submitter; therefore it cannot honestly demonstrate exhaustive live UTxO
discovery or a reference-vs-spend race against a node. That live boundary is a
named downstream #44 integration obligation, not a reason to add an off-chain
service here.

## Risks and stop conditions

- **Global-unicity overclaim:** accepting one supplied reference does not prove
  no omitted duplicate exists. Any contrary API/comment/test claim stops S3.
- **Containment bypass:** admitting Close from FROZEN lets current/stale keys
  defeat Freeze. Only ordinary Advance may restore closeability.
- **Burn/refund split-brain:** mint and spend must name the same ACTIVE outref,
  asset, and exact burn. Both sides land in S2 together.
- **Refund theft or underpayment:** the full address is signed and a dedicated
  exact-value output is mandatory; fees cannot be taken from checkpoint value.
- **Replay:** network, policy, outref, AID/name, old sequence, and refund address
  are message-bound. A fresh registration necessarily has a fresh outref.
- **Address codec drift:** Haskell and Aiken must freeze the same full-address
  Plutus Data and canonical CBOR; vector bytes, not structural intuition, are
  the gate.
- **Existing-path regression:** Register/Advance/Freeze/Convict and #116
  measurement rows stay green and unchanged outside mechanical compilation.
- **Budget miss:** less than 25.00% headroom on any required axis or failure to
  sum both close scripts is an immediate Q-file blocker.
- **Scope drift:** any new role, `d_reg` logic, MPF/shared state, docs/old-spec
  edit, batcher, or pair dispatch before A-013 stops work.

## Planning checkpoint

Q-013 asks the epic owner to ratify the five open points in `spec.md` and this
four-slice decomposition. No production/test/fixture/build-wiring implementation
begins until the answer is consumed and logged.
