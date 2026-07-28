# Tasks: M1 V1 preprod deployment (#158)

## Slice 0 — bootstrap and contract

- [x] **T158-S0** Verify #157 closure, record the baseline, create the story
  worktree, extend the ticket gate, and open draft PR #169.
- [x] **T158-S1** Freeze the issue-backed specification, implementation plan,
  parser prohibition, preprod verification boundary, and operator-merge rule.

## Slice 1 — shared derivation and manifest

- [ ] **T158-S2** Extract one shared production V1 script derivation used by
  E2E and `ckeri`.
- [ ] **T158-S3** Add deterministic manifest encoding/decoding and pure
  source/blueprint/script mismatch checks with tests.

## Slice 2 — binary, publisher, and verifier

- [ ] **T158-S4** Birth `ckeri` with nested `deploy` and `manifest verify`
  commands, using `opt-env-conf` exclusively across options, environment, and
  YAML.
- [ ] **T158-S5** Publish temporary Plutus V3 envelopes through the configured
  `cardano-cli`, wait for exact unspent references, and atomically write the
  manifest.
- [ ] **T158-S6** Verify blueprint/source rebuild plus exact live preprod
  references through the independent public chain index.
- [ ] **T158-S7** Package `ckeri` and its runtime tools with Nix and add parser
  surface/forbidden-dependency acceptance.

## Slice 3 — preprod release and delivery

- [ ] **T158-S8** Create and fund a dedicated preprod deployer, publish all
  five V1 references, and commit the captured manifest.
- [ ] **T158-S9** Add the navigable “The M1 preprod deployment” page with
  settled transaction IDs and the captured successful verifier transcript.
- [ ] **T158-S10** Add live manifest verification to CI, pass the exact local
  gate, restore the standing gate, mark PR #169 ready, and park it for operator
  merge.

