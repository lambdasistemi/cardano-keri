# Plan — #92 R-KEL checkpoint advance-storage & contention model

## Nature of the work

Design-**decision** ticket with a **delegated evidence** obligation. Unlike #91
(pure documentation), #92's matrix is closed by **whole-transaction-boundary
measurement + a live-devnet smoke** before a single physical model is selected.
The deliverable is therefore two-layered:

- a **planning record** (`spec.md`, already authored) that fixes the candidate
  set, the falsifiable matrix, the ratified-thresholds-before-measurement rule,
  and the evidence provenance — **no winner chosen, deciding cells `MEASURE`**; and
- an **evidence-gated decision** produced by dependency-ordered slices that ratify
  thresholds, measure each candidate at the real tx boundaries, run a named live
  smoke, then select **exactly one** candidate, record rejected alternatives +
  residual risks, and update the canonical docs.

Because every measurement harness, prototype validator, fixture, and the
evidence-schema assertions are **behavior-changing**, they are driven RED→GREEN by
the visible driver+navigator pair — **not** written by the ticket owner. The
ticket owner (`%1292`) owns only the ticket-local `spec/plan/tasks`, the RED-first
`accept.sh` acceptance **contract**, `gate.sh`, the `questions/` decisions, PR/issue
metadata, verification, and status. It **never** writes production or evidence code,
tests, fixtures, harnesses, or behavior-changing configuration.

## Owned-file set (whole ticket)

Ticket-owner-owned (the single planning commit + finalization):

- `specs/92-checkpoint-contention/spec.md`   (authored; the planning record)
- `specs/92-checkpoint-contention/plan.md`   (this file)
- `specs/92-checkpoint-contention/tasks.md`
- `specs/92-checkpoint-contention/accept.sh` (the RED-first final-acceptance
  **contract** skeleton — the acceptance *framework*, extended per-slice by the
  pair as the evidence schema solidifies; see "accept.sh contract" below)
- `gate.sh` (add / make tolerant-then-strict / extend / drop)
- `/tmp/epic-21/cardano-keri-92/questions/QUESTION-001-thresholds.md` (runtime
  decision surfaced to the operator — not a repo spec artifact)
- PR #104 body, issue #92 metadata (via `gh`, not files)

Slice-owned (driver `%1291` + navigator `%1293`), each slice pins its own subset:

- `spikes/92-checkpoint-contention/**` — the ticket-local **spike/evidence** area:
  the **shared** rotation harness, fair A/B/C prototype validators (one per
  candidate slice), the measurement harness, the transient-cage lifecycle
  prototype, and the live-boundary smoke harness. **Evidence, not production**
  (labelled as such in-file).
- `specs/92-checkpoint-contention/thresholds.md` — the ratified thresholds
  (Slice 2, its **own** reviewed commit, predating measurement). It carries the
  ratified **values + provenance only**: it **never** stamps its own commit SHA
  (a commit cannot contain its own hash — NOTE-003 item 1). The ratifying commit
  SHA is **derived from git history** (`git log -1 --format=%H --
  specs/92-checkpoint-contention/thresholds.md`) and referenced by every later
  evidence artifact as `thresholds_commit`.
- `specs/92-checkpoint-contention/evidence/` — machine-readable evidence: the
  fixed **10-column** `matrix.tsv` (schema below), `evidence.json` (tool versions
  / commands / protocol params / `thresholds_commit` / `selection`), raw run logs,
  the structured `live-smoke.tsv`, and `REPORT.md`.
- `specs/92-checkpoint-contention/DECISION.md` — the selected candidate + the
  **exactly two** rejected alternatives + residual risks, via machine headers
  (Slice 9).
- `specs/68-keystate-shape/identity-model.md` (**§7c consequence + §10 thread 8**)
  and `specs/68-keystate-shape/system-architecture.md` (**§3 R-KEL note, §6
  registry heading/body**) — canonical docs carry the decision (Slice 9).
- `specs/92-checkpoint-contention/accept.sh` — the RED-first final-acceptance
  contract **plus a staged (`accept.sh <slice-target>`) mode** giving each
  in-flight slice a real RED-before/GREEN-after target (NOTE-003 item 4); extended
  per measurement slice with the evidence-schema assertions, and flipped from
  tolerant to strict at the decision slice (Slice 9).

**Forbidden for every actor in this ticket** (guard rails):

- No production code under `onchain/`, `offchain/` **except** additive, clearly
  labelled evidence harness wiring that a spike genuinely requires (the smoke
  reuses `offchain/e2e/…/MpfProof.hs` `prove` and the `withDevnet` family). Any
  prototype **validator** lives under `spikes/92-checkpoint-contention/`, never in
  `onchain/validators/cage.ak` / `#24` / `#68` production paths.
- No absorbing #24 (full lifecycle/protocol), #25 (proof construction), #44 (live
  devnet product), or #68 (wire-schema freeze) — only their **consequences** are
  documented.
- No CESR parser / projection verifier, no adjudicator/governance-quorum code.
- No edits to sibling `specs/*/` other than `68-keystate-shape` (the canonical
  docs) and `92-checkpoint-contention`.
- No reopening of the #91 logical decisions, oracle gating, semantic-projection
  trust, the #91 teeth state machine, or the R-KEL checkpoint-vs-mirror
  classification — fixed inputs; a concrete contradiction is **escalated** to the
  epic owner, not silently resolved.

## Thresholds before measurement (hard gate — NOTE-016)

