# Tasks — #92 R-KEL checkpoint advance-storage & contention model

Task IDs are numeric (`T92NN`) so the `Tasks:` commit trailer satisfies the
finalization commit-gate. `docs(...)` slices are trailer-exempt by the gate but
still carry the trailer for the two-sided link. **All behavior/assertion slices
(1–9) belong to the exact pair** (driver `%1291` Opus 4.8 high; navigator `%1293`
Codex gpt-5.6-sol high), dispatched only after epic-owner `PLAN-ACCEPTED`. The
ticket owner `%1292` writes none of the evidence code, tests, fixtures, or
harnesses.

## Bootstrap (ticket owner — done / this run)

- [X] T92-B1 — Verify clean start (main @ `fa89c32`, no prior #92
  branch/worktree/spec/PR); bootstrap issue-backed worktree + branch
  `docs/92-checkpoint-contention`.
- [X] T92-B2 — Add PR-life `gate.sh` (`git diff --check` → `accept.sh` hook →
  `just ci`); open draft PR #104. Commit `chore: add gate.sh` (`b14d4c3`).
- [X] T92-B3 — Author `specs/92-checkpoint-contention/spec.md` (the planning
  record: logical/physical split, three candidates, falsifiable matrix, evidence
  plan, NOTE-013…018).

## Slice 0 — planning artifacts  (ticket owner; gate-lifecycle + planning commits after epic review)

- [X] T9200a — Author `plan.md` (owned-file sets, thresholds-before-measurement
  gate, evidence discipline, `accept.sh` contract, gate.sh tolerant-then-strict,
  dependency-ordered slices, explicit commit history).
- [X] T9200b — Author `tasks.md` (this file).
- [X] T9200c — Author `accept.sh` as the **RED-first final-acceptance skeleton**:
  structural FR checks over `spec.md` (pass now) — including the **NOTE-019/NOTE-020
  Candidate-A correction**: the minted AID-bound steady checkpoint asset
  `(checkpoint_policy_id, aid_asset_name)` + its domain-separated 32-byte
  `aid_asset_name` derivation via the **native `blake2b_256` builtin (require BLAKE2b;
  reject a BLAKE3 locator derivation without rejecting the #97 `blake3(icp)` genesis
  binding)**, the #99 combined policy-id=script-hash (naming/binding the combined
  script; the token **caged inductively** by mint-placement + spend-continuation, not
  by the equality alone), the `CheckpointStateOutput` shape + datum/address
  distinction, the `delta = 0`
  rotation, the **C9** generic-discovery criterion + falsifier, the ACDC user
  story, and a **negative guard** rejecting reintroduction of the
  bespoke/authoritative QVI-owned `AID → UTxO` database framing; final-deliverable
  gates (thresholds ordering, evidence-filled, no `MEASURE`/`PROVE`/`VERIFY` left,
  live smoke recorded, exactly-one selection + rejected/residual, canonical docs
  carry the decision, R-KEL classification + #99 invariants preserved) that are
  **RED** now and fail-safe on absent artifacts; the **negative** "selection without
  evidence" guard and the "filled-but-unselected" guard; structured-file-first
  parsing of `evidence/matrix.tsv` + `DECISION.md`. `sh -n` clean, `chmod +x`,
  demonstrate RED at planning HEAD; C9 positive/negative fixtures exercised.
- [X] T9200d — Create `questions/QUESTION-001-thresholds.md` (recommended defaults
  + provenance + impact + exact operator decision needed). **Measurement hard-stops
  until answered.**
- [X] T9201 — (ticket owner, pre-dispatch; **lands before T9200**) gate-lifecycle
  commit `chore(92): make acceptance gate tolerant until decision`: `gate.sh` requires
  the **current slice's staged `accept.sh <slice-target>` check** (`spec` at planning
  HEAD) **+ `just ci` (strict)** every slice, while the **`final`** `accept.sh` verdict
  is **run + reported but tolerant** (do not abort) for in-flight slices and **strict
  from the decision slice (Slice 9)** — removing the tolerance bypass there (NOTE-003
  item 4). Staged **only `gate.sh`**. Body trailer `Tasks: T9201`.
