# Specification: unattended checkpoint relayer

## Outcome

`ckeri relayer run` continuously advances every registered KERI checkpoint it
can safely serve. It discovers witnessed KEL endpoints from authenticated
chain state, fetches and verifies the immediate next rotation, constructs and
submits the existing permissionless advance transaction in-process, waits for
settlement, and emits a stable result containing the settled transaction id.

## User contract

- Command: `ckeri relayer run`.
- Primary discovery: authenticated endpoint-board records joined to live
  checkpoint datums in one follower snapshot.
- Optional `--oobi-list FILE`: operator-trusted fallback only when a coherent,
  authenticated board catalog has no matching witness for that checkpoint.
- Default poll interval: 5 seconds; witness request timeout: 15 seconds;
  settlement timeout: 600 seconds; witness body limit: 8 MiB.
- With a ready follower, responsive witness, valid immediate rotation, and
  sufficient funds, the documented completion bound is 620 seconds.
- One process serves all live registered AIDs. It advances at most one event
  per AID per cycle, then reacquires chain state.
- No relayer-owned durable cursor or cache exists; restart and rollback truth
  comes only from the follower's current snapshot.

Stable success lines:

`relayer result=advanced aid=<aid> old_seq=<n> new_seq=<n> txid=<hex>`

`relayer result=already-current aid=<aid> old_seq=<n> new_seq=<n> txid=<hex>`

Static fallback use also emits `discovery=static-fallback`.

## Safety invariants

- **INV-162-AUTH — BLOCKING:** reject forged, unauthenticated, mismatched, or
  oversized board/KEL material before transaction construction.
- **INV-162-ATOMIC — BLOCKING:** the final endpoint identity, predecessor
  checkpoint, exact output, reference scripts, and payer inputs used for a
  submission come from one current engine transaction and pass readiness.
- **INV-162-PERMISSIONLESS — BLOCKING:** use KEL-native controller signatures;
  never request an external controller witness or Cardano-domain signature.
- **INV-162-IDEMPOTENT — BLOCKING:** restart and races cannot create a duplicate
  logical transition. A loser succeeds only if chain state is later than the
  candidate, or is the same sequence with exactly the same candidate datum.
- **INV-162-NOCACHE — BLOCKING:** no relayer state survives rollback/restart.
- **INV-162-HOTPATH — BLOCKING:** no `cardano-cli`, Koios, or static witness JSON
  is used as the normal hot path.
- **INV-162-LIVENESS — ADVISORY:** document and prove the 620-second bound under
  its explicit prerequisites.
- **INV-162-OPERABILITY — ADVISORY:** exact command, logs, fallback, restart,
  race, and failure behavior are documented and exercised.

## Authentication and intake

The relayer calls a selected witness at
`GET /query?typ=kel&pre=<percent-encoded-aid>&sn=<old-sequence+1>` using the
board scheme and URL. It accepts HTTP 200 `application/json+cesr`, refuses
redirects and credential headers, bounds bytes and time, and parses exactly
the immediate next `rot` event against the active checkpoint.

Verification binds the AID, sequence, prior next-key commitments, signing
threshold, witness set/delta, receipt threshold, and event SAID. The checkpoint
datum does not contain the prior event SAID; continuity beyond the first event
is therefore established by the committed next keys plus exact sequence and
valid signatures/receipts, and documentation must not claim otherwise.

Fallback is fail-closed: it may fill a missing matching board entry only after
the board query and authentication succeeded. It cannot bypass unreadiness,
board corruption, query failure, endpoint conflict, or an invalid KEL.

## Race classification

After any submission, settlement, or competing-input failure, reacquire chain
state. Report `already-current` only when the current sequence is greater than
the candidate, or the sequence is equal and the current datum exactly equals
the candidate. Equal sequence with a different datum is a conflict, never a
success. The logged transaction id is the actual current checkpoint output's
transaction id, including a competing winner.

## Finite acceptance

Acceptance is exactly A1–A6 in `acceptance-map.md`: unattended live advance,
restart, race, rollback/current-snapshot safety, authentication rejection, and
user documentation. No unlisted transcript or deployment mutation is needed.

## Ownership and exclusions

Owned: `offchain/**`, `docs/user/**`, `mkdocs.yml`; `deploy/preprod/**` only for
agreed machine-captured evidence; `scripts/**` only for a focused checker.

Excluded: `onchain/**`, deployed validators, #163/#164/#166, persistent relayer
storage, `optparse-applicative`, and standalone `ckeri verify`. Ticket #220 is
parked and is not a predecessor or owned surface. Ticket #162 owns only the
minimal witnessed-KEL fetch/intake needed by the relayer.
