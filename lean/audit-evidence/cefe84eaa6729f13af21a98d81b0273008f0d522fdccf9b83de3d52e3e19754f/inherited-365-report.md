# Commit Audit

- Submission: `2/2`
- Base: `2fa084dd03453359a0e9adc917170c9b29826311`
- Rejected candidate: `3568e9f953fa4d7b92cb60a0fed20390fb2d4b53`
- Candidate: `127f2e8794d65987f3405610be30385992d4dd09`
- Mandate: `specs/365-semantic-atoms/spec.md` (`f851e25c7bc0aa9570a8613b37a338e29325f4bb95868500eb594d2d9d301fa6`)
- Packet: `/tmp/epic-367/to-365/audit-2/packet.manifest` (`0c377a9ba3b49da7727e1367a0603ef545757c8b5e0e13f8a1545d83434f318e`)
- Scope: REPAIR delta represented by equivalent commits `4e9185b = 127f2e8`, plus exact open finding `F-365-001` and touched cold-inventory/gate-provenance boundaries; upstream final-base changes were not attributed to this repair.
- Verdict: FINDINGS
- Audit loop: submission `2/2`; next submission `FORBIDDEN`; the blocking row requires ticket re-cut rather than another repair/audit round.
- Executions: `3/3`; remaining `0`; ledger `/tmp/epic-367/to-365/audit-2/execution-ledger.md`.
- Mutation campaign: CLOSED — retained campaign-030 reached SET-POINT (`79/79` atom rows and `20/20` theorem rows); it is supporting packet evidence, not a substitute for the mandatory fresh gate.
- Build receipts: cold inventory `cache=cold`, 10.854 s; missing-gate control entered no build, 0.062 s; full gate entered no build, 0.027 s.

## Mode and frozen inputs

COMMIT-AUDITOR repair-delta recheck with Lean mutation/provenance specialization. No statement, proof, inversion, or correspondence row was reopened. Pane `%695` was distinct from ticket owner `%455` and Muse commit owner `%493` in `keri:3 cardano-keri-e367-t365-atoms-mutants`. Independent packet verification and in-seat tool preflight passed before candidate inspection; launch receipt: `/tmp/epic-367/to-365/audit-2/launch-receipt.md` (`510a88af16b6a545ceeb91b3897826e2a63f0f08fdb06dea399b00798db5907a`).

The worktree was detached and clean at the exact candidate. `git range-diff` established that the repair commit was preserved across the final rebase (`4e9185b = 127f2e8`). Static receipt: `evidence/static-provenance.log` (`a39827e9ce79cc83f03d62271d7a3bd3e6a894c0dba8aa18fff1337d03a0ccb8`).

## Invariant matrix

| Invariant | Severity | Verdict | Row state | Proof / evidence |
|---|---|---|---|---|
| INV-365-PROVENANCE | BLOCKING | FAIL | BLOCKED | Cold inventory passed 79/20 and the explicit missing-path control failed for the intended `GATE-MISSING` reason, but the exact packet-bound gate exited 127 at line 23 before invoking the runner; rubric: `invariant-rubric.tsv`. |

All other invariant rows remain terminal from submission 1/campaign-030 and were not reopened by this repair-scoped audit. Retained packet evidence reports identity `SURVIVED`, wrong-reason `0`, blocked `0`, budget `197/210`, byte-identical generated receipts, empty pre/post diff, and clean-axiom closeout `210` theorems / `0 sorryAx`. These are inspection/replay evidence from campaign-030, not fresh audit execution.

## Decision coverage

| Repair obligation | Fresh result | Evidence |
|---|---|---|
| Cold detached inventory builds its own compiled modules | PASS — `.lake` was absent before execution; output contained exactly 79 atom and 20 theorem rows. | `evidence/cold-list.log` / `f442fcab98e48cd503d2e221770895dac305af1d4af91f44166c7c19376ce6fb` |
| Missing explicit gate path is caller-visible and fails before builds | PASS — exit 1 with `GATE-MISSING`; no work build was created. | `evidence/missing-explicit-gate.log` / `28b7be02331b04afc6a0cd877a42a03cdbb65af20d6fd31fa64410c622f04d4a` |
| Exact supplied gate reaches runner and records its path/hash | FAIL — exact gate exit 127 at line 23; runner and identity log were never reached. | `evidence/full-gate-v5.log` / `a607eb35fd571c74e831bd06bce698b174c5f65c4da909660f637e5f08a03147` |