- [X] T9200 — Commit the four ticket-owned planning files (`spec.md`, `plan.md`,
  `tasks.md`, `accept.sh`) as **one** planning commit landed **after** the T9201 gate
  commit — so the planning tree it stamps already passes `./gate.sh` — and **after**
  explicit epic-owner `PLAN-ACCEPTED`: `docs(92): add checkpoint-contention plan,
  tasks, and RED acceptance skeleton`, body trailer `Tasks: T9200`.

## Slice 1 — evidence schema + RED final-acceptance contract  (pair, RED→GREEN)

Owned files: `specs/92-checkpoint-contention/evidence/**`,
`specs/92-checkpoint-contention/accept.sh`, `spikes/92-checkpoint-contention/README.md`.
One bisect-safe commit.

- [ ] T9211 — **RED.** Materialize the machine-readable **schema** only:
  `evidence/matrix.tsv` with the fixed **10-column, tab-separated** header/column
  contract (`criterion  candidate  scenario  transaction  metric  value  unit
  class  outcome  provenance`) and **one literal placeholder row per cell in the
  plan's Required-coverage map** (`outcome=MEASURE`/`PROVE`/`VERIFY`) — every
  `COMMON`/`A`/`B`/`C` cell the map names, so `final`'s coverage check has the full
  set to fill; `evidence/evidence.json` skeleton (tool-versions/commands/
  protocol-params keys empty, `thresholds_commit` empty, `selection` null).
  Strengthen `accept.sh` with the schema assertions (10-column vocabulary — the
  criterion set is `C1a…C8` **plus C9** (per-candidate generic discovery) — + the
  five evidence classes measured/derived/estimated/declared/unsupported — **no**
  `class=proved`; `jq`-parsed `evidence.json`; header/column-count/duplicate-row-key
  checks; the **Required-coverage map** — `COMMON` only on C1a Step/Finish, C3b, C5,
  C7-lifecycle; `A/B/C` elsewhere (incl. **C9 A/B/C**); placeholder detection; the
  threshold-ordering,
  exactly-one-selection + exactly-two-rejected + complement, and negative
  "selection-without-evidence" guards) **and the `accept.sh schema` staged target**.
  Demonstrate RED on the placeholder-only tree (unfilled + unselected) for the
  `final` verdict, while `accept.sh schema` flips GREEN. Log RED in
  `spikes/92-…/README.md`.
- [ ] T9212 — **GREEN (schema, not data).** The schema files parse cleanly, the
  contract asserts exactly the intended shape, the **`accept.sh schema` staged
  target is GREEN**, and the **`final`** `accept.sh` verdict remains correctly
  **RED** on placeholders (this slice does not fill numbers). `./gate.sh` passes on
  doc-hygiene + the staged `schema` check + `just ci` (tolerant `final` hook).
  Commit once:
  `test(92): add machine-readable evidence schema + RED final-acceptance contract`,
  body trailer `Tasks: T9211, T9212`.

## Slice 2 — ratify thresholds before measurement  (pair, RED→GREEN; own commit)

**GATE: do not start until the operator answers `QUESTION-001-thresholds.md`.**
Owned files: `specs/92-checkpoint-contention/thresholds.md`, `…/accept.sh`. One
bisect-safe commit, landed **before any measurement**.

