# Plan: advance path (#115)

Stack unchanged: Aiken (onchain, pinned toolchain since #105), Haskell
(offchain mirror + fixture specs), keripy hermetic fixture flake, `just ci`
as the gate body (`./gate.sh` = `git diff --check` + full `just ci`).

## Module map

| Artifact | Fate |
|---|---|
| `onchain/lib/cardano_keri/checkpoint/message.ak` | AMEND: 18-field `AdvanceMessage`, `SpentCheckpoint.witnesses`, W1/W2 + derivation, amended eq7, two-seal comment fix |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Message.hs` | AMEND: mirror of the above |
| `onchain/.../message_tests.ak`, `vectors.ak` | regen goldens (advance only; registration bytes unchanged) |
| `offchain/.../MessageSpec.hs`, `offchain/app/GenCheckpointVectors.hs` | regen goldens |
| `onchain/lib/cardano_keri/checkpoint/advance.ak` (+`_tests`, `_vectors`) | NEW: `AdvanceEvidence`, AE1–AE10, receipt gate, `advance_predicate` |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Advance.hs` (+ specs) | NEW: mirror; imports re-spelling helpers from `Registration` (`respell_hex`, `respell_threshold`, `qb64_witness_verkey` are already `pub`/exported — no refactor of #114 modules) |
| `onchain/validators/checkpoint.ak` (+`_tests`, `_measurements`) | AMEND: spend redeemer sum, `Advance` branch V1–V7; other constructors fail closed; Register untouched |
| `offchain/test/keri-fixtures/gen_fixtures.py` + `fixtures/advance.json` | NEW family (existing bundles byte-unchanged) |
| `offchain/app/GenAdvanceVectors.hs`, `justfile` | shared-vector plumbing wired into `ci`, mirroring #114's registration vectors |
| `specs/115-advance/MEASUREMENTS.md` | S7 report |

## Slices (one bisect-safe commit each)

- **S1 — fixtures.** `gen_fixtures.py`: `_field_spans` learns `p`/`br`/`ba`
  spans; `adv_wit_2key`, `adv_wit_7key`, `adv_downgrade`, `adv_keep`
  bundles with offsets, controller sigs, witness receipts, seed export;
  regeneration byte-stable; existing bundles byte-unchanged (checked in the
  slice test).
- **S2 — Haskell message amendment.** `Message.hs`: 18-field
  `AdvanceMessage`, `SpentCheckpoint.witnesses`, `EqW1CutInvalid`/
  `EqW2AddInvalid`, derivation + amended eq7, two-seal doc fix;
  `MessageSpec.hs` + goldens regen; fixture-driven equalities specs over
  the S1 family.
- **S3 — Aiken message amendment + parity.** `message.ak` mirror,
  `vectors.ak` regen, shared vectors byte- AND verdict-identical.
- **S4 — Haskell advance predicate.** `Advance.hs`: evidence, AE1–AE10,
  receipt gate, reconstruction, `advancePredicate`; adversarial families
  (misdirection, receipt games, delta malformations, stolen quorum) as
  executable specs.
- **S5 — Aiken advance predicate + parity.** `advance.ak` mirror +
  `GenAdvanceVectors.hs` shared vectors (bytes AND verdicts) wired into
  `just ci`.
- **S6 — spend branch + measurement.** `checkpoint.ak` `Advance` V1–V7
  (constructed-`ScriptContext` end-to-end tests incl. fail-closed
  non-Advance redeemers and Register regression), `checkpoint_measurements.ak`
  cells (`adv_wit_2key`/`adv_wit_7key`/`adv_keep`); **A-001 STOP gate: any
  cell < 25% headroom stops the ticket for an epic Q-file.**
- **S7 — MEASUREMENTS.md** (docs-only; RED-skip authorized), amending the
  house report format with the advance table.

Orchestrator-owned: spec/plan/tasks, gate.sh lifecycle, PR metadata, this
file's amendments, finalization audit.

## Risks

- **S6 measurement miss** — receipts (`new_toad` Ed25519 verifies over
  potentially ~1 KB rot bytes) + dual-threshold sigs + slices in one spend.
  Mitigation: the #114 encoder work already cheapened qb64; STOP-on-miss
  protocol is pre-agreed (Q-file, fallback tiers are an epic decision).
- **Golden churn** — S2/S3 regenerate advance goldens; a stray registration
  byte change is a slice-review veto (explicit byte-unchanged check).
- **keripy witness receipts** — receipt generation needs nontransferable
  witness signers wired into the fixture flake; if keripy's witness API
  fights the hermetic build, S1 stops and Q-files me (ticket-internal).
