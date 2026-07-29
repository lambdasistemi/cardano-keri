# Story 160: land a `kli` rotation on the preprod checkpoint

## Outcome

A controller rotates a witnessed 2-of-5 identifier with stock keripy 1.3.5,
collects the ordinary KERI event signatures and witness receipts, and advances
the already-registered V1 checkpoint through the immutable
`observer-advance` reference in `deploy/preprod/m1-manifest.json`.
`ckeri status` then reports sequence 1, the rotated current key set, and the
intact checkpoint value.

`kli` remains the owner of KERI key creation, rotation, receipt collection,
KEL export, and controller signing. `ckeri` consumes exported public artifacts,
constructs the Cardano-specific signing preimage and transaction, and never
opens a keripy keystore.

## Signing boundary

The deployed V1 validator deliberately does not accept the controller
signatures attached to the KERI `rot` event. Those signatures cover the exact
KERI event bytes. The advance validator instead reconstructs an
outref-bound, 18-field `AdvanceMessage` and verifies controller signatures over
its canonical-CBOR bytes with the rotation event's new current keys. Witness
receipts continue to cover the exact KERI event bytes.

Keripy 1.3.5 exposes `kli sign`, but its `@file` path opens text and UTF-8
re-encodes it. It cannot sign the binary canonical-CBOR preimage byte-for-byte.
Therefore a one-shot `ckeri advance --kel ...` cannot truthfully derive all
deployed-validator evidence from a KEL export alone.

The implementation parked for epic-owner review uses one `advance` verb with
two explicit modes:

1. `ckeri advance ... --signing-package DIR` discovers the current checkpoint,
   parses the rotation and receipts, and writes the exact binary preimage plus
   public package metadata without spending funds.
2. Controller-side keripy tooling signs that binary file with the rotated KERI
   keys and writes indexed CESR signatures. The helper is binary-safe and
   executes in the KLI environment; it does not expose seeds or move keystore
   ownership into `ckeri`.
3. `ckeri advance ... --controller-signatures FILE` reconstructs the package
   from live state and the KEL, verifies every supplied signature, builds the
   transaction, and settles it. A changed checkpoint outref invalidates the
   package and requires preparation again.

The CLI never silently substitutes KERI-event signatures for
`AdvanceMessage` signatures.

## KEL and state derivation

`ckeri advance` consumes the binary stream produced by `kli export`, including
`/dev/fd/*` process-substitution paths. It frames the inception and rotation
messages from their KERI version strings and attachment counters, and derives:

- the exact `rot` event bytes and offsets for `t`, `i`, `s`, `k`, `kt`, `n`,
  `nt`, `br`, `ba`, and `bt`;
- the event's current and next key sets and thresholds;
- the witness cut/add delta and the derived incoming witness set;
- incoming-set witness receipts indexed against that derived set; and
- the successor V1 datum with Cardano sequence incremented once and native
  sequence equal to the KERI rotation sequence.

The parser verifies the native KERI rotation signatures over `rot.raw` and
checks lineage, sequence, thresholds, prior next-key commitment, witness delta,
and receipt quorum before preparing the Cardano signing package. These native
signatures authenticate the KEL but are not placed in the validator's
`ctrl_sigs` field.

## Transaction

The submit mode discovers exactly one live ACTIVE checkpoint by its singleton
asset, decodes its V1 inline datum, and builds one Conway transaction:

- spend the named checkpoint through the manifest's `checkpoint-register`
  reference with the thin `Advance` redeemer;
- withdraw zero from the applied `observer-advance` stake credential through
  its manifest reference and carry the observer envelope/evidence;
- create exactly one ACTIVE successor at the same address with the same full
  value and singleton token, and the rotated inline V1 datum;
- mint or burn nothing;
- use a distinct plain payer UTxO and collateral UTxO for fees; and
- sign only the Cardano transaction with the configured payment key.

All hashes, addresses, reference outrefs, policy identifiers, network facts,
and frozen deployment parameters come from the committed manifest. The command
requires preprod/network magic 1.

## CLI and configuration

Every setting uses `opt-env-conf` with option, environment, and YAML sources.
`Options.Applicative` and `optparse-applicative` are forbidden.

The public journey is:

```text
ckeri advance --network preprod --aid AID --kel KEL \
  --signing-package PACKAGE_DIR
ckeri advance --network preprod --aid AID --kel KEL \
  --controller-signatures SIGNATURES --payer PAYMENT_SKEY
ckeri status AID
```

Operational settings include node socket, funding address, `cardano-cli` path,
deployment manifest, Koios URL/token, settlement timeout, package/signature
paths, and acceptance-only evidence omissions used to demonstrate real
validator rejection. `KOIOS_TOKEN` is optional and redacted, with anonymous
fallback.

## Validator-boundary negatives

The acceptance journey includes three real `cardano-cli transaction build`
script-evaluation failures. No rejected transaction is submitted:

- **under-signed:** one valid event-own `AdvanceMessage` signature is supplied
  where the rotated state requires 2-of-5;
- **under-witnessed:** one valid incoming-set receipt is supplied where
  `toad = 2`; and
- **stale replay:** after the valid rotation settles, the same rotation KEL and
  its old signing package are rebuilt against the now-current checkpoint,
  reaching the observer and failing the native-sequence/outref-bound advance
  predicate.

Acceptance-only omission switches are explicit, alarming, and never enabled by
default. Ordinary malformed or incomplete packages fail before funds are
spent.

## Acceptance evidence

The PR body embeds a raw terminal transcript captured with `script(1)` and
`tee`, byte-for-byte equal to a committed LF-only artifact. It contains literal
`$` commands and unedited output for the complete journey:

1. clean keripy setup and the three witness OOBI resolutions;
2. witnessed 2-of-5 inception, KEL export, `ckeri register`, and ACTIVE seq-0
   status;
3. `kli rotate`, receipt collection, and a fresh full KEL export;
4. binary signing-package creation and controller-side signatures;
5. under-signed and under-witnessed validator rejections;
6. valid advance settlement with its preprod txid;
7. ACTIVE seq-1 status showing the rotated 2-of-5 keys and intact bond; and
8. stale replay rejection at the validator boundary.

A cheap CI job verifies transcript structure, the settled register/advance
txids through Koios (using optional `KOIOS_TOKEN`), package hashes, option
surface, and forbidden-parser absence. The live funded submission itself
remains an operator acceptance boundary.

## Done

- a genuine stock keripy 1.3.5 witnessed 2-of-5 rotation parses and authenticates;
- the binary Cardano signing boundary is explicit and no key material enters
  `ckeri`;
- the thin checkpoint arm and `observer-advance` reference path settle on
  preprod;
- under-signed, under-witnessed, and stale packages fail during real Plutus
  evaluation;
- `status` reports ACTIVE seq 1, rotated keys, and intact bond;
- docs teach the full rotation/signing journey and its security boundary;
- the raw full-journey transcript is committed and embedded byte-for-byte;
- `./gate.sh` and all GitHub checks are green; and
- the PR is parked for operator review and merge.
