# Cage Execution-Unit Measurement Report (#99 FR9)

## Question

Do the **hardened** `mpfCage` happy paths (Mint, Migrate, Modify, End) — after
the #99 Slice 2–5 security fixes — fit under the mainnet per-transaction
execution budget, and how many request inputs / refund outputs can a single
`Modify` transaction support within that budget?

Budget (mainnet per-tx):

- memory: 14,000,000
- CPU: 10,000,000,000

## Method

Measurements were taken with:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check --plain-numbers
```

Measurements live in the production onchain tree
(`onchain/validators/cage_measurements.ak`), following the #97 R2 precedent
(`spikes/97-blake3-multitx/validators/measurements.ak`, `REPORT.md`):

- **All fixtures are top-level `const`s** — the datums, inputs, outputs, mint
  values, `OutputReference`s, redeemers, and the owner-auth witness. Their
  construction is folded at compile time and is **not** charged to the measured
  validator cost, so setup work is never mistaken for validator cost. Each
  `test` body contains only the handler call.
- **The real handlers are measured on their accept path.** Every measurement
  invokes `cage.mpfCage.mint(...)` or `cage.mpfCage.spend(...)` on a full
  `Transaction` (the `_version` / `predecessorPolicy` validator parameters are
  passed first, per Aiken's parameterized-validator convention) and returns
  `True`. This exercises the hardened logic: `validateMint`'s exact-single-token
  + state-output confinement (FR1), `validateMigration`'s pinned predecessor +
  exact per-policy mint maps + confinement (FR3), `validateEnd`'s `-1` burn
  coupling (FR2), and `validModify`'s no-mint/burn reverse guard (FR2/H6),
  output confinement (FR4), input-root authentication (FR5), and aid↔key
  binding (FR6).
- **Modify batch sweep.** `Modify` folds over a list of request inputs and emits
  one refund output per owner. To measure the per-request cost and locate the
  handler-ceiling crossing, the batch is built from `n` identical request inputs
  (`list.repeat`), each carrying a genuine `UpdateAction`: a real Ed25519
  signature (the `gen-vectors` owner-auth fixture) verified over the request
  output reference, an MPF `Update`, and refund accounting. The MPF operation is
  a no-op `Update(v, v)` on a single-leaf value trie (proof `[]`) — the same
  no-op-MPF idiom `verifyOwnerAuth` itself uses to prove membership — so the
  continuing-state root is unchanged and each request genuinely drives
  `mkAction → verifyOwnerAuth` (Ed25519 + MPF-inclusion) plus the MPF value
  update and the refund fold. Batch sizes 0, 1, 10, 30, 50, 60, 64, 65, 66 were
  measured to bracket the budget crossing.

## Results

Percentages are of the mainnet per-tx budget above.

| Measurement            | Memory      | Mem %     | CPU            | CPU %   |
| ---------------------- | ----------: | --------: | -------------: | ------: |
| Mint                   |     111,887 |    0.80%  |     37,920,001 |  0.38%  |
| Migrate                |     118,608 |    0.85%  |     37,288,253 |  0.37%  |
| End                    |     126,174 |    0.90%  |     38,877,162 |  0.39%  |
| Modify — batch 0       |     225,990 |    1.61%  |     73,072,528 |  0.73%  |
| Modify — batch 1       |     435,322 |    3.11%  |    195,443,016 |  1.95%  |
| Modify — batch 10      |   2,319,310 |   16.57%  |  1,296,777,408 | 12.97%  |
| Modify — batch 30      |   6,505,950 |   46.47%  |  3,744,187,168 | 37.44%  |
| Modify — batch 50      |  10,692,590 |   76.38%  |  6,191,596,928 | 61.92%  |
| Modify — batch 60      |  12,785,910 |   91.33%  |  7,415,301,808 | 74.15%  |
| Modify — batch 64      |  13,623,238 |   97.31%  |  7,904,783,760 | 79.05%  |
| **Modify — batch 65**  |  13,832,570 |   98.80%  |  8,027,154,248 | 80.27%  |
| Modify — batch 66      |  14,041,902 | 100.30% ✗ |  8,149,524,736 | 81.50%  |

### Modify scaling

The cost is linear in the batch size `n`:

- **Base spend overhead** (batch 0 — spend the state UTxO, re-create it, no
  requests): 225,990 memory / 73,072,528 CPU.
- **Marginal per request** (each additional `UpdateAction` — one Ed25519
  verification, one MPF update, one refund entry): **+209,332 memory** (1.50% of
  the memory budget) / **+122,370,488 CPU** (1.22% of the CPU budget). This
  increment is constant across every measured point (e.g. batch 65 − batch 64 =
  209,332 memory / 122,370,488 CPU).

So `Modify(n)` ≈ `225,990 + 209,332·n` memory and `73,072,528 + 122,370,488·n`
CPU.

## Measured handler ceiling (NOT a production bound)

**65 is a measured HANDLER ceiling, not a production-supported on-chain bound.**
The figures above are produced by calling the `mpfCage.spend` handler directly on
top-level typed `const` fixtures (see Method). Two real on-chain costs are
therefore **excluded** from the 65 figure:

1. **Ledger→script `fromData` deserialization** of the datum, redeemer and
   transaction at the script boundary (the handler is handed already-typed
   values, so no `fromData` runs). Partially measured in the next section.
2. **Real MPF proof depth** — every request uses an empty single-leaf inclusion
   proof (`[]`); a real value trie carries a longer, costlier proof. This cost is
   **unquantified** in-scope (see Caveats).

Both excluded costs are positive, so the production-supported bound is lower than
the 65 handler ceiling — the depth-0 boundary measurement below already puts the
memory crossing near 59 — but its exact value is **not proven by this report**.
The handler-ceiling crossing itself:

- At **65** requests: 13,832,570 memory (98.80% of budget) and 8,027,154,248 CPU
  (80.27%) — both within budget.
- At **66** requests: 14,041,902 memory (**100.30%** of budget) — the memory
  budget is **exceeded**. The binding constraint is **memory**; CPU still has
  ~19.7% headroom at 65.

## Data-boundary measurement (S8, MPF proof depth 0)

To charge the excluded `fromData` cost (item 1 above), the **compiled** `mpfCage`
validator is evaluated against a serialized `ScriptContext` — the real
ledger→script boundary — instead of the handler being called on typed fixtures.
The context is built by `onchain/validators/cage_boundary.ak` and evaluated with
`aiken uplc eval`; the validator's own built-in context decode charges the full
`fromData` traversal. **The MPF proof depth is held at 0 (the same empty
single-leaf proof as S6)**, so this isolates the `fromData` axis only; it does
**not** address excluded cost item 2.

| Batch | S6 handler-only (mem / CPU) | Boundary incl. `fromData` (mem / CPU) | `fromData` delta (mem / CPU) |
| ----: | --------------------------: | ------------------------------------: | ---------------------------: |
| 0     | 225,990 / 73,072,528        | 227,825 / 74,158,815                   | +1,835 / +1,086,287          |
| 1     | 435,322 / 195,443,016       | 459,081 / 202,906,291                  | +23,759 / +7,463,275         |

Both boundary evaluations return `(con unit ())` (accept). The per-request
`fromData` increment is **+21,924 memory / +6,376,988 CPU**, i.e. each request
costs ~10.5% more memory once boundary deserialization is charged
(209,332 → ~231,256 per request).

**Revised memory crossing (still excluding MPF proof depth):** applying the
per-request boundary increment linearly,
`227,825 + 231,256·n ≥ 14,000,000` at **n ≈ 60**, so the boundary-inclusive
memory bound is **≈ 59 requests — down from the 65 handler ceiling.** This ≈59 is
an **extrapolation**, not a direct measurement: materializing a near-ceiling
`ScriptContext` as a `Data` term itself exceeds the standalone `aiken uplc eval`
memory budget (which has no override), so batches beyond ~30 cannot be evaluated
this way. This ≈59 also **still excludes MPF proof depth**: a non-empty proof adds
a positive but **unmeasured** per-request cost that *may* push the ceiling below
59, but nothing here proves it does. **The production-supported bound therefore
remains unproven** — ≈59 is the depth-0 boundary estimate, not a proven cap.

## Live-boundary batch sweep (S9b — real non-zero-depth MPF proofs on a node)

S6/S8 measure the **Aiken handler / data-boundary** execution ceiling in
isolation, at MPF proof depth 0. S9a then settled a single hardened `Modify`
on a real `cardano-node` via `withDevnet`, still with an **empty (zero-depth)**
proof. S9b closes the two follow-ups the caveats below named — a depth-N proof
generator and a live node Phase-2 exercise — and measures the live per-tx bound.

- **Off-chain depth-N MPF inclusion-proof generator — now delivered.**
  `offchain/e2e/Cardano/KERI/AID/E2E/MpfProof.prove` (a faithful port of the
  Aiken/mpfs `Trie.walk` + `Proof.rewind` + `merkleProof`) emits the real
  `Branch` / `Fork` / `Leaf` steps the on-chain `mpfCage` recomputes. Batching
  `N` distinct namespaced requests
  (`requestKey_i = blake2b_256(owner_aid) ++ be(i)`) into one `Modify` inserts
  each into an initially-empty value trie. The **1st insert is depth 0** (an
  empty proof into the empty trie — the S9a zero-depth case); the **2nd..N
  inserts are depth > 0** (genuine non-zero-depth proofs). The artifact records
  the ACTUAL per-insert proof-step count for each batch (`proof depths (1..N)`),
  so the depth>0 exercise is measured, not assumed.

- **Phase-2 non-zero-depth CORRECTNESS — proven live (RED→GREEN).** The SAME
  batch-2 `Modify` is **rejected** by the cage script at node Phase-2 when the
  2nd insert carries an empty proof (`excluding(k2, []) != root(T1)` fails MPF
  verification), and **settles** once `prove` supplies the real depth-1 proof.
  This is a genuine node Phase-2 pass/fail on proof correctness, not a fixture.

### Live sweep — supported per-tx bound (artifact `offchain/e2e/sweep-boundary.md`)

`cageSweepOne` (the flake-owned `nix run .#e2e-sweep`, opt-in
`KERI_CAGE_SWEEP=1`) submits, per batch size `N`, one `Modify` carrying the real
per-insert MPF proofs (insert 1 empty / depth 0; inserts 2..N depth > 0) through
`withDevnet`. It **asserts** each batch's expected node outcome (N = 1..4 settle;
N ≥ 5 reject at the specific Phase-1 limit), so a harness or boundary regression
fails the run. It records the node's Phase-1/Phase-2 result, the actual
per-insert proof depths, and — since the client `evalTxExUnits` hangs on
this script — the **declared, not measured**, deliberately **conservative**
per-redeemer ex-units (Modify 8,000,000 mem / 4,000,000,000 CPU; each Contribute
3,000,000 mem / 1,500,000,000 CPU). A settled batch therefore proves the ACTUAL
execution fit **within** those declared budgets and the aggregate fit the per-tx
limit; the reported aggregate is a conservative **over**-estimate of the real
cost (S6/S8 measure the far-smaller real handler cost).