- [ ] T9221 — **RED.** Add the `accept.sh thresholds` staged target + the ordering
  guard: a ratified `thresholds.md` must exist and carry the **machine-readable
  `key/value/unit/provenance` block** (plan §Ratified-thresholds machine-readable
  format). `check_thresholds_values` **parses each required key** — `C2_ADVANCE_SLO`,
  `C3_CAPITAL_LOCK_CAP`, `C3B_BLOAT_CAP`, `C3B_ABANDONED_ADA_CAP`,
  `C4_EMERGENCY_LATENCY_SLO`, `C6_PROOF_REDEEMER_CAP`, `C6_WHOLE_TX_CAP`,
  `C6_READ_EXMEM_CAP`, `C6_READ_EXCPU_CAP`, `C8_DOWNSTREAM_CAP`, `TIMEOUT`, `K_SWEEP`,
  `K_PROVISIONAL` — and **validates each key's value against its grammar and its
  `unit` against the key's allowed unit, rejects placeholders, and requires
  `K_PROVISIONAL ∈ K_SWEEP`** (NOTE-004 item 1); not mere token presence. Its
  ratifying commit SHA is **computed from git history**
  (`git log -1 --format=%H -- specs/92-checkpoint-contention/thresholds.md`), must
  **equal** each evidence artifact's recorded `thresholds_commit`, and must be a
  **strict ancestor of the latest data-bearing revision of every measurement
  artifact** (matrix.tsv, evidence.json, REPORT.md, live-smoke.tsv, raw logs —
  NOTE-004 item 4). **No self-referential `RATIFIED_COMMIT` in `thresholds.md`**
  (NOTE-003 item 1). Reject malformed / non-40-hex commit references. Demonstrate RED
  (no `thresholds.md` yet).
- [ ] T9222 — **GREEN.** Author `thresholds.md` from the operator answer as the
  machine-readable block: `C2_ADVANCE_SLO` (advances/block), `C3_CAPITAL_LOCK_CAP`
  (ada per 10⁶ active AIDs), `C3B_BLOAT_CAP` (count) **+ `C3B_ABANDONED_ADA_CAP`
  (ada)**, `C4_EMERGENCY_LATENCY_SLO` (blocks), `C6_PROOF_REDEEMER_CAP` (bytes) **+
  `C6_WHOLE_TX_CAP` (bytes) + `C6_READ_EXMEM_CAP` (mem_units) + `C6_READ_EXCPU_CAP`
  (cpu_units)**, `C8_DOWNSTREAM_CAP` (count), `TIMEOUT` (blocks), and `K_SWEEP` +
  `K_PROVISIONAL` (count) — each with **concrete value + allowed unit + provenance
  only, and no self-referential commit SHA** (NOTE-003 item 1). The
  `accept.sh thresholds` staged target flips GREEN; `./gate.sh` passes. Commit once:
  `docs(92): ratify measurement thresholds (SLO/cap/timeout/K) before measurement`,
  body trailer `Tasks: T9221, T9222`. **The ratifying commit SHA is derived from git
  history; every later evidence artifact records it as `thresholds_commit`, and
  `accept.sh` checks the ordering.**

## Slice 3 — transient inception-cage lifecycle + registration pipeline  (pair, RED→GREEN)

Owned files: `spikes/92-checkpoint-contention/**` (transient-cage prototype +
harness), `specs/92-checkpoint-contention/evidence/**`, `…/accept.sh`. One
bisect-safe commit. **Registration-pipeline transactions measured at their OWN
boundaries; never summed with the rotation advance.**

