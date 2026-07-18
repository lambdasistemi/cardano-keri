# Plan: registration path — icp admission and checkpoint genesis (#114)

Six pair-executed slices, one bisect-safe commit each, ordered so every
commit builds and the gate passes at HEAD. The orchestrator owns this file,
spec.md, tasks.md, gate.sh, and PR metadata; every behavior-changing edit is
driver+navigator work.

## Tech stack / conventions

- **Offchain:** Haskell library `offchain/lib/Cardano/KERI/AID/**`, Hspec
  suites under `offchain/test/`, fixture loading via
  `test/Cardano/KERI/AID/Checkpoint/FixtureLoader.hs`. Gate:
  `nix build --quiet .#checks.x86_64-linux.unit-tests` (or `just unit`).
- **Onchain:** Aiken under `onchain/lib/cardano_keri/` (pure predicates) and
  `onchain/validators/` (validators). Diagnostics need a TTY:
  `script -qec 'aiken check' /dev/null`. Pinned toolchain
  `github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken`.
- **Fixtures:** hermetic keripy flake `offchain/test/keri-fixtures/`
  (`run.sh` / `nix run .#gen`, `FIXTURES_OUT`); regeneration byte-stable;
  existing bundles byte-unchanged; extend `gen_fixtures.py` only.
- **Vector parity:** one Haskell generator executable (pattern:
  `gen-enforcement-vectors`) emits canonical vectors + Aiken literals from a
  single computation; a drift check asserts `git diff --exit-code`.
- **Aggregate gate:** `just ci` at the repo root; per-PR `./gate.sh`
  (authored by the orchestrator after the spec checkpoint).
- Reuse, never re-derive: `validate_inception`, `inception_datum`,
  `deriveAidAssetName`, `qb64_verkey`, `qb64_aid`, F18 `datum_well_formed`,
  `evaluate`, `blake3.verify`, the #99 `mpfCage` validator idioms
  (single-`Pair` mint check, `tokenFromValue`, address checks).

## Module map (new / touched)

| Path | Slice | Content |
|---|---|---|
| `offchain/test/keri-fixtures/gen_fixtures.py` | S1 | registration family + signer-seed export + per-field offsets |
| `offchain/test/keri-fixtures/fixtures/registration.json` | S1 | committed bundle (new file; existing bundles untouched) |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Registration.hs` | S2 | `RegistrationEvidence`, slice checks E1–E9 (incl. kt/nt/bt re-spelling + `B`-code qb64), `registrationPredicate` (R3–R8 pure parts), proof-token name derivation |
| `offchain/test/Cardano/KERI/AID/Checkpoint/RegistrationSpec.hs` | S2 | fixture-driven positive/negative suites |
| `offchain/app/…` (`gen-registration-vectors`) | S3 | shared vector generator (cabal executable) |
| `onchain/lib/cardano_keri/checkpoint/registration.ak` (+`_tests`, `_vectors`) | S3 | Aiken mirror + parity suites |
| `onchain/validators/hash_proof.ak` (+ tests) | S4 | H1–H4 minting policy |
| `onchain/lib/cardano_keri/checkpoint/registration_measurements.ak` | S4/S5 | measurement cells |
| `onchain/validators/checkpoint.ak` (+ tests) | S5 | combined validator scaffold: `Register` mint branch (R1–R10), fail-closed spend |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Registration.hs` (extension) | S5 | tx-level output/mint shape predicate mirror for parity |
| `specs/114-registration/MEASUREMENTS.md` | S6 | reported cells + budget verdict |

## Slices

### S1 — keripy registration fixture family

Extend the hermetic generator with the `registration` family per spec
(`reg_witnessed` 3-wit/toad-2, `reg_weighted`, `reg_dip`, `reg_drt`,
`reg_oversize`, signer-seed export, generator-emitted per-field offsets for
`t/i/s/k/kt/n/nt/b/bt`). RED: a Haskell loader spec asserting the new family
shape + offset ground truth (slices at the exported offsets reproduce the
expected qb64/re-spelling bytes) fails against the old bundle. GREEN:
regenerate; commit generator + new bundle together; drift check proves
byte-stable regeneration and untouched existing bundles.

### S2 — Haskell registration predicate

`Registration.hs`: qb64 `B`-code helper, canonical kt/nt/bt re-spelling
(exact keripy JSON token bytes), E1–E9 slice checks, proof-token name
`blake2b_256(bytes ‖ aid)`, and the pure registration predicate (R3/R4/R6/R7
+ R8 arithmetic) over `RegistrationEvidence` + a deployment context. Typed
error enum mirroring the house `Either Error ()` style. RED first against
S1 fixtures: honest positives (2-key reuse, witnessed, weighted), squat,
dip/drt, per-slice negatives, misdirected offsets, wrong-preimage
signatures.

