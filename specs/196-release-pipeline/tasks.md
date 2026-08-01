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
      (Corrected from an earlier, wrong assumption that this step could be
      skipped: the planner as shipped in #197 had no version-bump-selection
      logic at all — a real FR-1 gap, not a CI bug — so it would have
      re-tagged the stale `0.0.0` forever. Per `answers/A-003-...` and
      `answers/A-004-...`, this was fixed (`scripts/release/next-version`,
      seeds `0.1.0` since no `v*` tag had ever existed) and the real planner
      genuinely opened, and this lane merged, PR #203 "chore(release):
      0.1.0" — the path executed for real, not a checked box on an
      unexercised mechanism.)
- [x] T196-A-3 The next planner run pushes the matching `v<version>` tag and
      the tag workflow publishes the epic-marked prerelease. (Real tag
      `v0.1.0` pushed by the planner after PR #203 merged; `Linux Release`
      published `ckeri 0.1.0 [latest]` with AppImage/DEB/RPM assets:
      https://github.com/lambdasistemi/cardano-keri/releases/tag/v0.1.0)
- [x] T196-A-4 Verify the release URL/assets and attached clean-environment
      transcript show downloaded `ckeri --version` matching tag and Cabal.
      (Done: a plain `ubuntu:22.04` container with no clone and no
      pre-existing nix store downloaded the public AppImage asset and ran it
      via its own runtime; output `ckeri 0.1.0` matches tag `v0.1.0` and
      Cabal `0.1.0` exactly. Transcript attached to the release. Along the
      way, found that the CI smoke tests give false confidence via a shared
      nix store between build and test machines — filed as
      lambdasistemi/cardano-keri#205, not blocking this ticket since the
      real artifact genuinely works.)

