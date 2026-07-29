# Implementation plan: endpoint board

## Technical context

- On-chain: Aiken / Plutus V3 combined minting and spending validator.
- Off-chain: Haskell GHC 9.12, Cardano ledger types, `cardano-cli`, Koios.
- Configuration: `opt-env-conf` only, following the existing `ckeri` and
  `/code/amaru-treasury-tx` patterns.
- Tests: Aiken unit scenarios, Hspec/QuickCheck, command golden checks, raw
  acceptance checker, full `just ci`.
- Boundary: preprod node socket for mutations; Koios for independently settled
  catalog/status reads.

## Frozen wire shapes

`BoardDatumV1` is constructor 0 with four fields:

1. raw 32-byte witness key;
2. exact serialized KERI `/loc/scheme` reply bytes;
3. raw 64-byte Ed25519 signature over field 2;
4. 28-byte Cardano payment verification-key hash.

`BoardAction` has two constructors:

- `Update` (constructor 0);
- `Retire refundAddress` (constructor 1).

The mint branch distinguishes a positive post from a negative retire by the
complete own-policy mint map. The same script hash supplies the policy id and
payment credential of the marker address.

## External-boundary question

The unit suite cannot prove that Koios returns the exact inline datum/value
shape used on preprod or that `cardano-cli` builds transactions accepted by
the live validator. The final raw capture therefore runs the actual packaged
binary against the preprod node and independently settles every tx through
Koios after the final behavior-changing commit.

## Slice 1 — validator and settled contract seam

RED first: Aiken tests for honest post/update/retire and all amount,
address, owner, binding, signature, recreation, burn, and refund negatives.

GREEN: add the combined validator and minimal reusable board types. Extend the
Haskell script loader to derive the exact script artifact and produce its
preprod address. Rebuild the blueprint, freeze the script hash/address, add a
drift check, then publish the mandatory STATUS release line pointing at the
frozen `datum-schema.md` at this commit.

## Slice 2 — signed KERI record and catalog

RED first: genuine pool OOBI records plus forged, malformed, crossed-key,
invalid-signature, invalid-route, and duplicate fixtures. Add Koios
address-UTxO decoding tests that prove invalid markers fail the whole read.

GREEN: implement binary-safe extraction and verification of the signed KERI
`/loc/scheme` reply, board manifest codec, address query, catalog resolution,
and rendering. Q-001 controls the stale-record rule.

## Slice 3 — status and register preflight

RED first: status grades 0/0, 0/N, partial, complete, and duplicate board
records; register refuses missing witnesses and accepts the explicit
override.

GREEN: wire the verified catalog into `status` and `register`, replacing the
story-#159 placeholder warning while preserving its opt-env-conf override.

## Slice 4 — mutation transactions and CLI

RED first: argument-vector and runner tests for deploy, post, update, and
retire; prove required signatory, reference-script, exact datum/value,
spend/recreate, `-1` burn, complete refund, and preprod-only checks.

GREEN: add the board command group, settings, script deployment/manifest
writing, transaction plans, file materialization, submission, and settlement.
Every setting has CLI/env/YAML sources through `opt-env-conf`.

## Slice 5 — docs, raw live proof, and standing CI

Add the user page and navigation, capture/check scripts, board drift and
acceptance recipes, and CI tripwire. After all behavior changes are committed,
build the packaged binary and capture one real two-seat user journey: the
witness-operator machine posts, then a clean stranger machine follows only the
public docs to install the client, list and verify the record, and dial the
live witness. Continue that same raw `script(1)`/`tee` capture through the
complete update/retire/restore lifecycle, verify tx settlement independently,
commit the raw transcript and final manifest, embed the exact capture in the
PR body, run the full exported-TMPDIR gate, and wait for green GitHub CI.

## Merge and release discipline

One reviewed, bisect-safe commit per slice with `Tasks:` trailers. Log
`COMMIT`, `PUSHED`, `GATE-PASS`, and `GATE-FAIL` in lane STATUS at event time.
Never merge; mark ready and park for desk authorization.
