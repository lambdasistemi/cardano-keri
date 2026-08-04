# Plan — #181 no `cardano-cli` in the transaction path

## Architecture

The existing `deployment` library cannot import `indexer`: the indexer already
uses deployment codecs and manifests. The implementation therefore separates
transaction mechanics from production composition.

`deployment` owns an indexer-neutral transaction capability and the operation
builders. The capability receives raw UTxOs and pinned node operations; it does
not know how the follower is stored. The higher `cli` library introduced by
#177 depends on both `deployment` and `indexer`, opens the store with its
transaction runner, scans all payer addresses in one engine transaction, and
constructs the N2C provider/submitter. This is the only layer that wires real
lifetimes.

```text
ckeri CLI composition (#177 seam)
  ├─ one follower + RunTransaction
  │    └─ plural payer scan -> [(TxIn, TxOut)]
  └─ one N2C node-client lifetime
       ├─ queryProtocolParamsH
       ├─ evaluateTxH
       └─ Submitter.submitTx
             │
             v
deployment TransactionRuntime
  ├─ operation-specific ledger body
  ├─ Cardano.Tx selection/balance/witness helpers
  ├─ signing + pure tx id
  └─ settlement observer
```

The already merged query service exposes the store's rank-n
`RunTransaction` and a transaction-level address scan. Reuse and centralize
that primitive for payer reads; do not call `IndexerHandle.snapshotAt` once per
address and do not copy its cursor implementation again. If the pinned API
cannot expose the needed scan without increasing the existing private-copy
surface, stop and file an upstream capability question rather than forking the
package or changing dependency pins in this ticket.

## Slice 1 — coherent input/runtime seam

PAIR implementation. Add focused tests first for a plural raw-UTxO producer
executed in one engine transaction and for an indexer-neutral transaction
runtime whose evaluation/submission/observation calls are ordered and
fail-closed. Reuse the query transaction scan and expose the minimum payer read
needed by the CLI composition. Add shared deployment-side transaction error and
runtime types plus pinned in-process helpers for protocol parameters,
evaluation, signing, pure tx id, and local submission.

Expected surface:

- `offchain/indexer/Cardano/KERI/Indexer/Reads.hs` and/or the existing query
  transaction module, without a second scan implementation;
- a shared module under `offchain/deployment/Cardano/KERI/Deployment/`;
- focused indexer/deployment tests and Cabal exposure/dependencies;
- a `just transaction-path-check` focused recipe.

The immutable gate requires focused RED/GREEN tests, a one-runner-call proof,
call-order/error negative controls, formatting, and a dependency-pin fence.
The slice is behaviorally additive: existing commands still use their old
runner until later slices, so the commit remains bisect-safe.

## Slice 2A — shared build/sign kernel

PAIR implementation. Extend the accepted indexer-neutral runtime with the
operation-neutral `Cardano.Tx.Build`, balance, input selection, collateral,
signing, pure transaction-id, submission, and typed failure machinery needed
by every operation. Focused tests distinguish empty, insufficient, and
collateral-deficient snapshots and exercise evaluation, key, submission, and
restricted-`PATH` failures. Publisher and Registration remain on their old
paths in this bisect-safe additive commit.

The focused recipe takes an exact matcher, exits non-zero when it selects zero
examples, and is tested by the frozen gate with both an impossible sentinel
and every required proof name.

## Slice 2B — deploy / Publisher migration

PAIR implementation. Convert `Publisher` end to end to the accepted shared
runtime without waiting for Registration. Preserve reference output/script,
fee/change, collateral, signing, pure transaction id, local submission, exact-id
settlement matching, and timeout behavior. A Publisher-only subprocess guard
and restricted-`PATH` suite are independently reachable while Registration
still uses the old path.

## Slice 2C — register migration and fail-closed old CLI