Observed devnet limits (from the raw rejection diagnostics):
**`maxTxExUnits` = 140,000,000 mem / 10,000,000,000 CPU** (memory 10× mainnet,
**CPU identical to mainnet**), **`maxTxSize` = 16,384 bytes**.

| batch N | node result | declared agg mem | declared agg CPU | binding limit (Phase-1/Phase-2) |
|--------:|:-----------:|-----------------:|-----------------:|:--------------------------------|
| 1  | settled (Phase-2 pass) | 11,000,000 | 5,500,000,000 | — |
| 2  | settled (Phase-2 pass) | 14,000,000 | 7,000,000,000 | — |
| 3  | settled (Phase-2 pass) | 17,000,000 | 8,500,000,000 | — |
| 4  | settled (Phase-2 pass) | 20,000,000 | 10,000,000,000 | — (agg CPU at the 10G limit) |
| 5  | rejected | 23,000,000 | 11,500,000,000 | Phase-1 `ExUnitsTooBigUTxO` (CPU 11.5G > 10G) |
| 8  | rejected | 32,000,000 | 16,000,000,000 | Phase-1 `ExUnitsTooBigUTxO` |
| 16 | rejected | 56,000,000 | 28,000,000,000 | Phase-1 `ExUnitsTooBigUTxO` |
| 24 | rejected | 80,000,000 | 40,000,000,000 | Phase-1 `ExUnitsTooBigUTxO` + `MaxTxSizeUTxO` (19,723 > 16,384 B) |
| 44 | rejected | 140,000,000 | 70,000,000,000 | Phase-1 `ExUnitsTooBigUTxO` + `MaxTxSizeUTxO` (29,637 > 16,384 B) |

