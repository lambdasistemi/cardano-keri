# Lean audit report — issue #368

Terminal verdict: AUDIT-FINDINGS

The released tree has clean compiled proofs, but the inherited blocking
acceptance-provenance finding F-365-001 remains unresolved. This report is
complete as a findings report; it does not accept the model or close the
missing verification. No repairs are prescribed or performed here.

## Mode and frozen inputs

FULL-scope evidence consolidation, using NOTE-008's **pure-report finish**:
no commit owner or auditor was seated, no fresh independent FULL audit or
mutation campaign was commissioned. Fresh verification below is performed by
the report author. Historical audits retain their original scope and limits.

- Release: `a67e3ed16d4f406fa99dd8b746a65e0c2c0b8359`.
- Audited-input SHA-256: `cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f`.
- Identity and Git tree IDs: [identity.json](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/identity.json).
- [inputs.git-manifest](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inputs.git-manifest) binds every released tracked `lean/` path,
  mode and blob. Final recomputation excludes only this report and
  `lean/audit-evidence/**`, preventing self-reference.
- [source-sha256.txt](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/source-sha256.txt) freshly hashes the models, goals, decision
  documents, mandates, runner, ledger, toolchain and CI driver. These are
  re-derived bytes, not planning-boundary assertions.
- [receipt-hash-comparison.tsv](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/receipt-hash-comparison.tsv) confirms all three receipt hashes
  (ledger, runner, mutant specification) match the released files. No mismatch
  was found in those three fields; the historical base label is retained as
  history, not substituted for this report's release.
- [NOTE-008-frozen-tree.md](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/NOTE-008-frozen-tree.md) is the release authority;
  [pr-372.json](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/pr-372.json) and [pr-373.json](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/pr-373.json) record merged dependency
  disposition. The release excludes Lifecycle, Goals and Invariants.

Fresh commands and their real exits are in [commands.md](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/commands.md).
The build started with no `.lake`, compiled all library modules, and exited
0 (9 Lake jobs; ordinary unused-simp warnings). The compiled environment then
supplied the theorem inventory and all qualified axiom queries. Nix tooling
was reused; this is not a cold rebuild of the compiler itself.
All evidence files are hashed by [MANIFEST.sha256](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/MANIFEST.sha256).

## Decision coverage

The complete inherited ruling → model-site → theorem mapping is the frozen
[semantic ledger](SEMANTIC-ATOMS.md), whose SHA-256 is re-derived above.
This table identifies its distinct authority surfaces; it does not promote
mapping presence into statement-fidelity evidence.

| Authority | Constructor, guard or effect | Theorem surface | Disposition and limit |
|---|---|---|---|
| D-022…D-040; CP-01…CP-40 | Checkpoint poison, rotation, freeze, bonds, close/reopen, evidence and payment bindings | CheckpointGoals T1…T16, Step inversions, consumer mirror | Compiled proofs; 40 historical atom rows. External ruling fidelity not freshly read back. |
| Registry verbatim rulings, R1…R14; RG-01…RG-22 | processBody operations, request phases, fold generation/plugin, reap/convict | RegistryGoals R*, processOne/inv_step, seven action and five body inversions | Compiled proofs; 22 historical atom rows. ReachFar restriction remains material. |
| Cage authority/value modes; CG-01…CG-11 | ownerKeyed, ownerAndHook, delegated, refundAll, plugin routing | Cage theorems; two auxiliary Mutants assertions | 12 library theorems compiled; auxiliary assertions remain campaign-local evidence. |
| Samaritan fee/funding rulings; SM-01…SM-06 | reap and fold funding, premium and destinations | Six Samaritan theorems | Compiled arithmetic claims under their explicit funding/fee assumptions. |
| DISP-366-DELETE | Retire three superseded modules and 21 historical goals | traceability.csv retirement ledger | Fresh driver passes; each retired import fails with its module-specific missing-olean diagnostic. |

Statement readback: no fresh blind reader was seated under this pure-report
finish. Whole-tree independent statement completeness and the witness/sensitivity
floor for every theorem remain OPEN; the finite inherited campaigns below do
not establish that broader claim. This is an evidence limit, not a discovered
counterexample or authorization to alter statements.

