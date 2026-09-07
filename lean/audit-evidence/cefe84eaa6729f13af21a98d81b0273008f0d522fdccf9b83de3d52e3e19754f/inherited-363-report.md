# Commit Audit

- Submission: `1/2`.
- Base: `a7a409f9d9b71dcb038e2a93973f2820c06a42d8`.
- RED: `22d31239756ea35e885f1381bf185d66204e7bcb`.
- Candidate: `4a99ea42ccba83e0cb32692cb9cac75babdc5f20`.
- Mandate: `specs/363-checkpoint-inversions/`, composite `76f240ea10e46bf713fb85ec36e170a9f4c666fc7e80bd545157ef592038647a` (13,187 bytes, 278 lines).
- Models: modules `e27674aba071b1ea40dd5124e57b46ca2ec8f4483f92ceaa514b5f57f7f868bf`; data `ed406c205b0cae39f1f356a73fc89f4e97af37269cd5fc36534b4bcf02e63281`; functions `1a85366327c85d4f04e0d68db664e80c15a4f245e13d312b13eb92b71aed9ab4`.
- Gate: shell `70351d252247f7a4e6a98ff952a00adb43edfa4c6b37b5debb202ad5588c3f2d`; Lean `c660f30d86de8f2b6c4f19e060b3965ef7f3741fafec30ec3bc5cae8c7902ba0`; composite `7fc4beb0ed38edea4bd0e6c3a96708f02e9460844c52a3f4c37c3274f25a4ce2`.
- Owner receipt: `212c7c225945353d26c6474adf619ab951ff3c9bde04aa1e75775e2fbae60753`; handoff manifest `8b09aad5382951ee75c64e6ba5c2c58f8229d33c7ed412575f2693a5cbd51a9d`.
- Scope: FULL `base..candidate`; detached clean HEAD, two commits, one path `lean/CardanoKeri/CheckpointGoals.lean`, normal mode, `+325/-0`; binary diff `de121f3fe88a03f89c4aeb833be470fc6b8f52f65d9b5168383466927aca8c31`.
- Verdict: PASS.
- Audit loop: submission `1/2`; next submission `ALLOWED` by cap but not required by this verdict.
- Ceiling raises: `0/2`; ledger `/tmp/epic-367/to-363/ceiling-raises.tsv`, sha256 `cfa51f7d2fb9e26b0c5af1e870a79d9a7c00d029db5822a91ba35abfcf6f4a9f`.
- Campaign: CLOSED — ended by SET-POINT; ledger `/tmp/epic-367/to-363/auditor-s1/campaign.tsv`, sha256 `760597fd791db043e2aae821f7a8fc6a1a2e3b21d4bf993aecde238e276daf9b`.
- Builds: `1/2` this ticket; this audit `1`, `cache=cold`; direct warm elaboration probes `25` total (uncharged: 18 final/counting, 7 superseded harness-development runs).

## Invariant matrix

| Invariant | Severity | Verdict | Row state | Proof / evidence |
|---|---|---|---|---|
| INV-363-DENOMINATOR | BLOCKING | PASS | KILLED | Compiled discovery returned 13/13; compile-valid `auditDummy` was demanded and an empty inductive hit the explicit guard. `full-gate.log` `5b55e3cc...`; `structural-controls-v2.log` `b7ae015e...`; `empty-denominator-red-v2.log` `3d379655...`. |
| INV-363-EXACT-PREMISES | BLOCKING | PASS | KILLED | All 13 exact types compiled; duplicated `hsn` replacing the paid pool guard failed, and 13 per-constructor wrong types produced 13 type mismatches. `wrong-types-red.log` `2cd37601...`; dropped-guard log `b5fc5bdf...`. |
| INV-363-EXACT-EFFECTS | BLOCKING | PASS | KILLED | Exact action/slot/source/flow/successor types compiled for every row; one wrong indexed action/effect per row failed. Non-degenerate witnesses use payee 29, refund 37, D=2, B=3, P=5, paid/unpaid pools 9/4 and deposit `bIn=3`. `final-public-contract-green.log` `25c838ae...`; `witness-controls-green.log` `080758de...`; wrong types `2cd37601...`. |
| INV-363-BINDING | BLOCKING | PASS | KILLED | Renaming/count remained while binding `register_iff` to `.poison` failed in the proof and exact-type checker. `structural-wrong-binding-red.log` `10662ac2...`. |
| INV-363-SURFACE | BLOCKING | PASS | KILLED | A valid off-surface `register_iff` compiled separately; the imported goals surface still reported it missing. `structural-off-surface-red.log` `05644717...`. |
| INV-363-CAN-FAIL | BLOCKING | PASS | KILLED | Missing, duplicate, wrong-binding, dropped-guard, new-constructor and off-surface controls all reached Lean, exited 1 for intended markers, left tracked state clean, then the public contract returned GREEN. `structural-controls-v2.log` `b7ae015e...`; final GREEN `25c838ae...`. |
| INV-363-TRUST | BLOCKING | PASS | KILLED | Cold full build had no escape warnings; 13 qualified axiom rows: 11 none, close pair only `[propext, Quot.sound]`. A `sorry` proof-body mutant compiled with the expected warning and the gate-equivalent scan exited 93; candidate scan exited 0. `full-gate.log` `5b55e3cc...`; `trust-control-red-v2.log` `10631709...`; mutant compile `674f7016...`; GREEN `9c82f35f...`. |
| INV-363-IMMUTABLE | BLOCKING | PASS | KILLED | `Checkpoint.lean` is byte-identical base-to-candidate; diff is additive. A seeded deletion plus production-file change made the exact Git-manifest comparator exit 91; candidate exited 0. RED `0b910bbc...`; GREEN `e6300f2b...`; provenance `cdeacf1b...`. |
| INV-363-SCOPE | BLOCKING | PASS | KILLED | Only the owned goals path changed; no spec, import-root, toolchain, mutant, sibling, simulator, on/off-chain, CI or dependency path changed. Seeded forbidden `Checkpoint.lean` path exited 91. Same scope/provenance receipts as above. |

