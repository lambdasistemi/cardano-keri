# Spec — #257 one chain-query algebra

Artifact ceiling: 8,000 bytes and 180 lines.

## Outcome

Every write-path chain read is expressed as one provider-neutral query program.
The selected provider is one interpreter value for the whole program. Local
programs observe one RocksDB transaction, while the legacy Koios interpreter
reports that its sequential calls are non-atomic. Settlement remains a
separate temporal capability.

## User stories

- **US-257-01:** A write-command author can compose current checkpoint,
  reference-script, board-catalog, payer-UTxO, and watermark reads without
  selecting a provider or using `IO`.
- **US-257-02:** A local operator receives a snapshot whose rows and slot/hash
  watermark all came from one store transaction, even while blocks are being
  applied.
- **US-257-03:** A Koios operator can use the same program shape, while the
  consumer sees an explicit legacy sequential/non-atomic consistency claim.
- **US-257-04:** Registration consumes the algebra end to end and hands a
  resolved snapshot to its builder; it performs no chain query during a build.

## Functional requirements

- **RQ-257-01 — minimal algebra:** The operation functor contains exactly the
  currently required snapshot reads: current checkpoint/live checkpoint set,
  deployed reference scripts, authenticated board catalog, payer UTxOs, and
  store watermark. Each operation's Haddock names its current consumer.
- **RQ-257-02 — free programs:** Programs are provider-neutral and monad-free.
  No operation carries a URL, token, database handle, or provider callback.
- **RQ-257-03 — interpreter values:** Local and Koios are interpreter values
  selected once at composition. Adding Blockfrost requires another interpreter,
  not changes to programs or builders.
- **RQ-257-04 — local atomicity:** The local interpreter folds a whole program,
  including its slot/hash watermark, inside one existing store `Transaction`
  and invokes the transaction runner once.
- **RQ-257-05 — honest Koios semantics:** The Koios interpreter supports every
  operation Koios can answer and labels the resulting snapshot
  sequential/non-atomic where its consumer receives it. It never implies that
  several HTTP calls share a chain snapshot.
- **RQ-257-06 — temporal separation:** Settlement observation is a distinct
  capability. It is not a snapshot operation and cannot be composed into a
  local store transaction.
- **RQ-257-07 — resolved builders:** A transaction builder receives resolved
  snapshot values. It cannot import a concrete interpreter, receive
  `baseUrl`/token fields, or invoke a chain query while building.
- **RQ-257-08 — registration proof:** Production registration obtains its
  current-state inputs through one selected algebra interpreter and passes
  named resolved snapshots into the premint/register build boundary.
  Post-submit settlement polling uses only the separate temporal capability.
- **RQ-257-09 — historical inventory:** `queryScriptRedeemers` and
  `queryTransactionUtxos` have no current call sites; `queryAssetHistory` is
  used only by the #177 read backend. None becomes an algebra operation in this
  ticket. Issue #241 records that #181 overtook its write-path premise.
- **RQ-257-10 — mechanical boundary:** Cabal component direction prevents the
  builder component from depending on Koios, RocksDB, or an indexer
  interpreter. Source-search convention is supplementary, not the enforcement
  mechanism.
- **RQ-257-11 — focused gate:** A committed `query-algebra-check` recipe covers
  the focused contract and joins the immutable ticket gate before full
  root-level `just ci`.

## Invariants

- **INV-257-PROVIDER:** One program has exactly one interpreter; no operation
  falls through to or combines another provider.
- **INV-257-BUILDER:** Builder-owned Cabal components have no dependency edge
  to a concrete provider and no mid-build query capability.
- **INV-257-ATOMIC:** Every successful local result and its watermark are from
  one store transaction and one transaction-runner invocation.
- **INV-257-WATERMARK:** A watermark is the store slot and corresponding block
  hash that bound the returned rows; a cold store is represented explicitly.
- **INV-257-CONSISTENCY:** Snapshot metadata distinguishes atomic local
  observations from legacy sequential observations at the consumer boundary.
- **INV-257-SETTLEMENT:** Settlement observation can happen after submission
  and cannot appear in a snapshot program.
- **INV-257-HISTORY:** No ambient historical read is added unless a current
  write-path caller is identified; the verified inventory identifies none.

## Rejection behavior

- Unsupported operations fail as a named interpreter error; they do not select
  another provider or return a partial snapshot.
- A malformed or missing slot/hash watermark fails closed unless the store is
  explicitly cold.
- Board authentication, checkpoint uniqueness, reference resolution, and
  payer-output validation retain their existing closed-error behavior.
- Registration does not submit when its query program or snapshot validation
  fails.

## Observable acceptance

1. Algebra operations and both interpreters compile behind the declared Cabal
   direction, with registration using the common program surface.
2. Instrumentation proves a multi-read local program invokes the existing
   transaction runner once.
3. Concurrent block application cannot produce a result whose related rows
   and slot/hash watermark name different applied versions.
4. The atomicity property is observed failing under an intentional split-run
   mutation, then passes after restoration; the mutation is absent from the
   candidate.
5. Koios contract coverage observes explicit sequential consistency at the
   registration consumer and never claims local atomicity.
6. Cabal compilation and a focused guard reject a concrete-provider import or
   dependency from the builder component.
7. `query-algebra-check`, the immutable gate, and fresh root `just ci` pass on
   the accepted commit.

## Scope

Included: the common algebra and domain promotion required for it, local and
Koios interpreters, component ownership changes needed for a real dependency
boundary, registration as the proof write verb, deterministic coverage, and
focused gate wiring.

Excluded: indexer read-schema changes owned by #171, removing Koios from every
write verb owned by #240, implementing Blockfrost, documentation expansion,
live network submission, deployment, and merging the PR.
