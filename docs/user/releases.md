# Releases

`ckeri` ships self-contained Linux binaries for every tagged release.

## Channels

| Channel | Source | Stability |
|---------|--------|-----------|
| `latest` | Tagged releases (`v*`) | Production-ready |
| `dev-linux` | Manual dispatch builds | Development snapshots |

The active channel is declared in `.release-channel.json` at the repository
root.

## Artifacts

Each release produces three packages from the same Nix build:

| Format | File | Install |
|--------|------|---------|
| AppImage | `ckeri-<version>-x86_64.AppImage` | `chmod +x` and run directly |
| DEB | `ckeri_<version>_amd64.deb` | `sudo dpkg -i <file>` |
| RPM | `ckeri-<version>-1.x86_64.rpm` | `sudo rpm -i <file>` |

All artifacts bundle the `ckeri` witness-node runner together with its
complete runtime closure, including the CA certificate bundle used for
TLS verification.

## Verifying a release

```bash
# AppImage
chmod +x ckeri-*-x86_64.AppImage
./ckeri-*-x86_64.AppImage --version

# DEB
dpkg-deb -x ckeri_*_amd64.deb /tmp/ckeri
/tmp/ckeri/usr/bin/ckeri --version

# RPM
rpm2cpio ckeri-*.rpm | cpio -idmv
./usr/bin/ckeri --version
```

## Release process

Releases are driven by the Cabal version in `offchain/cardano-keri.cabal`
(the single source of truth) and automated by two GitHub Actions workflows:

1. **Release Planner** (`release-plan.yml`) — runs on every push to `main`.
   It computes the next version via `scripts/release/next-version`, writes
   it into the Cabal file, adds a `CHANGELOG.md` section, and opens a
   release preparation PR on the `release/cabal-release` branch.  When the
   Cabal version already has a matching `CHANGELOG.md` section but no git
   tag (i.e. the PR was merged), it creates and pushes `v<version>`.

2. **Linux Release** (`release.yml`) — triggered by `v*` tag pushes,
   pull requests, and manual dispatch. Tag pushes build release artifacts
   and publish them to the GitHub release. PRs and manual dispatches build
   dev artifacts and smoke-test them without publishing.

Merging a release PR does **not** publish. The next planner run on `main`
creates the tag, and the tag-push workflow publishes.

### Version selection: seed vs. computed

The **first release** (`0.1.0`) was a deliberate choice, not derived from
scanning commit history.  The repository had 367 commits before any release
rule existed; scanning them for conventional-commit prefixes would produce
a number that looks derived but means nothing.  When `scripts/release/next-version`
detects that no `v*` tag exists anywhere in the repository, it seeds the
version `0.1.0` directly.

**Every version after the first** is computed from the commits since the
previous `v*` tag, using conventional-commit classification:

| Commits since last tag | Bump class | Example (`0.1.0` →) |
|------------------------|------------|----------------------|
| Any `type!:` or `BREAKING CHANGE:` body | breaking | `0.2.0` (minor — see below) |
| Any `feat:` / `feat(scope):` | feature | `0.2.0` |
| Only `fix`, `chore`, `docs`, etc. (or nothing notable) | patch | `0.1.1` |

**Breaking changes in `0.x` bump the minor component, not major.**
This guarantees `1.0.0` is never reachable by accident — a major bump
requires an explicit non-zero major already present in the Cabal file.
Once the major component is `≥ 1`, breaking changes bump major per
ordinary SemVer (`1.2.3` → `2.0.0`).
