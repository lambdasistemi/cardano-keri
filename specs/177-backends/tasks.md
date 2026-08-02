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

## Slice 2 — user docs and truthful three-tier evidence

- [ ] T177-S2-1 Document exact installed `ckeri` commands for local, hosted,
      and Koios tiers, configuration precedence, source/freshness, and closed
      errors
- [ ] T177-S2-2 Explicitly document fork retirement: rough
      `list`/`checkpoint`/`payer` shell behavior dropped; transactional
      store/query engine and production `status`/board/manifest commands kept
- [ ] T177-S2-3 Add an executable validator/helper for UTC-dated transcript
      provenance and exact production command shapes
- [ ] T177-S2-4 Run the same AID through local, hosted, and Koios using the
      built production binary; preserve exact commands, raw output, source,
      binary/store provenance, operator identity, timestamp, and exit status
- [ ] T177-S2-5 Validate committed concise evidence against preserved raw
      runtime artifacts without touching the hosted service lifecycle
- [ ] T177-S2-6 Immutable slice gate and `./gate.sh` green; navigator verifies
      one docs/evidence commit

## Orchestrator-owned completion

- [ ] T177-O-1 Independently inspect both accepted commits/diffs, task stamps,
      gate hashes, no-fork audit, and exact packaged binary help
- [ ] T177-O-2 Push the branch, keep the issue-linked PR draft during work,
      and ensure assignment/labels/body/checks are correct
- [ ] T177-O-3 Run fresh final `just ci` and `./gate.sh`, record filesystem
      deltas, and confirm no live service or flake pin was changed
- [ ] T177-O-4 Mark the PR ready only after three-tier evidence and CI are
      green; append `COMPLETE <pr> ready-for-review`; never self-merge
