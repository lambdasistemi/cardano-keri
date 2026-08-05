# Plan — #220 hear a rotation (`ckeri verify`)

## Architectural shape

Keep acquisition, judgment, and presentation separate:

```text
authenticated chain observation
  ├─ checkpoint for AID
  └─ complete board catalog
            │
            ▼
per-witness keripy sampler processes
  └─ exact CESR KEL/receipt captures + acquisition failures
            │
            ▼
Haskell verifier and reconciler
  ├─ verified histories and establishment projections
  ├─ currency quorum
  ├─ cross-witness duplicity
  └─ checkpoint comparison
            │
            ▼
stable rendering + exit 0 / 1 / 2
```

The Haskell side owns a typed observation boundary. Acquisition supplies a
map keyed by board witness key; every successful value contains exact bytes,
not a boolean "valid" assertion. Judgment returns one of affirmative,
negative, or cannot-answer plus structured coverage and findings. Rendering
is total over that result.

The private sampler protocol is versioned. Haskell creates one private output
directory per witness, writes one request naming the target AID, witness
identifier, authenticated OOBI URL, and deadline, then launches the packaged
sampler. The sampler writes a versioned JSON acquisition record and a binary
CESR capture inside that directory. Haskell validates identity/path ownership,
reads the bytes itself, and performs all domain verification. A process is not
reused between witnesses.

The production wrapper binds the sampler by an absolute Nix-store path. Tests
inject a deterministic sampler at the Haskell process-adapter boundary; there
is no user-facing option that can silently replace the verifier's acquisition
implementation.

## Stable source use

- Board authenticity: `Cardano.KERI.Indexer.Board.indexedBoardCatalog` and
  `Cardano.KERI.Deployment.EndpointBoard`.
- Local checkpoint/catalog reads: `Cardano.KERI.Indexer.Reads` and the landed
  transactional query surface, without modifying `offchain/indexer/`.
- General KEL history proof belongs in a new read-only module. Reuse stable
  primitives from `Cardano.KERI.Deployment.KEL` without changing
  register/advance/close behavior. Notify the parent before a pair commits any
  edit to `offchain/deployment/Cardano/KERI/Deployment/KEL.hs`; if general
  history verification cannot remain separate from transaction semantics,
  stop and file a parent question.
- Pinned witness implementation: keripy 1.3.5 from the existing committed
  `offchain/test/keri-fixtures` lock; promote/reuse the pin rather than creating
  an independently drifting dependency.
- Treat `ckeri-follower`, `Cardano.KERI.Indexer.Shell`, and
  `Cardano.KERI.Deployment.CheckpointIndex` as absent.

The exact #216 CLI registration and backend binding remain deferred. After the
parent's release note, inspect only the landed contract and update this plan's
binding paragraph before creating the first implementation gate. Any needed
shared `QueryBackend` record change is a parent question, not an implicit
extension.

## Pre-slice probe — pinned release closure (complete)

Before any implementation dispatch, a bounded scratch-only probe against the
archived #216 head proved that a Nix-built `ckeri` package can carry and invoke
the existing pinned keripy 1.3.5 runtime without ambient Python, ambient `kli`,
network access, or checkout access. The wrapper needs the closure-owned
libsodium directory in `LD_LIBRARY_PATH` and `binutils` in its strict runtime
`PATH`, because Nix Python disables the host `ldconfig` lookup and pysodium's
`ctypes.util.find_library` falls back to `ld`.

The final isolated bubblewrap invocation used a cleared environment, mounted
only `/nix/store` plus ephemeral `/proc`, `/dev`, and `/tmp`, and unshared the
network namespace. It reported keripy and KLI library version 1.3.5 and exited
0. The package build exited 0, and the repository's full
`nix develop --quiet -c just ci` contract (with scratch path-input rebinding)
also exited 0. Evidence is in:

- `/code/tmp/e156/story-220-closure-probe-build-final.log`;
- `/code/tmp/e156/story-220-closure-probe-invoke-final.log`;
- `/code/tmp/e156/story-220-closure-probe-just-ci.log`.

