# Freeze supersession v1 → v2 — issue 365 (A-001 additive freeze)

Authority: epic ruling A-001 (`/tmp/epic-367/to-365/answers/A-001-unobservable-atoms.md`),
NOTE-025 integration steps 1–3 + AUX rows + v2 freeze. Re-freeze by versioning,
never by overwriting: v1 artifacts and hashes are preserved below.

## v1 (frozen, preserved)

- Ledger `lean/SEMANTIC-ATOMS.md` SHA-256:
  `925da1965de854b089f262e8eddae0519ae88f3275bc6471622b7675128975be`
  (verified against `git show e03b678:lean/SEMANTIC-ATOMS.md`).
- Gate `/tmp/epic-367/to-365/gates/gate-v1.sh` SHA-256:
  `68426237888ae3c170c57362e97564bea6442df2e75a9b7359f1b1490b16e029`
  (file untouched; hash re-verified at freeze time).
- Planning commit: `e03b678a827077c05399421a40a7507d52db6ac5`.
- Denominators: 79 atoms / 18 theorem rows.

## v2 (frozen here; full campaign NOT yet run)

- Ledger `lean/SEMANTIC-ATOMS.md` SHA-256:
  `3c1d0c229d1d46fba6388919d95fc48467f0b7e6a517f767bea7c7bff6906c5a`
- Runner `lean/mutants/run.sh` SHA-256:
  `4fbedb99d616ac34f0887306d46e2d1d26e635b20f066fc63ebef3f099fde2ea`
- Spec `lean/mutants/mutants.txt` SHA-256:
  `8e9d636c7a92455a6c69e6599f6df5658c18893dc0442ff71e3b82599cbd5a67`
  (84 records: 79 atoms + AUX TH-06/03/08/09/12).
- Gate `/tmp/epic-367/to-365/gates/gate-v2.sh` SHA-256:
  `bddf56d64431f41390d9eeb1be8e13945f173a926b88537271a294008a6e1eeb`
  (ignored root `gate.sh` is byte-identical: `cmp` clean).
- Owned sensors (`lean/mutants/sensors/`, example-only, no theorems):
  `5a9690c870b7dea1ed29d3ce8a9e76e80aa02ff79cfd990c9111e67a720fc1e2  AUX-TH03.sensor.lean`
  `bf1690c3e4db5b0ef0824bcc8ea609743dee61f539751a296f1170cfdedf3926  AUX-TH08.sensor.lean`
  `be765119609ab6dd6e25cfa8d93985603122d351a6a10392a7fc4df474f369a6  AUX-TH09.sensor.lean`
  `9872df6ac4eeb816a5fb585e671c921c44313496891078690ccbb8db76cf9031  AUX-TH12.sensor.lean`
- Owned witnesses TH-19/20 (`lean/mutants/witnesses/`):
  `a53f1902cdbdc3a7bfa78dbde0bb02737c3ca6f01a83f9144ef5ccbd3c8ff0c8  TH-19.lean`
  (`CardanoKeri.Mutants.CG03_ownerAndHook_requires_hook`, clean rc0)
  `81a22c65a97487c3d25492dcff3f961b9a30ca26635c7b2327cd54ac8d93dd50  TH-20.lean`
  (`CardanoKeri.Mutants.CG09_refundAll_returns_exact_bond`, clean rc0)
- Denominators: 79 atoms / 20 theorem rows.
- Base commit at freeze: `27295bba437c567256cc1b20eb17d9fb0e20848b`
  (v2 files uncommitted at freeze; committed hashes recorded at submission).

## Why (what changed, what evidence)

Campaign-021 (preserved under `/tmp/epic-367/to-365/owner-1/campaign-021`)
reached 77/79 atoms and 5/18 theorem rows: CG-03
(`CG-M03-ownerAndHook-no-plugin`) and CG-09 (`CG-M09-refundAll-zero-bond`)
SURVIVED because the frozen named theorems (`ownerAndHook_trivial_breaks_inv`
exercises only the both-true case; `refundAll_never_locks` concludes only
`locked`-unchanged) cannot observe amount/destination drift. Four further Cage
rows had no shared exact failure (`delegated_permissionless`,
`ownerAndHook_trivial_breaks_inv`, `owner_swaps_plugin`,
`refundAll_fold_locks_nothing`). Q-001 parked on this gap; A-001 authorized
the additive escape hatch already used in-epic (registry R14 theorems):
additive owned assertions alongside — never instead of — the frozen theorems.

