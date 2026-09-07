# Commit Audit

- Submission: `1/2`
- Base: `5d3c4f31bf23925579d8d49166b073a338ce43e5`
- RED: `0f67e0a0edc497f4d5d2d0cb4b28ad19e0c4329a`
- Candidate: `55e932f8912392a3dbcdc201bb870996ff44b140`
- Mandate: `ae4460fa064d952dc1cd7a15f0e99cf24e4bcb18361b73966a04f4db95976983`; all six supplied member hashes matched
- Scope: FULL `base..candidate`
- Verdict: `PASS`
- Audit loop: submission `1/2`; next submission `ALLOWED` by cap but not required by this verdict
- Ceiling raises: `0/2`; input ledger `/tmp/epic-367/to-364/campaign-ledger.md` sha256 `c41f501234225067211699b37353a88b25c7f88d56226aff46711ee796f8ba0d`
- Campaign: `CLOSED` — ended by `SET-POINT`
- Builds: `15/16` this audit; focused/module-cold `1`, row mutants `1 cold + 11 warm`, frozen self-test `1 cold`, final full build `1 warm`

## Invariant matrix

| Invariant | Severity | Verdict | Row state | Proof / evidence |
|---|---|---|---|---|
| INV-364-DENOM | BLOCKING | PASS | KILLED | Live inventory and compiled probe report 7 Action + 5 Op = 12/12; missing/duplicate controls exit nonzero. `evidence/focused-gate.log` sha256 `5be883e4d74f7ad72f2483bc42ec9bf9dc3019d49639b4cf0f25698e385db03c`; self-test sha256 `5c0bbdb2b22255038663c3c6df466c8b67a80c8aef66205511011e19048dbdee`. |
| INV-364-BIND | BLOCKING | PASS | KILLED | Exact compiled types expose each branch's guards and whole result record; 12/12 reachable witnesses and 12/12 owning-theorem guard/effect mutants. Row campaign sha256 `d6962763116428dd7d1492c455ffaf9e5dab26cb1a41b863057fbb33712b0f07`. |
| INV-364-WIRING | BLOCKING | PASS | KILLED | Twelve unique theorem constants resolve through `import CardanoKeri`; missing and wrong-branch compiled controls fail. Focused and self-test receipts above. |
| INV-364-PRESERVE | BLOCKING | PASS | KILLED | Git proves two normal-mode files and +388/-0 only; executable definitions, `R*`, `ReachFar`, imports, adjacent modules, simulator and on-chain paths are unchanged. Statement-byte mutant RED 93 then GREEN: `evidence/preservation-run.log` sha256 `407d567c4cb59b4ac4b95c3ab129808a87da3772b3ecd66822b175d6a6d40f46`; provenance sha256 `25cf7f88894d0b47a10bdae3c003fff44f5edb709b10c9aa3ed9e86c14e9a61b`. |

## Mode and frozen inputs

Commit audit with Lean `INVERSIONS` and `PROOFS` surfaces. Frozen gate member
hashes matched the primary `1f1edea2...3674`, public Lean probe
`971bdd66...5e68f6e`, and v5 self-test `2eaf7a00...f8eca`. The official
manifest validator and `verify-commit-handoff` both exited 0; the candidate is
clean, detached, two non-merge commits after base, and exactly equals the frozen
GREEN handoff.

## Decision and inversion coverage

`DEC-364-STEPFN` is recorded in the Registry header. `stepFn` and `processBody`
remain authoritative; no inductive `Step` was added. The derived denominator is
the seven live `Action` alternatives and five live `Op` alternatives. All 12
map one-to-one to public `*_iff` theorem constants with exact type ascriptions.
The frozen missing, duplicate, wrong-branch, and dropped-guard controls all
failed for their intended reason (`faults=4/4`).

## Theorem outcomes

All twelve outcomes are `PROVED`. The focused clean-module build produced no
`sorry`, `admit`, or `sorryAx`. Theorem-qualified `#print axioms` produced ten
`[propext]` receipts and two `[propext, Quot.sound]` receipts (`revive` and
`convict`), with no `Classical.choice` or other axiom.

## Mutation adequacy

