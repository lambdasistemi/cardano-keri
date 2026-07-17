# Plan: #106 — convict/freeze enforcement spend paths

Spec: `specs/106-enforcement/spec.md`. Five bisect-safe slices; one commit
each. The unifying method: **keripy is the oracle** — every predicate is
proven against fixtures the KERI reference implementation actually produced
(events, indexed controller signatures, witness receipts), not against our
reading of the spec. O1/O2 are resolved *empirically* in Slice 1 and the
answers propagate as committed fixtures.

## Tech stack

- **Fixture generation**: python + keripy in a nix-run environment
  (`nix shell` python3 + pip-installed keripy pinned by version + hash, or
  keripy vendored via nixpkgs python packages if available — Slice 1 decides
  and records the pin). Deterministic via fixed salts. Generator script
  committed; fixtures committed; a drift check (regenerate + git diff) added
  to gate.sh.
- **Haskell**: `Cardano.KERI.AID.Checkpoint.Enforcement` (pure predicate
  layer, mirrors the #68 schema-support style) + `EnforcementSpec` (hspec,
  consuming the keripy fixtures + verifying real Ed25519 signatures with
  cardano-crypto-class).
- **Aiken**: `cardano_keri/checkpoint/enforcement.ak` + tests; fixtures
  imported through the existing vector generator (extended).
- **Measurement**: spike-88 style `--plain-numbers` cells appended to the
  #109 matrix file.

## Slices

### Slice 1 — keripy oracle harness + O1/O2 resolution (T106-S1)

`specs/106-enforcement/fixtures/` + `gen_fixtures.py` (committed, nix-runnable,
fixed salts). Produces a JSON bundle per scenario:

- `honest/`: icp → rot for a 2-key AID and a 7-key reserve-shaped AID
  (3-of-7 reveal), each event with its indexed controller signatures and
  (for the witnessed AID) witness receipts.
- `fork/`: the SAME identity state rotated two conflicting ways (two
  keystores seeded with the same salt, diverged at the same sn — the
  double-sign artifact pair).
- `lag/`: a witnessed rotation strictly ahead of a recorded checkpoint state.
- `manifest.json`: for every signature, WHAT BYTES it covers (SAID vs
  serialization), verified inside the generator by re-checking each
  signature with raw pynacl Ed25519 against both candidate byte strings and
  recording which verifies. **This closes O1 with evidence.** Threshold
  spellings recorded verbatim per event (**O2 evidence**).

RED: a failing hspec that loads the manifest and asserts the harness's own
signature re-verification (proves fixtures are self-consistent before any
implementation exists). GREEN: generator + fixtures committed, drift check in
gate.sh.

Note (from Slice 2, Q-001): the shipped `parsePrimitive` gained `D`-code
(transferable verkey) decode in the `fix(cesr)` commit under T106-S2. Slice 3's
convict predicate relies on it (decode the event's `k` to raw, compare to the
datum's raw `cur_keys`). `qb64Aid` is an E-code *encoder* (forward), unaffected.

### Slice 2 — Haskell predicates (T106-S2)

`EventEvidence`, `convictPredicate`, `freezePredicate` per spec, with
`qb64Aid` added beside `qb64Verkey` in CESR.hs. RED: EnforcementSpec cases
loading Slice-1 fixtures — honest rotation does NOT convict (F3), the fork
pair DOES convict, the lag bundle freezes, signature verification uses the
O1-pinned bytes. GREEN: implementation. Includes F1–F7, F10 negatives derived
by mutating fixtures in the spec (not in the fixture files).

### Slice 3 — Aiken mirror + vectors + verdict parity (T106-S3)

`enforcement.ak` mirroring Slice 2 (verdict types per the #68 convention),
`qb64_aid` helper, vector-generator extension emitting the fixture-derived
byte constants, aiken tests asserting byte + verdict parity incl. the
fork/lag scenarios. Gate: full `aiken check` + drift check.

### Slice 4 — lifecycle vectors F8–F13 + output-shape predicates (T106-S4)

Tombstone datum type (`TombstoneV1`), output-shape checks (Convict 5 /
Freeze 4 as pure predicates over abstracted continuing-output descriptions),
remaining negatives (F8, F9, F11, F12, F13) in both languages.

### Slice 5 — measurement cells + gate finalization (T106-S5)

Extend the #109 matrix: SAID recomputation + per-signature Ed25519 + slice
checks in full proof context at the 2-key and 7-key fixture sizes; assert the
≥ 25% headroom target from the spec; record O3/O4 as #24 parameters in the
spec's open-questions section (updated in place). Gate extended with the
measurement invocation.

## Slice ordering rationale

1 before 2/3 because the signing-target answer (O1) is an input to every
signature check. 2 before 3 mirrors the #68 pattern (Haskell is the vector
source). 4 after 3 so output-shape predicates land on settled types. 5 last
because it measures the finished shapes.