## Unchanged surfaces (still frozen)

- 79 atom rows: same IDs, severities, canonical mutants.
- Original 18 theorem rows: same qualified names and witness surfaces.
- Zero edits to any statement in `CardanoKeri/*.lean`
  (`git status`/`git diff HEAD` on `lean/CardanoKeri/` empty at freeze).
- Finite operator set, stopping reason `frozen-ledger`, budget hard ceiling 210
  (full-run budget 197: 158 atoms + 20 witnesses + 2 TH-06 AUX + 12 sensor AUX
  + 5 closeout).
- AUX TH-06 (`bypassed` Inv-holds) retained with its full-build attribution.

## Added surfaces (v2 only)

- Ledger: TH-19/20 rows (`Mutants.CG03_ownerAndHook_requires_hook`,
  `Mutants.CG09_refundAll_returns_exact_bond`); CG-03/CG-09 owning sets are
  supersets retaining the frozen theorems.
- Runner: denominator 20; CG-03/CG-09 additive legs (same 2-build atom budget,
  file-first error at/after the appended declaration); generic AUX sensor
  branch for TH-03/08/09/12 (clean sensor + mutated prefix + mutated sensor =
  3 builds each, example-only/sorry guards, file-first sensor attribution);
  sensors hashed into pre/post CLEAN proof and receipt hash.
- Gate v2: counts/totals/final 20; CG-03/09 superset + additive-row predicates;
  4-sensor presence + example-only/sorry-free; summary additive-kill rows;
  budget `builds_spent<=210` with `budget==210`; prepost diff present + empty;
  receipt comparisons retained.
- Each new gate predicate was falsified with a temp control (see
  `/tmp/epic-367/to-365/owner-1/handoffs/v2freeze/` logs); every control fails
  nonzero for its intended reason.

## Status

Hashes frozen. Full v2 campaign NOT run: it starts only after the epic owner
records these v2 hashes in the parent STATUS.

## v3 supersedes v2 after campaign-026 RED

Campaign-026 did run from the v2 hashes and was preserved at
`/tmp/epic-367/to-365/owner-1/campaign-026`: 79/79 atoms, 18/20 theorem rows,
2 blocked, 0 wrong-reason exclusions, identity survived, clean axiom account,
195/210 builds, exit 1. TH-19 and TH-20 were blocked only because the witness
validator required the exact application on the physical `example` line while
both valid witnesses place the application on a following line.

The v3 repair changes no ledger, spec, sensor, witness, operator, model, or
theorem statement. It changes only the runner's exact-application parser to
recognize the complete multiline example declaration, and adds two gate calls
that exercise the fixed predicate on TH-19/20 before the campaign:

- Ledger SHA-256 (unchanged):
  `3c1d0c229d1d46fba6388919d95fc48467f0b7e6a517f767bea7c7bff6906c5a`
- Spec SHA-256 (unchanged):
  `8e9d636c7a92455a6c69e6599f6df5658c18893dc0442ff71e3b82599cbd5a67`
- Runner v3 SHA-256:
  `bb465537d5aa1f97265670d934d988ef1edd21b4cf168264698cc45869f84520`
- Gate v3 SHA-256:
  `e5b340342920e889a6c7983933f6b13cac439b02e391bcf96c5690a210f60368`
  (`/tmp/epic-367/to-365/gates/gate-v3.sh`, byte-identical to ignored root
  `gate.sh`; gate-v1 and gate-v2 remain preserved unchanged).

Parser controls are preserved under `handoffs/v3freeze/`: both real multiline
witnesses return 0; deleting each exact application returns 2 with
`WITNESS-EXACT-MISSING`.

## v3 campaign-027 GREEN (receipt-only change after)

