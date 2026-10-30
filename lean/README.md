# The M1 identity model

As an identity owner, keep a checkpoint alive — bonds, rotations, freeze and
unfreeze — until it is convicted; there is no owner exit, no parking and no
revival. As a relying party, see a checkpoint that is either alive or
convicted, and refuse pending outputs. Conviction starts pending termination;
an associated consuming fold completes retirement.

The project uses Lean 4.27.0 and the public Singular pin below. Checkpoint owns
the funded lifecycle; Registry is the imported economic transport adapter.
The prose in each theorem comment states its complete Given/When/Then contract.
The model is not a claim of production validator or builder conformance.

## Build and inspect

```sh
cd lean
lake build
lake build CardanoKeriStatements
lake env lean --run AxiomInventory.lean
```

Use the repository's pinned compiler, through elan or
`nix shell --no-write-lock-file .#lean --command lake build`. The compiled
axiom inventory includes module-owned public, private and generated declarations;
the allowed trust set is exactly `propext`, `Quot.sound` and `Classical.choice`.
The traceability gate performs a clean build and checks exact contract types.

## Model and proof ownership

| Source | Responsibility |
| --- | --- |
| `Checkpoint.lean` | Local states/actions, addressed flow, concrete evidence, executable mirror, associated SysStep and SysReach |
| `CheckpointGoals.lean` | Local and system invariants, inversions, executable equivalence and consumer refusal |
| `CheckpointCompletionGoals.lean` | Stored origin, whole pending entry, request/key binding and completion consequences |
| `CheckpointCertificate.lean`, `CheckpointSystemEvidence.lean` | Executable certificates and their actual SysStep proofs |
| `Registry.lean`, `RegistryAgreement.lean` | Complete generic booking/fold/recovery execution and projection correspondence |
| `RegistryInvariant.lean`, `RegistryReach.lean`, `RegistryCompleteness.lean` | Well-formedness, reachable preservation and complete reconstruction |
| `RegistryCustody.lean`, `RegistryBurns.lean`, `RegistryAuthorization.lean` | Whole pending custody, fold-only retirement and application authorization |
| `RegistryGoals.lean` | Numbered consequences and inversions |
| `Samaritan.lean` | Booking conservation and conditional actual-fold addressed accounting |

Supporting metadata/fold/termination modules prove the intermediate list and
projection lemmas. `RegistryReplay.lean` replays a fixed context.
`RegistryAdapterFacts.lean` proves construction exclusions used by the finite
refusal inventory; an excluded construction is not an executed refusal.

## Stories, executions and mutation evidence

The canonical reader register is `simulator/M1-STORIES.md`; Registry stories
live in `simulator/REGISTRY-STORIES.md`. Stable story IDs retain explicit
migration records. `CheckpointTraceDriver.lean` emits local wire-v2 traces,
grid and stories. `RegistryTraceDriver.lean` emits wire-v3 complete economic
transactions; `CheckpointSystemDriver.lean` emits the associated system's
connected 34-cell journeys. Local cases alone do not establish SysReach.

`CheckpointLifecycleExamples.lean` and `RegistryLifecycleExamples.lean`
provide connected witnesses. Runtime subjects in the project root check full
successors, addressed flows and named refusals. Current mutation manifests and
the runner live in `retained-parking/`; model/subject compilation must succeed
before a named runtime failure counts as a kill. Fabricated JavaScript checker
failures and implementation mutants are recorded separately.

The 88 changed contracts and 63 preserved live contracts are checked under
explicit expected types in `retained-parking/ReviewedContracts.lean` and
`PreservedContracts.lean`. Historical identities retain their dispositions;
retired contracts do not count as current proofs or fresh mutation passes.
`NO-OWNER-EXIT-DISPOSITIONS.md` records each statement the owner-exit removal
retired, changed or replaced.
The pre-D-036 retirement ledger remains `traceability.csv`.

Read [the Registry design](../docs/design/registry-as-mpfs.md) for model limits
and [the simulator guide](../simulator/README.md) for replay commands.

## Statements: ACDC admission, the revocation mirror, delegation

