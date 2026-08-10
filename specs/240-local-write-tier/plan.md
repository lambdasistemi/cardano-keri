# Plan — #240 local-only write tier

Artifact ceiling: 8,000 bytes and 190 lines.

## Strategy

Create a provider-free write-composition Cabal component downstream of
`deployment`, `chain-query`, and `indexer`, but upstream of the existing
top-level CLI/read-provider composition. Move the write command module into
that component and replace every write-facing Koios setting/call with a
bracketed local store runtime. The read-only CLI remains free to depend on the
Koios component without granting that edge to write code.

Compose each build phase from #257 smart operations. Execute the whole program
once through the local interpreter, then pass only resolved ledger inputs into
the existing builders. Extend the local interpreter's unsupported reference
operation by deriving reference scripts from stored live outputs. Keep
settlement outside the free program and implement its asset/reference/tx-id
probes over the follower store.

## Technical context

- Language/tooling: GHC 9.12 Haskell, Cabal components, haskell.nix, just.
- Storage: existing RocksDB UTxO index and transaction runner; no schema or
  history enablement.
- Tests: Hspec/QuickCheck plus compiled migration, runner-count, boundary, and
  mutation checks.
- Per-submission gate: focused recipe then root `just ci-offchain`.
- Final gate: root `just ci`, with #259's `--no-write-lock-file` and unchanged
  lock assertion.
- Build budget: 12, accounted in the runtime campaign ledger.

## Constitution check

- Design precedes implementation through the six ticket artifacts.
- No onchain rule or protocol serialization changes; on/offchain vector parity
  is unaffected.
- RED precedes GREEN for provider boundary, parity migration, local reference
  derivation, and settlement behavior.
- Evidence stays under the ticket runtime root; no private material is
  committed.
- `docs/` is forbidden by the parent brief despite the general documentation
  principle; the ticket's public contract is its issue-linked spec and PR.

## Frozen state

- Base: `5bf84982f837c0f5bdd16fd244ae31b31224d147`.
- #257 exposes current checkpoint/live checkpoints, reference scripts, board
  catalog, payer UTxOs, and watermark; local execution already runs a whole
  program in one store transaction.
- The local reference operation currently fails `UnsupportedOperation`.
- Write composition currently lives beside read-provider composition and has a
  direct `chain-query-koios` dependency.
- Live write call sites remain for Koios checkpoint, board, payer, reference,
  and settlement reads. Historical write calls are absent; `queryAssetHistory`
  remains read-only.
- `offchain/flake.lock` is guarded by #259 and is mutation-forbidden here.

## Dependency direction

`deployment` remains the provider-neutral builder owner. `chain-query` remains
the provider-neutral algebra owner. `indexer` owns the store interpreter and
local temporal probes. A new write-composition component owns write settings,
store lifetime, program composition, and builder orchestration; it has no edge
to Koios or HTTP. The existing CLI component owns read-provider selection and
depends on the write component, never the reverse.

This component split, not a source convention, enforces
**INV-240-NOPROVIDER**. A focused external-client compile probe and Cabal
dependency census demonstrate the edge is unavailable.

## Parity establishment before migration

Use a clean detached worktree at the frozen base to generate a retained oracle
for every distinct transaction shape. The generator receives deterministic
Koios-shaped/current-state fixtures, protocol parameters, keys, and build
inputs and records normalized resolved inputs, canonical transaction-body
bytes, and transaction IDs. The candidate receives equivalent local-store
fixtures and must match those base artifacts exactly. The receipt binds base
SHA, candidate SHA, fixture blobs, outputs, and command. No candidate-side copy
of the migrated implementation may serve as the legacy oracle.

The first parity build establishes base artifacts; the second executes the
candidate comparison. Those are the two allocated parity builds.

## OWNER slice S240-1 — complete local write path

1. Freeze RED tests and the base parity oracle before production migration.
2. Establish the provider-free write component and local-only opt-env-conf
   settings, leaving read-only provider commands downstream.
3. Extend the local interpreter to derive exact reference outputs from the
   follower's live rows, with fail-closed cardinality and decode checks.
4. Add local temporal observers for assets, reference outputs, and transaction
   IDs, preserving existing timeout/match semantics.
5. Compose one local query program per build phase for registration,
   checkpoint consumers, Publisher, and endpoint-board transactions; remove
   every write-facing provider field/call and every mid-build query capability.
6. Exercise each write entry point and compare every transaction shape with
   the base oracle.
7. Mutate one write module toward the provider component, retain compiled RED,
   restore, and retain GREEN.
8. Run the focused gate and `ci-offchain`; after audit/acceptance and task
   stamping, run root `just ci` once before push.

The commit owner may use local proof/implementation commits but returns one
candidate for audit and one final squashed behavior commit after acceptance.

## Verification contract

- Initial gate RED: the frozen gate fails because the focused local-write-path
  recipe/contract is absent at the planning base.
- Five focused verification rows: Registration, AdvanceTransaction,
  current-checkpoint/CheckpointIndex consumers, EndpointBoard, and Publisher.
  Each row proves local source, atomic snapshot, no mid-build query, and its
  relevant concrete write commands.
- Parity: base oracle build plus candidate comparison build.
- Falsifiability: provider reintroduction compiled RED plus restored GREEN.
- Submission: focused recipe and `just ci-offchain`; no `onchain/` path is
  expected. If CKERI_BLUEPRINT/Aiken wiring changes, add `ci-onchain`.
- Final: root `just ci` via a quiet receipt, exact lock/tree checks, and root
  disk delta from the 53 GiB baseline.

Evaluation failure or cold-store timeout is `GATE-INCOMPLETE`, never success.

## Risks and controls

- Provider code remains in the executable: component direction prevents the
  write module from depending on it; compile a real forbidden client/import.
- A reference scan returns a plausible wrong row: validate script bytes against
  each requested hash and require exact cardinality/order.
- One program hides several runner invocations: retain #257 runner-count and
  concurrent-update instrumentation at each migrated program boundary.
- Builders are unchanged but inputs drift: normalized snapshot comparison and
  base-vs-candidate body/ID goldens cover both acquisition and output.
- Polling is mislabeled atomic: settlement retains a separate temporal type and
  never enters `ChainQueryF`.
- Build pressure exceeds budget: stop at 12 and escalate a re-cut; no thirteenth
  build.

## Project structure

Changed source stays under `offchain/query`, `offchain/indexer`,
`offchain/cli`, their focused test suites, `offchain/cardano-keri.cabal`,
`offchain/flake.nix`, and the root `justfile`. Planning is under this directory.

## Artifact measurements

| Artifact | Ceiling bytes / lines | Actual bytes / lines |
|---|---:|---:|
| `spec.md` | 8,000 / 180 | 7,803 / 148 |
| `plan.md` | 8,000 / 190 | 7,726 / 155 |
| `modules-model.md` | 6,000 / 150 | 5,081 / 103 |
| `data-model.md` | 6,000 / 150 | 4,411 / 112 |
| `functions-model.md` | 6,000 / 150 | 4,402 / 105 |
| `tasks.md` | 6,000 / 150 | 4,988 / 89 |
