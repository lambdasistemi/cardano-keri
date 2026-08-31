# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## Unreleased
## 0.4.1

### Added

- determine S2 witness mode with a measured inline control
- split S0 staging into premint plus burn
- repair S0 skeletons for reachable measurement
- add S0 family size skeletons
- prove board migration continuity field by field
- enforce atomic migration continuity
- split the entitlement observer and bind both observers in the register
- enforce lean checkpoint migration family
- bind migration value continuity and replay to the real input
- enforce checkpoint migration family
- add migration parity types
- enforce one-use OOBI authorization
- add canonical OOBI authorization codec
- add standalone bounty commitment component
- route every write build read through the local ChainQuery interpreter
- add atomic chain-query algebra
- compose the live in-process transaction path, retire cardano-cli
- migrate advance, close, and board transactions off cardano-cli
- migrate Registration off cardano-cli
- migrate Publisher off cardano-cli
- add shared build and signing kernel
- add coherent in-process runtime seam
- Stage D dual-head bump with identity consistency check

### Fixed

- repair changelog generation and the silent planner skip
- bump MPF proof verification to v2.1.0 (#307)
- adopt S0-only deployment classification
- bind TxB evidence files in Nix tests
- emit exact measured-source and trace-level lines
- accept measured source commit distinct from HEAD
- apply predecessor policy in derivation
- compare independently sourced continuity fields
- make witness anchor cwd-independent
- derive the register version-remnant census from syntax trees
- align register deployment arity
- parameterize commitment lifetime
- bound phase-2 collateral loss
- recover deployed board validator artifact
- make the public-surface enumeration fail closed instead of silently skipping
- close the public surface over formatting and nesting, and guard the callback slot
- derive the eager-rejection property over the whole public export surface
- retire the unsafe public snapshot runners instead of avoiding them
- preserve the inline datum, and state the deferred disposition honestly
- fail closed on an undecodable checkpoint output, in one shared decode
- layout-independent Cabal-parser boundary check (A-011)
- repair vacuous no-cli guard's stale CLI path (#240)
- retire stale write-verb Koios assertions in check-ckeri-cli.sh (#240)
- stop rewriting acceptance evidence
- restore acceptance checker coverage
- remove cardano-cli from packaged closure
- strengthen Registration migration proofs
- rename the multi-address payer scan away from the merged API
- list the shared transaction fixtures in deployment-tests
- keep transaction checks lockfile-clean
- scope the S2 advance-family record out of this run
- re-measure the observer-advance size pin after rebasing onto main
- name missing query manifest inputs

### Changed

- apply 4 behavior-preserving hlint hints (A-009)
- authenticate advance events from the KEL

### Documentation

- record the delegated-AID feasibility evaluation
- specify MPF v2.1 proof bump (#307)
- report duplicity as a fact, not a recovered verdict
- state current-key compromise and correct conviction terminality
- bind the mandate to gate v1.2
- land the projection-fidelity design record (#300) (#301)
- freeze the S2-without-B witness-mode mandate
- mark S0 size gate complete
- correct S0 provenance and arithmetic
- name S2 co-residency witness handoff
- record Tx-B co-residency as unresolved
- record S0 two-transaction family sizes
- record S0 family size measurements
- record S0 family size measurements
- record S0 family size measurements
- freeze S0 size-failfast mandate
- define live entitlement E2E wiring
- stamp the delivered S254-2 board tasks
- distinguish target script identity
- stamp T254-004 and record the three-counter budget
- insert register arity repair slice
- pin revised entitlement component
- defer sibling authentication schemas
- cut speculative migration metadata
- record entitlement slice ruling
- align the #271 dependency with the entitlement ruling
- define validator migration mandate
- amend component contract after YAGNI audit
- separate target board planners
- slim board authorization lifecycle contract
- split standalone commitment delivery
- instantiate campaign ledger, record the unconfirmed-reveal residual
- define bounty entitlement mandate
- instantiate board campaign ledger
- define board OOBI binding contract
- state KERI projection constitution
- seed lane for #272 projection constitution
- define bounded collateral mandate
- define GHC-derived public surface guard
- correct board proof path fence
- plan reproducible board validator
- define ChainQuery-only write routing
- define local-only write tier
- specify chain query algebra
- state cardano-cli-free transaction path
- recut deploy and register migration
- record PR #243's merge and open Slice A6 (rebase onto main)
- record the E2E blueprint FOD staleness finding and Slice A4
- record the pre-commit vector-drift gate substitution
- record the emergent CLI-permissionlessness finding
- record the cross-fence AdvanceMessage leftover ruling
- spec, plan, and tasks for the permissionless advance path
- add the Why Cardano page
- correct how cardano-backer anchors
- record deploy checkout input
- plan installed status manifest diagnostics

### Testing

- isolate S0 Blake3 reachability
- wire live entitlement commitments
- pend live freeze/convict stories on #271 entitlement wiring (#280)
- cover both inventory uniqueness call sites
- expose migration continuity gaps
- close migration proof gaps
- prove migration safety properties
- prove bounty payees are unauthenticated at base
- prove register deployment arity mismatch
- reproduce the audit findings at the transaction boundary
- freeze the checkpoint migration RED bundle
- derive public guard from GHC export data
- freeze the S262-1 RED proof bundle
- observe the inline datum and the deferred-invariant disposition
- complete non-degenerate entrypoint proof for the local write path
- RED proof bundle for local write-path S240-1
- prove CLI composition is absent
- freeze advance close board migration proofs
- give testPParams a real key deposit

### Maintenance

- open the validator-migration lane
- add a PR description template (#275)
- stamp the accepted local write tier tasks
- correct the flake invocation census
- define flake-lock enforcement contract
- lock declared deployPreprod input (pre-existing main defect)
- stamp Slice 4 tasks complete
- stamp Slice 3 tasks complete
- stamp Slice 2C and deposit-oracle tasks complete

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
