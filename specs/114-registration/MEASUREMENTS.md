# #114 registration transaction measurements

## Verdict

**Both #114 measurement acceptance rows are met.** The A-001 QB-2 measurement
gate PASSES: every registration Tx B cell holds ≥ 25% headroom on both axes,
with the binding cell — the GLEIF-shaped 7-key registration — at **64.56%
memory headroom** and **77.66% CPU headroom**. The hash-proof Tx A cells meet
the ≥ 25% target across the whole ≤ 1024 B single-chunk domain: the binding
tier (16 blake3 blocks, 961–1024 B) measures **26.85% memory headroom** and
**44.89% CPU headroom**. Memory binds before CPU on every cell.

Both rows carry a slice-5b history recorded below: the first slice-5
measurement fired the QB-2 STOP at the 7-key shape (15.44% headroom), and the
same remediation — the 3-bytes-per-step base64url encoder — resolved both the
Tx B miss and the pre-5b Q-002 finding on the Tx A > 960 B tier. No check was
changed on either path.

Mainnet per-tx budget:

| resource | budget |
| --- | ---: |
| memory | 14,000,000 |
| cpu | 10,000,000,000 |

## Tx A — hash-proof mint (`hash_proof.ak`)

Measured with the pinned aiken
(`github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken`) and
`aiken check --plain-numbers -m measure_hash_proof` at the slice-5 tree
(`898cbcc`); reproduce with `just measure-hash-proof`. Each `test measure_*`
in `onchain/validators/hash_proof_measurements.ak` invokes the real
`hash_proof.hash_proof.mint` handler on its ACCEPT path over a full mint
transaction: H1 tier/span checks, H2a span equality against
`qb64_aid(cesr_aid)` at both offsets, H2b blake3 over the SAID-dummied bytes
(the vendored lane-packed single-chunk core), and the H3 single-name
quantity-one mint over the blake2b_256 token name. The 393 B cell is the
committed keripy `honest_2key` icp; the 966 B (GEDA-scale) and 1024 B
(single-chunk boundary) cells are the deterministic blank-first synthetic
vectors, each SAID-verified (`blake3(said_blank) == aid`) before committing.

| tier | mem | mem used | mem headroom | cpu | cpu used | cpu headroom |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 393 B (keripy honest_2key icp) | 4,603,746 | 32.88% | 67.12% | 2,467,204,800 | 24.67% | 75.33% |
| 966 B (GEDA-scale synthetic) | 10,241,045 | 73.15% | 26.85% | 5,510,557,652 | 55.11% | 44.89% |
| 1024 B (single-chunk boundary synthetic) | 10,241,066 | 73.15% | 26.85% | 5,510,621,625 | 55.11% | 44.89% |

Minimum headroom across the Tx A cells: **26.85% memory** and **44.89% CPU**
(both on the 16-block tier) — above the ≥ 25% target. The ratified 1024 B cap
(A-001 QE) stands.

### Block-boundary analysis

The lane-packed blake3 core absorbs 64 B blocks, so a mint costs
`ceil(len / 64)` compressions and the ≤ 1024 B domain splits at 960 B:
sizes ≤ 960 B cost at most 15 blocks; sizes 961–1024 B all cost 16. That is
why the 966 B and 1024 B cells are near-identical (memory differs by 21
units): they price the same 16 compressions. The 16-block zone is the binding
tier at 73.15% memory used.

### Q-002 — resolved history (the > 960 B tier)

At slice 4, before the 5b encoder rewrite, the 16-block tier measured
10.70M/10.71M memory = 76.5% used = **23.5% headroom**, below the 25% target.
Q-002 (2026-07-18) recorded the finding and recommended keeping the ratified
1024 B cap with a rationale (Tx A is composition-free and retryable; a failed
submission costs nothing at the protocol level), pending epic-owner ack. The
slice-5b encoder rewrite also cheapened Tx A — H2a computes
`qb64_aid(cesr_aid)` once per mint, and the per-encode cost fell ~638K →
~150K memory — dropping every Tx A cell by ~0.48M memory. The fresh cells
above put the 16-block tier at 26.85% headroom: the target is met with no
waiver, and Q-002 is resolved as moot (A-007, 2026-07-18). The 1024 B cap
stands on the ratified QE ruling alone.

