# #188 tasks

## Slice 1 — runnable local-store follower

- [x] T18801 Add the standalone `ckeri-follower` process using the existing
  config, manifest, RocksDB, and bracketed follower path.
- [x] T18802 Add Haskeline verbs, completion/history, rendering, and live
  progress over one local query interface with no backend selection.
- [x] T18803 Prove every verb re-reads the real local store/readiness after
  apply, spend, and rollback-shaped changes; prove malformed input rejection.
- [x] T18804 Expose and invoke the executable/focused tests through Cabal,
  Nix package/app/runCommand checks, and deterministic `just ci` wiring.
- [x] T18805 Commit the separately-versioned M1 preprod follower start point
  with earliest-reference-transaction resolution provenance.
- [x] T18806 Make the frozen Slice 1 gate and full deterministic gate GREEN.

## Slice 2 — preprod documentation and cast

- [ ] T18807 Dry-run the final documented command against the live preprod
  node with the committed manifest/start point and a fresh store.
- [ ] T18808 Record the 80x24 preprod cast from the production executable,
  identifying the runner/date and demonstrating the interactive query surface.
- [ ] T18809 Validate the cast for JSONL/header, sanitization, event length,
  exact command provenance, and real output.
- [ ] T18810 Make `docs/user/follower.md` executable documentation and embed
  the cast through preview-safe MkDocs configuration.
- [ ] T18811 Make strict docs, the frozen Slice 2 gate, and the full final gate
  GREEN at the final commit.