This resolves closure feasibility only. Slice 2 still owns production-quality
sampler isolation, protocol design, Nix wiring, extracted-artifact proof, and
live-boundary tests. The disposable probe changes do not belong in the
production branch; the same sandboxed assertion and its libsodium-path
negative control do belong permanently in Slice 2's repository gate.

## Slice 1 — verified-history and verdict core

Purpose: make every domain outcome executable without HTTP, subprocess, CLI,
or release packaging.

PAIR owns the read-only verifier/reconciler modules and focused tests. RED
first defines:

- complete multi-event lineage, including interaction events and more than one
  rotation;
- forged, truncated, wrong-AID, bad-prior, bad-sequence, bad-next-key,
  under-signed, bad-witness-delta, and below-receipt-threshold rejection;
- `3/3`, `2/3`, `1/3`, and strict-coverage outcome matrix;
- exact checkpoint match, stale ancestor, absent checkpoint, and mismatch;
- planted valid duplicity finding plus full/partial absence rendering.

The navigator's PROVE-LIST must state what makes each check fail and must prove
the 2/3 boundary would fail under an accidental unanimity mutation. GREEN adds
the minimum typed history/verdict implementation. Existing transaction-facing
KEL APIs remain behaviorally unchanged.

Focused gate: the new verifier/verdict suite, a seeded unanimity mutation or
equivalent negative control, planted duplicity positive control, forged and
truncated negatives, formatting, and `nix develop --quiet -c just ci`.

Proposed commit: `feat(verify): judge witnessed key histories`

## Slice 2 — pinned keripy sampler and release closure

Purpose: cross the real witness-protocol boundary without contaminating
Haskell judgment or merging witness observations.

PAIR owns the Python sampler/helper, its hermetic fixtures, Haskell process
adapter, Nix/lock wiring, Cabal data/component declarations, and packaging
tests. RED first proves:

- one isolated sampler process/state directory per witness;
- genuine pinned-keripy OOBI/query/replay acquisition against a local witness
  boundary;
- exact CESR bytes survive the private protocol;
- unreachable, timeout, malformed response, wrong witness, and non-zero helper
  outcomes remain acquisition failures;
- two witness responses are not merged before Haskell comparison;
- the packaged `ckeri` closure contains keripy 1.3.5 and its runtime probe
  invokes the version path without an ambient `kli`, Python, Docker, checkout,
  or network;
- the release-closure assertion runs under `--unshare-net --clearenv`, checks
  that the closure-owned `kli` reports library version 1.3.5, and goes red
  when the wrapper's closure-owned libsodium loader path is removed.

The helper may generate a private ephemeral protocol identity, but accepts no
user keys and persists no state. Tests verify cleanup after success, failure,
and timeout. The package reuses the existing keripy lock and must not bump
unrelated flake inputs.

Focused gate: sampler protocol tests, local live-boundary smoke using pinned
keripy, process cleanup control, package-closure inspection, the permanent
sandboxed `--unshare-net --clearenv` version assertion, the demonstrated
missing-libsodium-path negative control, extracted-artifact smoke, formatting,
and full CI.

Proposed commit: `feat(verify): sample witnesses with pinned keripy`

## Slice 3 — authenticated bootstrap and `ckeri verify`

Purpose: connect the pure verdict and sampler to Cardano and expose the command.

This slice begins only after the parent releases #216's merged CLI contract.
PAIR owns the new verify command modules, tests, and the minimum landed CLI
registration/config changes. It consumes indexer reads and does not edit
`offchain/indexer/`.

RED first proves:

- positional AID and every new setting use `opt-env-conf` option/env/YAML
  precedence;
- chain is the default bootstrap and fails closed;
- explicit file bootstrap accepts the existing `witnesses.json` shape and is
  never selected implicitly;
- local/Koios board enumeration is authenticated; hosted endpoint enumeration
  reports unsupported rather than an empty catalog;
- changed witness sets expand independent sampling to a fixed point;
- the production command reaches exit 0, 1, and 2 through its real caller;
- partial coverage qualifies absence, while `--require-full-coverage` converts
  the same observation to UNKNOWN;
- no N2C address-scan, transaction builder, or forbidden module is reached.

The command renders structured verdict data only after judgment. It does not
re-parse stdout to decide its exit code.

