# Feature specification: the endpoint board

Issue: [#165](https://github.com/lambdasistemi/cardano-keri/issues/165)
Parent: [producer applications epic #156](https://github.com/lambdasistemi/cardano-keri/issues/156)

## Priority user story

As a Cardano/KERI watcher, I can discover the current public endpoints for
witnesses from the chain alone, verify every endpoint under the witness's own
KERI key, and compare a checkpoint's declared witness set with that public
catalog.

This story proves the board itself. Hunter chain-bootstrap acceptance belongs
to #163 and relayer chain-bootstrap acceptance belongs to #162, as the issue's
reordering note states.

## Vertical E2E user story

As a witness operator, I publish my genuine KERI OOBI record on preprod with
`ckeri board post`. A stranger on another machine, with no private handoff,
static witness file, repository-local fixture, or operator explanation, follows
only the public user documentation. They install `ckeri`, run
`ckeri board list`, obtain and cryptographically verify my current record from
the chain, then dial the listed HTTPS endpoint and receive a real successful
response from my witness.

This is a binding acceptance journey, not a mocked integration scenario. The
S5 raw capture must visibly distinguish the operator and stranger seats,
identify their different machines, show the literal commands and outputs at
both seats, and preserve the board post txid, verified list result, and live
witness response. The same vertical-E2E-user-story requirement applies to
every later application story in this milestone.

## Ratified ledger shape

- A single, well-known Plutus V3 script is both the marker minting policy and
  the marker spending address.
- Each record is one unspent UTxO carrying exactly one marker token.
- The asset name is exactly the raw 32-byte Ed25519 key decoded from the
  witness's non-transferable `B...` identifier.
- The inline datum contains the witness key, the exact KERI `/loc/scheme`
  reply bytes, its decoded Ed25519 signature, and the posting Cardano payment
  verification-key hash.
- Posting mints exactly one marker and succeeds only when the Ed25519
  signature verifies over the posted KERI reply bytes.
- Updating spends one board UTxO and recreates exactly one board UTxO with the
  same marker and deposit. The replacement record must have a valid signature
  under the marker key. No marker is minted or burned.
- Retiring spends one board UTxO, burns exactly one matching marker, requires
  the recorded Cardano owner, and refunds the complete board deposit to the
  requested target. Fees come from a separate funding input.
- The Cardano owner is required as an extra signatory on update and retire.
  Readers parse the owner but never use it for witness selection.
- The policy does not enforce global uniqueness. Every valid unspent
  duplicate remains visible until its owner burns it.
- The policy authenticates bytes and lifecycle shape; semantic KERI endpoint
  validation remains fail-closed in readers.

## User-visible commands

All settings use `opt-env-conf` and therefore have option, environment, and
YAML configuration sources. `optparse-applicative` is forbidden.

- `ckeri board deploy` publishes the board script as a preprod reference and
  writes the reproducible board manifest.
- `ckeri board post --endpoint-record FILE` verifies a witness-signed KERI
  endpoint record, mints its marker, and posts the inline datum.
- `ckeri board list` enumerates every valid current board UTxO, including
  visible duplicates, with witness AID, URL, out-ref, and deposit.
- `ckeri board update --endpoint-record FILE` spends and recreates the
  selected witness marker with a newly verified record.
- `ckeri board retire` spends and burns the selected marker and prints the
  complete refund.
- `ckeri status` adds `watchable M/N`, where `N` is the checkpoint's declared
  witness count and `M` is the number whose raw keys have at least one valid
  board record.
- `ckeri register` replaces the story-#159 placeholder preflight: witnessed
  registration refuses by default when any declared witness is absent from
  the board and retains the explicit reduced-watchability override.

## Functional requirements

### FR-001 — deterministic marker identity

The same compiled script bytes must deterministically yield the committed
preprod policy id and marker address. CI rebuilds them and rejects drift.
The instant this hash settles, STATUS publishes the registered release note
for the e171 indexer lane.

### FR-002 — authentic post

The minting validator must reject wrong-length asset names, quantities other
than one, extra entries under its policy, missing/duplicate marker outputs,
wrong addresses, malformed datums, asset/key mismatches, and invalid Ed25519
signatures.

### FR-003 — protected update

The spending validator must reject a missing owner signatory, changed marker
key, missing/duplicate continuing output, changed deposit, marker mint/burn,
or forged replacement record.

### FR-004 — protected retire and exact refund

The spending and minting branches must jointly require the recorded owner,
the exact `-1` burn, and one token-free output to the requested address
containing the complete board deposit.

### FR-005 — fail-closed catalog

`board list` accepts only UTxOs at the committed marker address whose policy,
quantity, 32-byte asset/key binding, datum shape, KERI endpoint fields, and
Ed25519 signature all verify. It never silently drops an invalid marker:
invalid board state makes the command fail with the out-ref and reason.

There is no TTL or clock input. A spent predecessor is stale; current is
exactly the unspent set. Valid unspent duplicates remain visible at distinct
out-refs.

### FR-006 — watchability

Status counts declared witness keys against the verified current catalog.
Zero declared witnesses renders `watchable 0/0`. Duplicates do not increase
the numerator.

### FR-007 — preprod proof

After the last behavior-changing commit:

1. deploy/verify the fixed board script on preprod;
2. from the witness-operator seat, post all three pool witness records and cite
   settled txids;
3. from a stranger seat on another machine, using only the public docs and a
   clean client installation, list and cryptographically verify the live
   catalog, then dial a listed witness and capture its real successful HTTPS
   response;
4. show a checkpoint status with its watchability grade;
5. capture forged and stale read failures;
6. update one record and cite the settled replacement txid;
7. retire one record, show its complete deposit refund, and cite the txid;
8. repost that witness so all three pool records are live at handoff.

The proof is one literal-dollar-command `script(1)`/`tee` capture, never
retyped, with explicit operator-seat and stranger-seat machine facts. Nothing
in the vertical path is mocked. The raw full journey is embedded verbatim in
the PR body and checked mechanically in CI where feasible.

## Non-functional requirements

- Only preprod network magic 1 is accepted by M1 board mutation commands.
- Koios bearer authorization uses optional `KOIOS_TOKEN`; anonymous reads
  remain supported.
- Secrets, signing keys, and bearer tokens never appear in diagnostics,
  transcripts, manifests, or committed artifacts.
- Every devnet, e2e, and gate run exports `TMPDIR=/code/tmp/e156`.
- All new Haskell exports have Haddock and all new modules have module docs.
- The docs page “Discovery — the endpoint board” ships in this PR.

## Deliverables

- Aiken board validator and negative/positive tests.
- Frozen follower-facing datum schema at `datum-schema.md`.
- Haskell record codec/verifier, board manifest, index reader, transaction
  runner, and `ckeri board` command family.
- Registration preflight and status watchability integration.
- Committed preprod board manifest and raw acceptance capture with settled
  transaction facts.
- CI checks for script/manifest drift, CLI opt-env-conf surface, and transcript
  consistency.
- `docs/user/discovery-endpoint-board.md` plus MkDocs navigation.

## Success criteria

- The full local gate exits zero at the PR head.
- GitHub CI is green.
- The captured live journey is dated after the last code change and all cited
  transactions are independently settled.
- The committed policy id/address equal the release line consumed by e171.
- The PR remains unmerged and parked for desk authorization.