The theorem-row ledger is 12/12 reachable and 12/12 killed. Witness values are
non-degenerate (nonzero economic values, nonempty fold batch, and pre-existing
locked/refund lists where preservation/append behavior matters). Mutants cover
guard relaxation/removal and successor/value effects, and each compiled failure
lands inside its owning theorem range. The four blocking invariant rows are
separately terminal as `KILLED`; see `campaign-ledger.md`.

## Correspondence

No relation/function correspondence row applies because the frozen decision
forbids a second `Step` relation. The audited public equivalences invert the
authoritative functions directly. Simulator/replay behavior was not re-derived;
its byte preservation is covered by Git scope evidence.

## Failure modes altered

None altered — checked the complete base-to-candidate diff. It adds one module
header decision and pure theorem declarations only; it acquires no resource,
moves no work to a thread, changes no synchronization primitive, and changes no
degradation/refusal path in `stepFn` or `processBody`.

## Residuals

None.

## Candidate invariants

- `CINV-364-SELFTEST-RETIRE` (proposed `ADVISORY`, unratified): a frozen
  self-test run should leave no registered worktree it created. The v5 cleanup
  attempted non-forced removal of a deliberately dirty mutant, leaving
  `/tmp/cardano-keri-364-guard-mutant.wfS5lW` registered; the auditor validated
  its exact candidate and one-file mutation, then retired `34,842,767` bytes.

## Onward discoveries — outside this ticket

None.

## Blocking findings

None.

## Verification receipts

| Command | Exit | Duration | Evidence |
|---|---:|---:|---|
| `./gate.sh` | 0 | 8.412s | `evidence/focused-gate.log`, sha256 `5be883e4d74f7ad72f2483bc42ec9bf9dc3019d49639b4cf0f25698e385db03c` |
| Reachability RED then 12/12 GREEN | 0 | 7.914s | `evidence/reachability-run-v4.log`, sha256 `8e9fe410e68263b48b3c4e084c435230a76e8bb9b04c4e05f75c6bb63a242a62` |
| Row-mutation zero-build preflight | 0 | 1.316s | `evidence/row-mutations-preflight.log`, sha256 `7d3f3715ff6a778debd736462dba44f9f2bc254a7ba2a06c34bfb43c1cb6871c` |
| Twelve compiled row mutants | 0 | 86.220s | `evidence/row-mutations-run.log`, sha256 `d6962763116428dd7d1492c455ffaf9e5dab26cb1a41b863057fbb33712b0f07` |
| Preservation mutant RED then GREEN | 0 | 0.287s | `evidence/preservation-run.log`, sha256 `407d567c4cb59b4ac4b95c3ab129808a87da3772b3ecd66822b175d6a6d40f46` |
| Frozen v5 self-test | 0 | 10.918s | `evidence/frozen-selftest-run.log`, sha256 `5c0bbdb2b22255038663c3c6df466c8b67a80c8aef66205511011e19048dbdee` |
| `cd lean && nix shell --no-write-lock-file ../offchain#lean --command lake build` | 0 | 0.741s | `evidence/full-lake-build.log`, sha256 `ef64c2bfc380cfcca0bddad0147be17fa2c366300161561374e13b6257f6b0dc` |
| Validate handoff manifest v2 | 0 | 0.057s | `evidence/manifest-validate.log`, sha256 `0cbbeb69444f479947b7fdef33081aef077ad650cb0c088d0898272b359d0a9c` |
| Verify commit handoff | 0 | 0.131s | `evidence/commit-handoff-verify.log`, sha256 `e246a100c3c971866cf85278beebd11d619a807b1d110537bfc3fe708500e358` |
| Provenance RED then GREEN | 0 | 0.301s | `evidence/provenance-run-v2.log`, sha256 `25cf7f88894d0b47a10bdae3c003fff44f5edb709b10c9aa3ed9e86c14e9a61b` |

Superseded setup/parser and shell-quoting attempts are retained but excluded
from semantic totals. No network, GitHub contact, candidate edit, stage, commit,
or push occurred.

## Advisories

- The self-test cleanup property above is not enforced by v5. Its semantic
  verdict remained valid because the auditor independently checked and removed
  only the worktree created by this run.

## Honest limits

This audit covers the declared 12-row finite denominator and named single-atom
fault model. It does not claim arbitrary mutation coverage or absence of other
fault classes. Simulator and on-chain semantics were outside scope; only their
unchanged Git identity is established. Remote publication state and CI were not
checked because the brief forbids GitHub contact.