## Inversion coverage

All rows share compiled public-surface evidence `final-public-contract-green.log` sha256 `25c838aec96faf1966ae9b31d30a91775b257171d9e524a86a336c8693d2bb37`, concrete witness evidence `witness-controls-green.log` sha256 `080758dee88aa38ec033455a0b22b05ba731ee5838df96e47f87367c489750da`, and per-row falsification evidence `wrong-types-red.log` sha256 `2cd37601d94ebb4ca6117ca5614c8139bfe5fc0af14dcbbd8e198a6af3719e7f`.

| Constructor | Public inversion | Exact premises | Exact indexed result / witness distinction | Outcome |
|---|---|---|---|---|
| `register` | `Step.register_iff` | `True` | register/refund/pool input, absent, all three inputs, fresh live state | PROVED |
| `rotateKeepPaid` | `Step.rotateKeepPaid_iff` | rotation, increasing seq, keep intent, `P <= pool` | payee 29 receives P=5; refund changes to 37; pool 9 to 4 | PROVED |
| `rotateKeepUnpaid` | `Step.rotateKeepUnpaid_iff` | rotation, increasing seq, keep intent, `pool < P` | empty flow; pool 4 retained; `none` refund retains 11 | PROVED |
| `rotateDepositPaid` | `Step.rotateDepositPaid_iff` | rotation, increasing seq, deposit intent, `P <= pool` | frozen input contributes non-zero B=3; payee receives P=5; unfreezes | PROVED |
| `rotateDepositUnpaid` | `Step.rotateDepositUnpaid_iff` | rotation, increasing seq, deposit intent, `pool < P` | frozen input contributes B=3; no premium; pool 4 retained; unfreezes | PROVED |
| `poison` | `Step.poison_iff` | quorum, not already poisoned | empty flow; only poison bit becomes true | PROVED |
| `freeze` | `Step.freeze_iff` | rotation, increasing seq, low pool, unfrozen, clean | hunter 29 receives B=3; only frozen bit changes | PROVED |
| `topUp` | `Step.topUp_iff` | `True` | poolIn=7 and live pool 9 to 16 | PROVED |
| `convict` | `Step.convict_iff` | duplicity | refund 11 gets B=3/pool=9; convictor 29 gets D=2; convicted | PROVED |
| `convictParked` | `Step.convictParked_iff` | duplicity at parked hash | empty flow from parked hash to convicted | PROVED |
| `closePaid` | `Step.closePaid_iff` | rotation, increasing seq, close intent bound to payee, `P <= pool` | refund 37 gets D=2/B=3/pool=4; payee 29 gets P=5; parked (3,4) | PROVED |
| `closeUnpaid` | `Step.closeUnpaid_iff` | rotation, increasing seq, close intent bound to payee, `pool < P` | refund 37 gets D=2/B=3/pool=4; no hunter; parked (3,4) | PROVED |
| `reopen` | `Step.reopen_iff` | rotation from parked hash, increasing seq | fresh D=2/B=3/pool=7, refund 31, bornAt 42, present at (epoch 3, seq 4) | PROVED |

