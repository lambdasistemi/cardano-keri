# Tasks — #196 day-0 release pipeline

## Slice 1 — release pipeline

- [x] T196-S1-1 Add Cabal-version, changelog, release-channel, notes, and
      planner helpers with positive and negative controls; reject
      release-please state.
- [x] T196-S1-2 Add the App-token-authenticated `Release Planner` workflow for
      `release/cabal-release` and tag creation.
- [x] T196-S1-3 Add `NixOS/bundlers` with an additive-only lockfile diff and no
      existing revision/hash changes.
- [x] T196-S1-4 Add flake-owned release/dev Linux AppImage artifacts for the
      existing `ckeri` inventory, including checksums and bundled `pkgs.cacert`.
- [x] T196-S1-5 Add an artifact smoke that extracts the package, proves the CA
      closure is present, and checks exact `ckeri --version` output without a
      live socket/service.
- [x] T196-S1-6 Add safe PR/dev/tag modes to `Linux Release`; tag publication
      uses configuration-driven epic/prerelease metadata. The no-clone
      clean-container download/run transcript itself is captured post-merge
      against a real tag (see T196-A-4), not fabricated in PR/dev mode — this
      slice ships the mechanism, not a rehearsal transcript.
- [x] T196-S1-7 Document Linux installation, planner/tag lifecycle,
      epic-scoped status, acceptance evidence, and #188's single inventory
      extension point without touching its owned files.
- [x] T196-S1-8 Prove the focused release gate RED on the baseline, GREEN on
      the implementation, then run `./gate.sh` and every offchain flake check;
      one commit with `Tasks:` trailer.

## Post-merge acceptance — real release

- [x] T196-A-1 Milestone desk merges the pipeline PR; this lane resumes
      rather than declaring the ticket complete. (Corrected: #196 is a
      standalone milestone ticket, not epic-owned — there is no epic owner
      in this chain. Merged as `705a423` via merge-guard, method=merge,
      authorized in `answers/A-001-merge-197-authorized.md`.)
- [x] T196-A-2 Release planner opens/updates `release/cabal-release`; checks
      pass and this lane merges only that planner-generated PR under A-001.
      (Not needed this cycle: `CHANGELOG.md` already carried the `## 0.0.0`
      section from the slice-1 commit, so the planner's first push-to-main
      run went straight to tagging — see A-3 — with no intermediate release
      PR to merge.)
- [ ] T196-A-3 The next planner run pushes the matching `v<version>` tag and
      the tag workflow publishes the epic-marked prerelease.
- [ ] T196-A-4 Verify the release URL/assets and attached clean-environment
      transcript show downloaded `ckeri --version` matching tag and Cabal.