## Disputed evidence

None.

## Failure modes altered

- No production model failure mode was altered by the repair: the equivalent repair commit changes the runner, generated receipts, supersession record, and task record, but no `lean/CardanoKeri/*` source.
- Cold inventory acquisition now builds its required modules and returns a non-empty exact inventory in a genuinely cold detached worktree; build failure remains caller-visible through the runner diagnostic.
- Missing explicit gate acquisition now fails fast and caller-visible with `GATE-MISSING`, as demonstrated by the negative control.
- The frozen acceptance gate introduces a new pre-run failure path: line 23 is executable prose rather than a comment. The shell reports `epic-owner: command not found` and exits 127 before the ancestry, inventory, campaign, axiom, and full-build legs.

## Lean outcomes and mutation adequacy

- Theorem outcomes: not reopened; campaign-030's packet-bound summary retains 20/20 REACHED+KILLED.
- Mutation adequacy: not rerun in this repair audit after the exact frozen gate failed. Campaign-030 retains 79/79 atom kills, 20/20 theorem-row kills, identity SURVIVED, zero excluded wrong-reason rows, zero blocked rows, and SET-POINT stopping.
- Axioms: campaign-030's retained raw stdout says `AXIOMS clean build: 210 theorems; sorryAx: 0`; the fresh gate never reached its axiom leg.
- Honest limit: this audit establishes the cold inventory and missing-path behavior freshly. It does not establish a fresh full campaign, supplied-gate identity logging, fresh axiom closeout, or fresh full `lake build`, because the sole authorized full gate aborted before those legs and the execution ceiling forbids a retry.

## Residuals

None. `INV-365-PROVENANCE` is BLOCKING and cannot become a residual.

## Candidate invariants

None.

## Onward discoveries — outside this ticket

None.

## Blocking findings

1. **F-365-001 / INV-365-PROVENANCE** — `/tmp/epic-367/to-365/gates/gate-v5.sh:23`: the exact packet-bound acceptance gate contains an uncommented prose line and exits 127 (`epic-owner: command not found`) before it invokes `run.sh`. The required property class remains violated: the frozen acceptance command does not replay from the bound candidate plus packet and does not record the supplied gate path/hash. Evidence: `evidence/full-gate-v5.log` (`a607eb35fd571c74e831bd06bce698b174c5f65c4da909660f637e5f08a03147`) and `evidence/static-provenance.log` (`a39827e9ce79cc83f03d62271d7a3bd3e6a894c0dba8aa18fff1337d03a0ccb8`). Honest limit: the runner itself passed the cold-list and missing-path sub-obligations; the failing frozen gate prevents assessment of the explicit supplied-path success branch in the authorized full command.

## Verification receipts

| Command | Exit | Duration | Evidence |
|---|---:|---:|---|
| `lean/mutants/run.sh --list` | 0 | 10.854 s | `evidence/cold-list.log` / `f442fcab98e48cd503d2e221770895dac305af1d4af91f44166c7c19376ce6fb` |
| `MUTATION_GATE_FILE=<missing> BUDGET_MAX=0 lean/mutants/run.sh --run <control>` | 1 (expected control RED) | 0.062 s | `evidence/missing-explicit-gate.log` / `28b7be02331b04afc6a0cd877a42a03cdbb65af20d6fd31fa64410c622f04d4a` |
| `bash /tmp/epic-367/to-365/gates/gate-v5.sh` | 127 | 0.027 s | `evidence/full-gate-v5.log` / `a607eb35fd571c74e831bd06bce698b174c5f65c4da909660f637e5f08a03147` |
| Static candidate/gate identity and rebase-equivalence receipt | 0 | 0.058 s | `evidence/static-provenance.log` / `a39827e9ce79cc83f03d62271d7a3bd3e6a894c0dba8aa18fff1337d03a0ccb8` |

## Advisories

None.
