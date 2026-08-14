# Checkpoint version-remnant audit

**Slice:** #254 S254-R / T254-109 — register deployment arity and version-remnant repair.
**Standing check:** `just check-version-remnant-sweep`
(`scripts/check-version-remnant-sweep.sh`, plus
`s254_r_version_remnant_sweep_is_complete` in `ScriptAritySpec.hs`).

## Why this document exists

The #254 family cut the version integer. Cutting a pervasive feature does not
remove it in one place; it scatters remnants that surface one at a time, and
each one is found by whoever trips over it next. Two had already surfaced —
the #253 sequence field, then the register's stray applied argument — so this
audit stops enumerating remnants by accident and starts enumerating them by
rule.

## What the arity defect actually was

`checkpoint_register` declares eight applied parameters. `deriveV1Scripts`
applied nine: a leading `v1CheckpointVersion` left over from the cut feature.

A ninth argument applied to an eight-parameter program does not partially
apply anything. It lands in the slot the ledger fills with the script context.
Every identity the branch derived from that program — the `checkpoint-register`
script hash, its policy id, and `checkpointAddress` — therefore belonged to a
program that could not have settled a transaction. The branch had no settleable
register identity at any point in its history: before `449b14d` the register
declared nine parameters and the derivation applied eight, and `449b14d`
replaced `version, predecessor_policy` with `migration_hash` on the validator
without removing `version` from the derivation.

The corrected eight-argument applied program is this branch's **first**
canonical register identity. No prior register hash was ever settleable, so
nothing is being invalidated by correcting it.

## The rule that replaces the enumeration

A version reference is legitimate exactly when something concrete consumes it.
For an applied argument that means: **the blueprint declares a version-shaped
parameter at that position.** For a serialized field it means: **settled bytes
that must keep parsing.**

That rule is enforced twice, from two directions, because a single instrument
would have to be trusted on both the structural and the textual question:

| Question | Instrument |
|---|---|
| Does every version argument land on a declared version parameter, and does the register declare and apply none? | `s254_r_version_remnant_sweep_is_complete`, structurally, over the live blueprint and the derived artifacts |
| Is any version reference left in deployment/derivation/serialization/manifest code that nothing consumes? | `scripts/check-version-remnant-sweep.sh`, textually, over the declared surfaces |
| Is **every live blueprint validator group** either bound to a recovered applied count or explicitly classified as unapplied? | `s254_r_every_blueprint_group_is_bound_or_unapplied` |
| Is **every place in the repository that applies arguments** to a program classified, with an exact call count? | the application-site census in `scripts/check-version-remnant-sweep.sh` |

The last two exist because "every validator" is not "every artifact the
derivation publishes". The publication list covers seven groups; the live
blueprint carries nine, and a program applied somewhere outside that list would
keep a deployment identity that no parity check ever saw. The group census
requires exact set equality between the blueprint's groups and an explicit
classification, so a new group fails as unclassified and a stale classification
fails as vanished. The site census requires an exact executable call count per
row, so a new call added to a file that already has a row cannot inherit that
row's rationale in silence.

`cage.mpfCage` is the interesting case: `applyParams` is a real production
application boundary that does **not** run through `mkAppliedArtifact`, because
its only consumer, `offchain/e2e/CageTxBuilder.hs`, is outside this slice's
fence. It is bound rather than excused — the group census drives that exact
production applier and structurally recovers the two arguments it applied,
comparing them against `mpfCage`'s declared parameter count.

Neither writes down a count. The declared arity comes from the blueprint's own
`parameters` array; the applied arity is recovered from the artifact's bytes
and verified by re-applying the recovered list and requiring byte-identical
output. A duplicated hand-authored `8` on both sides would have passed
throughout the period the branch was broken, which is precisely why the parity
is never expressed that way.

## What the sweep found

Three cuts, verified absent on every run:

| Cut | Where | By |
|---|---|---|
| `register-applied-version-argument` | `applyCheckpointParams`' plan | S254-R |
| `register-derivation-version-argument` | the `appliedCheckpoint` call in `deriveV1Scripts` | S254-R |
| `register-declared-version-parameter` | `onchain/validators/checkpoint_register.ak` | T254-104, held absent here |

Nine retained references, each with a consumer the script checks still exists:

| Surface | Reference | Concrete consumer |
|---|---|---|
| `Script.hs` | `v1CheckpointVersion` | `deploy/preprod/m1-manifest.json` carries `"checkpointVersion"`; applied only where the blueprint declares a version parameter |
| `Script.hs` | `applyParams version` / `I version, B predecessorPolicy` | `onchain/validators/cage.ak` declares `mpfCage(_version: Int, predecessorPolicy: PolicyId)`; applied by `offchain/e2e/CageTxBuilder.hs` |
| `Script.hs` | `applyLifecycleParams version` | `observer_lifecycle(_version: Int, …)` declares it as its first parameter |
| `Script.hs` | `applyAdvanceParams version` / `[I version]` | `observer_advance(_version: Int)` and `observer_enforcement(_version: Int)` declare it as their only parameter |
| `Script.hs` | `versionTag` | the UPLC **program-format** version field, unrelated to the checkpoint family; carried through so an applied argument keeps the program's own encoding |
| `Manifest.hs` | `parameterCheckpointVersion` / `checkpointVersion` | `deploy/preprod/m1-manifest.json` carries `"checkpointVersion":0`; cutting the field would make the settled preprod manifest unparseable |
| `Manifest.hs` | `manifestSchemaVersion` | the deployed manifest's own `"schema"` identifier |
| `EndpointBoardManifest.hs` | `endpointBoardManifestSchemaVersion` | `deploy/preprod/board-manifest.json`'s `"schema"` identifier |
| `checkpoint_observer.ak` | `_version: Int` ×3 | the declared applied parameters the deployment supplies |

Fourteen files under `deploy/preprod` carry a version reference. They are
settled history, reported as **ADVISORY** and never rewritten: the immutable M1
fixture and its acceptance transcripts are read-only evidence about what was
deployed, not a description of what the derivation now produces. The branch
already diverged from the deployed family when S254-1 added `observer-migration`
as a sixth artifact.

## Retained is not "legacy"

The word `legacy` is not an argument, and the script does not accept one. Every
retained row names a file and a pattern, and the run fails if that consumer has
disappeared — a permission that outlives its reason is how a census becomes
decoration. It fails equally if a retained row no longer matches anything,
because a stale row is a rule nobody is testing.

## Showing the scanner can fail

`./scripts/check-version-remnant-sweep.sh --self-test` seeds mutations into
isolated temporary copies and requires the same scanner, unmodified, to reject
each one. It runs before every real sweep, so the pass is only believed after
the failure has been demonstrated:

| Leg | Seeded into a temporary copy | Required |
|---|---|---|
| `green` | nothing | accepts the valid corrected derivation call |
| `injected` | an unallowlisted `v1InjectedVersionRemnant` on an active surface | rejects |
| `returned_cut` | `v1CheckpointVersion` back inside the `appliedCheckpoint` call | rejects |
| `stale_consumer` | `"checkpointVersion":0` removed from the copied manifest | rejects |
| `unclassified_site` | an `applyDataArgs` call in a file with no site row | rejects |
| `absorbed_site` | an **extra** `applyDataArgs` call in a file that already has one | rejects |
| `stale_site` | `applyProgram` renamed so a site row matches nothing | rejects |
| `stale_row` | `versionTag` renamed so a retained row matches nothing | rejects |

`absorbed_site` is the leg that makes the site census mean something within a
file and not merely across files: before the row carried an exact count, a new
call beside an existing one inherited that row's class and rationale without
anyone noticing.

The group census carries its own three negative controls, in Haskell rather
than in the scanner, because it is a fact about the parsed blueprint: it is
shown rejecting a blueprint with a new group, one with a group removed, and one
with a duplicated validator title.

The `green` leg is what distinguishes this from a scanner that rejects
everything, and it is also what proves the structural derivation check accepts
a valid call rather than merely noticing that `applyCheckpointParams` is
called. The self-test earned its keep immediately: the first `injected` control
seeded a symbol whose name contained no `version` substring, so it tested
nothing, and the leg reported that instead of quietly passing.

## What this audit does not establish

- That the blueprint's `compiledCode` is itself unapplied. The parity check
  establishes that an artifact equals the blueprint program plus exactly the
  recovered arguments; a program that arrived from the toolchain with arguments
  already applied would satisfy that without being caught. Nothing in this
  repository checks it.
- That the corrected register behaves correctly. `just checkpoint-register-blaster`
  executes the compiled program and establishes where its parameter surface
  ends — that it settles at eight applied parameters and adjudicates a ninth —
  not that any of its handlers implement the intended rules.
- That the four policy hashes the compiled-target evidence applies are the real
  sibling hashes. They are placeholders of the correct width; the applied
  identity in the M8 target row comes from the production derivation, bound to
  the executed program by requiring both to read a program with the same
  SHA-256.