Every reject is **Phase-1** (structural tx limit), never Phase-2 — as expected:
Phase-2 only enforces `actual ≤ declared`, so at the declared budgets the tx
ex-unit / size ceiling binds first. The supported bound is therefore the largest
`N` that passes Phase-1 **and** settles Phase-2:

- **On the observed devnet** (140M mem / 10G CPU): the aggregate declared CPU
  (`4G + 1.5G·N`) reaches 10G at **N = 4** — the largest batch that settles —
  and exceeds it from N = 5. (Memory would allow N ≤ 44.) The observed tx-size
  data points: **N = 16 has no reported size failure; N = 24 is 19,723 B >
  16,384 B**, so the `maxTxSize` limit is crossed somewhere in `16 < N ≤ 24`
  (not measured more precisely here — this report does not extrapolate a
  per-request byte rate or an exact size-limited N).
- **Projected to the mainnet per-tx budget (14,000,000 mem / 10,000,000,000
  CPU):** the aggregate declared **memory** (`8M + 3M·N`) reaches 14M at
  **N = 2**, so at these conservative declared budgets a mainnet `Modify` is
  bounded to **N = 2** (memory-bound; CPU alone would allow N = 4).

**Qualified bound (NOT a universal cap).** N = 2 (mainnet) / N = 4 (devnet) is the
bound **at the fixed, conservative, over-declared per-redeemer budgets** and the
empty-start state — a *lower* bound on real capacity, not a production cap. The
real handler cost is much smaller than these declared budgets (S6/S8: base ~226k
mem + ~209k mem/request at depth 0), so S6/S8 **suggest** the real mainnet
capacity is higher than N = 2; this report does not prove a higher figure. The
upper references remain **estimates, not proven caps**: the S6/S8 Aiken **depth-0
memory ceiling of ≈ 59 (an estimate)**, which non-zero proof depth only lowers,
and the `maxTxSize` 16,384 B limit, whose size-limited batch is bracketed only to
`16 < N ≤ 24` above (**not** a precise `~17`). **No extrapolation gives a
universal safe cap.** The end-to-end contribution of S9b is the **live Phase-2
correctness proof** for real non-zero-depth proofs (RED→GREEN) plus the
**tx-ex-unit/size-limited** live bound above.

