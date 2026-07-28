# Story 159: register a `kli` identity on preprod

## Outcome

A stranger can export an inception KEL with stock keripy 1.3.5 and pass that
stream directly to `ckeri register`. The command publishes the existing
two-transaction permissionless registration protocol through the immutable V1
reference scripts from `deploy/preprod/m1-manifest.json`. `ckeri status`
discovers the resulting checkpoint through a generic Koios asset lookup and
reports the authenticated V1 state.

`kli` remains the sole owner of key creation, inception, witness interaction,
receipt collection, and KEL export. `ckeri` neither opens a keripy keystore nor
performs a KERI operation.

## Supported journey

The acceptance journey covers both:

- an unwitnessed 1-of-1 transferable inception; and
- a witnessed 2-of-5 transferable inception using all three public preprod
  witnesses and `toad = 2`.

For each identity, `ckeri register`:

1. reads the first complete message from the binary-safe `--kel` path, including
   `/dev/fd/*` process-substitution paths;
2. extracts the exact compact JSON inception bytes using the embedded KERI
   version/size field;
3. decodes controller indexed signatures and witness indexed receipts from the
   CESR attachment group;
4. derives the frozen V1 datum, E1-E9 offsets, registration evidence, proof
   token name, and AID token name from those bytes;
5. validates that the parsed datum/evidence passes the already-merged pure
   registration predicate before spending funds;
6. mints the hash-proof token through the manifest reference, waits for its
   output, then burns it while minting the checkpoint token through the
   checkpoint and lifecycle references;
7. signs with the Cardano payment key named by `--payer`; and
8. prints both settled transaction IDs and the protected
   `2 + 1000 + 5 = 1007 tADA` escrow.

No KEL content is accepted from a narrated JSON projection. The parser consumes
the bytes emitted by `kli export`.

## CLI and configuration

Every setting uses `opt-env-conf` with option, environment, and YAML sources.
`Options.Applicative` and `optparse-applicative` are forbidden.

The new commands are:

```text
ckeri register --network preprod --kel KEL --payer PAYMENT_SKEY
ckeri status AID
```

Operational settings include the node socket, funding address, cardano-cli
path, deployment manifest, Koios URL/token, settlement timeout, and an
acceptance-only escrow override used to demonstrate the real underfunded
validator rejection. Defaults remain preprod-specific; network magic 1 is
checked before submission. `KOIOS_TOKEN` is optional and redacted, with
anonymous lookup when unset.

## Witness policy before board story 165

Story 165 owns `ckeri board list`, board records, and board-backed health
preflight. This story does not invent that surface.

When a KEL declares witnesses, board membership cannot yet be proved. Therefore
`register` refuses by default before spending funds and explains that public
watchability is unverified. `--allow-unlisted-witnesses` is an explicit
acknowledgement that permits public or private witnesses and prints the
watchability consequence. This is off-chain policy only; the on-chain
validators remain witness-board agnostic.

The documented 2-of-5 journey uses that acknowledgement. Once story 165 lands,
the default can become a real board-record check without changing the
registration protocol.

## Existing checkpoint preflight and protocol conflict

Before preminting, `register` performs exact-asset discovery. If a live
checkpoint for the AID already exists, it refuses by default and spends
nothing. An explicit repeat-registration override is not exposed in this
story.

This refusal is deliberately off-chain. The merged #114 protocol and
`specs/114-permissionless-registration/spec.md` require registration to remain
repeatable, including duplicate and post-conviction registration. Duplicate
ACTIVE outputs are a deposit-backed, fail-closed residual. Consequently the
issue-body phrase “already-registered AID rejects at the validator” is
incompatible with the ratified validator and cannot be truthfully captured by
an application-only PR. The PR must disclose this exact exception; it must not
claim or synthesize a validator failure.

The underfunded negative remains a real validator-boundary test. A transaction
whose ACTIVE output is one lovelace below the applied
`minADA + d_reg + freeze_bond` floor must fail during `cardano-cli transaction
build` script evaluation, and no invalid transaction is submitted.

## Status

`ckeri status AID`:

- accepts the 44-character E-code AID;
- derives the checkpoint asset name and queries exact unspent asset outputs;
- requires one unambiguous output at a known V1 role address;
- decodes the inline V1 datum and verifies that its AID matches the query;
- verifies the singleton checkpoint token and protected escrow floor; and
- prints role, checkpoint sequence, native KERI sequence, current threshold and
  key count, witness count/toad, and bond integrity.

Zero results print `NOT REGISTERED`. Multiple live matches fail closed as
ambiguous.

## Acceptance evidence

The PR body embeds a raw terminal transcript captured with `script(1)` and
`tee`. It contains literal `$` commands and their unedited outputs for the
full journey: clean keripy setup, witness OOBI resolution, both inceptions,
both KEL exports, both successful registrations, both status queries, the
already-registered preflight refusal, and the underfunded real validator
rejection. Settled preprod transaction IDs appear in command output.

The committed transcript is byte-compared with the PR body. A cheap CI check
also proves the opt-env-conf surface, real keripy export parser compatibility,
transcript shape, and forbidden-parser absence. Live preprod submission remains
the named operator acceptance boundary because it needs a funded payment key
and node socket.

## Done

- genuine keripy 1.3.5 exports parse for 1-of-1 and witnessed 2-of-5;
- both successful registrations settle on preprod and `status` reports ACTIVE;
- witnessed registration default-refuses until explicitly acknowledged;
- an already-live AID default-refuses before preminting;
- underfunded registration reaches and fails Plutus evaluation;
- docs teach the complete stranger journey and the repeatability caveat;
- raw transcript is committed and embedded byte-for-byte in PR #172;
- `./gate.sh` and all GitHub checks are green; and
- the PR is parked for operator merge.