The matrix criteria that read "target / budget / bounded / SLO / cap" (C2, C3, C4,
C6, C8) and the transient-cage **timeout** and candidate-C **K** are **not
falsifiable until each names a concrete number**. Repository evidence pins the
mainnet ex-unit budget (14 M mem / 10 G CPU, #97/#99) and the devnet observation
(140 M mem / 10 G CPU, `evalTxExUnits` hang; #99) but **cannot** determine the
operator SLOs/caps. Those are therefore surfaced now in
`questions/QUESTION-001-thresholds.md` (concrete recommended defaults — labelled
policy proposals, not repository facts — + provenance + impact + the exact operator
decision needed). **Measurement hard-stops until the operator answers.** The
ratified thresholds then land in their **own reviewed commit** (Slice 2) carrying
**values + provenance only** — `thresholds.md` **never** stamps its own commit SHA
(NOTE-003 item 1). The ratifying commit SHA is **computed from git history**
(`git log -1 --format=%H -- specs/92-checkpoint-contention/thresholds.md`); every
later evidence artifact records it as `thresholds_commit`, and `accept.sh`
recomputes it, checks it equals the recorded header, and checks it is a **strict
ancestor of the latest commit of every data-bearing measurement artifact** —
`evidence/matrix.tsv`, `evidence/evidence.json`, `evidence/REPORT.md`,
`evidence/live-smoke.tsv`, and any committed raw measurement logs (NOTE-004 item 4;
skeleton/schema commits may predate thresholds, but the latest data-bearing revision
of each must follow). If the thresholds change, the **new** threshold commit
invalidates all prior measurements and **forces remeasurement**. **Choosing a
threshold after seeing a candidate's result is forbidden.**

### Ratified-thresholds machine-readable format (fixed contract — NOTE-004 item 1)

`thresholds.md` carries a **machine-readable ratified-values block** that
`accept.sh check_thresholds_values` parses and validates by **value + unit +
provenance** — not the mere presence of tokens like `C2`/`C3` and one digit
somewhere (NOTE-003 item 8, NOTE-004 item 1). The block is a fixed **4-column,
tab-separated** table delimited by the literal markers `<!-- THRESHOLDS:BEGIN -->`
and `<!-- THRESHOLDS:END -->`, with header row `key<TAB>value<TAB>unit<TAB>provenance`
and **exactly one row per required key**:

| key | value grammar | allowed unit | criterion |
|---|---|---|---|
| `C2_ADVANCE_SLO` | positive number | `advances/block` | C2 |
| `C3_CAPITAL_LOCK_CAP` | positive integer | `ada` (per 10⁶ active AIDs — basis stated in provenance) | C3 |
| `C3B_BLOAT_CAP` | positive integer | `count` (peak concurrent live attempts) | C3b (falsifier) |
| `C3B_ABANDONED_ADA_CAP` | positive number | `ada` (unreclaimable abandoned-attempt min-ADA ceiling) | C3b (falsifier) |
| `C4_EMERGENCY_LATENCY_SLO` | positive number | `blocks` | C4 |
| `C6_PROOF_REDEEMER_CAP` | positive integer | `bytes` | C6 proof/redeemer |
| `C6_WHOLE_TX_CAP` | positive integer | `bytes` | C6 whole-tx |
| `C6_READ_EXMEM_CAP` | positive integer | `mem_units` | C6 read ex-mem |
| `C6_READ_EXCPU_CAP` | positive integer | `cpu_units` | C6 read ex-cpu |
| `C8_DOWNSTREAM_CAP` | positive integer | `count` (downstream contracts/tickets) | C8 |
| `TIMEOUT` | positive integer | `blocks` | C3b / lifecycle |
| `K_SWEEP` | comma-list of ≥2 positive integers | `count` | C (all C rows) |
| `K_PROVISIONAL` | positive integer, **member of `K_SWEEP`** | `count` | C (all C rows) |

`check_thresholds_values` (extended by the pair in Slice 2, RED-first) validates,
for the block: **every required key present exactly once**; **value** matching its
grammar (a real number, or for `K_SWEEP` a comma-separated integer list) and **not**
a placeholder (`MEASURE`/`TBD`/`TODO`/`???`/`n/a`); **unit** equal to the key's
allowed unit (drawn from the matrix unit vocabulary
`{mem_units,cpu_units,bytes,ada,advances/block,blocks,count}`); **provenance**
non-empty; and `K_PROVISIONAL ∈ K_SWEEP`. It also keeps rejecting a self-referential
`RATIFIED_COMMIT=` (NOTE-003 item 1) — the ratifying SHA stays **computed from git
history**. Each matrix row whose criterion is capped is `PASS`/`FAIL`ed against the
matching key's value+unit; a threshold change lands a **new** threshold commit and
forces remeasurement.

## Evidence discipline (mandatory — brief / spec §Evidence)

Each measurement slice produces **raw + machine-readable** evidence
(`evidence/matrix.tsv` + `evidence/evidence.json` + raw logs + `REPORT.md`) that:

- measures at the **actual transaction boundary of each distinct transaction** —
  the **registration pipeline** (Step / Finish / activation-promotion) and the
  **rotation advance** (two-seal Ed25519 + storage update + `Data` boundary) at
  their **own** boundaries, and **never sums disjoint transactions** into one
  per-tx budget claim (NOTE-018);
- records exact **commands, tool versions, protocol parameters**, realistic
  **non-zero MPF depths**, **mainnet declared-budget** evaluation, **tx-size /
  min-ADA**, and, for the smoke, **actual node Phase-1/Phase-2** submission
  evidence;
- classifies **every** cell as one of **measured / derived / estimated / declared /
  unsupported** — C7 (#99 invariants) and C5 (confinement) read `PROVE`/`VERIFY`,
  i.e. **unbuilt until proved by the delegated prototype**, never asserted "yes"
  from framing.

`#99 Modify N ≈ 2` is a **value-write** bound and is **never** reused as the
checkpoint-advance or genesis batch bound (NOTE-013); each family's batch bound is
measured directly at its own boundary.

### Evidence schema (fixed contract — NOTE-003 item 2)

The five-column `criterion/candidate/value/class/provenance` TSV cannot distinguish
Step vs Finish vs activation, average vs targeted, metric/unit, or pass/fail. The
evidence is therefore recorded in a **fixed 10-column, tab-separated** `matrix.tsv`:

`criterion  candidate  scenario  transaction  metric  value  unit  class  outcome  provenance`

with these column contracts (all fields non-empty; the later `accept.sh` repair
enforces them):

- `criterion` ∈ `{C1a,C1b,C2,C3,C3b,C4,C5,C6,C7,C8,C9}` (spec matrix vocabulary; C9
  = trust-minimized generic discovery, a per-candidate design-property proof —
  `PASS`/`FAIL`, no numeric threshold, NOTE-019).
- `candidate` ∈ `{A,B,C}`, or `COMMON` **only** for genuinely shared rows (the
  transient-cage lifecycle).
- `scenario` ∈ `{single,average,adversarial,targeted-victim,peak,abandoned,batch,
  population}` — the axis distinguishing average vs targeted (C2/C4), peak vs
  abandoned (C3b), single vs batch (C1b), and per-population growth (C3).
- `transaction` ∈ `{Step,Finish,Activation,Rotation,Read,n/a}` — the **own** tx
  boundary, so C1a's Step/Finish/Activation are never summed (NOTE-018).
- `metric` — the named quantity (`ex_mem`,`ex_cpu`,`tx_size`,`min_ada`,
  `advances_per_block`,`latency_blocks`,`proof_bytes`,`redeemer_bytes`,
  `utxo_count`,`invariant`, …).
- `value` — the number, or `PASS`/`FAIL` for proof rows.
- `unit` — the unit (`mem_units`,`cpu_units`,`bytes`,`ada`,`advances/block`,
  `blocks`,`count`,`bool`); `n/a` allowed only on boolean/proof rows.
- `class` ∈ **exactly** the spec's five evidence classes
  `{measured,derived,estimated,declared,unsupported}` — there is **no**
  `class=proved` (NOTE-003 item 2).
- `outcome` ∈ `{PASS,FAIL,MEASURE,PROVE,VERIFY}`: `MEASURE`/`PROVE`/`VERIFY` are
  the **placeholder (RED)** states; `PASS`/`FAIL` are terminal vs the ratified
  threshold. A proved **C5/C7** invariant is `value=PASS`, `outcome=PASS` with a
  real `class`+`provenance` — **not** `class=proved`.
- `provenance` — command + tool version + protocol-params ref (+ the
  `thresholds_commit` the row was measured against).

**Row key** `(criterion,candidate,scenario,transaction,metric)` is unique.

**Required coverage (fixed map — NOTE-004 item 2).** Final acceptance
(`check_matrix_filled`) requires **exactly** the following
`criterion × candidate × scenario × transaction` cells present and non-placeholder —
`COMMON` **only** on the genuinely shared criteria/transactions, `A/B/C` on the
per-candidate ones. The `metric family` column is illustrative (the measured
quantities); the hard contract is presence + non-placeholder of each listed cell:

| criterion | candidate(s) | scenario(s) | transaction(s) | metric family |
|---|---|---|---|---|
| C1a | COMMON | single | Step, Finish | ex_mem, ex_cpu, tx_size |
| C1a | A, B, C | single | Activation | ex_mem, ex_cpu, tx_size |
| C1b | A, B, C | single (+ optional `batch`) | Rotation | ex_mem, ex_cpu, tx_size |
| C2  | A, B, C | average, adversarial | Rotation | advances_per_block |
| C3  | A, B, C | population | n/a | min_ada, utxo_count |
| C3b | COMMON | peak, abandoned | n/a | utxo_count, min_ada |
| C4  | A, B, C | average, targeted-victim | Rotation | latency_blocks |
| C5  | COMMON | single | n/a | invariant |
| C6  | A, B, C | single | Read | proof_bytes, redeemer_bytes, tx_size, ex_mem, ex_cpu |
| C7  | COMMON | single | n/a | invariant (registration lifecycle) |
| C7  | A, B, C | single | n/a | invariant (candidate-scoped #99) |
| C8  | A, B, C | single | n/a | downstream_count |
| C9  | A, B, C | single | n/a | discovery_property (invariant; PASS/FAIL, no numeric threshold) |

- **`COMMON` is legal only** for C1a Step/Finish, C3b peak/abandoned, C5 confinement,
  and the **C7 registration-lifecycle** row (the shared per-attempt transient cage);
  every other cell is candidate-scoped `A/B/C`. C1a **Activation** is per-candidate
  (selected-store materialization differs — incl. A's post-Finish steady-token mint),
  so it is `A/B/C`, never `COMMON`.
- The **`registration` staged target** requires only the rows that land in Slice 3 —
  C1a **COMMON** Step/Finish + **A/B/C** Activation, C3b **COMMON** peak/abandoned,
  C5 **COMMON** confinement, and **`C7 COMMON`** — and **must not** demand the
  A/B/C-scoped C7 rows (those land in Slice 7).
  (NOTE-004 item 2: staged `registration` no longer demands candidate C7.)
- A **selected** candidate at `final` must carry **all** of its own `A/B/C` cells
  **and** every required `COMMON` cell, each with a terminal `PASS`/`FAIL` outcome and
  **no `FAIL`/`unsupported`/placeholder** cell; the two **rejected** candidates keep
  their falsifying cells honestly (not erased).

`evidence.json` holds the tool-versions / commands / protocol-params, the recorded
`thresholds_commit`, and `selection` (null until **Slice 8**, which records the
provisional selection; Slice 9 **references** but never rewrites it).

### Live-smoke schema (fixed 11-column contract — NOTE-004 item 5)

The single-tx boundary smoke on the operator's tx-tool devnet is recorded in a
**fixed 11-column, tab-separated** `evidence/live-smoke.tsv` (header row exact,
≥ 1 data row), so the smoke carries **structured PASS evidence for
`cardano-tx-tools` inspect *and* validate in addition to the node Phase-1/Phase-2**,
plus tx id / network / node / protocol-params:

`candidate  tx_id  network  node_version  protocol_params  tx_tool_version  inspect  validate  phase1  phase2  note`

- `candidate` — must equal the **selected** candidate (`== evidence.json.selection`).
- `tx_id` — the **real submitted** checkpoint-advance tx id, `^[0-9a-fA-F]{64}$`.
- `network` — devnet network id/magic (non-empty).
- `node_version` — `cardano-node` version (non-empty).
- `protocol_params` — protocol-parameters ref/hash used (non-empty).
- `tx_tool_version` — `cardano-tx-tools` version (non-empty).
- `inspect` — `cardano-tx-tools` inspect outcome; **must be `PASS`**.
- `validate` — `cardano-tx-tools` validate outcome; **must be `PASS`**.
- `phase1` — node Phase-1 outcome; **must be `PASS`**.
- `phase2` — node Phase-2 outcome; **must be `PASS`**.
- `note` — non-empty; carries the **#99 devnet limitation verbatim** (devnet
  `maxTxExUnits` 140 M mem / 10 G CPU; conservative/declared, not a mainnet ex-unit
  fit).

`check_smoke` validates the header, column count (11), the `PASS`-only inspect /
validate / phase1 / phase2 gates, the 64-hex tx id, `candidate == selection`, and
non-empty provenance columns. This remains a **single-tx boundary smoke, not a
throughput/load claim**; a unit/golden proof does **not** substitute for the live
node boundary. (If the tool workflow is captured in referenced raw artifacts rather
than inline columns, those artifacts are enumerated in `evidence.json.commands` and
committed alongside — but the `PASS` gates above stay mandatory.)

## accept.sh contract (the RED-first final-acceptance skeleton)

`specs/92-checkpoint-contention/accept.sh` is a **real POSIX-shell** final
acceptance check authored **now** as the acceptance *contract*. It is:

- **structural (layer 1, GREEN at planning HEAD)** — over `spec.md`: the
  logical/physical split, three named candidates, the falsifiable matrix
  (C1a…C8 **plus C9** trust-minimized generic discovery), the transient-cage
  lifecycle, and the **NOTE-019/NOTE-020 Candidate-A correction** — the minted
  AID-bound steady checkpoint asset `(checkpoint_policy_id, aid_asset_name)` with its
  domain-separated 32-byte `aid_asset_name` derivation via the **native `blake2b_256`
  builtin (not BLAKE3)**, the #99 combined policy-id=script-hash naming/binding the
  combined script (the token **caged inductively** by mint-placement +
  spend-continuation, not by the equality alone), the `CheckpointStateOutput` shape,
  the datum/address distinction, the `delta = 0` rotation, the **inductive downstream
  trust boundary** (CIP-31 ref read → no spend validator / no KERI replay / no
  genesis-BLAKE3 / no MPF proof; only a bounded boundary check), the **C9 falsifier**,
  and the ACDC user
  story — including a **negative guard** that rejects any reintroduction of the
  bespoke/authoritative QVI-owned `AID → UTxO` database framing (it must remain a
  withdrawal/falsifier only);
- **RED on `origin/main`** (no spec dir) and **RED at this planning HEAD** (spec
  present, but thresholds/evidence/decision absent);
- **GREEN only** when **all** hold: `thresholds.md` exists and its **computed**
  ratified commit strictly predates every measurement commit; the machine-readable
  evidence (`matrix.tsv` + parsed `evidence.json` + `REPORT.md`) exists with
  provenance and **no material `MEASURE`/`PROVE`/`VERIFY` placeholder** remains; the
  structured live-boundary smoke result is recorded; **exactly one** candidate is
  selected with **exactly two distinct** rejected alternatives + residual risks; the
  transient inception-cage lifecycle is covered; and the canonical docs carry the
  decision with R-KEL classification + #99 invariants preserved;
- **fail-safe** — every gate first tests artifact existence and treats absence as
  RED (never a crash, never a false pass);
- **structured-file-first (real parsing — NOTE-003 item 3)** — `evidence.json` is
  **parsed with `jq`** (not `grep` over key names; the gate **fails closed** if no
  `jq`/equivalent is available), and `evidence/matrix.tsv` is validated by
  **header + column count + duplicate row-key + required-coverage** checks over the
  fixed 10-column schema (the coverage map above). The selection is read from
  `DECISION.md` **machine headers**. Ordering uses **repo-relative git pathspecs**
  (`git log -- specs/92-checkpoint-contention/evidence/matrix.tsv`, never an absolute
  path). Prose grep is used **only** for the canonical-doc decision presence +
  R-KEL-classification preservation;
- **ordering over all committed outputs (NOTE-004 item 4)** — `check_ordering`
  proves the computed threshold commit is a **strict ancestor of the latest commit of
  every data-bearing measurement artifact**, not just `matrix.tsv`:
  `evidence/matrix.tsv`, `evidence/evidence.json`, `evidence/REPORT.md`,
  `evidence/live-smoke.tsv`, and any committed raw measurement logs **when present**.
  Skeleton/schema commits may predate thresholds; the **latest data-bearing revision**
  of each named artifact must follow. Every SHA it handles is **full 40-hex validated**
  (repo-relative pathspecs, never an absolute path);
- **value/unit-validated (NOTE-003 item 8, NOTE-004 item 1)** — it parses the
  ratified `thresholds.md` **machine-readable block** (the `key/value/unit/provenance`
  table above), validating **each required key's concrete value against its grammar
  and its `unit` against the key's allowed unit** and rejecting placeholders — not the
  mere presence of tokens like `C2`/`C3` and one digit somewhere; it **rejects
  malformed / non-hex** commit references; it requires the recorded `thresholds_commit`
  to **equal** the computed threshold-file commit and to **strictly predate** every
  measurement artifact;
- **structured smoke + decision contracts (NOTE-003 item 3, NOTE-004 items 3/5)** —
  `live-smoke.tsv` is a fixed **11-column** contract (§Live-smoke schema, above)
  requiring the **selected** candidate, a **real 64-hex tx id**, network / node /
  protocol-parameter provenance, **`cardano-tx-tools` version + `inspect`=PASS +
  `validate`=PASS**, and explicit node **Phase-1=PASS / Phase-2=PASS** (structured
  columns, not substring presence). `DECISION.md` machine headers verify **exactly
  one** selected candidate and **exactly two distinct** rejected candidates (the
  complement — neither equal to the selection), the selection rule, non-empty residual
  risks, and the **cross-bound references**:
  `DECISION.SELECTED_CANDIDATE == evidence.json.selection == live-smoke.candidate`;
  `DECISION.THRESHOLDS_COMMIT == the computed threshold-file commit ==
  evidence.json.thresholds_commit`; and `DECISION.EVIDENCE_REF` **resolves to the
  actual evidence commit** (`git rev-parse` of the last `evidence/**` revision);
- **negatively guarded** — a named selection **without** `REPORT.md`, a parsed
  `evidence.json`, a complete matrix, the recorded smoke, and the canonical-doc
  update stays **RED** ("selection without evidence" is explicitly forbidden);
  likewise a selection with unfilled cells, missing provenance, or a
  threshold-ordering violation is **RED**, and a filled matrix with **no** selection
  is **also** RED (permanent non-selection fails the deliverable).

**Staged mode (NOTE-003 item 4).** Because the full final-acceptance verdict is
legitimately RED until Slice 9, `accept.sh` also exposes a **staged** invocation —
`accept.sh <slice-target>` (`schema`, `thresholds`, `registration`, `candidate-A`,
`candidate-B`, `candidate-C`, `contention`, `smoke`, and the default `final`) —
whose **targeted** assertions are **RED before** that slice's evidence lands and
**GREEN after**. This gives every in-flight slice a real GREEN target rather than
"GREEN because the final verdict remains correctly RED". `gate.sh` runs the current
slice's staged target **strict** and the `final` verdict **tolerant** (report-only)
in flight; Slice 9 flips `final` strict and removes the tolerance.

The pair **extends** this contract per measurement slice (finer evidence-schema
assertions + the slice's staged target, RED-first) and **flips `final` strict in
`gate.sh`** at the decision slice. The ticket owner authors only the acceptance
*framework/logic* (including the staged targets), not the evidence data or harness
it validates.

## gate.sh — slice-local strict; final verdict tolerant-then-strict in flight

`gate.sh` (bootstrapped at `b14d4c3`, made tolerant by **T9201**) runs
`git diff --check`, then the **current slice's staged `accept.sh <slice-target>`
check (strict)** (`spec` at planning HEAD), then the **`final` `accept.sh` verdict
(run + reported, tolerant in flight)**, then `nix develop --quiet -c just ci`.
The **`final` verdict** is expected **RED at planning HEAD and at every in-flight
slice until the decision lands** — documented, **not** a claimed green planning gate
(constraint 7) — but each slice's **staged target is GREEN once that slice's
evidence lands**, so every in-flight slice has a real pass/fail target (NOTE-003
item 4).

A ticket-owner `chore(92): make acceptance gate tolerant until decision` commit
(**T9201**, landed **before** the T9200 planning commit) wires this: the **staged
slice check + `just ci` are required (strict)** every slice, while the **`final`
verdict is tolerant** (run + report RED, do not abort) for in-flight slices and
**strict** from the decision slice (Slice 9) onward, which also removes the tolerance
bypass. Each slice's own
RED→GREEN scope is verified by the navigator against the exact committed SHA; the
overall `final` verdict stays RED until Slice 9 by design.

## Slice breakdown (dependency-ordered; each = one bisect-safe commit, `Tasks:` trailer)

Slices are ordered so each depends only on its predecessors, and small enough to
review. Disjoint Step/Finish and rotation operations are **never** combined into
one per-tx budget claim. All slices after the planning commit are dispatched to the
**exact pair** only after epic-owner `PLAN-ACCEPTED`.

### Slice 0 — planning artifacts (ticket owner)

`spec.md`, `plan.md`, `tasks.md`, `accept.sh` (RED-first skeleton), and
`QUESTION-001-thresholds.md`. Landed as **two** ticket-owner commits **after**
epic-owner `PLAN-ACCEPTED`, gate first: the T9201 gate-lifecycle commit
(`chore(92): make acceptance gate tolerant until decision`) **precedes** the T9200
planning commit (`docs(92): add checkpoint-contention plan, tasks, and RED
acceptance skeleton`, `Tasks: T9200`), so the planning tree the T9200 commit stamps
already passes `./gate.sh`.

### Slice 1 — evidence schema + RED final-acceptance contract + staged mode (pair)

Materialize the fixed **10-column** evidence **schema** (`evidence/matrix.tsv`
header + column contract, `evidence/evidence.json` skeleton with placeholder rows —
`outcome=MEASURE/PROVE/VERIFY`, `thresholds_commit` empty, `selection` null) and
**strengthen `accept.sh`** with the schema assertions (10-column vocabulary, the
five evidence classes, `jq`-parsed `evidence.json`, header/column-count/
duplicate-key/coverage checks, the selection / ordering / negative guards) **and the
`accept.sh schema` staged target**. RED-first: with only placeholders present, the
strengthened `final` contract **fails** exactly on the unfilled/unselected state,
while `accept.sh schema` flips **GREEN** once the schema shape is materialized. No
numbers measured. Owned: `specs/92-checkpoint-contention/{evidence/**,accept.sh}`,
`spikes/92-…/README.md`.
`test(92): add machine-readable evidence schema + RED final-acceptance contract`,
`Tasks: T9211, T9212`.

### Slice 2 — ratify measurement thresholds before measurement (pair; own reviewed commit)

**Gated on the operator answer to QUESTION-001.** Land the ratified thresholds in
`thresholds.md` as the **machine-readable `key/value/unit/provenance` block** defined
in §Ratified-thresholds machine-readable format — the required keys
`C2_ADVANCE_SLO`, `C3_CAPITAL_LOCK_CAP`, `C3B_BLOAT_CAP`, `C3B_ABANDONED_ADA_CAP`,
`C4_EMERGENCY_LATENCY_SLO`, `C6_PROOF_REDEEMER_CAP`, `C6_WHOLE_TX_CAP`,
`C6_READ_EXMEM_CAP`, `C6_READ_EXCPU_CAP`, `C8_DOWNSTREAM_CAP`, `TIMEOUT`, `K_SWEEP`,
`K_PROVISIONAL` — each with **concrete value + allowed unit + provenance only** and
**no self-referential `RATIFIED_COMMIT`** (NOTE-003 item 1). Extend `check_thresholds_values`
(the `accept.sh thresholds` staged target) to **parse/validate each key's value
against its grammar and its unit against the key's allowed unit, reject placeholders,
and require `K_PROVISIONAL ∈ K_SWEEP`** (NOTE-004 item 1). Add the ordering guard: the
ratifying commit SHA is **computed** (`git log -1 --format=%H -- …/thresholds.md`),
must equal each evidence artifact's recorded `thresholds_commit`, and must be a
**strict ancestor** of the latest data-bearing revision of every measurement artifact
(NOTE-004 item 4). **Its own commit, before any measurement.** Owned:
`specs/92-checkpoint-contention/{thresholds.md,accept.sh}`.
`docs(92): ratify measurement thresholds (SLO/cap/timeout/K) before measurement`,
`Tasks: T9221, T9222`.

### Slice 3 — transient inception-cage lifecycle + registration-pipeline measurements (pair)

The **common** per-attempt transient cage/thread token: mint **tied to the consumed
attempt input**, **exactly-one-token** Step continuing output, Finish
**burn-or-promote exactly once**, bounded **timeout → reclaim/burn** (deposit-funded,
cannot activate or bypass byte binding); the **C5** zero-cross-AID-interference
proof (recorded `outcome=PASS`, a real evidence `class`, **not** `class=proved`);
the **C3b** peak-concurrent / abandoned-attempt bloat measurement; and the
**registration-pipeline C1a** per-tx ex-units/size for **Step**, **Finish**, and
**activation/promotion** (oracle gate + MPFS absence/unicity + selected-store
materialization, incl. A's post-Finish steady-token mint) — each at its **own**
boundary (`transaction` column, never summed). Fills C1a (COMMON Step/Finish +
A/B/C Activation, measured), C3b (COMMON peak/abandoned, measured), C5 (COMMON
confinement, `VERIFY→PASS`), and the **`C7 COMMON` registration-lifecycle** row.
Adds the `accept.sh registration` staged target — which requires only the COMMON
rows landing here (C1a Step/Finish, C3b, C5, **`C7 COMMON`**) and **must not** demand
the A/B/C-scoped C7 rows (those land in Slice 7; NOTE-004 item 2). Owned:
`spikes/92-…/**`, `specs/92-…/{evidence/**,accept.sh}`.
`test(92): measure transient inception-cage lifecycle + registration pipeline (C1a/C3b/C5)`,
`Tasks: T9231, T9232, T9233`.

### Slice 4 — common rotation harness + candidate A: rotation-advance, cost, min-ADA, proof, discovery (pair)

Build the **shared** rotation-advance full-tx harness (a **separate** tx from
Step/Finish): §6a **two-seal threshold Ed25519** (Seal W vs stored `(witnesses,toad)`,
Seal K vs endorsed `(W',toad')`, one advance), the selected-store update slot,
continuing output/token placement, and the ledger→script `Data` boundary — reused
unchanged by Slices 5/6 so A/B/C record the **same metrics/schema** for a fair
comparison (NOTE-003 item 5). Then **candidate A** (direct datum spend, no MPF) — the **minted AID-bound steady
checkpoint asset** `(checkpoint_policy_id, aid_asset_name)` (NOTE-019/NOTE-020; the
mint — `aid_asset_name` derived via the **native `blake2b_256` builtin, not BLAKE3** —
the `#99` combined policy-id=script-hash with **inductive** mint-placement +
spend-continuation caging, `CheckpointStateOutput` shape and `delta = 0`
rotation are prototyped by the pair, not authored here):
**C1b** rotation-advance per-tx ex-units/size at N=1 (measured); A's optional
multi-AID **batch** sweep; **C3** state/min-ADA (A = O(#active AIDs) UTxOs,
reclaimable on close/burn; derived); **C6** read cost (minimal datum read;
measured/derived); and **C9** trust-minimized generic discovery — an exact
`(checkpoint_policy_id, aid_asset_name) → current unspent output` lookup via **any**
generic Cardano asset index (**no** bespoke/authoritative QVI-owned `AID → UTxO`
database), with rotation-successor tracking, migration/policy-version lineage,
stale-result rejection against the ledger, and a closed/tombstone story
(`PASS`/`FAIL`, class derived/declared — no numeric threshold). RED assertions on the
harness: `seq`-monotonicity / domain-binding replay rejection, same-AID
serialization, stale-proof handling. Adds the `accept.sh candidate-A` staged target
(A's C1b/C3/C6/**C9**). Owned: `spikes/92-…/**`,
`specs/92-…/{evidence/**,accept.sh}`.
`test(92): common rotation harness + candidate A — rotation-advance, cost, min-ADA, proof, discovery (C1b/C3/C6/C9)`,
`Tasks: T9241, T9242, T9243`.

### Slice 5 — candidate B: rotation-advance, cost, min-ADA, proof (pair)

Reuse the shared harness (Slice 4). **Candidate B** (single-store MPF update at a
stated **non-zero** proof depth): **C1b** per-tx ex-units/size at N=1 (measured);
B's checkpoint-advance **batch** bound sweep against the binding mem/CPU/tx-size
constraint (**not** #99's value-write `N` — NOTE-013; measured); **C3** state/min-ADA
(B = O(1) UTxO; derived); **C6** read cost (MPF proof size at realistic depth,
asymptotics **per the actual MPF impl** — not assumed; measured/derived); and **C9**
trust-minimized discovery (MPF inclusion vs windowed root **+ off-chain MPFS state
materializer/proof builder** — an on-chain root is **not** free leaf discovery;
`PASS`/`FAIL`, class derived/declared). **Same metric/scenario rows as Slice 4** so
A/B compare fairly. Adds the `accept.sh candidate-B` staged target (B's
C1b/C3/C6/**C9**). Owned: `spikes/92-…/**`, `specs/92-…/{evidence/**,accept.sh}`.
`test(92): candidate B — rotation-advance, cost, min-ADA, proof (C1b/C3/C6/C9)`,
`Tasks: T9251, T9252, T9253`.

### Slice 6 — candidate C: rotation-advance, lane grinding surface, cost, min-ADA, proof (pair)

Reuse the shared harness (Slice 4). **Candidate C** (per-lane MPF update,
`lane = f(cesr_aid)`, K lanes at the ratified/predeclared K sweep): **C1b** per-tx
ex-units/size at N=1 (measured); C's per-lane checkpoint-advance **batch** bound
sweep (measured); **C3** state/min-ADA (C = O(K) UTxO; derived); **C6** read cost
(per-lane MPF proof size, asymptotics **per the actual impl**; measured/derived);
**C9** trust-minimized discovery (per-lane MPF inclusion **+ off-chain MPFS state
materializer/proof builder**; `PASS`/`FAIL`, class derived/declared); and the
**grindable-lane surface** (`lane = f(cesr_aid)` — recorded for the Slice-7
targeted-victim contention run, NOTE-017). **Same metric/scenario rows as Slices
4/5.** Adds the `accept.sh candidate-C` staged target (C's C1b/C3/C6/**C9**). Owned:
`spikes/92-…/**`, `specs/92-…/{evidence/**,accept.sh}`.
`test(92): candidate C — rotation-advance, lane grinding surface, cost, min-ADA, proof (C1b/C3/C6/C9)`,
`Tasks: T9261, T9262, T9263`.

### Slice 7 — cross-candidate contention/latency/grinding + #99 invariants + downstream (pair)

**C2** sustained honest advance throughput measured **separately** for the
average/uncoordinated and the targeted/adversarial case; **C4** emergency-rotation
latency for the average lane and a **grinding-targeted victim** lane; targeted
**lane-grinding** of C (`lane = f(cesr_aid)` grindable — average ≠ adversarial,
NOTE-017). **Honest classing (NOTE-003 item 6):** a script-budget / tx-size run is
`measured`; max-operations/block derived from the protocol block budget is
`derived`; targeted grinding / mempool scheduling is `estimated`/modeled **unless**
an actual multi-block load run is performed — the method and class are stated per
cell, per scenario. The inherited **#99 invariant proofs** per candidate (**C7**:
predecessor/version continuity, output confinement, exact burn/lifecycle) are
recorded `outcome=PASS` with a real evidence `class` + provenance — **never**
`class=proved`. **C8** downstream #68/#24/#25/#44 re-cut bound (versioned, additive,
bisect-safe; bounded number of downstream contracts/tickets; class derived/declared).
Fills C2/C4/C7/C8, completing the matrix. Adds the `accept.sh contention` staged
target. Owned: `spikes/92-…/**`, `specs/92-…/{evidence/**,accept.sh}`.
`test(92): contention/latency/grinding + #99 invariants + downstream (C2/C4/C7/C8)`,
`Tasks: T9271, T9272, T9273`.

### Slice 8 — provisional selection + named live-boundary smoke (pair)

Apply the **selection rule** to the fully-filled, threshold-anchored matrix →
**provisional** selection (write `evidence/REPORT.md` distinguishing the five
classes with exact commands / tool-versions / protocol-parameters); then a **named
live-boundary smoke** on the operator's tx-tool devnet (`withDevnet`, the
`KERI_CAGE_SWEEP` / e2e family, reusing `Cardano.KERI.AID.E2E.MpfProof.prove` for
real depth-N proofs) that **loads `cardano-tx-tools` and uses its inspect/validate
workflow** around a **real submitted checkpoint-advance tx** and **asserts the node
Phase-1/Phase-2 outcome**, failing loudly at the node boundary. Records to the
structured **11-column** `evidence/live-smoke.tsv` (§Live-smoke schema): selected
candidate (`== evidence.json.selection`), **real 64-hex tx id**, network / node /
protocol-param provenance, **`cardano-tx-tools` version + structured `inspect`=PASS +
`validate`=PASS** (in addition to node **Phase-1=PASS / Phase-2=PASS**; NOTE-004
item 5), with the **#99 devnet limitation** verbatim in the `note` column (devnet
`maxTxExUnits` 140 M mem / 10 G CPU — mem 10× mainnet, CPU identical; `evalTxExUnits`
hung on the #99 cage → **conservative/declared**, not a precise mainnet ex-unit fit;
a **single-tx smoke is not a throughput load test** and a unit/golden proof does
**not** substitute for the live node boundary — NOTE-003 item 6). Extend `check_smoke`
to the 11-column contract (inspect/validate/phase1/phase2 all `PASS`). Adds the
`accept.sh smoke` staged target. Slice 8 records the provisional
`evidence.json.selection`; its reviewed commit is the **immutable `EVIDENCE_REF`**
consumed by Slice 9. Owned: `spikes/92-…/**`,
`specs/92-…/{evidence/{evidence.json,live-smoke.tsv},REPORT.md,accept.sh}`.
`test(92): provisional selection + named live-boundary checkpoint-advance smoke`,
`Tasks: T9281, T9282`.

### Slice 9 — final decision + canonical-doc update + final acceptance GREEN (pair)

Name **exactly one** selected candidate in `DECISION.md` machine headers
(`SELECTED_CANDIDATE=`, `REJECTED_CANDIDATES=` — exactly two distinct, neither equal
to the selection, i.e. the **complement** of the selection — `SELECTION_RULE=`,
`EVIDENCE_REF=`, `THRESHOLDS_COMMIT=`, `RESIDUAL_RISKS=`), record the **rejected
alternatives + residual risks**, and update the canonical docs — `identity-model.md`
§10 **thread 8** (resolved) + §7c consequence, and `system-architecture.md` §3 R-KEL
note + §6 registry — with the decision, **preserving** the R-KEL checkpoint-vs-mirror
classification and the #99 invariants. Extend `check_decision` to enforce the
**cross-bound references** (NOTE-004 item 3):
`SELECTED_CANDIDATE == evidence.json.selection == live-smoke.candidate`;
`THRESHOLDS_COMMIT == the computed threshold-file commit == evidence.json.thresholds_commit`;
`EVIDENCE_REF` **resolves to the actual evidence commit** (`git rev-parse`), and the
two `REJECTED_CANDIDATES` are exactly the complement. `EVIDENCE_REF` is **Slice 8's
immutable reviewed evidence commit** — Slice 9 **references** it and does **not** modify
`evidence/**` or re-fill the matrix; if the smoke forces any evidence/selection change,
a new evidence/smoke correction slice lands and is reviewed first, then that prior commit
is referenced. Flip the `gate.sh` `final`
`accept.sh` hook **strict** (removing the tolerance bypass). `accept.sh` (`final`) +
`./gate.sh` **GREEN**. Owned:
`specs/92-…/{DECISION.md,accept.sh}`,
`specs/68-keystate-shape/{identity-model.md,system-architecture.md}`, `gate.sh`.
`docs(92): select the R-KEL checkpoint storage model — decision + canonical docs (thread 8)`,
`Tasks: T9291, T9292, T9293`.

**If the evidence does not cleanly separate the candidates** (survivors within
measurement noise), the decision slice applies the tie-break (smaller downstream
re-cut, C8) and **records the tie honestly** — it must still end with exactly one
selection. A genuine inability to select (e.g. an unratified threshold surfaced late)
is **escalated** to the epic owner, not resolved by leaving the matrix open.

## Commit history (explicit — conventional subjects + numeric task IDs)

| # | Subject | Owner | `Tasks:` | RED→GREEN |
|---|---|---|---|---|
| — | `chore(92): make acceptance gate tolerant until decision` | ticket owner | T9201 | n/a (gate) |
| 0 | `docs(92): add checkpoint-contention plan, tasks, and RED acceptance skeleton` | ticket owner | T9200 | n/a (planning) |
| 1 | `test(92): add machine-readable evidence schema + RED final-acceptance contract` | pair | T9211, T9212 | yes (staged `schema`) |
| 2 | `docs(92): ratify measurement thresholds (SLO/cap/timeout/K) before measurement` | pair | T9221, T9222 | yes (staged `thresholds`) |
| 3 | `test(92): measure transient inception-cage lifecycle + registration pipeline (C1a/C3b/C5)` | pair | T9231, T9232, T9233 | yes (staged `registration`) |
| 4 | `test(92): common rotation harness + candidate A — rotation-advance, cost, min-ADA, proof, discovery (C1b/C3/C6/C9)` | pair | T9241, T9242, T9243 | yes (staged `candidate-A`) |
| 5 | `test(92): candidate B — rotation-advance, cost, min-ADA, proof (C1b/C3/C6/C9)` | pair | T9251, T9252, T9253 | yes (staged `candidate-B`) |
| 6 | `test(92): candidate C — rotation-advance, lane grinding surface, cost, min-ADA, proof (C1b/C3/C6/C9)` | pair | T9261, T9262, T9263 | yes (staged `candidate-C`) |
| 7 | `test(92): contention/latency/grinding + #99 invariants + downstream (C2/C4/C7/C8)` | pair | T9271, T9272, T9273 | yes (staged `contention`) |
| 8 | `test(92): provisional selection + named live-boundary checkpoint-advance smoke` | pair | T9281, T9282 | yes (staged `smoke`) |
| 9 | `docs(92): select the R-KEL checkpoint storage model — decision + canonical docs (thread 8)` | pair | T9291, T9292, T9293 | yes (final GREEN) |
| — | `chore: drop gate.sh (ready for review)` | ticket owner | — | n/a (finalize) |

Each behavior/assertion slice is one bisect-safe commit, RED demonstrated
pre-commit, navigator-reviewed, and pushed only after ticket-owner verification of
the exact committed SHA.

## Orchestrator-owned finalization (post-slice)

- Verify `gate.sh` (strict) + `accept.sh` GREEN at HEAD; fresh GitHub CI green.
- Update PR #104 body + issue #92: state the selected model, link #97/#99, and note
  the R-KEL classification + #99 invariants preserved.
- Finalization audit (commit-gate over all commits, no open tasks, satisfied
  `spec.md` success criteria stamped); drop `gate.sh` **last**
  (`chore: drop gate.sh (ready for review)`); `gh pr ready 104`. **Do not merge** —
  the epic owner performs the guarded merge. Report `COMPLETE` on STATUS.

## Reporting / hard stops

Append durable milestones to `STATUS.md` (START done; discovery done; planning SHA;
PLAN-REVIEW; QUESTION-001 raised; per-slice RED/GREEN + reviewed SHAs; pushes; CI;
COMPLETE/BLOCKED). Genuine decisions go in `questions/`. **First hard stop
(now): planning artifacts + draft PR + gate installed, awaiting explicit epic-owner
`PLAN-ACCEPTED`.** Measurement is a **second hard stop** pending the QUESTION-001
answer.

## Risks / notes

- **QUESTION-001 is a real blocker.** No operator SLO/cap/timeout/K → no
  measurement. Surfaced early so the epic owner/operator can ratify before Slice 2.
- **Candidate A needs a generic off-chain asset index** (an exact `(policy_id,
  asset_name) → current unspent output` lookup answerable by any indexer/node/sidecar/
  replica — **not** a bespoke QVI-owned `AID → UTxO` directory, NOTE-019); this is an
  evidenced availability cost (Slice 4), not a free property, and it supplies
  freshness, **not** identity truth (re-checked against the ledger).
- **C's `lane = f(cesr_aid)` is grindable** — average-case ≠ targeted-worst-case; the
  grindable surface is recorded in Slice 6 and the targeted-victim contention run in
  Slice 7 (average `measured`; targeted grinding `estimated`/modeled unless a
  multi-block load run — NOTE-003 item 6), and a fixed K must plan for skew +
  re-shard migration (NOTE-017).
- **The advance path is unbuilt.** C5/C7 are `VERIFY`/`PROVE` until the delegated
  prototype proves them; the smoke corroborates the boundary but does **not** yield
  a precise mainnet ex-unit fit (devnet limitation).
- **Do not let a unit/golden proof stand in for the live node boundary**, and do
  **not** sum the registration pipeline and the rotation advance into one per-tx
  figure.
