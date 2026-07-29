# Tasks: endpoint board

## Slice 1 — validator and contract seam

- [ ] T001-S1 Add RED Aiken board lifecycle and adversarial tests.
- [ ] T002-S1 Implement the combined board validator and frozen wire types.
- [ ] T003-S1 Derive and drift-check the script policy/address; publish the release seam.

## Slice 2 — signed record and catalog

- [ ] T004-S2 Add genuine and adversarial KERI endpoint-record fixtures/tests.
- [ ] T005-S2 Implement fail-closed record parsing, board manifest, Koios address query, and catalog rendering.

## Slice 3 — status and preflight

- [ ] T006-S3 Add RED watchability and witnessed-registration preflight tests.
- [ ] T007-S3 Wire verified board membership into `ckeri status` and `ckeri register`.

## Slice 4 — mutation transactions and CLI

- [ ] T008-S4 Add RED transaction-plan/runner and opt-env-conf surface tests.
- [ ] T009-S4 Implement board deploy/post/update/retire transactions and command settings.

## Slice 5 — docs, live proof, and CI

- [ ] T010-S5 Add the endpoint-board user page, navigation, capture/check scripts, and CI tripwire.
- [ ] T011-S5 Capture the post-change full preprod journey with settled txids and commit the raw machine transcript.
- [ ] T012-S5 Embed the exact raw capture in the PR body, pass the final gate and CI, and park for desk merge.