Campaign-027 ran once from the frozen v3 inputs (BUDGET_MAX=210) at
`/tmp/epic-367/to-365/owner-1/campaign-027`, stdout
`handoffs/campaign-027-stdout.log`, rc=0: atoms 79/79 KILLED, theorem rows
20/20 (REACHED+KILLED, incl. TH-19/20 via CG-M03/CG-M09 additive kills and
TH-03/08/09/12 + TH-06 via AUX), BLOCKED 0, wrong-reason exclusions 0,
identity control SURVIVED, clean axiom account 185 theorems / 0 sorryAx,
PREPOST clean, `builds_spent=197 / budget=210`, PROVENANCE source
`27295bb` with the v3 ledger/runner/spec hashes. Generated receipts were
copied byte-for-byte to `lean/CHECKPOINT-MUTANTS.md` and
`lean/REGISTRY-MUTANTS.md` (`cmp` clean); no runner input (ledger, runner,
spec, sensors, witnesses, gate) was modified — receipts only.

## v4 cold-acceptance repair (audit-1 PROVENANCE FINDINGS)

Submission-1 candidate `3568e9f` replayed 99/99 semantic rows but the frozen
acceptance boundary failed in a cold detached worktree: `--list` invoked
compiled imports it never builds (exit 1 `unknown module prefix`), and
`--run` hashed the absent ignored root `gate.sh` ( auditor evidence
`audit-1/evidence/focused-list.log`, `full-gate.log`, `missing-root-gate.log`).
Per AUDIT-REPAIR-028, ledger denominator, atom mappings, witnesses, sensors,
theorem statements, and `lean/CardanoKeri/*` are untouched; only the
cold-worktree boundary is repaired:

- `--list` builds
  `CardanoKeri.CheckpointGoals/RegistryGoals/Cage/Samaritan` before the
  `#check` inventory (own oleans, never owner-warmed); the
  compiled-declaration check is retained.
- `--run` resolves the invoking frozen gate via `MUTATION_GATE_FILE` with a
  documented fallback to ignored root `gate.sh` for direct owner runs;
  a missing resolved gate fails fast (`GATE-MISSING`, zero builds spent);
  the resolved file is hashed in both pre/post manifests (drift still
  rejected by the prepost identity check; provenance row kept).
- Gate v4 exports `MUTATION_GATE_FILE` (its own path) and raises only the
  `--list` timeout 30→300 (measured 15s end-to-end cold `--list`: ~8s module
  build + toolchain startup; ~20x margin).
- Ledger SHA-256 (unchanged):
  `3c1d0c229d1d46fba6388919d95fc48467f0b7e6a517f767bea7c7bff6906c5a`
- Spec SHA-256 (unchanged):
  `8e9d636c7a92455a6c69e6599f6df5658c18893dc0442ff71e3b82599cbd5a67`
- Runner v4 SHA-256:
  `932e34da034cf34678bc126af9fa198c05cb95cf4c67e1c982c763868c1dee95`
- Gate v4 SHA-256:
  `86b949d3c0f8a4084e5493ce3c1abc5939bdf6c857c8fbc4fdc03fc4368b42d4`
  (`/tmp/epic-367/to-365/gates/gate-v4.sh`, byte-identical to ignored root
  `gate.sh`; gates v1–v3 preserved byte-identical).
- Full-run budget unchanged: 158 atoms + 20 witnesses + 2 TH-06 AUX +
  12 sensor AUX + 5 closeout = 197 (ceiling 210); the `--list` build leg
  spends no campaign budget.
- Cold controls in `handoffs/v4freeze/` (`RESULTS.tsv`, all PASS): finding
  reproductions (no-build inventory rc1, absent-gate hash crash rc1),
  offline cold module build rc0, v4 `--list` genuinely-cold rc0 79/20,
  verbatim gate list leg fresh-cold rc0 79/20, missing/var-missing gate
  fast `GATE-MISSING` rc1 with zero builds, var-set BUDGET_MAX=0 honest RED
  with resolved gate-v4 path+hash in pre-hashes, synthetic pre/post gate-row
  drift rejected.
- Exactly one full v4 owner campaign follows (campaign-028, BUDGET_MAX=210).

## campaign-028 pause/supersession disposition (NOTE-029 terminal transition)

