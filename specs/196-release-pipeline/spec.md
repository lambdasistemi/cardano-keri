# Spec — #196 day-0 release pipeline

Child of epic #171. This ticket runs in parallel with #188 and proves the
release path using the `ckeri` executable that already exists today.

## User story

As a person who has not cloned `cardano-keri`, I can download a tagged Linux
release, run `ckeri --version` in a clean environment, and see the same version
as the Git tag and `offchain/cardano-keri.cabal`.

## Functional requirements

### FR-1 — Cabal owns the version

`offchain/cardano-keri.cabal` is the only version source of truth. A release
planner opens or refreshes `release/cabal-release`, changes only the Cabal
version and generated `CHANGELOG.md` section, and uses conventional commits to
select the PVP bump. Release-please manifests/configuration are rejected.

Merging the planner PR does not publish. The next planner run on `main` creates
`v<version>`. The planner must authenticate its checkout/push with a
short-lived token minted from the org-owned `lambdasistemi-ci` GitHub App so
the tag push triggers downstream workflows.

### FR-2 — Artifact creation belongs to the flake

`offchain/flake.nix` exposes release and revision-suffixed development Linux
artifact packages. Packaging uses the approved `NixOS/bundlers` input. Its
lockfile change is additive only: no existing input `rev` or `narHash` may
move.

The executable inventory is declared once so #188 can add its future binary
without redesigning workflows. This ticket packages only `ckeri`.

### FR-3 — HTTPS works after distribution

The packaged `ckeri` wrapper carries `pkgs.cacert` in the artifact closure and
sets the certificate environment used by its Koios HTTPS path. The artifact
smoke proves the wrapper and CA bundle both survive extraction; a dev-shell CA
path is not evidence.

### FR-4 — Tag-driven publication with safe non-release modes

The Linux release workflow:

- builds and smoke-tests development artifacts on relevant pull requests;
- builds release artifacts from `v*` tag pushes;
- defaults manual dispatch to build-only;
- publishes only on tag push or explicit `publish=yes` release dispatch;
- may publish a mutable `dev-linux` channel only in explicit dev mode.

Published assets include checksums. Publication is idempotent.

### FR-5 — Epic identity is configuration, not workflow logic

A validated release-channel configuration controls release title decoration
and whether GitHub marks a release as a prerelease. The initial configuration
identifies epic #171. No workflow hard-codes where the epic artifact graduates;
the later owner changes the configuration without redesigning the pipeline.

### FR-6 — Smoke the package, then the public release

PR/dev smoke extracts the produced artifact and runs the extracted `ckeri`,
with no node socket or live service. It checks the exact expected version and
the packaged CA closure.

After publication, a clean Ubuntu container with no repository clone downloads
the public GitHub asset, runs `ckeri --version`, checks tag/Cabal/output
agreement, and records a transcript. The transcript is uploaded to the GitHub
release as acceptance evidence.

### FR-7 — Operator documentation

Documentation covers the Linux install/run path, the Cabal-owned release
lifecycle, the epic/prerelease marker, the clean-environment evidence, and the
single executable-inventory edit #188 needs to join the pipeline.

## Rejection behavior

- A tag that differs from the Cabal version fails before packaging.
- A release without a matching changelog section fails.
- Release-please state fails the version contract.
- Missing/invalid release-channel configuration fails.
- PR and default manual runs cannot publish.
- A package missing `ckeri`, its version, its wrapper, or the CA bundle fails.
- Any change to an existing flake lock revision/hash fails the slice gate.

## Observable success

1. The pipeline PR is green and merged by the epic owner.
2. The planner-generated release PR is green and merged under the narrow
   authority granted in A-001.
3. The planner creates a tag whose version equals Cabal.
4. The tag workflow creates an epic-marked prerelease with a runnable Linux
   artifact and checksum.
5. The attached clean-environment transcript shows a fresh download and
   successful `ckeri --version` with the exact tag version.

## Non-goals and fences

- No release-please.
- No Hackage publication.
- No dependency-pin bumps; only the additive bundlers input is allowed.
- No #188 executable or `offchain/app/` edits.
- No indexer or #186 quality-gate work.
- No `offchain/cardano-keri.cabal` change beyond a planner-owned `version:`
  change on the later generated release branch.

