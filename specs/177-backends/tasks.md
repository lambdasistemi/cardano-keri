# Tasks — #177 one production query command across three backends

Boxes are stamped only by the ticket orchestrator after the immutable gate and
independent navigator review pass. Each slice is one bisect-safe commit with a
`Tasks:` trailer.

## Slice 1 — backend seam, production CLI, and fork retirement

- [x] T177-S1-1 RED: parser tests cover `--aid`, explicit local/endpoint/Koios
      selection, endpoint shorthand, default Koios, opt-env-conf inputs, and
      rejection of missing or cross-backend settings
- [x] T177-S1-2 RED: adapter contract tests cover common successful rendering,
      malformed identifiers/payloads, stale or impossible freshness, named
      unsupported operations, and no fallback
- [x] T177-S1-3 RED: local mutation/rollback proves payload plus `as_of_slot`
      come from one transaction and no derived cache survives
- [x] T177-S1-4 RED: endpoint tests consume exact #176 response shapes and
      reject mismatched AID, HTTP 503, malformed JSON, and dishonest freshness
- [x] T177-S1-5 RED: Koios tests derive `as_of_slot` from supporting records,
      compare a fresh tip, and reject missing/incoherent provenance
- [x] T177-S1-6 GREEN: implement one typed query backend seam, the local,
      endpoint, and Koios adapters, validated configuration, and one renderer
- [x] T177-S1-7 GREEN: route packaged `ckeri status` through the selected
      backend while preserving released Koios defaults and exact endpoint
      shorthand journey
- [x] T177-S1-8 Remove `ckeri-follower`, its interactive shell surface,
      package/app/check wiring, fork-only tests/docs/cast; retain engine/query
      code used by `ckeri` and `ckeri-query`
- [x] T177-S1-9 Prove dispatch wiring can fail by disconnecting one adapter,
      capture the named failure, restore, and rerun green
- [x] T177-S1-10 `just backend-check`, immutable slice gate, `./gate.sh`, and
      named Nix/package checks green; navigator verifies one behavior commit

## Corrective Slice 1R — capability-safe fork retirement

- [x] T177-S1R-1 Freeze the complete six-verb inventory from base `8153606`,
      classifying `status`/`list`/`checkpoint`/`payer` as retained capabilities
      and `help`/`quit` as excluded REPL affordances
- [x] T177-S1R-2 RED: focused production-surface tests fail because packaged
      `ckeri` does not yet expose every retained capability
- [x] T177-S1R-3 RED: separate no-loss and no-leak controls are each able to
      fail on, respectively, a disconnected retained verb and an added
      forbidden affordance/output marker
- [x] T177-S1R-4 GREEN: route all four retained capabilities through the typed
      backend seam with production configuration/rendering and named
      unsupported-capability errors without fallback
- [x] T177-S1R-5 Remove both mutations, pass focused/package/full gates, and
      obtain independent navigator acceptance of the corrective behavior

## Slice 2 — user docs and truthful three-tier evidence

Slice 2 remains paused until corrective Slice 1R is accepted. Parent NOTE-001
supersedes the earlier `list`/`checkpoint`/`payer` retirement classification.

- [x] T177-S2-1 Document exact installed `ckeri` commands for local, hosted,
      and Koios tiers, configuration precedence, source/freshness, and closed
      errors
- [x] T177-S2-2 Explicitly document capability-safe fork retirement: production
      `status`/`list`/`checkpoint`/`payer` kept; `help`/`quit`, the prompt,
      completion/history, progress framing, and rough rendering dropped
- [x] T177-S2-3 Add an executable validator/helper for UTC-dated transcript
      provenance and exact production command shapes
- [x] T177-S2-4 Run the same AID through local, hosted, and Koios using the
      built production binary; preserve exact commands, raw output, source,
      binary/store provenance, operator identity, timestamp, and exit status
- [x] T177-S2-5 Validate committed concise evidence against preserved raw
      runtime artifacts without touching the hosted service lifecycle
- [x] T177-S2-6 Immutable slice gate and `./gate.sh` green; navigator verifies
      one docs/evidence commit

## Slice 3 — hosted board enumeration after retirement

- [ ] T177-S3-1 Freeze `GET /board` as an authenticated deterministic catalog
      with top-level `as_of_slot` and `tip_lag_slots`
- [ ] T177-S3-2 RED: HTTP and encoder-derived OpenAPI drift tests cover the
      populated list shape; demonstrate a drifted response field makes the
      enforcing check fail, then restore it
- [ ] T177-S3-3 GREEN: reuse one `boardTx` for populated/empty catalogs, fail
      the whole route closed on a forged record, and omit `board` on 503
- [ ] T177-S3-4 Amend OpenAPI and user docs, pass the immutable Slice 3 gate and
      full gate, then publish the registry-facing `NOTE RELEASE` line

## Orchestrator-owned completion

- [x] T177-O-1 Independently inspect both accepted commits/diffs, task stamps,
      gate hashes, no-fork audit, and exact packaged binary help
- [ ] T177-O-2 Push the branch, keep the issue-linked PR draft during work,
      and ensure assignment/labels/body/checks are correct
- [ ] T177-O-3 Run fresh final `just ci` and `./gate.sh`, record filesystem
      deltas, and confirm no live service or flake pin was changed
- [ ] T177-O-4 Mark the PR ready only after three-tier evidence and CI are
      green; append `COMPLETE <pr> ready-for-review`; never self-merge