The denominator is derived from compiled `Step`, not pinned to 13. Each theorem's left side is the constructor's exact result and each right side is all/only proof premises in constructor order. The concrete examples inhabit every left side through the public inversion's reverse direction. The two close proofs use prior proved theorem `T16_close_destination`; their qualified axioms remain exactly the allowed pair.

## Test, value and failure-mode coverage

- Test coverage: the cold gate built all 12 Lean targets, then independently imported `CardanoKeri`, derived all constructors, resolved the public theorem for each, elaborated 13 exact types and printed 13 qualified axiom outcomes.
- Value coverage: distinct non-zero addresses and values exercise destinations, paid/unpaid branches, full/missing freeze bond, pool subtraction/retention, registration/reopening inputs, and fresh successors. The per-row wrong types prevent agreement through those fixture values alone.
- Failure modes covered: empty/truncated extent, missing/duplicate/wrong/off-surface binding, dropped/duplicated premise, wrong action/flow/successor, escape proof, deletion and forbidden path.
- Failure modes altered: none altered — checked the complete `base..candidate` diff. It adds proof declarations and compile-time environment inspection only; it acquires no runtime resource, moves no work to a thread, changes no synchronization primitive, and changes no degradation path. `Step`, `stepFn` and runtime definitions are unchanged.

## Theorem outcomes and correspondence

- Outcomes: 13/13 `PROVED`; no `OPEN`, `REFUTED`, `WITHDRAWN`, `sorryAx`, `admit`, or `Classical.choice`.
- Statement immutability: all pre-existing theorem text is retained; new inversions and checker are additive.
- Relation/function/replay correspondence: not reopened by `INVERSIONS+PROOFS` mode; the complete diff leaves `Step`, `stepFn`, replay and simulator-facing code unchanged.

## Verification receipts

| Command / control | Exit | Duration | Cache / free bytes | Evidence |
|---|---:|---:|---|---|
| Exact `/tmp/epic-367/to-363/gates/checkpoint-inversions-v1.sh` | 0 | 10,923 ms | cold; before 419,022,602,240; after 416,638,173,184 | `full-gate.log` `5b55e3cc5f16d65a445d0777e491e827ea53245421633ea973bd3c926d66abd0` |
| 13 wrong exact types | 1 | 1,218 ms | warm | `wrong-types-red.log` `2cd37601d94ebb4ca6117ca5614c8139bfe5fc0af14dcbbd8e198a6af3719e7f` |
| 13 constructor/value witnesses | 0 | 2,311 ms | warm | `witness-controls-green.log` `080758dee88aa38ec033455a0b22b05ba731ee5838df96e47f87367c489750da` |
| Six structural controls | 0 (six inner exits 1) | 25,957 ms | warm | `structural-controls-v2.log` `b7ae015ee7505acf208ddeecac197bd3a0592a57769c6852635b653a5f285316` |
| Empty denominator guard | 1 | 1,242 ms | warm | `empty-denominator-red-v2.log` `3d3796550288bcfe1cf70aa2cce59bb44eb9e87bbc5b371dd6f93d5aba6abb94` |
| Trust mutant / candidate | 93 / 0 | 4,345 / 4,368 ms | warm | RED `106317094cab08781613083b3ceb82ab597418ab4e67c07f80e02210268f735a`; GREEN `9c82f35fb39c1dcc5c4603683c624f3ebbdb7036d4a43a7a98ca42f0c3aec28b` |
| Scope mutant / candidate | 91 / 0 | 9 / 30 ms | no build | RED `0b910bbc9a51d096b89fb3edae82f249603ccaf5289413d884fbca0473e48f30`; GREEN `e6300f2bd125fe889833c266815c599c1c80075b0ab7c5a1574155742f7bb3ec` |
| Provenance and frozen hashes | 0 | 97 ms | no build | `provenance-v2.log` `cdeacf1bc26740a47ecd977f3950880bb026d5fb33d28904d5e6784d1ab93c4b` |
| Final public contract after controls | 0 | 1,549 ms | warm | `final-public-contract-green.log` `25c838aec96faf1966ae9b31d30a91775b257171d9e524a86a336c8693d2bb37` |

Superseded harness-development attempts are retained but not counted; each failed before it could judge the candidate and the final frozen versions were rerun.

## Residuals

None.

## Candidate invariants

None.

## Onward discoveries — outside this ticket

None. Durable handoff: `/tmp/epic-367/to-363/auditor-s1/onward.md`.

## Blocking findings

None.

## Advisories

None.

## Honest limits

This establishes exact public inversions over the compiled model vocabulary and the declared finite mutation classes. It does not establish that the model vocabulary matches product intent, validate simulator/on-chain transcription, or exhaust arbitrary equivalent, pairwise, higher-order or toolchain-bug mutants.
