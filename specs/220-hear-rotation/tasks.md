# Tasks — #220 hear a rotation (`ckeri verify`)

All implementation slices are PAIR, RED-first, GPG-signed, and independently
accepted by the ticket owner. These boxes are stamped only after acceptance.

## Planning and lane bootstrap

- [x] T220-P0 Run the bounded scratch-only release-closure probe before Slice
  1: build `ckeri` with pinned keripy 1.3.5, invoke it with no ambient Python,
  `kli`, network, or checkout, and run full `just ci`; record exit-0 logs and
  the required libsodium/binutils wrapper details.
- [x] T220-P1 Copy the parent-approved runtime spec, plan, and tasks into
  `specs/220-hear-rotation/` under the NOTE-004 partial release.
- [x] T220-P2 Bootstrap `/code/cardano-keri-220-verify` on
  `feat/220-hear-rotation` from the released `origin/main`; record clean
  baseline CI and resource deltas, plus a fresh packaged sandbox invocation
  asserting closure-owned `kli` reports keripy 1.3.5 under
  `--unshare-net --clearenv`, including the missing-libsodium-path negative
  control.
- [ ] T220-P3 Create the ignored ticket gate, GPG-signed planning commit, push,
  and draft PR with issue linkage, label, and assignee.
- [ ] T220-P4 Bind the command-registration paragraph to the landed #216 CLI
  contract; escalate any shared-backend-record change before implementation.

## Slice 1 — verified-history and verdict core

- [ ] T220-S1-1 Freeze and falsify the Slice 1 gate, including the 2/3
  non-unanimity mutation and planted-duplicity positive control.
- [ ] T220-S1-2 RED: add complete-history rejection tests for truncation,
  forgery, lineage, sequence, commitments, signatures, witness deltas, and
  receipt threshold; observe the focused failures.
- [ ] T220-S1-3 RED: add the 3/3, 2/3, 1/3, strict-coverage, checkpoint, and
  duplicity verdict matrix; observe the focused failures.
- [ ] T220-S1-4 GREEN: implement the minimal verified-history projection,
  quorum, chain comparison, coverage qualification, and exit-class model
  in a new general-history module without changing transaction behavior.
- [ ] T220-S1-5 Navigator verifies RED/GREEN, exact gate, scope, signed commit,
  and planted controls; ticket owner independently accepts and pushes. Notify
  the parent before committing any edit to `Deployment/KEL.hs`.

## Slice 2 — pinned keripy sampler and release closure

- [ ] T220-S2-1 Freeze and falsify the Slice 2 gate against a missing/broken
  sampler boundary and absent packaged runtime; remove the closure-owned
  libsodium loader path and observe the permanent sandbox assertion fail with
  the pysodium unable-to-find-libsodium error.
- [ ] T220-S2-2 RED: prove one private keripy process/database per witness,
  exact CESR capture, explicit acquisition failures, and terminal cleanup.
- [ ] T220-S2-3 RED: prove two witness samples remain independent until Haskell
  comparison and the pinned local witness boundary is genuinely exercised.
- [ ] T220-S2-4 GREEN: implement the versioned private sampler protocol and
  Haskell process adapter using the existing keripy 1.3.5 lock.
- [ ] T220-S2-5 GREEN: include the sampler/Python/CA closure in Nix and Linux
  artifacts, provide closure-owned libsodium through `LD_LIBRARY_PATH` and
  closure-owned binutils in strict `PATH`, and prove the packaged runtime's
  version path executes without checkout, Docker, ambient Python, ambient
  `kli`, or network. The permanent assertion must require `kli` to report
  keripy library version 1.3.5.
- [ ] T220-S2-6 Navigator and ticket owner verify cleanup, package provenance,
  exact gate, signed commit, full CI, and push.

## Slice 3 — authenticated bootstrap and command

- [ ] T220-S3-1 After the parent releases Slice 3 from the #216 dependency,
  freeze and falsify the Slice 3
  gate against the landed CLI/backend contract.
- [ ] T220-S3-2 RED: prove positional AID and opt-env-conf precedence, default
  chain bootstrap, explicit-only file fallback, and fail-closed catalog errors.
- [ ] T220-S3-3 RED: prove fixed-point witness discovery, endpoint enumeration
  limitation, and absence of N2C address scans or forbidden transaction paths.
- [ ] T220-S3-4 RED: invoke the production command through affirmative,
  negative, UNKNOWN, partial-coverage, and strict-coverage paths with exact
  exit statuses.
- [ ] T220-S3-5 GREEN: bind authenticated observations, sampler, Haskell
  judgment, rendering, and the minimal landed `ckeri verify` registration.
- [ ] T220-S3-6 Navigator and ticket owner verify caller reachability, no
  shared-contract drift, exact gate, signed commit, full CI, and push.

## Slice 4 — acceptance and docs

- [ ] T220-S4-1 Freeze and falsify the transcript/docs gate with removed-line,
  changed-exit, fake-zero, and missing-installed-artifact controls.
- [ ] T220-S4-2 RED: make the transcript checker require 3/3, 2/3, 1/3,
  strict-coverage, forged/truncated, planted-duplicity, stale/mismatch, chain,
  fallback, and installed-release evidence.
- [ ] T220-S4-3 GREEN: capture the raw `script(1)` live-preprod journey using
  deterministic fault proxies and the installed release; commit the raw
  transcript and checker.
- [ ] T220-S4-4 GREEN: ship the user docs page and MkDocs navigation covering
  source precedence, exit 0/1/2, quorum, coverage, and honest absence claims.
- [ ] T220-S4-5 Navigator and ticket owner verify the live boundary, instrument
  positive controls, exact gate, signed commit, docs, full CI, and push.

## Final audit

- [ ] T220-F1 Run the ignored ticket gate fresh at HEAD and tee it to
  `/code/tmp/e156/story-220-final.log`.
- [ ] T220-F2 Run commit-message/task finalization audit, verify every commit's
  GPG signature, and prove no forbidden path or tracked gate entered the PR.
- [ ] T220-F3 Verify draft-PR body answers: “A person can now run
  `ckeri verify <AID>` to fetch witnessed key history and compare it with
  Cardano without keys or a node.”
- [ ] T220-F4 Verify pushed HEAD, green CI, labels/assignee/issue linkage, mark
  ready, and hand off merge without merging.