Focused gate: production CLI tests with deterministic acquisition/chain
boundaries, option/env/YAML precedence, exit-status triad, caller reachability
for UNKNOWN, forbidden-path scans, packaged command help/smoke, formatting,
and full CI.

Proposed commit: `feat(ckeri): verify witnessed key state`

## Slice 4 — live controls, transcript, and user documentation

Purpose: prove the installed product across the live seams and teach the exact
contract.

PAIR owns the raw acceptance capture, transcript checker, deterministic fault
proxy/harness, `docs/user/` page, and `mkdocs.yml` navigation. No transaction
or production deployment state is changed.

RED first makes the transcript checker reject captures missing each of:

- 3/3 affirmative full coverage;
- 2/3 affirmative currency with qualified duplicity absence;
- 1/3 UNKNOWN;
- 2/3 strict-coverage UNKNOWN;
- forged/truncated rejection;
- planted duplicity detection;
- a genuine exit-1 stale/mismatch result;
- explicit chain bootstrap and explicit-only file fallback;
- installed-release identity and sampler version evidence.

The harness uses mechanically identified loopback fault proxies so failures
are caused and repeatable, while successful legs forward to the public preprod
witnesses. Capture runs under `script(1)` and preserves real commands, output,
exit statuses, AID, board policy, endpoints, package version, and sampler
version. The checker uses a positive control proving it recognizes a planted
duplicity before accepting `duplicity none`.

Docs explain command usage, source precedence, the 0/1/2 contract, quorum
versus full coverage, qualified absence, and operational interpretation. The
page does not imply that hosted `GET /board` enumeration exists.

Focused gate: transcript checker self-tests (including removed-line and
mutated-exit negatives), docs build/link check, installed-artifact full journey,
formatting, and full CI.

Proposed commit: `docs(verify): prove the live witness journey`

## Gate and execution rules

- The completed closure probe precedes Slice 1 and is not a slice or pair.
- All four implementation slices are PAIR with fresh, model-diverse contexts.
  The driver runs
  `claude --dangerously-skip-permissions --model sonnet` at medium effort; the
  navigator runs
  `claude --dangerously-skip-permissions --model claude-opus-5 --effort high`.
  No pair may seat identical models.
- Before each dispatch, freeze one immutable runtime slice gate and a snapshot
  of the ignored ticket `./gate.sh`, record their hashes/base/fence/budgets,
  and prove the exact slice gate RED for the intended reason.
- The test added during RED is frozen and observed failing before production
  implementation; the same test is present in the eventual signed slice
  commit and flips GREEN for the reviewed reason.
- No worker pushes. The driver creates a GPG-signed local commit only after
  navigator GREEN approval. A signing hang is a parent question; unsigned
  bypass is forbidden.
- Every gate is tee'd with pipefail-safe status to
  `/code/tmp/e156/story-220-<slice>-<phase>.log`.
- Before every push, run `TMPDIR=/code/tmp/e156 nix develop --quiet -c just ci`
  fresh and record exit 0. A timeout is recorded and rerun, never called a
  verdict.
- The ticket owner independently checks the full diff, path fence, RED/GREEN
  evidence, gate, commit signature/message, and navigator SHA before stamping
  tasks and pushing.

## Partial-release handshake

NOTE-004 releases bootstrap and Slice 1 only from exact `origin/main`
`c9c1f96697875f3b0c8824f66ab331b002c52655`; it supersedes A-001 only for
those actions. Bootstrap has therefore established
`/code/cardano-keri-220-verify` on `feat/220-hear-rotation`, passed full CI, and
repeated the sandboxed `--unshare-net --clearenv` keripy-1.3.5 assertion. The
paired negative control removed the closure-owned libsodium loader path and
failed with the expected unable-to-find-libsodium error.

The remaining released sequence is:

1. copy these planning artifacts into `specs/220-hear-rotation/` and create the
   ignored ticket gate;
2. GPG-sign the planning commit, run fresh full CI, push, and open the draft
   PR;
3. freeze/falsify Slice 1 and dispatch the fresh model-diverse pair.

Slices 2 and 3 remain parked pending an explicit parent release after #216.
The deferred CLI-binding paragraph must not be implemented or inferred during
Slice 1. Slice 4 remains downstream of the parked implementation slices.