## Verdict

Judged on the **full mint/spend validator context** — the per-transaction
figures #99 FR9 asks for:

- **All four hardened happy paths fit the per-tx budget.** Mint, Migrate, and
  End each consume under **1%** of both the memory and CPU budgets (worst case:
  End at 0.90% memory / 0.39% CPU) — abundant headroom for the single-token
  lifecycle transitions.
- **Modify scales linearly, but 65 is a handler ceiling — not a safe on-chain
  cap.** 65 is the crossing when the handler is measured on typed fixtures with
  empty MPF proofs; it excludes ledger `fromData` deserialization and real MPF
  proof depth. The S8 boundary measurement shows `fromData` alone lowers the
  extrapolated memory crossing to **≈ 59** (MPF depth 0). The MPF-proof-depth cost
  is unmeasured and may lower the ceiling further, so the **production-supported
  bound remains unproven**. Off-chain batching must **not** treat 65 as a safe cap.
  As a conservative **operator policy** (not a proven bound), stay comfortably
  under the ≈59 depth-0 estimate and leave headroom until the boundary is proven
  end-to-end on a node at a stated MPF depth.

The hardening added by Slices 2–5 does not push any happy path outside the
budget; the dominant Modify cost is the per-request Ed25519 verification and MPF
update, both of which are load-bearing security work (FR5/FR6 authentication),
not overhead.

