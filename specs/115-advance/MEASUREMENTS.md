# #115 advance transaction measurements

## Verdict

**The #115 A-001 measurement acceptance gate passes.** Every measured
`Advance` cell retains at least 25% headroom on both mainnet execution-unit
axes. The binding cell is the GLEIF-scale witnessed 7-key rotation at
**45.62% memory headroom** and **65.62% CPU headroom**. No fallback tier was
used and no validator check was weakened.

Mainnet per-transaction budget:

| resource | budget |
| --- | ---: |
| memory | 14,000,000 |
| cpu | 10,000,000,000 |

Headroom is calculated as `(budget - used) / budget * 100`. The binding gate
requires every resource in every cell to have at least 25.00% headroom.

## R1 family-split deployability contract

The A-007 full repository gate passed with the final family split. The
permanent `check-checkpoint-deployability` recipe compiles the live Aiken
sources with the pinned offchain compiler, applies parameters through the
builder's `applyProgram`/`serialiseUPLC` path, and rejects any applied program
at or above 16,133 bytes.

| applied program | size (bytes) | script hash |
| --- | ---: | --- |
| `observer_lifecycle` | 6,454 | `e1ccfe3abf9a539beaa7bed9d4afd1341963c9ec0aa9389f4705dcfd` |
| `observer_enforcement` | 14,347 | `d7d22ccdb22fa1abffec72dcac1d28cd0ca07514e133e40131e7d534` |
| `checkpoint` | 7,063 | checkpoint identity `h`; the R1 gate records its applied size |

**R1 verdict: PASS — all three programs are strictly below 16,133 bytes.**
The binding program is `observer_enforcement`, with 1,786 bytes of strict
stock-cap gate room. Reproduce with `just check-checkpoint-deployability`;
the successful A-007 `./gate.sh` run reproduced both observer hashes and all
three sizes above.

## Checkpoint `Advance` spend (`checkpoint.ak`)

Measured with the pinned Aiken
(`github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken`) and
`aiken check --plain-numbers -m measure_checkpoint` at the accepted slice-6
tree (`ba3b414`); reproduce with `just measure-checkpoint`. Each advance cell
in `onchain/validators/checkpoint_measurements.ak` invokes the real
`checkpoint.checkpoint.spend` handler on its ACCEPT path over a full spend
transaction. Fixture construction is held in top-level constants, so it is
not charged to the measured validator execution.

Every cell includes V1 named-own-input, ACTIVE-address, inline-datum, and
derived-token checks; V2 unique ACTIVE successor, inline successor datum,
same-token, and no-own-policy-mint/burn checks; the V3 deposit floor; and the
V4-V7 `advance_predicate` path over a `SpentCheckpoint` reconstructed from
the deployment parameters, named outref, and spent datum. That predicate
performs message reconstruction and equalities, controller-signature
admission, AE1-AE10 event binding, witness-delta validation, and receipt
quorum verification.

| cell | fixture (verification shape) | mem | mem used | mem headroom | cpu | cpu used | cpu headroom |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `adv_wit_2key` | witnessed cut+add, 2 controller signatures + 2 witness receipts | 4,226,861 | 30.19% | 69.81% | 2,046,910,284 | 20.47% | 79.53% |
| `adv_wit_7key` | GLEIF-scale 7-key partial reveal, 3 controller signatures + 2 witness receipts | 7,612,741 | 54.38% | 45.62% | 3,438,427,877 | 34.38% | 65.62% |
| `adv_keep` | no-delta steady-state rotation, 2 controller signatures + 2 witness receipts | 3,824,714 | 27.32% | 72.68% | 1,886,941,692 | 18.87% | 81.13% |

**A-001 verdict: PASS — all cells have at least 25% headroom on both axes.**
Minimum headroom is **45.62% memory** and **65.62% CPU**, both on
`adv_wit_7key`.

## Gate history

The first complete GREEN measurement also passed, before the mechanical
Q-009 correction: `adv_wit_2key` used 4,225,237 memory / 2,045,150,133 CPU;
`adv_wit_7key` used 7,611,117 / 3,436,667,726; and `adv_keep` used 3,823,090 /
1,885,181,541. Q-009 did not concern execution headroom: `git diff --check`
found trailing whitespace produced by the formatter around the V1 ACTIVE
address pattern. The formatter-stable equivalent split the address check
into payment-credential and staking-credential assertions. The final values
in the table rose by only 1,624 memory and 1,760,151 CPU per cell and still
clear the gate comfortably.

The driver, navigator, and ticket orchestrator each independently reproduced
the final raw values and headroom arithmetic. The reserved measurement-STOP
Q-007 was never opened because no cell or resource missed 25.00%; there was
no measurement stop, fallback, waiver, or weakened check to preserve.

## Residuals

- The cells measure only the #115 `Advance` branch. `Freeze`, `Convict`, and
  `Close` remain explicit fail-closed constructors for #116/#117 and are not
  represented as ACCEPT-path measurement cells here.
- The extra-input gate-room required for #116 is behaviorally covered by the
  Slice 6 end-to-end tests. Its unrelated input is intentionally not a
  separate measurement tier because V1 names one input without scanning or
  constraining the total input count.