## Tx B — registration (`checkpoint.ak`, `Register`) — the A-001 QB-2 gate

Measured with the same pinned aiken and `aiken check --plain-numbers -m
measure_checkpoint` at the same tree; reproduce with `just
measure-checkpoint`. Each `test measure_*` in
`onchain/validators/checkpoint_measurements.ak` invokes the real
`checkpoint.checkpoint.mint` handler on its ACCEPT path over a full Tx-B
transaction — R1 mint shape, R2 ACTIVE-output checks, R5 proof-input lookup +
burn-map check + blake2b proof-name recompute, R3 datum reconstruction, the
E1–E9 slice set, the R4 schema predicate, R7 signatures over the
reconstructed `InceptionMessage` preimage, and the R8 deposit check. The
fixtures are the committed keripy registration family (slice 5a), each cell's
true signer shape:

| cell | fixture (signer shape) | mem | mem used | mem headroom | cpu | cpu used | cpu headroom |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| reg_2key | 393 B icp, 2 keys, `kt = 2`, unwitnessed (2 Ed25519) | 1,520,762 | 10.86% | 89.14% | 698,587,600 | 6.99% | 93.01% |
| reg_7key | 943 B icp, 7 keys, weighted 7 × 1/3 (GLEIF board shape; 7 Ed25519) | 4,961,877 | 35.44% | 64.56% | 2,234,283,607 | 22.34% | 77.66% |
| reg_witnessed | 533 B icp, 2 keys `kt = 2`, 3 witnesses `toad = 2` (parent-acceptance 2-of-3) | 2,089,816 | 14.93% | 85.07% | 927,791,786 | 9.28% | 90.72% |

**A-001 QB-2 verdict: PASS — ALL cells ≥ 25% headroom on both axes.** Minimum
headroom across the Tx B cells: **64.56% memory** and **77.66% CPU** (both on
reg_7key).

### The slice-5 gate stop and the 5b remediation

The QB-2 gate FIRED on the first slice-5 measurement (pre-fix cells):
reg_2key 3,806,953 memory (27.2% used), reg_witnessed 5,737,176 (41.0% used),
and reg_7key **11,837,984 memory = 84.6% used = 15.44% headroom**, below the
25% target. The STOP was honored: nothing was committed or reviewed under the
miss (Q-005; epic escalation Q-003). Diagnosis: the per-byte-fold
`base64url.encode` cost ~638K memory per 33-byte-class encode, and the
E-binding derives every expected qb64 value from the datum (the A-001
security argument — offsets locate, never define, content), so a registration
runs `2N + 1 + W` encodes: 15 at the 7-key shape ≈ 10.05M memory, while the
slice-5 validator shell itself added only ~465K. The remediation (interposed
slice 5b, A-005) rewrote the encoder to consume 3 bytes per step with
byte-identical output — parity pinned by `base64url_tests`, the S3 qb64
goldens, and the shared registration vectors — with zero check changes;
per-encode memory fell ~638K → ~150K. The post-fix cells are the table above
(reg_7key 84.6% → 35.44% memory used). The A-001 fallback (re-introducing the
attested tier) was never engaged, and no check was weakened.

## Residuals

- **Temporary pre-deployment unicity window (gate = #116 scope).** Nothing in
  this path prevents minting the same `(policy, aid_asset_name)` twice (spec
  §Unicity; ruled at A-001 QC). The window is accepted only pre-deployment —
  the script hash freezes at deployment, and the unicity/absence gate is
  explicit #116 scope. #114's structural obligation holds in the measured
  cells: the `Register` branch admits inputs beyond those R5 names (room for
  the future gate input), exercised by the slice-5 extra-input positive
  vector. Interim harm is bounded: a duplicate's datum is forced to the
  victim's own key-state at the attacker's deposit expense, and the duplicate
  cannot advance (`AdvanceMessage` binds the exact spent `TxOutRef`).
