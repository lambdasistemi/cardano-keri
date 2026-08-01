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
   When the Cabal version has a matching `CHANGELOG.md` section but no git
   tag, it creates and pushes `v<version>`. Otherwise it opens a release
   preparation PR on the `release/cabal-release` branch.

2. **Linux Release** (`release.yml`) — triggered by `v*` tag pushes,
   pull requests, and manual dispatch. Tag pushes build release artifacts
   and publish them to the GitHub release. PRs and manual dispatches build
   dev artifacts and smoke-test them without publishing.

Merging a release PR does **not** publish. The next planner run on `main`
creates the tag, and the tag-push workflow publishes.
