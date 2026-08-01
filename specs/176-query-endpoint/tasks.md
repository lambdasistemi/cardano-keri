# Tasks — #176 the hosted query endpoint

Boxes are stamped by the ticket orchestrator only after the relevant immutable
gate and independent navigator review pass. Each slice is one bisect-safe
commit with a `Tasks:` trailer.

## Slice 1 — transactional HTTP service and frozen contract

- [x] T176-S1-1 RED: application-level tests freeze exact `/ready`,
      `/checkpoint/{aid}`, `/board/{witness_key}`, and `/watchability/{aid}`
      JSON including `as_of_slot` and `tip_lag_slots`
- [x] T176-S1-2 RED: malformed identifiers return 400; unknown valid records
      return 200/null; disconnected, cold, impossible-tip, and lag-over-60 data
      requests return 503 with no endpoint payload field
- [x] T176-S1-3 RED: one request after mutation changes immediately; one after
      rollback loses abandoned data and reports the lower store watermark even
      when readiness's processed slot remains ahead
- [x] T176-S1-4 RED: runner instrumentation proves checkpoint/board/watermark—and
      both watchability address scans—execute in exactly one transaction per
      response
- [x] T176-S1-5 RED: forged/malformed board output fails the whole catalog;
      valid signed board data resolves by B-code witness key; duplicates do not
      inflate watchability
- [x] T176-S1-6 GREEN: implement transaction-scoped reads, board codec, public
      types/API/server, and common readiness/freshness gating without mutable
      derived state
- [x] T176-S1-7 GREEN: implement `ckeri-query` using one
      `withRocksDBIndexerRunner` + one linked follower + Warp lifetime; preserve
      `ckeri-follower`
- [x] T176-S1-8 Commit generated Swagger/OpenAPI, serve Swagger UI, and add a
      drift check against the exact public routes and response types
- [x] T176-S1-9 Add Cabal dependencies/modules/executable and flake
      package/app/check/OCI-image outputs; invoke binary help and image contents
      in checks
- [x] T176-S1-10 Prove the contract check can fail: rename one freshness field,
      capture the expected named golden failure, restore, and re-run green
- [x] T176-S1-11 Prove the no-cache guard can fail using its positive-control
      fixture, then pass it against the real HTTP modules
- [x] T176-S1-12 `just query-endpoint-check`, immutable slice gate,
      `./gate.sh`, and named flake checks green; navigator approves; one commit
      with task stamps and `Tasks:` trailer

## Slice 2 — docs and live acceptance helper

- [ ] T176-S2-1 Document “the query endpoint — checkpoint answers without a
      node”, the public URL, every route/field, curl examples, freshness, and
      fail-closed semantics
- [ ] T176-S2-2 Document opt-env-conf/service configuration, the one-process
      architecture, no-cache/rollback guarantee, and explicit #177 consumer
      handoff
- [ ] T176-S2-3 Register the page in MkDocs and verify the docs build
- [ ] T176-S2-4 Add a checked operator helper for the public curl, exact
      upstream stop/restart with cleanup, recovery, and declarative rebuild
      journey; it must not imperatively bring up the query service
- [ ] T176-S2-5 Run the helper only after deployment and commit a concise dated
      transcript whose claims match preserved raw runtime evidence
- [ ] T176-S2-6 Immutable slice gate and `./gate.sh` green; navigator approves;
      one commit with task stamps and `Tasks:` trailer

## Slice 3 — `/code/infrastructure` declarative deployment

- [ ] T176-S3-1 Create a clean infrastructure worktree/branch and pin the
      accepted cardano-keri query-image commit as a flake input
- [ ] T176-S3-2 Declare Nix-owned Compose/systemd lifecycle, persistent store,
      exact preprod socket mount, restart policy, process-health probe, external
      `web` network, and Traefik HTTPS route for `ckeri.dev.plutimus.com`
- [ ] T176-S3-3 Validate Compose/Nix evaluation and review the generated unit
      and container/image references before applying
- [ ] T176-S3-4 Run the declarative host rebuild; prove public HTTPS readiness
      and an M1 checkpoint/board/watchability response from a nodeless context
- [ ] T176-S3-5 Stop only `cardano-preprod`; prove 503/no-payload and degraded
      `/ready`; restore it and prove automatic recovery without restarting the
      endpoint
- [ ] T176-S3-6 Re-run the declarative rebuild and prove the endpoint returns
      without any manual compose/container command
- [ ] T176-S3-7 Infrastructure review/gates green; commit/push a focused PR;
      preserve unrelated dirty canonical-worktree changes untouched

## Orchestrator-owned completion

- [ ] T176-O-1 Push the frozen contract commit and append `NOTE RELEASE: query
      endpoint HTTP contract at <commit-or-PR-url>` before #177 binds
- [ ] T176-O-2 PR body states journey steps executed and explicitly records
      that `ckeri status --endpoint` moved to #177 to avoid a dependency cycle
- [ ] T176-O-3 Independently verify both PR diffs, exact heads, task stamps,
      checks, signatures, public TLS/curl evidence, upstream recovery, and
      declarative rebuild recovery
- [ ] T176-O-4 Final `./gate.sh` plus named flake checks green at the accepted
      cardano-keri head; infrastructure checks green at its accepted head
- [ ] T176-O-5 Append `COMPLETE <cardano-keri PR> ready-for-review`, link the
      infrastructure PR, and request epic-owner acceptance; never self-merge