- [ ] T9231 — **RED.** Add full-tx harness assertions for the **common per-attempt
  transient cage/thread token**: mint **tied to the consumed attempt input** (one
  input cannot fund two live attempts); Step **preserves exactly one** token in
  **exactly one** continuing output (address+value+**token**), carrying `cv`
  forward; Finish **consumes-and-burns-or-promotes exactly once**; bounded
  **timeout → reclaim/burn** that is **deposit-funded** and **cannot activate or
  bypass byte binding**. Add the **C5** cross-AID-interference attack (two concurrent
  unrelated inceptions must **not** consume each other's intermediate `cv`) — RED
  against a no-thread-token baseline (the spike `has_continuing_output` gap).
- [ ] T9232 — **GREEN + measure.** The prototype confines `cv` (**C5**: recorded
  `value=PASS`/`outcome=PASS` with a real evidence class + provenance — **not**
  `class=proved`; zero cross-AID interference). Measure and record to
  `evidence/matrix.tsv` / `evidence.json` **per the Required-coverage map**:
  **C1a** per-tx ex-units/size for **`COMMON` Step** and **`COMMON` Finish** (the
  shared registration pipeline) plus **`A/B/C` Activation** (oracle gate + MPFS
  absence/unicity + per-candidate selected-store materialization incl. A's post-Finish
  steady-token mint) — each at its own `transaction` boundary, class `measured`;
  **C3b** `COMMON` peak-concurrent-live-attempts and abandoned-attempt cost (min-ADA
  held + reclaim/burn) against `C3B_BLOAT_CAP` / `C3B_ABANDONED_ADA_CAP`, class
  measured/derived; **C5** `COMMON` confinement; and the **`C7 COMMON`**
  registration-lifecycle row (#99 invariants at the shared transient-cage scope)
  recorded `outcome=PASS` with class derived/declared — **not** the A/B/C-scoped C7
  rows (those land in Slice 7). Exact commands/tool-versions/protocol-params +
  realistic non-zero MPF depth recorded; `thresholds_commit` referenced.
- [ ] T9233 — Extend `accept.sh`: the `registration` staged target checks the filled
  **`COMMON` C1a Step/Finish, `A/B/C` C1a Activation, `COMMON` C3b, `COMMON` C5, and
  `C7 COMMON`** cells (non-placeholder), **not just the schema and — per NOTE-004
  item 2 — not the A/B/C-scoped C7 rows** (which are Slice 7). Keep the overall
  **`final`** verdict **RED** (matrix still has later-slice placeholders). The
  `accept.sh registration` staged target flips GREEN; `./gate.sh` passes on hygiene +
  staged `registration` + `just ci`. Commit once: `test(92): measure transient
  inception-cage lifecycle + registration pipeline (C1a/C3b/C5)`, body trailer
  `Tasks: T9231, T9232, T9233`.

## Slice 4 — common rotation harness + candidate A: rotation-advance, cost, min-ADA, proof, discovery  (pair, RED→GREEN)

Owned files: `spikes/92-checkpoint-contention/**` (the **shared** rotation harness +
candidate-A prototype), `specs/92-…/evidence/**`, `…/accept.sh`. One bisect-safe
commit. The harness is **reused unchanged by Slices 5/6** so A/B/C record the same
metric/scenario rows (NOTE-003 item 5).

- [ ] T9241 — **RED.** Add the **shared rotation-advance** full-tx harness (a
  **separate** tx from Step/Finish): §6a **two-seal threshold Ed25519** (Seal W vs
  stored `(witnesses,toad)`, Seal K vs endorsed `(W',toad')`, one advance), the
  selected-store update slot (per-candidate plug-in), continuing output/token
  placement, and the ledger→script `Data` boundary. RED assertions:
  `seq`-monotonicity / domain-binding replay rejection, same-AID serialization,
  stale-proof handling.
- [ ] T9242 — **GREEN + measure (candidate A).** Candidate A = direct datum spend
  (no MPF) over the **minted AID-bound steady checkpoint asset**
  `(checkpoint_policy_id, aid_asset_name)` (NOTE-019/NOTE-020; the mint — deriving
  `aid_asset_name` via the **native `blake2b_256` builtin, not BLAKE3** — the #99
  combined policy-id=script-hash with **inductive** mint-placement + spend-continuation
  caging, `CheckpointStateOutput` shape and `delta = 0` rotation are
  prototyped by the pair). Record **C1b** rotation-advance per-tx ex-units/size at
  N=1 (class `measured`); A's optional multi-AID **batch** sweep; **C3** state/min-ADA
  (A = O(#active AIDs) UTxOs, per-UTxO datum+token min-ADA × projected **active**
  population, reclaimable on close/burn; class derived); **C6** read cost (minimal
  datum read; class measured/derived); and **C9** trust-minimized generic discovery —
  an exact `(checkpoint_policy_id, aid_asset_name) → current unspent output` lookup
  via **any** generic Cardano asset index (**no** bespoke/authoritative QVI-owned
  `AID → UTxO` database), with rotation-successor tracking, migration/policy-version
  lineage, stale-result rejection against the ledger, and closed/tombstone semantics
  (recorded `value=PASS`/`outcome=PASS` with a real evidence class derived/declared —
  **not** `class=proved`; no numeric threshold). Same 10-column schema rows as Slices
  5/6. Reference `thresholds_commit`.
- [ ] T9243 — Extend `accept.sh` (the `candidate-A` staged target checks A's
  C1b/C3/C6/**C9** cells non-placeholder & classified); **`final`** verdict
  still **RED** (B/C + C2/C4/C7/C8 pending). The `accept.sh candidate-A` staged
  target flips GREEN; `./gate.sh` passes on hygiene + staged `candidate-A` +
  `just ci`. Commit once: `test(92): common rotation harness + candidate A —
  rotation-advance, cost, min-ADA, proof, discovery (C1b/C3/C6/C9)`, body trailer
  `Tasks: T9241, T9242, T9243`.

## Slice 5 — candidate B: rotation-advance, cost, min-ADA, proof  (pair, RED→GREEN)

Owned files: `spikes/92-checkpoint-contention/**` (candidate-B prototype, reusing
the Slice-4 harness), `specs/92-…/evidence/**`, `…/accept.sh`. One bisect-safe
commit.

- [ ] T9251 — **RED.** Plug candidate B (single-store MPF update at a stated
  **non-zero** proof depth) into the shared harness; RED assertions on B's
  selected-store update, stale-proof rejection, and same-AID serialization.
- [ ] T9252 — **GREEN + measure (candidate B).** Record **C1b** per-tx ex-units/size
  at N=1 (class `measured`); B's checkpoint-advance **batch** bound sweep against the
  binding mem/CPU/tx-size constraint (**not** #99's value-write `N`, NOTE-013; class
  measured); **C3** state/min-ADA (B = O(1) UTxO; class derived); **C6** read cost
  (MPF proof size at realistic depth, asymptotics **per the actual MPF impl** — not
  assumed; class measured/derived); and **C9** trust-minimized discovery (MPF
  inclusion vs windowed root **+ off-chain MPFS state materializer/proof builder** —
  an on-chain root is **not** free leaf discovery; `value=PASS`/`outcome=PASS`, class
  derived/declared). **Same metric/scenario rows as Slice 4** so A/B compare fairly.
  Reference `thresholds_commit`.
- [ ] T9253 — Extend `accept.sh` (the `candidate-B` staged target checks B's
  C1b/C3/C6/**C9** cells); **`final`** verdict still **RED**. The `accept.sh candidate-B`
  staged target flips GREEN; `./gate.sh` passes on hygiene + staged `candidate-B` +
  `just ci`. Commit once: `test(92): candidate B — rotation-advance, cost, min-ADA,
  proof (C1b/C3/C6/C9)`, body trailer `Tasks: T9251, T9252, T9253`.

## Slice 6 — candidate C: rotation-advance, lane grinding surface, cost, min-ADA, proof  (pair, RED→GREEN)

Owned files: `spikes/92-checkpoint-contention/**` (candidate-C prototype, reusing
the Slice-4 harness), `specs/92-…/evidence/**`, `…/accept.sh`. One bisect-safe
commit.

- [ ] T9261 — **RED.** Plug candidate C (per-lane MPF update, `lane = f(cesr_aid)`,
  K lanes at the ratified/predeclared K sweep) into the shared harness; RED
  assertions on C's per-lane store update, stale-proof rejection, same-lane
  serialization, and the **grindable-lane** surface (`lane = f(cesr_aid)`).
- [ ] T9262 — **GREEN + measure (candidate C).** Record **C1b** per-tx ex-units/size
  at N=1 (class `measured`); C's per-lane checkpoint-advance **batch** bound sweep
  (class measured); **C3** state/min-ADA (C = O(K) UTxO; class derived); **C6** read
  cost (per-lane MPF proof size, asymptotics **per the actual impl**; class
  measured/derived); **C9** trust-minimized discovery (per-lane MPF inclusion **+
  off-chain MPFS state materializer/proof builder**; `value=PASS`/`outcome=PASS`,
  class derived/declared); and record the grindable-lane surface for the Slice-7
  targeted-victim run (NOTE-017). **Same metric/scenario rows as Slices 4/5.**
  Reference `thresholds_commit`.
- [ ] T9263 — Extend `accept.sh` (the `candidate-C` staged target checks C's
  C1b/C3/C6/**C9** cells); **`final`** verdict still **RED** (C2/C4/C7/C8 pending). The
  `accept.sh candidate-C` staged target flips GREEN; `./gate.sh` passes on hygiene +
  staged `candidate-C` + `just ci`. Commit once: `test(92): candidate C —
  rotation-advance, lane grinding surface, cost, min-ADA, proof (C1b/C3/C6/C9)`, body
  trailer `Tasks: T9261, T9262, T9263`.

## Slice 7 — cross-candidate contention/latency/grinding + #99 invariants + downstream  (pair, RED→GREEN)

Owned files: `spikes/92-checkpoint-contention/**`, `specs/92-…/evidence/**`,
`…/accept.sh`. One bisect-safe commit. Completes the matrix.

- [ ] T9271 — **GREEN + characterize (throughput/latency).** **C2** sustained honest
  advance throughput recorded **separately** for the average/uncoordinated and the
  targeted/adversarial case, against the ratified SLO; **C4** emergency-rotation
  latency for the average lane **and** a grinding-targeted victim lane, against the
  ratified SLO; the targeted **lane-grinding** of C (`lane = f(cesr_aid)` — a victim
  lane degrades toward B under grinding; average ≠ adversarial, NOTE-017).
  **Honest classing (NOTE-003 item 6):** a script-budget/tx-size run is `measured`;
  max-operations/block from the protocol block budget is `derived`; targeted
  grinding / mempool scheduling is `estimated`/modeled **unless** an actual
  multi-block load run is performed — state the method + class per cell. Both cases
  recorded as distinct scenario rows.
- [ ] T9272 — **GREEN + prove (#99 invariants).** The **`A/B/C`-scoped C7** proofs at
  each candidate's stated scope (distinct from the `C7 COMMON` registration-lifecycle
  row landed in Slice 3): predecessor/version continuity, output confinement,
  owner-authorized-against-authenticated-AID, exact burn/lifecycle (A per-AID cage;
  B registry-scoped; C per-lane). Recorded **`value=PASS`/`outcome=PASS`** with a
  real evidence class (derived/declared) + provenance — **not** `class=proved`;
  **C7 reads `PROVE`, i.e. unbuilt until reproduced** — no "yes" from framing.
- [ ] T9273 — **GREEN + derive (downstream).** **C8** #68/#24/#25/#44 re-cut bound:
  the chosen-shape consequence for the #68 wire (leaf value B/C vs UTxO datum A),
  the #24 registry validator/redeemer (single vs per-AID vs per-lane spend + the
  depth-10 window fate), #25 proof construction (proof-simple A vs MPF-inclusion
  B/C), and the #44 live smoke — each expressible as a **versioned, additive,
  bisect-safe** change within the ratified bound (bounded number of downstream
  contracts/tickets, not a line-count proxy — NOTE-003 item 7); class
  derived/declared. Extend `accept.sh` (the `contention` staged target checks all
  material cells filled & classified; **`final`** verdict still **RED** because no
  selection/decision yet). The `accept.sh contention` staged target flips GREEN;
  `./gate.sh` passes on hygiene + staged `contention` + `just ci`. Commit once:
  `test(92): contention/latency/grinding + #99 invariants + downstream
  (C2/C4/C7/C8)`, body trailer `Tasks: T9271, T9272, T9273`.

## Slice 8 — provisional selection + named live-boundary smoke  (pair, RED→GREEN)

Owned files: `spikes/92-checkpoint-contention/**` (smoke harness),
`specs/92-…/evidence/{evidence.json,live-smoke.tsv,REPORT.md}`, `…/accept.sh`. Slice 8's
reviewed commit is the **immutable `EVIDENCE_REF`** consumed by Slice 9. One bisect-safe
commit.

- [ ] T9281 — **Provisional selection.** Apply the **selection rule** to the fully
  filled, threshold-anchored matrix (eliminate falsified candidates; among survivors
  pick the C2/C3/C4 dominator at lowest C6/C8; tie → smaller downstream re-cut,
  recorded honestly), and record it to `evidence.json.selection`. Write
  `evidence/REPORT.md` distinguishing
  **measured/derived/estimated/declared/unsupported** cells, with exact
  commands/tool-versions/protocol-parameters, non-zero MPF depths, mainnet
  declared-budget evaluation, and tx-size/min-ADA. **Provisional**, pending the smoke.
- [ ] T9282 — **Live-boundary smoke.** A **named** smoke on the operator's tx-tool
  devnet (`withDevnet`, `KERI_CAGE_SWEEP`/e2e family, reusing
  `Cardano.KERI.AID.E2E.MpfProof.prove` for real depth-N proofs) that **loads
  `cardano-tx-tools` and uses its inspect/validate workflow** around a **real
  submitted checkpoint-advance tx** and **asserts the node Phase-1/Phase-2 outcome**,
  failing loudly at the node boundary; record to the structured **11-column**
  `evidence/live-smoke.tsv` (plan §Live-smoke schema:
  `candidate  tx_id  network  node_version  protocol_params  tx_tool_version  inspect
  validate  phase1  phase2  note`) — selected candidate (`== evidence.json.selection`),
  **real 64-hex tx id**, network / node / protocol-param provenance, `cardano-tx-tools`
  version, **`inspect`=PASS + `validate`=PASS** (structured tx-tool evidence, NOTE-004
  item 5) **and** node **`phase1`=PASS + `phase2`=PASS**, with the **#99 devnet
  limitation** verbatim in `note` (devnet `maxTxExUnits` 140 M mem / 10 G CPU — mem
  10× mainnet, CPU identical; `evalTxExUnits` hung on the #99 cage →
  **conservative/declared**, not a precise mainnet ex-unit fit; a **single-tx smoke
  is not a throughput load test** and a unit/golden proof does **not** substitute —
  NOTE-003 item 6). Extend `check_smoke` to the 11-column contract (inspect / validate
  / phase1 / phase2 all `PASS`; 64-hex tx id; `candidate == selection`; non-empty
  provenance). The `accept.sh smoke` staged target flips GREEN; `./gate.sh`
  passes on hygiene + staged `smoke` + `just ci`. Commit once:
  `test(92): provisional selection + named live-boundary checkpoint-advance smoke`,
  body trailer `Tasks: T9281, T9282`.

## Slice 9 — final decision + canonical docs + final acceptance GREEN  (pair, RED→GREEN)

Owned files: `specs/92-checkpoint-contention/DECISION.md`, `…/accept.sh`,
`specs/68-keystate-shape/{identity-model.md,system-architecture.md}`, `gate.sh`.
One bisect-safe commit.

- [ ] T9291 — **Decide.** Author `DECISION.md` with the machine headers
  `SELECTED_CANDIDATE=<A|B|C>`, `REJECTED_CANDIDATES=<X,Y>` (**exactly two distinct,
  neither equal to the selection — the complement**), `SELECTION_RULE=`,
  `EVIDENCE_REF=`, `THRESHOLDS_COMMIT=`, and `RESIDUAL_RISKS=`; the applied selection
  rule, the **rejected alternatives** and their **residual risks**, and honesty
  boundaries (advance path unbuilt beyond the evidence scope; smoke is conservative;
  griefing mitigated not eliminated; freshness is a separate liveness knob). Set the
  headers so the **cross-bound references** hold (NOTE-004 item 3):
  `SELECTED_CANDIDATE == evidence.json.selection == live-smoke.candidate`;
  `THRESHOLDS_COMMIT == the computed threshold-file commit == evidence.json.thresholds_commit`
  (full 40-hex); `EVIDENCE_REF` **resolves** to the actual evidence commit
  (`git rev-parse`) — **Slice 8's immutable reviewed evidence commit**, which Slice 9
  references and never rewrites (if the smoke forced any evidence/selection change, a new
  evidence/smoke correction slice must have landed and been reviewed first, and that
  prior commit is referenced).
- [ ] T9292 — **Canonical docs.** Resolve `identity-model.md` §10 **thread 8**
  (contention/storage shape now decided) + §7c consequence line, and
  `system-architecture.md` §3 R-KEL note + §6 registry, to carry the decision —
  **preserving** the R-KEL on-chain-checkpoint (non-mirror) classification and the
  #99 ownership/token invariants. No reopening of the #91 logical decisions.
- [ ] T9293 — **GREEN.** Reference Slice 8's immutable reviewed evidence commit as
  `EVIDENCE_REF` (Slice 9 does **not** modify `evidence/**` or re-fill the matrix); flip
  the `gate.sh` `final` `accept.sh` hook **strict** (remove the tolerance bypass); the
  **`final`**
  `accept.sh` verdict (exactly-one-selection + exactly-two-rejected-complement +
  rejected/residual + the **cross-bound `SELECTED_CANDIDATE`/`THRESHOLDS_COMMIT`/
  `EVIDENCE_REF` references** + **ordering over all data-bearing artifacts** + the
  **full Required-coverage map** with the selected candidate carrying no
  FAIL/unsupported/placeholder + evidence-backed via parsed
  `evidence.json`/`REPORT.md`/11-column smoke + docs-carry-decision) and `./gate.sh`
  **pass GREEN**. Commit once: `docs(92): select
  the R-KEL checkpoint storage model — decision + canonical docs (thread 8)`, body
  trailer `Tasks: T9291, T9292, T9293`.

## Orchestrator finalization (ticket owner; post-slice, after review + push)

- [ ] T92-F1 — Update PR #104 body + issue #92: state the selected model, link
  #97/#99, note R-KEL classification + #99 invariants preserved. (`gh`, no file
  commit.)
- [ ] T92-F2 — Finalization audit (commit-gate over all commits; no open tasks;
  stamp satisfied `spec.md` success criteria); confirm `accept.sh` (strict) +
  `./gate.sh` GREEN + fresh CI green; drop `gate.sh` **last**
  (`chore: drop gate.sh (ready for review)`); `gh pr ready 104`. **Do not merge** —
  epic owner performs the guarded merge. Report `COMPLETE`.
  **GATE: do not start until the epic owner sends explicit `FINAL-AUDIT-ACCEPTED`
  after the latest reviewed slice SHA is pushed.**

## Explicitly out of scope (guard rails)

- Selecting the physical shape **in this planning record** (selection is Slice 9,
  evidence-gated — and permanent non-selection is **not** acceptable).
- Any production validator / Haskell / wire-schema / storage-layout code outside the
  labelled `spikes/92-checkpoint-contention/**` evidence area; no edits to
  `onchain/validators/cage.ak` / `#24` / `#68` production paths.
- Absorbing #24 (lifecycle/protocol), #25 (proof construction), #44 (live devnet
  product), or #68 (schema freeze) — only their **consequences** are documented.
- Reopening hybrid genesis, oracle gating, semantic-projection trust, the #91 teeth
  state machine, or the R-KEL checkpoint-vs-mirror classification — fixed inputs; a
  concrete contradiction is **escalated** to the epic owner.
- No CESR parser / projection verifier; no adjudicator/governance-quorum code.
- Summing the registration pipeline and the rotation advance into one per-tx budget
  claim; reusing #99 `Modify N` as the checkpoint-advance/genesis batch bound
  (NOTE-013/018).
