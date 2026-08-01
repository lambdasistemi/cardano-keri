# #188 — runnable follower and interactive local-store queries

## Outcome

A person can run `nix run ./offchain#ckeri-follower -- ...` against the
committed M1 preprod deployment and a node socket, watch the follower advance
in the background, and query the same local RocksDB store from an interactive
prompt.

The executable is the standalone artifact for epic #171. It is not a
subcommand of production `ckeri`; #177 will move the verbs onto that surface
and add backend selection.

## User stories

1. As an operator, I can cold-start from a committed real preprod chain point
   instead of replaying preprod from Origin.
2. As an operator, I can see processed slot, node tip, lag, upstream state,
   checkpoints, and decode rejects while the follower continues underneath
   the prompt.
3. As a consumer, I can ask for one checkpoint, all checkpoints and rejects,
   store/readiness status, and payer UTxOs without an HTTP index, third-party
   service, second node, or node query per verb.
4. As a reviewer, I can see executable proof that repeated verbs read the
   store again and therefore reflect apply, spend, and rollback changes.
5. As a newcomer, I can follow `docs/user/follower.md` verbatim and watch a
   recorded preprod session showing the real outcome.

## Functional requirements

### FR1 — standalone process and configuration

- Add an executable named `ckeri-follower`.
- Its settings combine the existing `IndexerConfig` opt-env-conf surface with
  a required deployment manifest path. Existing option and environment names
  stay canonical; no duplicate parser is introduced.
- The production lifetime is one bracketed process:
  `withRocksDBIndexer` owns the store, `withChainSyncFollower` runs as its
  existing async, and the Haskeline shell stays in the foreground on the same
  `IndexerHandle`. Link the follower async so an unexpected follower failure
  is not hidden.
- No HTTP server, Unix query socket, IPC protocol, `--backend`, hosted tier, or
  third-party tier is added.

### FR2 — interactive query surface

The prompt supports line editing, persistent-in-process history, verb-name
completion, `help`, and clean EOF/`quit` termination. It provides:

- `status`: upstream connection state, follower processed slot, observed tip,
  slot lag, and the store's persisted point;
- `list`: every currently live decoded checkpoint plus every current decode
  reject and its reason;
- `checkpoint <AID>`: the current checkpoint for one complete 44-character
  KERI E-code AID, or an explicit not-found result;
- `payer <ADDRESS>`: raw funding UTxOs for a configured payer address;
- `help` and `quit`.

Malformed verbs, AIDs, and addresses produce one concise error and return to
the prompt. The shell must not crash or silently reinterpret them.

The command parser/rendering boundary accepts a local query implementation as
an input so #177 can add selection without rewriting verbs. This ticket ships
only the local implementation over `IndexerHandle` and `FollowerHandle`; it
does not select among implementations.

### FR3 — live progress without stale derived state

- The terminal visibly reports processed slot, tip, lag/upstream state, live
  checkpoints, and decode rejects while waiting at the prompt.
- Every progress sample is recomputed from the readiness STM snapshot and the
  store. It may be periodic or event-driven, but it must not retain a cache,
  memo, `IORef`, warmed map, or previous query result.
- Output must coexist with Haskeline without corrupting the prompt.

### FR4 — no derived state outside the engine transaction

Every verb executes its local-store/readiness IO action on every invocation.
There is no cross-prompt result cache. Deterministic tests must demonstrate:

- the same `list` and `checkpoint` command before and after a real in-memory
  indexer apply/spend observes the new canonical contents;
- a store mutation between repeated status/payer reads is visible;
- a rollback-shaped store change removes an answer on the next invocation;
- each command dispatch invokes the supplied query action again, rather than
  re-rendering an earlier value.

The tests cross the production local-query seam; counter-only mocks are not
sufficient evidence by themselves.

### FR5 — committed preprod cold-start point

Commit `deploy/preprod/m1-follower-start.json` rather than changing
`m1-manifest.json`. The manifest is already a published v1 artifact; follower
bootstrap metadata is operational data and does not justify a schema bump.

The record uses schema `cardano-keri/m1-follower-start/v1` and binds:

- network `preprod`, magic `1`;
- slot `129566111`;
- block hash
  `52457d38ab799de201f67936cec9bbc86948adcc2a2685bf80b5690eb1377887`;
- earliest manifest reference transaction
  `5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c`
  (`hash-proof`);
- resolution method: the preprod Koios `tx_info` response for all five
  manifest reference transactions was compared by `absolute_slot`, and this
  transaction was earliest.

The intersection block itself is not replayed by chain sync; that is safe
because the deployment references precede the checkpoint lifecycle records
this follower indexes.

### FR6 — packaging and deterministic gates

- Cabal builds the executable with explicit dependencies and strict warnings.
- The existing flake exposes `packages.ckeri-follower` and
  `apps.ckeri-follower` on Linux and Darwin wherever its dependencies build.
- A real runCommand check invokes a focused CLI/query test app; a wrapper that
  is merely built is not a check.
- `just ci` stays deterministic and node-free and runs the focused proof.
- No dependency pin changes are permitted.

### FR7 — documentation and preprod cast

- `docs/user/follower.md` becomes executable documentation: prerequisites,
  exact build/run command and flags, prompt verbs, cold/warm boot semantics,
  store reuse/recovery, and shutdown.
- The documented command uses the committed manifest, start record, and live
  socket `/code/cardano-preprod/ipc/node.socket`.
- Record `docs/assets/video/follower-preprod.cast` on the live preprod node,
  at 80x24, using the demo-casts conventions. It shows the follower catch up,
  the shell remaining interactive, `status`, `list`, one `checkpoint`, payer
  UTxOs, and a repeat read from the same process. It contains real output only.
- The docs identify who ran the cast and the UTC recording date. The cast is
  embedded with matching width, and preview `site_url` remains overridable.
- The cast validates as JSONL, has `SHELL=/bin/bash`, has no `/nix/store`
  paths or raw exception markers, and has no output event longer than 400
  characters.

## Rejection behavior

- A missing/unreadable/invalid manifest or invalid configuration fails before
  opening the prompt with a concise non-zero error.
- A start slot without a hash (or vice versa) is rejected by the existing
  paired parser.
- Invalid AIDs and addresses are rejected without store access.
- A missing node does not make existing local-store query verbs perform a node
  round trip; readiness reports the disconnected upstream while the prompt and
  reads remain available under the reconnect supervisor.
- A follower async failure propagates and terminates the process instead of
  leaving a misleading live shell.

## Observable acceptance

- The exact focused #188 test target is proved RED on the base and GREEN after
  implementation.
- `./gate.sh` and the relevant flake checks pass from a clean final tree.
- The start record mechanically agrees with the earliest manifest reference
  transaction and the resolved values above.
- The real preprod dry-run and cast use the final production binary path, the
  committed start point, and the live node socket; they are usability evidence,
  not part of deterministic CI.
- One sentence answers the epic question: a person can now run
  `nix run ./offchain#ckeri-follower -- ...` to follow M1 preprod and query its
  local store interactively.

## Non-goals

- Production `ckeri` changes or `--backend` selection.
- HTTP/hosted/third-party implementations.
- Changes to rollback/resume machinery, dependency pins, or the retired fork
  drill.
- A live preprod requirement inside `just ci`.

