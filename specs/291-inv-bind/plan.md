# Plan

## Scope and topology

One TIER-1 `OWNER` slice closes the caller-offset authority class across the
deployed checkpoint family. A Grok commit owner produces the RED proof and
repair; each submission receives a fresh Codex or Claude audit. Maximum two
audited submissions; submission 2 is delta-scoped and final.

## Strategy

- Introduce one shared bytes-only establishment-event decoder in the on-chain
  checkpoint library and one Haskell parity mirror.
- Make the decoder own canonical JSON/CESR framing, variant selection, complete
  consumption, declared-size consistency, and protected raw field values.
- Route registration, Advance, enforcement, and hash-proof SAID blanking
  through decoded results before their existing semantic/authentication checks.
- Remove caller offsets from all four wire interfaces and propagate the new
  shapes through observers, validators, entitlement digests, generators,
  transaction builders, vectors, and wire goldens.
- Retain keripy-produced offset metadata only as an independent test oracle;
  production code cannot receive or consult it.

## RED fixture design

Every row is signed over its exact bytes with fixture-owned keys, asserts
rejection, and must be observed failing against the unfixed binders before any
production repair:

- **FX291-GRIND-DIP:** canonical keripy `dip`; its true `t` is `dip`, while a
  ground key/AID byte run contains chance `icp`. Legacy `off_t` points at the
  chance run and the remaining legacy spans are honest. Record grind seed,
  attempts (the known exemplar budget is 1,216), duration, raw bytes, true type
  span, forged span, datum, and valid signatures.
- **FX291-GRIND-DRT:** canonical `drt`/rotation-family event with a chance `rot`
  run outside `t`, proving the class is not registration-specific.
- **FX291-VERSION-SIZE:** valid signed content with a declared KERI JSON size
  different from the complete byte length.
- **FX291-TRAILING:** a valid signed event followed by one unparsed byte.
- **FX291-DUPLICATE:** a signed object with a duplicated protected field whose
  selected legacy slice names the favorable copy.
- **FX291-REORDERED:** a signed object with valid field spellings in a
  non-canonical order and recomputed legacy spans.
- **FX291-DELIMITER:** one signed framing delimiter is replaced while all
  protected value substrings remain available to legacy slices.
- **FX291-UNKNOWN:** a signed object carries an extra unknown top-level field
  and recomputed legacy spans.

The RED receipt names all eight rows and records eight intended legacy
acceptances; compile errors, missing tests, skips, or wrong-reason failures do
not count.

## Mutation campaign and stopping rule

The permanent harness derives framing positions independently from the keripy
oracle: braces, commas, colons, field-name bytes, quotes, array delimiters, and
the complete version/framing value. For each position and each supported shape,
it applies a deterministic different byte, proves the mutant differs at exactly
one position, invokes both decoders, and reports shapes, positions, mutants,
and accepts. Stop only when every enumerated framing position ran and accepted
count is zero. Payload-byte mutation outside that set is not claimed by this
gate. Discoveries outside INV-BIND enter the parent census.

## Live boundary

The local protocol-11 node receives exactly one malformed hash-proof mint
transaction using `FX291-GRIND-DIP`. The new bytes-only `HashProofRedeemer`
contains no spans; structural type rejection occurs before a proof token can
be created. The test records the transaction ID, rejection class, wall time,
funding input before/after, and zero checkpoint/proof-token outputs before and
after. It must not submit an honest hash-proof, Register, Advance, Freeze, or
Convict transaction.

## S291-1 — Total parse and remove caller offsets

Implementation horizon:

- `onchain/lib/cardano_keri/checkpoint/{event_decoder,registration,advance,enforcement}.ak`
- `onchain/validators/{hash_proof,checkpoint}.ak` and their focused tests/
  measurements
- `offchain/lib/Cardano/KERI/AID/Checkpoint/`
- affected generators, keripy fixture proof modules, wire goldens, and the
  local-node checkpoint harness
- `scripts/check-inv-bind-interface.sh` for the exact-shape interface census
- `justfile`, Cabal/flake registration only where required to run lasting proof

Forbidden: production/preprod/mainnet use, credentials, dependency upgrades,
unrelated validator behavior, and any positive live product-state deployment.

## Immutable gate contract

Runtime gate: `/tmp/ms-keri-1/e274/t291-owner/gates/inv-bind-v1.sh`.
Worktree mirror: ignored `/gate.sh`. The SHA-256 is frozen in owner STATUS.

- `red` mode captures both decoder suites rejecting their assertions against
  the unfixed implementation for all eight fixtures and requires the exact
  CAN-FAIL counts.
- `green` mode runs the source/interface census, focused Haskell and Aiken
  decoder proofs, all affected generated-vector drift checks, the bounded live
  rejection, and full `just ci`.
- Every realizing command first checks
  `df -B1 --output=avail /nix/store`. An invalid/missing store path or broken
  untouched recipe is a MACHINE EVENT: stop and report, never retry.

## Resource and evidence budget

- Event bytes: 1–1024 inclusive; live smoke timeout: 20 minutes.
- RED and GREEN logs live below the ticket runtime evidence directory.
- Full-scope submission 1; at most one auditor-authorized delta repair.
- No push, GitHub mutation, or live-network mutation is authorized.

## Output ceiling

This artifact is limited to 125 lines and 11 KiB.
