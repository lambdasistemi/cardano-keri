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
      the tag workflow publishes the epic-marked prerelease. Real tag
      `v0.1.0` was pushed and published first, but its DEB/RPM assets
      carried the wrong package version (`1.0`, a real `NixOS/bundlers`/
      `parseDrvName` defect — see `lambdasistemi/cardano-keri#207`) and were
      withdrawn (see `answers/A-005-...`). The genuinely complete first
      release is **`v0.1.1`**, produced by the fully-fixed pipeline:
      https://github.com/lambdasistemi/cardano-keri/releases/tag/v0.1.1
      (AppImage/DEB/RPM, all three correctly versioned `0.1.1`).
- [x] T196-A-4 Verify the release URL/assets and attached clean-environment
      transcript show downloaded `ckeri --version` matching tag and Cabal,
      **for all three shipped formats**. Done for `v0.1.1`: a plain
      `ubuntu:22.04` container with no clone and no pre-existing nix store
      downloaded each public asset and exercised it the way a real user
      would — AppImage run directly, DEB installed via real `dpkg -i` (and
      `dpkg -s` confirms the installed package version), RPM verified via
      `rpm -qp` metadata and its extracted binary executed. All three report
      `ckeri 0.1.1`, matching tag `v0.1.1` and Cabal `0.1.1` exactly.
      Transcript attached to the `v0.1.1` release.

      **What the automated CI smoke does and does not prove**: the frozen
      slice gate's `linux-artifact-smoke` and CI's smoke steps only extract
      the AppImage with `--appimage-extract` and run the result directly —
      which only "works" because the CI runner and the build happen to
      share a nix store, not because the artifact is genuinely
      self-contained (confirmed by reproducing the failure in a clean
      container with no shared store: `bad interpreter`). Automated CI
      smoke has never exercised the DEB or RPM at all. **This manual,
      clean-environment transcript is what actually establishes correctness
      today** for all three formats; the CI smoke's blind spot is filed as
      `lambdasistemi/cardano-keri#205` and does not block this ticket, since
      the real artifacts were independently proven to work.

      **Also found and fixed while shepherding the real release** (each is
      a real defect the frozen local gate could not see, only real
      execution against real GitHub infrastructure surfaced them):
      `#207` DEB/RPM version defaulted to `1.0`;
      `#208` the release planner's control flow could never reach its
      version-bump computation once a release had happened once, so no
      release after the first could ever be cut;
      `#210` the changelog-section insertion silently no-op'd on an
      unexpanded `$$` inside single quotes, so generated changelog entries
      were silently dropped;
      `#204` (**not yet merged** — blocked on a persistent, unrelated
      self-hosted CI runner-fleet disk exhaustion, tracked separately from
      this ticket) makes `gh pr create` use the App token so future
      planner-generated release PRs get real CI checks instead of
      `action_required` gating; manually approved the gated runs for both
      `v0.1.0`'s and `v0.1.1`'s release PRs as a stopgap.
      Known cosmetic defect, disclosed rather than fixed: generated
      changelog entries render as `- release): fix ...` instead of
      `- fix(release): fix ...` (a `sed` scope-stripping pattern bug in
      `scripts/release/changelog`) — doesn't affect version agreement or
      any acceptance criterion, not worth another slice.