### S3 — Aiken mirror + shared-vector parity

`registration.ak` mirroring S2 exactly (same error constructors, same
verdict semantics). `gen-registration-vectors` emits both the canonical
vector set and Aiken literals from one computation; Aiken suites assert
byte-identity of encodings AND verdict identity per vector (parity =
serialization + behavior). Wire the drift check beside the existing
generators. The offset-misdirection family (A-001 QB condition 1: wrong
offsets, overlapping spans, spans into `a`/other fields, code-prefix
confusion, truncated slices) must be executable in BOTH languages within
S2+S3 — S3 is not acceptable without it.

### S4 — hash-proof minting policy

`hash_proof.ak`: H1–H4 over the vendored lane-packed blake3. Tests: honest
mints for the fixture inceptions (300 B-class, 966 B-class, boundary),
oversize/wrong-AID/multi-name/extra-quantity rejections, burn branch.
Haskell side only re-exports the name derivation (already in S2) — no new
mirror. Measurement cells for the three sizes.

### S5a — true 2-key/7-key registration shapes (interposed; Q-003 option B)

The S1 bundle's frozen legacy families (`honest_2key`/`honest_7key`) carry
no seeds/offsets, so no `InceptionMessage` signatures exist for the A-001
2-key/7-key measurement shapes. Extend the registration family with
`reg_2key` + `reg_7key` (≤1024 B, seeds + offsets) and an honest vector
scenario each — existing bundles byte-unchanged, S1 loader spec updated.
One pair commit; then S5 proceeds on true shapes.

### S5b — base64url encoder optimization (interposed; A-001 QB-2 stop)

The S5 measurement gate fired: reg_7key at 84.6% mem (15.4% headroom).
Diagnosis: `base64url.encode` folds per byte (~19K mem/input byte); E2/E4/
E6/E8 run 2N+1+W encodes. Remediation: 3-bytes-per-step encoder,
byte-identical output (parity pinned by base64url_tests, S3 qb64 goldens,
shared vectors). No check changes. Attested-tier fallback (the A-001-named
path) is reserved for a post-5b miss — epic Q-003 records the stop.

### S5 — checkpoint validator scaffold + Register branch

`checkpoint.ak` with parameters `(version, hash_proof_policy, network_id,
d_reg)`: `Register` mint branch composing R1–R8 (S3 predicate + mint/output/
value checks in the validator body), R10 fail-closed spend handler. The
branch must not assume a fixed input count nor reject extra inputs beyond
those R5 names — structural room for the #116 unicity-gate input (A-001
QC).
ScriptContext-level end-to-end tests: full Tx-B contexts for the three
positive fixtures (proof input present + burned), and the R1/R2/R5/R8/R10
transaction-shape negatives. Registration-context measurement cells (2-key,
7-key, witnessed 2-of-3).

### S6 — measurements report + finalization

Pair: `MEASUREMENTS.md` under this spec dir (cells from S4/S5, headroom
verdict vs the ≥25% target, rationale if missed) and any cell gaps closed.
Orchestrator (after review): PR body audit, gate drop, mark-ready Q-file to
the epic owner.

## Risks / notes

- **E5/E7/E9 re-spelling** is the main novelty risk: it must byte-match
  keripy's compact JSON exactly; S1's generator-emitted offsets + expected
  bytes give the oracle; any spelling keripy can emit that the re-speller
  cannot reproduce is a spec-checkpoint escalation, not an improvisation.
- **Budget:** the boundary blake3 (71.7% mem) is Tx A alone; if S4 cells
  show the full mint context breaching headroom at 1024 B, record the
  rationale and the effective cap (e.g. 966 B GEDA-scale) — an epic
  escalation, not a silent cap. **Tx B is gated (A-001 QB condition 2):**
  2-key and 7-key registration contexts must meet ≥25% headroom; on a miss,
  STOP and Q-file the epic owner (fallback = attested tier, never weakened
  checks).
- **Aiken silent diagnostics:** always `script -qec 'aiken check' /dev/null`
  in briefs and the gate.
- Slice order is strict: S2 depends on S1; S3 on S2; S5 on S3+S4; S4 only on
  the vendored blake3 (kept after S3 to keep one pair cadence, no
  parallelism across the single driver/navigator pair).
