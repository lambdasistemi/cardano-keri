# Spec — #240 local-only write tier

Artifact ceiling: 8,000 bytes and 180 lines.

## Outcome

Every transaction-producing `ckeri` command builds, submits, and observes its
transaction with no Koios or other third-party provider reachable from the
write path. Current-state reads come from the local follower store through
#257's query algebra; node access remains limited to protocol queries,
evaluation, signing support, and submission.

## User stories

### US-240-01 — write without a third party (P1)

An operator can deploy scripts, register, advance, close, and post, update, or
retire endpoint-board entries using a node socket and the local follower store,
without configuring or contacting Koios.

Independent test: each write entry point succeeds against deterministic local
store/node capabilities while a forbidden-provider trap remains unreachable.

### US-240-02 — coherent transaction inputs (P1)

An operator receives a transaction built from one atomic local snapshot for
each build phase, rather than values acquired by independent calls while the
store changes.

Independent test: runner-count and concurrent-update instrumentation show one
store transaction per snapshot and no query after the builder starts.

### US-240-03 — behavior-preserving migration (P1)

An operator gets the same transaction as before the provider migration when
the legacy and local paths observe identical ledger inputs.

Independent test: base-revision and candidate executions over the same frozen
fixtures produce identical canonical transaction bodies and transaction IDs.

## Requirements

- **RQ-240-01 — complete write inventory:** Cover `deploy`, `register`,
  `advance`, `close`, and endpoint-board `deploy`, `post`, `update`, and
  `retire`, including their preflight, build-input, and settlement reads.
- **RQ-240-02 — no provider reachability:** A write-owned component has no
  dependency on Koios, HTTP provider packages, provider settings, or a callback
  capable of reaching them. The boundary must fail compilation if reintroduced.
- **RQ-240-03 — local interpreter:** Every migrated current-state read is an
  operation in #257's existing provider-neutral algebra and is interpreted by
  the local store interpreter selected once for the whole program.
- **RQ-240-04 — one snapshot:** All local reads needed by one transaction build
  phase are composed before building and execute in one store transaction with
  one watermark. A builder receives resolved values and cannot query.
- **RQ-240-05 — derived references:** The local reference-script operation
  derives complete reference outputs from live outputs already held by the
  follower. It performs no provider or node lookup, returns exactly one current
  output per requested hash, and fails closed on absence, duplication, decode,
  or hash mismatch.
- **RQ-240-06 — local settlement:** Post-submit polling observes the follower's
  own live tracking. Asset, reference-script, and transaction-id observers keep
  the existing match and timeout behavior and do not become snapshot operations.
- **RQ-240-07 — local configuration:** Write commands use opt-env-conf local
  store settings and expose no Koios URL or token setting. Provider settings
  may remain on read-only commands.
- **RQ-240-08 — read-only compatibility:** Existing Koios read backends,
  `manifest verify`, and board listing may remain downstream of the write
  boundary; this ticket does not implement or remove the future third-party
  tier.
- **RQ-240-09 — parity oracle:** Before candidate migration, the frozen base
  `5bf8498` generates canonical outputs from fixed resolved-input fixtures.
  Candidate checks consume the same fixture identities and compare normalized
  snapshots plus canonical transaction bodies/IDs. Both revision and fixture
  hashes are retained.
- **RQ-240-10 — falsifiability:** A controlled mutation that adds provider
  reachability to a write verb makes the permanent boundary check RED; the
  restored candidate makes the same check GREEN.
- **RQ-240-11 — focused gate:** A durable focused recipe executes all local
  write-path proofs, emits non-zero coverage counts, and joins `ci-offchain`.
  Full root `just ci` runs once before push.

## Invariants

- **INV-240-NOPROVIDER (BLOCKING):** no write verb can reach Koios or any
  third-party provider; component direction enforces this.
- **INV-240-LOCALTIER (BLOCKING):** every migrated write read resolves through
  #257's local interpreter.
- **INV-240-SNAPSHOT (BLOCKING):** each build phase consumes one atomic
  snapshot and performs no mid-build query.
- **DATA-INV-240-01 (BLOCKING):** Publisher's reference-script read is derived
  from follower-held outputs and never fetched from a provider.
- **INV-240-PARITY (BLOCKING):** each migrated transaction shape is identical
  to pre-migration behavior on identical inputs.
- **INV-240-FALSIFIABLE (BLOCKING):** a provider-call reintroduction is caught
  in a retained RED/restored-GREEN mutation proof.
- **INV-240-SWEEP (ADVISORY):** all remaining third-party reachability is
  reported and classified as write-reachable or read-only.

## Rejection and edge behavior

- A missing, cold, unreadable, or identity-mismatched local store fails closed
  and names the local source; it never falls back to a provider.
- Missing or ambiguous checkpoint, board, payer, or reference rows reject the
  phase before build/submission under the existing domain rules.
- A store change between transactions requires a new snapshot; settlement is a
  separate temporal loop and makes no atomicity claim across polls.
- A zero-second settlement timeout still performs the real first observation
  where the pre-migration observer did so.
- Read-only Koios code is not evidence of write reachability, but sharing its
  dependency with the write-owned component is forbidden.

## Observable acceptance

1. The write-owned Cabal component compiles without any provider component or
   HTTP dependency; a real forbidden import/dependency mutation fails.
2. All write settings and help/config surfaces contain the local store path and
   no Koios URL/token fields.
3. Registration, current-checkpoint consumers, endpoint-board transactions,
   Publisher, payer selection, references, and settlement execute through the
   local tier, with non-zero focused coverage for every write entry point.
4. Instrumentation proves one local store transaction per build snapshot and
   proves no query occurs after the builder boundary begins.
5. The reference operation derives and validates exact current reference
   outputs from follower-held rows and is observed failing for absent,
   duplicate, malformed, and hash-mismatched rows.
6. Base-vs-candidate parity receipts cover every distinct transaction shape and
   show identical canonical transaction bodies and IDs.
7. The provider-reintroduction mutation is RED, restoration is GREEN, the
   focused gate and `ci-offchain` pass, then fresh root `just ci` passes without
   changing `offchain/flake.lock`.

## Scope

Included: offchain local query interpretation, follower-store derived reads,
write CLI composition/settings, component boundaries, settlement observation,
tests, focused gate wiring, and the parity/mutation proofs.

Excluded: onchain files, `docs/`, follower schema/history changes, read-command
provider removal, Blockfrost or a third-party tier, live network deployment,
and merging the PR.

## Assumptions

- #181 removed the historical write-path calls and #241 is closed overtaken.
- #257 and #259 are present at base `5bf8498` and remain the governing query
  and immutable-lock contracts.
- The follower store contains the configured funding, checkpoint, board, and
  published reference outputs needed by the selected write command.
