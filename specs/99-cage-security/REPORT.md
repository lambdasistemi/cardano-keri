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
  supported bound, the batch is built from `n` identical request inputs
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

## Supported batch / output bound

**The supported Modify bound is 65 request inputs and 65 refund outputs.**

- At **65** requests: 13,832,570 memory (98.80% of budget) and 8,027,154,248 CPU
  (80.27%) — both within budget.
- At **66** requests: 14,041,902 memory (**100.30%** of budget) — the memory
  budget is **exceeded**, so 66 does not fit. CPU at 66 is 8,149,524,736
  (81.50%), still within budget.

The **binding constraint is memory**: it saturates at 65 while CPU still has
~19.7% headroom. Extrapolating the linear CPU cost, the CPU budget alone would
not be reached until ~81 requests, but memory caps the transaction first. The
sweep was stopped at 66 because that is the first batch size over budget; this
cap is recorded as the supported bound.

## Verdict

Judged on the **full mint/spend validator context** — the per-transaction
figures #99 FR9 asks for:

- **All four hardened happy paths fit the per-tx budget.** Mint, Migrate, and
  End each consume under **1%** of both the memory and CPU budgets (worst case:
  End at 0.90% memory / 0.39% CPU) — abundant headroom for the single-token
  lifecycle transitions.
- **Modify fits and scales linearly.** A single `Modify` transaction supports up
  to **65** request inputs / refund outputs within the mainnet per-tx budget,
  memory-bound at 98.80% (CPU 80.27%). Batches at or below 65 fit; 66 exceeds the
  memory budget. Off-chain batching should therefore cap a single settlement
  transaction at 65 requests and split larger request sets across transactions.

The hardening added by Slices 2–5 does not push any happy path outside the
budget; the dominant Modify cost is the per-request Ed25519 verification and MPF
update, both of which are load-bearing security work (FR5/FR6 authentication),
not overhead.

## Caveats and follow-ups

- **Ledger-level `Data` deserialization excluded (close lower bound).** As in
  #97, the measurement calls the handler directly, so it **includes** the full
  transaction-context traversal (input/output folds, MPF operations, Ed25519
  verification) but **excludes** the ledger-level deserialization of the redeemer
  and datums from `Data` at the script boundary. The reported figures are a close
  **lower bound** on true on-chain cost. For `Modify`, the redeemer grows with
  the batch (one `UpdateAction` per request), so the excluded deserialization
  also grows with `n`; the real supported bound may be marginally below 65 once
  boundary deserialization is charged. Off-chain builders should treat 65 as a
  ceiling and leave margin.
- **Batch fixtures reuse one owner-auth witness (cost-faithful, uniqueness
  relaxed).** Every request input in a batch reuses the single `gen-vectors`
  output reference and signature, so all `n` Ed25519 verifications run over the
  same message. The Ed25519 verification cost is identical to distinct
  references (the dominant fixed per-request cost is measured faithfully); only
  the real-transaction requirement that inputs have distinct output references is
  relaxed, which is cost-neutral for this measurement.
- **MPF updates use single-leaf empty proofs (per-request MPF cost is a floor).**
  Each request applies a no-op `Update` on a single-leaf value trie with an empty
  inclusion proof, so the MPF portion of the per-request cost is minimal. A real
  request against a larger, deeper value trie carries a longer inclusion proof
  and costs more per operation. The Ed25519 verification (the larger fixed
  component) is measured faithfully, but the MPF component is a floor; the
  reported per-request cost is therefore a lower bound and the derived batch bound
  (65) is an optimistic ceiling on the MPF axis. This is the same
  "close lower bound" posture as #97 and does not change the verdict that
  Mint/Migrate/End sit far under budget.
