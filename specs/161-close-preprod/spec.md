# Story 161: close a checkpoint and reclaim its escrow

## Outcome

A controller starts from a fresh KLI identity, registers its V1 checkpoint on
Cardano preprod, authorizes Close with the identity's current KERI keys, and
settles a transaction that burns the singleton checkpoint token and refunds
the checkpoint's complete lovelace value to a chosen Cardano address.

For the default M1 registration value, the refund is exactly 1,007 tADA:
2 tADA checkpoint minimum, 1,000 tADA registration bond (`D_reg`), and 5 tADA
freeze bond (`B`). If a valid checkpoint holds more lovelace, Close refunds
that complete value rather than truncating it to the minimum.

After settlement, `ckeri status AID` reports that no checkpoint is registered
and cites the exact transaction proven by chain history to have executed the
deployed `CloseBurn` mint redeemer and `Close` spend redeemer.

## Controller and signing boundary

The deployed validator reconstructs a binary, canonical-CBOR `CloseMessage`
from trusted chain state:

- preprod's frozen network discriminator;
- checkpoint policy and AID-derived asset name;
- the exact ACTIVE input transaction id and output index;
- the AID and current native/Cardano sequence numbers;
- the complete refund address; and
- the old checkpoint's current controller threshold and keys.

The KERI keys sign those exact bytes. Native signatures already present in a
KLI KEL authenticate KERI events, not the Cardano outref-bound Close message,
so they are never substituted.

As with Story #160's ratified Advance boundary, keripy 1.3.5's public
`kli sign --text @file` path cannot byte-exactly sign arbitrary binary CBOR.
Close therefore has prepare and submit modes under one `ckeri close` verb:

1. `--signing-package DIR` discovers the exact ACTIVE checkpoint, validates
   the KLI export's AID, and writes `close-message.cbor` plus public metadata.
2. `scripts/kli-sign-close.py` runs beside the controller's KLI keystore,
   checks the package schema/AID/hash, and signs the binary bytes with KLI's
   current verifiers without exporting private keys.
3. `--controller-signatures FILE` re-discovers and reconstructs the package,
   verifies the indexed CESR signatures against the live current keys, and
   submits Close.

Any changed input outref or refund address changes the preimage and invalidates
the signatures.

## KLI export

`--kel` accepts the binary stream produced by `kli export`, including a
`/dev/fd/*` process-substitution path. Close authenticates the stream's
inception framing, self-addressing identifier, controller signatures, and
public key state, and requires its AID to equal `--aid` and the live
checkpoint AID.

The live checkpoint remains the authoritative current key state. A KLI
habitat that has rotated beyond or behind it cannot create a locally accepted
Close package because its current-key signatures fail against the checkpoint
datum.

`ckeri` never reads a KLI keystore, passcode, or private key.

## Transaction

Submit mode builds one Conway transaction through the immutable
`checkpoint-register` reference in
`deploy/preprod/m1-manifest.json`:

- consume exactly the named ACTIVE checkpoint with spend constructor
  `Close { evidence }`;
- burn exactly one AID checkpoint token under mint constructor
  `CloseBurn { checkpoint_ref }`;
- create exactly one datum-free output at `--to` containing the complete
  checkpoint lovelace value and no checkpoint token;
- create no successor checkpoint;
- use distinct, plain payer and collateral inputs for fees;
- route fee-input change to a change address distinct from the refund target;
  and
- sign the Cardano transaction only with the configured payment key.

The plan refuses non-preprod manifests, malformed or checkpoint-script refund
addresses, incomplete/foreign checkpoint assets, ambiguous ACTIVE outputs,
same refund/change addresses, invalid signatures, and non-positive timeouts
before submission.

All deployment hashes, parameters, addresses, and reference outrefs come from
the committed manifest. No on-chain script changes or redeployment belong to
this story.

## Status after closure

An empty live `asset_utxos` result alone means only "not currently
registered"; it does not prove Close. To render the closed transaction id,
`status` additionally:

1. reads the AID asset's ordered Koios mint/burn history;
2. requires the latest asset event to burn exactly one token;
3. reads the deployed checkpoint script's redeemer history; and
4. requires the same transaction to contain both the mint-purpose
   constructor-1 `CloseBurn` and spend-purpose constructor-0 `Close`.

Only then does it render:

```text
state NOT REGISTERED (closed at TXID) aid AID
```

If no live checkpoint and no provable Close pair exist, status preserves the
generic `state NOT REGISTERED aid AID` result. A conviction burn must never be
misreported as a controller Close.

## Non-controller validator negative

The raw acceptance journey creates a second, unrelated KLI identity and uses
its current key to sign the genuine controller's exact Close package. An
explicit `--validator-test-non-controller` switch permits that structurally
valid but unauthorized signature to reach `cardano-cli transaction build`.

The deployed checkpoint Plutus V3 validator must reject it during script
evaluation. The rejected transaction is never submitted. Without this
acceptance-only switch, the same signature set is refused locally by the
shared Close predicate.

## CLI and configuration

Every `ckeri close` setting uses `opt-env-conf` and supports command-line,
environment, and YAML sources:

- network and network magic;
- AID, KEL path, refund target, signing package, and controller signatures;
- payer key, node socket, funding and change addresses, and `cardano-cli`;
- manifest, Koios URL and optional `KOIOS_TOKEN`, and settlement timeout; and
- the acceptance-only non-controller switch.

`Options.Applicative` and `optparse-applicative` are forbidden. Optional Koios
authentication has anonymous fallback and secret values are never printed.

## Acceptance evidence

The PR body embeds a raw `script(1)` plus `tee` transcript byte-for-byte equal
to a committed LF-only artifact. It contains literal `$` commands and their
unedited output for the complete vertical journey:

1. create and export a fresh controller KLI identity;
2. prove initial NOT REGISTERED status;
3. register it and cite the settled premint/register transaction ids;
4. prove ACTIVE seq-0 state and the intact 1,007-tADA escrow;
5. prepare the exact Close package;
6. create an unrelated KLI identity, sign the package, and capture its real
   validator rejection;
7. sign with the controller, settle Close, and cite its transaction id and
   1,007-tADA target refund; and
8. prove `status` reports NOT REGISTERED with that Close transaction id.

A cheap CI job validates transcript ordering and package hashes, re-queries
all settled transaction ids and the exact refund through public Koios with
optional `KOIOS_TOKEN`, and compares the live `ckeri status` output.

## Done

- a fresh stock KLI identity registers and closes on preprod;
- the current controller threshold authorizes the exact Close preimage;
- the deployed reference script burns the token and refunds the full escrow;
- an unrelated KLI controller fails at the real validator boundary;
- status proves and reports the exact Close transaction;
- `docs/user/close.md` teaches the executable journey and security boundary;
- the raw full-journey transcript is committed and embedded byte-for-byte;
- `./gate.sh` and every required GitHub check are green; and
- the ready PR is parked for milestone-desk audit and merge.
