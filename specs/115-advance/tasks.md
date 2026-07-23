# Tasks: permissionless advance projection (#115 re-land)

All PR #120 checkmarks are superseded. These tasks begin unchecked on the
91ccc71 re-land base.

## Planning checkpoint

- [x] T115-P0 Verify main/base, run baseline just ci and ./gate.sh, create
      feat/115-advance, push bootstrap commit 49d6487, and open draft PR #132.
- [x] T115-P1 Verify preprod route, key-path permissions without reading key
      contents, and the exact 10,000 tADA funded UTxO.
- [x] T115-P2 Replace spec.md, plan.md, and tasks.md with the permissionless
      projection, observer, stock-cap, burn, measurement, preprod, and demo
      contract.
- [x] T115-P3 Obtain epic-owner approval through Q-001/A-001 before any
      implementation dispatch.

## R1 — family-split withdraw-0 observer forwarding

- [x] T115-R1 Replace the oversized generic observer with
      observer_lifecycle (Register; Advance reserved fail-closed) and
      observer_enforcement (Freeze/Convict); retain checkpoint
      state/Value/own-token/payout logic; move the hash-proof evidence burn;
      slim checkpoint redeemers to an exact opaque-payload family claim; cover
      all absent/mismatch/cross-family coupling negatives; remove the obsolete
      network_id parameter; register both observer stake credentials in devnet
      setup; prove both certificate handlers reject deregistration; apply/build
      checkpoint plus both observers; prove all three are less than 16,133
      bytes without opening Advance. The independently reviewed A-004 forward
      probe (12,239 checkpoint-plus-Register / 20,092
      Freeze+Convict+Advance) is a BUST and does not consume either of the two
      permitted complete family-split attempts.

## R2 — production cap

- [x] T115-R2 Delete the 32 KiB genesis/runner and NON-DEPLOYABLE runtime
      banner; restore stock maxTxSize 16,384; settle all three reference-script
      creation shapes on stock devnet; permanently gate all three applied sizes
      and executable/config source against 32768; preserve honest #190 pending
      labels.

## R3 — event-own advance authentication

- [ ] T115-R3 Delete AdvanceMessage, its domain/reconstruction/CBOR
      fresh-signature helpers and goldens; verify indexed controller
      signatures over event_bytes; preserve dual thresholds, W1-W3,
      AE1-AE10, and incoming-set receipts; add ObserveAdvance to
      observer_lifecycle and regenerate Haskell/Aiken byte and verdict parity
      vectors.

## R4 — all live Advance roles

- [ ] T115-R4 Open one Advance branch from ACTIVE, ARMED, and FROZEN; require
      exact ACTIVE/ARMED Value preservation, FROZEN input plus B, unique ACTIVE
      successor, pre-deadline ARMED response, exact observer coupling, and the
      full role/time/value/token adversarial matrix; activate production-shaped
      E2E builders honestly.

## R5 — conviction burn

- [ ] T115-R5 Burn the exact AID token on ACTIVE/ARMED/FROZEN Convict; create
      no continuing output; route min-ADA/D_reg/B exactly; remove TombstoneV1,
      Tombstone role/tag, codecs, predicates, and dispatch; update Lean,
      Haskell, generated vectors, Aiken lifecycle mirror, traceability,
      terminality, value conservation, and re-registration properties without
      touching #117.

## R6 — final budgets

- [ ] T115-R6 Gate exactly thirteen full-handler ACCEPT rows at no more than
      10.5M memory and 7.5B CPU each; measure the selected family observer plus
      checkpoint at final arity; record exact headroom and all three applied
      sizes in MEASUREMENTS.md; run the stock-cap live-node boundary.

## R7 — manual preprod and demo tooling

- [ ] T115-R7 Ship a standalone manual preprod just recipe and runner using
      KERI_PREPROD_KEY_DIR, the ruled socket/container/magic/address,
      D_reg=5 ADA, B=5 ADA, W_freeze=120 seconds; protect/redact secrets; add
      both observer stake registrations and record their txids; add genuine
      pinned-keripy demo AIDs/KELs and hermetic dry-run tests; prove no
      gate.sh, just ci, Nix-check, or workflow dependency.

## R8 — pair-owned narrative

- [ ] T115-R8 Update only identity-ops, trust-model, M1 blog, and milestones
      deck advance fragments for permissionless replay, event-own evidence,
      response/thaw, advance-totality, bounded interference, conviction
      history-by-burn, both observer-registration/deregistration liveness
      dependencies, and the rolling genuine-keripy preprod demo; keep #117 held; pass strict
      docs/link/presentation gates.

## Final local and public evidence

- [ ] T115-F1 Run clean final ./gate.sh; independently recompute all three
      applied sizes and audit the exact 13-row headroom table.
- [ ] T115-F2 Manually settle all three reference scripts and Register, Arm,
      Claim on preprod after registering both observer stake credentials; run the
      ACTIVE advance, ARMED response, and FROZEN thaw demo; record redacted
      output, script hashes, AIDs, explorer URLs, and txids.
- [ ] T115-F3 Update and independently verify the PR body, push final HEAD,
      and obtain green required checks.
- [ ] T115-F4 File mark-ready Q with local gates, size/exunit evidence,
      preprod txids, demo proof, and residual #190 truth; wait for an A-file
      before gh pr ready.
- [ ] T115-F5 After authorization, mark the PR ready, re-check CI, and park for
      the epic owner to merge. Do not self-merge and do no #117 work.
