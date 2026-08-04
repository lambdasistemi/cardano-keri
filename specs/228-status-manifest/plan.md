# Plan: installed `status` manifest error (#228)

## Decision

Choose NOTE-011's clear named-error branch, not silent watchability degradation. `StatusView` and both local/Koios adapters model watchability as non-nullable, so making the board manifest optional would widen the backend contract and risk losing an already shipped field. A concise loader-boundary error is the smallest honest correction and also covers the sibling read-query commands that share the loader.

## Invariants

- Endpoint selection performs no local manifest I/O.
- Local/Koios selection loads both manifests before backend use.
- Successful status rendering is byte-for-byte unchanged around `watchable n/m`.
- File-open failures cross the same `dieConcisely` boundary as other CLI configuration errors.
- Validation failures inside readable JSON remain distinct from file-open failures.

## Live boundary

The boundary missed by existing tests is packaged executable + process working directory + filesystem lookup. The focused gate therefore runs the built `ckeri` binary from a fresh temporary directory with no checkout tree. It is deterministic and needs neither credentials nor a live Cardano service because manifest loading fails before Koios access. The existing endpoint production test protects the no-I/O branch; an existing backend status rendering proof protects `watchable` when valid manifests are supplied.

## Slice 1: named installed-manifest diagnostics

1. Add a packaged outside-checkout regression smoke/test and observe the current raw board-manifest exception (RED).
2. Normalize checkpoint/board manifest file-open failures at the shared read-query loading boundary into concise option-named diagnostics.
3. Prove explicit and default missing paths, valid-manifest watchability, endpoint independence, and the audited shared query surface.
4. Run the focused backend gate and full ticket gate, then create one behavior commit.

Anticipated implementation fence: `offchain/cli/Cardano/KERI/CLI.hs`, CLI production/config tests or strict-PATH smoke under `offchain/`, and only directly relevant test registration when required. Documentation changes are limited to `docs/user/status-backends.md` if the new diagnostic contract needs operator-facing wording.

## Release follow-up inventory

The transaction/deployment parser defaults listed in `spec.md` are not silently repaired here. They remain visible in the PR's audit section for parent/product routing; this slice does not invent an embedded release-asset policy.

## Verification-instrument ruling

The `E2E (withDevnet)` harness is not evidence for this ticket while #219 repairs its stale fixed-output validator script. No remaining #228 proof touches it: the focused gate builds the packaged CLI and runs it from tmpfs outside a checkout, `backend-check` is node-free, and the aggregate `just ci` recipe does not depend on the separately declared `e2e` or `ci-live` recipes. An E2E green elsewhere must not be cited as the live leg for this fix.