## Inversion coverage

[inventory.log](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inventory.log) derives 13 Checkpoint.Step constructors, seven
Registry.Action constructors and five Registry.Op constructors from the compiled
environment. [inversion-rows.tsv](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inversion-rows.tsv) maps all 25 to resolved theorem
constants with fresh axiom receipts. Checkpoint's embedded checker also reports
13/13 in [build.log](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/build.log); Registry uses the authoritative executable
functions under DEC-364-STEPFN, with no second Step relation.

| Surface | Exact-premise and self-falsification evidence | Evidence class |
|---|---|---|
| Checkpoint 13/13 | [#363 report](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-363-report.md): all exact premise/result types, 13 witnesses and wrong types; missing, duplicate, wrong binding, dropped guard, new constructor and off-surface controls | Historical independent audit; goals bytes match its candidate. Controls not rerun here. |
| Registry 7+5/12 | [#364 report](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-364-report.md): exact compiled branch types, 12 reachable witnesses and owning mutants; missing, duplicate, wrong-branch and dropped-guard controls | Historical independent audit; goals bytes match its candidate. Controls not rerun here. |

[inherited-byte-identity.tsv](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-byte-identity.tsv) proves the stated byte identities,
not identity of every historical environment or fresh semantic kills. The
current compilation confirms theorem availability and proof trust. Whole-tree
structural closure beyond these inherited finite surfaces is not claimed.

## Theorem outcomes

[theorem-outcomes.tsv](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/theorem-outcomes.tsv) records **PROVED** for each of the 749
compiled theorem constants under `import CardanoKeri`, with its exact
axiom set and raw [axioms.log](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/axioms.log) pointer. This includes 210 explicit
source-level theorems ([source-theorem-names.txt](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/source-theorem-names.txt)) plus generated
constants; 749 is not the mutation denominator. Receipt/name sets agree
exactly. Allowed axioms are only `propext` and `Quot.sound`; there are
zero unapproved axioms, including zero `sorryAx` or `Classical.choice`.

The fresh retirement driver independently reports 210 source theorems,
21 retirement rows, three retired modules, build pass and axioms pass
([traceability.log](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/traceability.log)). Retired goals are WITHDRAWN from the live
proof scope by DISP-366-DELETE, with repository disposition RETIRED.
Standalone trace drivers and mutant witnesses are outside the imported library
proof denominator; their presence is not a fresh proof or execution receipt.

PROVED describes the compiled proposition, not fidelity to an external mandate.
No new constructive refutation was produced. Cage's deliberately proved bypass
counterexamples remain model statements about alternative modes; they do not
license the bypass as the intended delegated configuration. Statement readback
and whole-tree theorem non-vacuity remain OPEN as described above.

## Mutation adequacy

Two separate finite ledgers are retained. **Fresh semantic mutants executed in
this report finish: zero.** No historical spend or kill is charged as fresh.

| Ledger | Severity/operator | Retained result | Current use and stopping reason |
|---|---|---|---|
| CP 40 + RG 22 + CG 11 + SM 6 = 79 semantic atoms | All blocking; guard relax/delete, force-false liveness, evidence swap, effect/edge changes, one-sided correspondence break | Historical 79/79 KILLED, identity SURVIVED, zero blocked or wrong-reason exclusions | Supporting campaign evidence only; frozen finite-ledger stop, 197/210 recorded invocations. |
| 20 Cage/Samaritan theorem rows | Reachable witness plus relevant canonical/AUX sensitivity kill | Historical 20/20 REACHED+KILLED | Distinct from atom coverage; includes two auxiliary assertions. Not all 210 library theorems. |
| 13 Checkpoint and 12 Registry inversion rows | Exact premise/effect, reachability and binding controls | Historical reports described above | Separate inversion campaigns, not extra rows added to the 79-atom total. |

The row-by-row IDs, operators, outcomes and discounted theorem sets are in
[Checkpoint receipts](CHECKPOINT-MUTANTS.md), [Registry/Cage/Samaritan receipts](REGISTRY-MUTANTS.md)
and [freeze history](mutants/FREEZE-SUPERSESSION.md). Structural mirrors,
including T7_step_iff_stepFn, T9_juvenility_is_consumer_only and broad Cage
correspondence, are not independent owning semantic kills. Setup/import/syntax,
sorryAx evaluation and unrelated failures are excluded from semantic totals.
Equivalent/shadowed mutants cannot close a row merely by being counted.

**F-365-001 remains blocking** for acceptance provenance: submission 2's exact
gate exited 127 at line 23 before invoking the runner. Its retained campaign-030
summary is supporting inspection evidence, not a fresh successful full gate.
The merged receipts also preserve campaign-029 history. These campaign identities
are not collapsed into one execution. No new campaign is launched to reinterpret
the exhausted submission-2 audit.

## Correspondence

| Boundary | Evidence and outcome | Limit |
|---|---|---|
| Checkpoint Step ↔ stepFn | T7_step_iff_stepFn: PROVED, current qualified axiom receipt | Agreement inside the Lean model. |
| Checkpoint Trace ↔ replay | T7_trace_iff_replay: PROVED, current qualified axiom receipt | Does not prove external replay implementation fidelity. |
| Checkpoint Bool ↔ Prop | consumableStateB_iff: PROVED, current qualified axiom receipt | Consumer predicate includes the frozen/age conditions expressed in Lean. |
| Registry backward execution interface | Seven stepFn and five processBody iff theorems: PROVED | No independent Step relation by DEC-364-STEPFN; ReachFar carries now < far. |
| Cage delegated ↔ Registry | applyBatch_delegated_eq, delegated_is_registry: PROVED | The declared delegated plugin/value mode; alternative bypass modes differ intentionally. |
| Registry replay and both simulator trace drivers | Frozen source only in this report | No fresh driver run, cross-language comparison, browser exercise or whole replay correspondence conclusion. |
| On-chain/off-chain implementation | No fidelity verdict | Model proofs and green repository CI do not establish transcription correctness. |

## Honest limits

| Finding | Violated row / class / blocking | Hashed evidence | Honest limit |
|---|---|---|---|
| F-365-001 (inherited, unresolved) | INV-365-PROVENANCE; report INV-368-05/08 acceptance evidence; provenance; **blocking** | [inherited-365-report.md](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-365-report.md), [inherited-365-full-gate-v5.log](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-365-full-gate-v5.log), [inherited-365-gate-v5.sh](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-365-gate-v5.sh) | Exact historical gate failed before its runner/axiom/build legs; fresh proof checks here do not retroactively make that command pass. |
| F-368-001 | REQ-368-COVERAGE/MUTATION; whole-tree statement and sensitivity coverage; **blocking for a pass** | [source-theorem-names.txt](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/source-theorem-names.txt), [inherited-363-report.md](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-363-report.md), [inherited-364-report.md](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-364-report.md), [inherited-365-report.md](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/inherited-365-report.md) | The retained bounded reports and 20-row theorem ledger do not establish fresh blind readback or reachable/sensitive witnesses for every source theorem. OPEN assessment, not a demonstrated false theorem. |

NOTE-008 records #373 merged at 127f2e8 with 23/23 green including the E2E
rerun. The live PR snapshot is retained separately. Re-cut #383 was opened and
closed superseded-by-merge and, per the release authority, never dispatched
([issue-383.json](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/issue-383.json)); it supplies no independent replacement verdict.
The E2E timing race is tracked as #382 ([issue-382.json](audit-evidence/cefe84eaa6729f13af21a98d81b0273008f0d522fdccf9b83de3d52e3e19754f/issue-382.json)).
OD-366-001 remains the recorded, unopened textual follow-up:
`onchain/lib/cardano_keri/checkpoint/lifecycle_model.ak:1` names the deleted
Lifecycle Lean model. It is outside this report's implementation-fidelity scope.

Finite campaigns cannot establish absence of arbitrary, equivalent, combined
or higher-order mutants. Environment Booleans abstract real evidence and
cryptographic verification; model proofs do not discharge those assumptions.
No source repair, statement change, merge or independent acceptance occurs in
this report finish. The project desk owns review and merge disposition.