Campaign-028 started from pre-base v4 inputs but was SIGSTOP-suspended at
RG-phase per milestone pause, then terminated as a superseded pre-base
partial on the NOTE-029 terminal transition (base
`370a23b64a581c7ad80681700a459372b8005ba9`, rebased HEAD `16f7a5b3`). It is
not evidence and never resumes. Its 74-line stdout log is preserved at
`handoffs/campaign-028-stdout.log` (SHA-256
`04bc438fb089cf04317047323c88f165cc0ca0620e9983c3a444c0da3c7fba70`).
The stale watcher pgid was left dead. The single terminal campaign runs
fresh as campaign-029 from the rebased tree.

## v5 terminal-base freeze (NOTE-029)

Rebased HEAD `16f7a5b33e1514395acde2ebe84faa13f3973a04` descends from the
exact epic-owner C1+C2 base `370a23b64a581c7ad80681700a459372b8005ba9`
(`git merge-base --is-ancestor` rc0; reversed/bogus controls rc1/rc128).
Four ticket commits sit above the base; rebase had no conflicts; the v4
repair edits were verified restored byte-for-byte
(`git diff --binary | git hash-object --stdin` =
`a42c306edf10a0cf833c0a547b64e4c08c1646f3`). Changes since v4:

- Runner: receipt template `Terminal merged base: pending-premerge` now names
  the exact base (historical `Model base`/`Pre-slice base` preserved). No
  logic change. Runner v5 SHA-256:
  `4e9ee740d01bad45335be1c914865517472d11c8ff0b3c2d3332067e9b063c7e`
- Gate v5 SHA-256:
  `10f06795bb5bb279a585466f4245ec0c10a28a4cc7c9ea07b0454a6d5e82719b`
  (`/tmp/epic-367/to-365/gates/gate-v5.sh`, byte-identical to ignored root
  `gate.sh`; gates v1–v4 preserved byte-identical). Adds: ancestry proof
  (fail-fast pre-build), generated-receipt exact-base assertions, all v4
  repairs retained (MUTATION_GATE_FILE export, list timeout 300).
- Ledger `3c1d0c22…`, spec `8e9d636c…`, sensors+witnesses `6fdeab7a…`:
  all unchanged and re-verified (per-file sensors/witnesses match v2).
- Controls in `handoffs/v5freeze/` (all PASS): receipt-base NEG/POS per file,
  ancestry POS/NEG-reversed/NEG-bogus, fresh-cold `--list` rc0 79/20 (15s),
  missing/var-missing gate fast `GATE-MISSING` rc1 zero-build, var-set
  BUDGET_MAX=0 honest RED with gate-v5 path+hash in pre-hashes, synthetic
  pre/post gate-row drift rejected.
- Full-run budget still 197 (ceiling 210). Exactly one terminal campaign
  follows (campaign-029, BUDGET_MAX=210).

## campaign-029 terminal GREEN (submission-2 evidence)

Campaign-029 ran once from the frozen v5 inputs (BUDGET_MAX=210) at
`/tmp/epic-367/to-365/owner-1/campaign-029`, stdout
`handoffs/campaign-029-stdout.log`, rc=0: atoms 79/79 KILLED right-reason
(CG-03/CG-09 via additive Mutants tokens; merged-base inversion theorems
such as `Step.reopen_iff`/`processBody_register_iff` appear only as extra
counted context inside exact owning intersections), theorem rows 20/20
(REACHED+KILLED: 13 shared + TH-06 AUX + 4 sensor AUX + TH-19/20 via
additive atom kills), BLOCKED 0, wrong-reason exclusions 0, identity control
SURVIVED, clean axiom account 210 theorems / 0 sorryAx (merged base adds
C1+C2 inversion theorems to the pre-merge 185; exact 210/210 account
enforced by the runner predicate), PREPOST clean, `builds_spent=197 /
budget=210`, GATE resolved to root `gate.sh` == gate-v5
`10f06795…`, receipts name terminal base `370a23b…`. Generated receipts
copied byte-for-byte to `lean/CHECKPOINT-MUTANTS.md` and
`lean/REGISTRY-MUTANTS.md` (`cmp` clean); `lean/CardanoKeri/` diff empty.
