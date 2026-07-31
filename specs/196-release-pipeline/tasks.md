# Tasks — #196 day-0 release pipeline

## Slice 1 — release pipeline

- [ ] T196-S1-1 Add Cabal-version, changelog, release-channel, notes, and
      planner helpers with positive and negative controls; reject
      release-please state.
- [ ] T196-S1-2 Add the App-token-authenticated `Release Planner` workflow for
      `release/cabal-release` and tag creation.
- [ ] T196-S1-3 Add `NixOS/bundlers` with an additive-only lockfile diff and no
      existing revision/hash changes.
- [ ] T196-S1-4 Add flake-owned release/dev Linux AppImage artifacts for the
      existing `ckeri` inventory, including checksums and bundled `pkgs.cacert`.
- [ ] T196-S1-5 Add an artifact smoke that extracts the package, proves the CA
      closure is present, and checks exact `ckeri --version` output without a
      live socket/service.
- [ ] T196-S1-6 Add safe PR/dev/tag modes to `Linux Release`; tag publication
      uses configuration-driven epic/prerelease metadata and records a
      no-clone clean-container download/run transcript.
- [ ] T196-S1-7 Document Linux installation, planner/tag lifecycle,
      epic-scoped status, acceptance evidence, and #188's single inventory
      extension point without touching its owned files.
- [ ] T196-S1-8 Prove the focused release gate RED on the baseline, GREEN on
      the implementation, then run `./gate.sh` and every offchain flake check;
      one commit with `Tasks:` trailer.

## Post-merge acceptance — real release

- [ ] T196-A-1 Epic owner merges the pipeline PR; this lane resumes rather
      than declaring the ticket complete.
- [ ] T196-A-2 Release planner opens/updates `release/cabal-release`; checks
      pass and this lane merges only that planner-generated PR under A-001.
- [ ] T196-A-3 The next planner run pushes the matching `v<version>` tag and
      the tag workflow publishes the epic-marked prerelease.
- [ ] T196-A-4 Verify the release URL/assets and attached clean-environment
      transcript show downloaded `ckeri --version` matching tag and Cabal.