PAIR implementation. Convert `Registration` to the accepted shared runtime,
preserving premint/register datum, mint, reference inputs/scripts, lifecycle
withdrawal, fee/change, collateral, signing, transaction id, submission,
settlement, and actionable error detail. Then retire only deploy/register
`cardano-cli` fields and make those old CLI commands fail closed before funding,
build, sign, submit, or success pending Slice 4's #177 composition. The final
sub-gate cumulatively rejects subprocess paths in both operations and proves
the combined restricted-`PATH` suite selects and runs its named examples.

## Slice 3 — advance, close, and endpoint-board migration

PAIR implementation. Apply the same runtime to `AdvanceTransaction`,
`CloseTransaction`, and `EndpointBoardTransaction`. Preserve advance/rotate,
close/burn, and board post/update/retire semantics. Tests cover reference
inputs/scripts, redeemers, collateral, mint/burn, update/retire ownership, and
all fail-closed signals.

The immutable gate covers all five transaction modules, deliberately injects
a subprocess call into an isolated guard fixture to prove the guard red, and
then passes the restored tree. No transaction DSL migration from #183 is
included.

## Slice 4 — #177 composition, CLI retirement, and live proof

This slice starts only after the epic owner supplies an integration base that
contains #177's accepted CLI-library seam. Rewire the production `ckeri`
commands to one follower/store transaction runner plus one N2C provider and
submitter. Remove every transaction command's `cardano-cli` option and the
runtime closure dependency. Add the exact `transaction-path-no-cardano-cli-live`
operator journey, deterministic wrapper checks, docs, and mechanically
generated register/rotate/close/advance/deploy/board transcripts.

The live helper must prove `command -v cardano-cli` is non-zero in its restricted
environment before invoking the packaged production binary. A positive-control
fixture reintroduces a shellout and must fail. The real-node run then proves
settlement and an underfunded non-zero error. This slice does not start or stop
the node, follower service, or infrastructure.

## Ordering with #177

Slices 1–3 own transaction modules that #177 does not edit. Both tickets touch
the Cabal file and old CLI parser/tests, so those shared surfaces are deferred
or reconciled only on an epic-owner-provided integration base. This ticket does
not merge, rebase over, or edit the sibling worktree. Slice 4 records the exact
#177 commit it consumes.

## Verification

Per-slice deterministic gates:

- `just transaction-path-check`;
- the ticket-owner-frozen slice gate and accumulated `./gate.sh`;
- focused deployment/indexer tests with deliberate signal mutations;
- source, executable-closure, and dependency-pin guards.

Final verification:

- fresh `just ci` and `./gate.sh` at the accepted head;
- packaged `ckeri` help/config contains no transaction `cardano-cli` option;
- no-CLI guard positive control fails and restored production passes;
- `just transaction-path-no-cardano-cli-live` against the real node;
- transcript regeneration is clean and its UTC/network/node/tx-id/settlement
  provenance matches preserved raw runtime evidence.

Timeouts are recorded as no verdict. `/`, `/code`, and `/run` free space is
measured before and after each expensive gate, with the ticket brief's stop
thresholds. Processes are identified by executable and `/proc/<pid>/exe`, never
by command-line substring.

## Risks and controls

- **Split UTxO snapshot:** one rank-n transaction scans all payer addresses;
  test runner invocation count and address permutation/duplicate behavior.
- **Cabal dependency cycle:** deployment owns an injected capability; the #177
  CLI layer alone imports both deployment and indexer.
- **Transaction-body drift:** operation tests freeze ledger semantics, not old
  `cardano-cli` argument strings.
- **Reported/submitted id mismatch:** derive once from the signed transaction
  and assert submitted bytes and observed id agree.
- **Hidden subprocess survives:** source and packaged-closure gates plus an
  executable positive control.
- **Upstream private API copy:** reuse the existing transaction scan; escalate
  a missing capability instead of copying or changing a pin.
- **Sibling conflict:** keep shared CLI/Cabal reconciliation behind the #177
  integration boundary controlled by the epic owner.
