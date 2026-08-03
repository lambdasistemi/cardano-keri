# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## Unreleased
## 0.4.0

### Added

- blaster): record the S2 terminal builtin-support FAIL
- blaster): pin exact UPLC extraction path

### Documentation

- 192): plan exact-UPLC tractability experiment

## 0.3.0

### Added

- cli): preserve follower capabilities
- cli): add production query backends

### Fixed

- ci): follow named status interface

### Documentation

- spec): stamp PR finalization
- spec): stamp orchestrator verification
- spec): stamp backend evidence slice
- cli): record backend status evidence
- spec): stamp capability retirement slice
- spec): recut retirement around capabilities
- spec): stamp backend implementation slice
- spec): define production query backends

## 0.2.0

### Added

- indexer): add transactional query endpoint

### Fixed

- release): use the App token for gh so release PRs get real CI

### Documentation

- publish hosted query journey
- spec): align query JSON with acceptance contract
- spec): freeze hosted query endpoint contract

### Maintenance

- 196): record the real RPM install evidence, close out the ticket
- 196): record the real v0.1.1 acceptance and the full defect trail
- retire legacy tracked gate script
- ignore ticket gate runtime

## 0.1.1

### Fixed

- release): fix changelog insertion silently no-op'ing on unexpanded $$
- release): reach the next-version check when the current tag already exists
- release): give DEB/RPM the real Cabal version, not fpm's 1.0 default

### Maintenance

- 196): stamp post-merge tasks A-3 and A-4, correct A-2


## 0.1.0

Initial release of the `ckeri` KERI witness node runner with Linux
binary distribution (AppImage, DEB, RPM).
