# Tasks: endpoint board

## Slice 1 — validator and contract seam

- [x] T001-S1 Add RED Aiken board lifecycle and adversarial tests.
- [x] T002-S1 Implement the combined board validator and frozen wire types.
- [x] T003-S1 Derive and drift-check the script policy/address; publish the release seam.

## Slice 2 — signed record and catalog

- [x] T004-S2 Add genuine and adversarial KERI endpoint-record fixtures/tests.
- [x] T005-S2 Implement fail-closed record parsing, board manifest, Koios address query, and catalog rendering.

## Slice 3 — status and preflight

- [x] T006-S3 Add RED watchability and witnessed-registration preflight tests.
- [x] T007-S3 Wire verified board membership into `ckeri status` and `ckeri register`.

## Slice 4 — mutation transactions and CLI

- [x] T008-S4 Add RED transaction-plan/runner and opt-env-conf surface tests.
- [x] T009-S4 Implement board deploy/post/update/retire transactions and command settings.

## Slice 5 — docs, live proof, and CI

- [ ] T010-S5 Add the endpoint-board user page, navigation, capture/check scripts, and CI tripwire.
- [ ] T011-S5 Capture the binding witness-operator → clean stranger-machine
      public-docs-only post/list/verify/dial journey with nothing mocked.
- [ ] T012-S5 Continue the same raw capture through forged/stale failures,
      status watchability, update, retire/refund, and all-three-live restore;
      commit settled txids and machine facts.
- [ ] T013-S5 Embed the exact raw capture in the PR body, pass the final gate
      and CI, and park for desk merge.