`CardanoKeri/Statements/` is a **separate Lake library**,
`CardanoKeriStatements`, that is *not* a default target: `lake build`
never touches it, so the zero-`sorry` gate above is unaffected. It holds
the specification of the 2026-09-10 design
(`docs/design/credential-verification.md`; #391, #392, #292) as repaired
by the statement audit and the invariant review of the same day: four
models, four statement files, four proof-side helper files and one probe
file.

| Module | Model | Statements |
|---|---|---|
| `Statements/History.lean` | key-state history with back-pointers, approval position (KERI rules B1–B3), `cover`, the seal walk over well-formed TEL events, anchors | `HistoryGoals.lean` H1–H12, S1–S8 (proved) |
| `Statements/Mirror.lean` | per-registry revoked set with its inception anchor, `open`, permissionless `push`, `reanchor`, `miss` | `MirrorGoals.lean` M1–M13 (proved) |
| `Statements/Credential.lean` | ACDC chain admission with policy links and registry anchors, bound to the actor; the cage, `evict` on evidence, `expire`, `gate` | `CredentialGoals.lean` C1–C20 (proved) |
| `Statements/Delegation.lean` | approval certificates with position and anchor, delegated `dip`/`drt` with re-validation, rule-B superseding, ancestry | `DelegationGoals.lean` D1–D18 (proved) |
| `Statements/Probes.lean` | 39 executable `#guard` scenarios from the invariant review, with controls; the build fails if any scenario changes outcome | — |

```
cd lean
lake build CardanoKeriStatements   # zero sorry; probes run at build
```

`STATEMENTS-ATOMS.md` is the theorem ledger (ruling, witness of the
antecedent, falsifying mutant, kind, status), the semantic-atom ledger,
the dispositions of the invariant review and the explicit residuals.
All 71 statements are proved: `#print axioms` reports at most `propext`,
`Quot.sound` and `Classical.choice`, never `sorryAx`. Proof-side lemmas
live in `Statements/*Helpers.lean`.

## Pinned Singular dependency (#381; successor to #478)

KERI pins public Singular main commit
`d69ab005c3b710aeebf033d3c5cd08c56feb5643`,
Git tree `2979dcfc58b092313b0ce7fa0493722539b9ea65`. This merged commit has
the same source tree as the previously pinned branch commit. Both projects declare
`leanprover/lean4:v4.27.0`. `lakefile.lean` and `lake-manifest.json` pin the
Git dependency; `flake.nix` and `flake.lock` pin its source and compiler.
The compiler comes from nixpkgs `7f4e8517083e42a1b38907598dadc02c7235b30e`.
The GitHub source NAR is
`sha256-vV5/4mW4O4NwAsr8rAyTZUhH3pvqlBmsAJQIHUqTVfA=`; the fixed-output
Git checkout retains Lake's required commit and tree metadata as deterministic
loose Git objects, independent of the fetched pack layout. Its NAR hash is
`sha256-Pv45FlCcNHxp97iddexrEcNA0bjAcmSoY+wkw3ZlvTU=`.

From a clean checkout, in order:

```sh
# At repository root: sandboxed, cache-free build and controls, also in just ci.
just check-singular-lean
# To retain readable receipts in a chosen directory:
nix run --no-write-lock-file ./lean#singular-dependency -- "$PWD/lean-receipts"
# Interactive Lake use (Git access is required for the first resolution):
cd lean
nix shell --no-write-lock-file .#lean --command lake update singular
nix shell --no-write-lock-file .#lean --command lake build CardanoKeri CardanoKeriStatements Singular
nix shell --no-write-lock-file .#lean --command lake env lean SingularDependencyProbe.lean
```

The Nix check starts without build products, re-resolves Lake against a
fixed-output Git checkout without network, requires byte-identical locks and
clean source at the pin, and builds all three library targets. Receipts retain
the compiler version, consumer identity, source/lock hashes, build output,
axiom report and rejected controls. The dedicated hosted CI job retains these
receipts for 14 days, including its build log on failure. Missing dependency
source and an invalid lock are errors, with executable refusal controls.
The existing required Lean CI status explicitly checks this dependency job's
result with `if: always()`: failure, cancellation or skip cannot become a
successful skipped required status. Repository branch protection is unchanged.

`CardanoKeri.singular_step_binding` states: **Given** any
`Singular.RegistryState`, **when** `Singular.step` executes
`Singular.canonicalRequest .updateActive`, **then** it returns
`.error "edge-inadmissible"`. This is the pinned model's excluded-edge
boundary (`allowed`, `canonicalRequest`, `refusal`, `step` in
[`Singular/Model/Fold.lean`](https://github.com/lambdasistemi/singular/blob/d69ab005c3b710aeebf033d3c5cd08c56feb5643/lean/Singular/Model/Fold.lean)).
The proof uses `rfl`; its axiom closure is exactly `propext` and `Quot.sound`,
already used by upstream `step` and allowed by KERI's trust policy.
`SingularDependencyProbe.lean` executes that request on an empty fixture and
checks that `insertActive` without approval instead returns `no-approval`.
The check rejects a changed expected error and a substituted action by
executing the guards; this is a finite API check, not a lifecycle journey.
It also injects an unproved binding in a disposable control and requires the
same axiom policy to reject its `sorryAx` dependency.

The dependency check establishes the pinned import and compiler boundary. The
retained-output model additionally executes imported booking and fold judgments
and proves its own correspondence contracts. Neither class of evidence proves
production Aiken/Haskell correspondence or discharges consumer authentication
(#439) and broader application recovery (#468).
