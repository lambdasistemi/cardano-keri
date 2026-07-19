# Tasks: advance path (#115)

## Slice 1 — keripy witness-rotation fixtures

- [x] T115-S1 `gen_fixtures.py`: `p`/`br`/`ba` spans in `_field_spans`;
  `adv_wit_2key`/`adv_wit_7key`/`adv_downgrade`/`adv_keep` bundles
  (offsets, controller sigs, incoming-set witness receipts, seeds);
  byte-stable regen; existing bundles byte-unchanged; committed
  `fixtures/advance.json`; fixture spec coverage.

## Slice 2 — Haskell message amendment

- [x] T115-S2 `Message.hs`: 18-field `AdvanceMessage` (`wit_cut`/`wit_add`),
  `SpentCheckpoint.witnesses`, W1/W2 errors, derivation, amended eq7,
  two-seal doc fix; `MessageSpec.hs` + goldens regen; S1-fixture-driven
  equalities specs (incl. stolen-quorum, delta malformations).

## Slice 3 — Aiken message amendment + parity

- [x] T115-S3 `message.ak` mirror + `message_tests.ak` + `vectors.ak`
  regen; shared vectors byte-identical AND verdict-identical; registration
  goldens byte-unchanged.

## Slice 4 — Haskell advance predicate

- [x] T115-S4 `Advance.hs`: `AdvanceEvidence`, AE1–AE10, receipt gate,
  message reconstruction, `advancePredicate`; adversarial families
  (offset misdirection, receipt-index games, cut-witness receipts,
  outgoing-only quorum).

## Slice 5 — Aiken advance predicate + parity

- [x] T115-S5 `advance.ak` mirror (+tests) + `GenAdvanceVectors.hs`
  shared vectors (bytes AND verdicts) wired into `just ci`.

## Slice 6 — spend branch + measurement gate

- [x] T115-S6 `checkpoint.ak` spend redeemer sum + `Advance` V1–V7;
  end-to-end `ScriptContext` tests (4 honest shapes + shape vectors +
  fail-closed non-Advance redeemers + Register regression);
  `checkpoint_measurements.ak` cells at `adv_wit_2key`/`adv_wit_7key`/
  `adv_keep`; A-001 ≥25% STOP gate honored.

## Slice 7 — measurements report (docs-only)

- [ ] T115-S7 `specs/115-advance/MEASUREMENTS.md`: advance cells vs
  budget, headroom verdicts, any gate history preserved.