## Caveats and follow-ups

- **Ledger `Data` deserialization — now partially measured (S8, MPF depth 0).**
  The S6 handler figures exclude the ledger→script `fromData` conversion. The S8
  Data-boundary measurement charges it by evaluating the **compiled** validator
  against a serialized `ScriptContext` (`cage_boundary.ak`), at batches 0 and 1,
  MPF proof depth 0. Result: `fromData` adds **+21,924 memory / +6,376,988 CPU per
  request**, which lowers the memory crossing from 65 to **≈ 59** (extrapolated).
  This closes the `fromData` axis at depth 0 but not beyond ~batch 30 directly
  (the standalone eval budget caps context materialization).
- **MPF proof depth — the S6/S8 measurement is still depth 0; a depth-N generator
  now exists (S9b).** Every request in S6 and S8 uses an empty single-leaf proof
  (`[]`), so the ≈59 depth-0 ceiling still **excludes** the real per-request proof
  cost. S9b delivers the previously-missing **off-chain depth-N MPF
  inclusion-proof generator** (`Cardano.KERI.AID.E2E.MpfProof.prove`, real
  `Branch`/`Fork`/`Leaf` steps) and proves those depth-N proofs **validate at node
  Phase-2** (see the live sweep). It does not re-measure the S6/S8 Aiken handler
  cost at depth N, so the exact depth-N handler ceiling remains unquantified and
  the ≈59 figure stays a depth-0 estimate; non-zero depth only lowers it.
- **Full node Phase-2 boundary — now exercised (S9a/S9b), tx-limited not
  script-limited.** A real `Modify` (with real non-zero-depth proofs) is built by
  the off-chain `withDevnet` builder (`offchain/e2e/**`) and **submitted to a
  cardano-node**, settling on-chain — AC9's live evaluation, no longer an operator
  follow-up. The live per-tx bound is the **tx ex-unit / size (Phase-1) limit**,
  not a separate Phase-2 script-cost boundary: Phase-2 only enforces
  `actual ≤ declared`, so there is no distinct Phase-2 size ceiling below the tx
  max, and inflating the devnet `maxTxExUnits` to expose one would yield a number
  that does not apply to mainnet. See the live-boundary sweep section above for the
  qualified bound and the RED→GREEN Phase-2 correctness proof.
- **Batch fixtures reuse one owner-auth witness (cost-faithful, uniqueness
  relaxed).** Every request input in a batch reuses the single `gen-vectors`
  output reference and signature, so all `n` Ed25519 verifications run over the
  same message. The Ed25519 verification cost is identical to distinct
  references (the dominant fixed per-request cost is measured faithfully); only
  the real-transaction requirement that inputs have distinct output references is
  relaxed, which is cost-neutral for this measurement.
