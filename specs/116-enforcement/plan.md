# Plan: enforcement wiring (#116)

The implementation keeps the existing Haskell-first/shared-vector discipline,
then opens one live validator behavior at a time. Every slice is one
bisect-safe commit with a RED→GREEN driver/navigator handshake. `just ci` is
the mechanical gate body; the final `gate.sh` also audits task trailers and
generated-vector drift.

## Module map

| Artifact | Fate |
| --- | --- |
| `offchain/test/keri-fixtures/gen_fixtures.py` + `fixtures/{fork,fork_witnessed,lag}.json` | AMEND: export enforcement field offsets without changing event/signature bytes |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Enforcement.hs` + `EnforcementSpec.hs` | AMEND: wire evidence/binding; distinct receipts; `kt` conflict axis |
| `onchain/lib/cardano_keri/checkpoint/enforcement.ak` + tests/vectors | AMEND: exact mirror and shared verdicts |
| `offchain/app/GenEnforcementVectors.hs` | AMEND: emit wire evidence + binding vectors |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Unicity.hs` + spec | NEW: registry datum/name/key/marker and MPFS transition reference model |
| `onchain/lib/cardano_keri/checkpoint/unicity.ak` + tests/vectors | NEW: registry types/derivations/absence transition mirror |
| `onchain/lib/cardano_keri/checkpoint/role.ak` + tests | NEW: deterministic ACTIVE/FROZEN/TOMBSTONE/REGISTRY addresses |
| `onchain/validators/checkpoint.ak` + tests/measurements | AMEND: bootstrap, Register gate, role dispatch, Freeze, Convict, thaw, F11 |
| `onchain/validators/checkpoint_registry_tests.ak` | NEW if separation keeps unicity vectors reviewable; otherwise owned sections in `checkpoint_tests.ak` |
| `offchain/e2e/Cardano/KERI/AID/E2E/{MpfTrie,MpfProof}.hs` | AMEND only if needed to generate exclusion proofs at declared depths; no duplicate MPF implementation when existing utilities suffice |
| `justfile`, `offchain/cardano-keri.cabal`, `offchain/test/Main.hs` | AMEND only for new modules/vector drift/measurement recipes |
| `specs/116-enforcement/MEASUREMENTS.md` | NEW final evidence report |

Exact filenames for generated unicity vectors may be collapsed into the
existing enforcement generator if that yields less plumbing; the wire and
constructor order fixed by the spec may not change.

## Slices

### Slice 1 — oracle offsets, byte preservation (T116-S1)

Extend the hermetic keripy fixture generator to record `t/i/s/d/k/kt/n/nt/bt`
value offsets for the existing `fork`, `fork_witnessed`, and `lag` evidence.
RED asserts the fields are absent/unusable; GREEN regenerates byte-stably and
proves every pre-existing event and signature byte is unchanged. No validator
behavior changes.

Owned files:

- `offchain/test/keri-fixtures/gen_fixtures.py`
- `offchain/test/keri-fixtures/fixtures/fork.json`
- `offchain/test/keri-fixtures/fixtures/fork_witnessed.json`
- `offchain/test/keri-fixtures/fixtures/lag.json`
- fixture loader/spec files needed for the preservation assertion

### Slice 2 — live evidence binding + schema corrections (T116-S2)

Add `EnforcementEvidence`, EE0–EE9 binding, and decoded-evidence construction
in Haskell, then mirror it in Aiken with shared vectors. Correct both existing
predicates to count distinct witness indices and include `cur_threshold`/`kt`
in Convict conflict agreement. RED covers offset misdirection, `d` width/slice,
duplicate receipt quorum, and kt-only conflict; GREEN establishes byte- and
verdict-parity. No transaction branch opens yet.

Owned files:

- `offchain/lib/Cardano/KERI/AID/Checkpoint/Enforcement.hs`
- `offchain/test/Cardano/KERI/AID/Checkpoint/EnforcementSpec.hs`
- `onchain/lib/cardano_keri/checkpoint/enforcement.ak`
- `onchain/lib/cardano_keri/checkpoint/enforcement_tests.ak`
- `onchain/lib/cardano_keri/checkpoint/enforcement_vectors.ak`
- `offchain/app/GenEnforcementVectors.hs`
- minimal cabal/justfile vector plumbing if required

### Slice 3 — append-only MPFS unicity + registry bootstrap (T116-S3)

Land the pure registry model/vectors, deterministic role helper (including
REGISTRY), one-shot `BootstrapRegistry`, `RecordRegistration`, and the Register
absence transition. The live Register handler changes from four to five
applied arguments by adding `registry_seed`. Existing R1–R8 stay intact.

RED first demonstrates duplicate Register is currently accepted, then covers
U1–U5 and role derivation. GREEN requires an atomic registry input/successor,
valid MPFS absence proof, paired registry spend, and exact bootstrap/thread
token confinement. Add full Register regression vectors and gate-room tests.

Owned files:

- new Haskell unicity model/spec and proof-vector support
- new `onchain/lib/cardano_keri/checkpoint/{unicity,role}.ak` + tests/vectors
- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_tests.ak` and optional focused registry test module
- `onchain/validators/checkpoint_measurements.ak`
- generator/cabal/justfile plumbing needed for shared roots/proofs

### Slice 4 — Freeze, role transition, and thaw (T116-S4)

Change `Freeze` to carry wire evidence, admit ACTIVE→FROZEN only, enforce
byte-identical datum and complete value preservation, and amend Advance input
admission from ACTIVE-only to ACTIVE|FROZEN while keeping its successor ACTIVE.
RED covers EE binding (including the 1024-byte cap) at the ledger boundary,
wrong roles/output/value, replay,
and attempts at standalone thaw. GREEN opens only Freeze and the ordinary
Advance thaw; Convict and Close remain fail-closed.

Owned files:

- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_tests.ak`
- `onchain/validators/checkpoint_measurements.ak`
- shared role helpers from S3, amended only if review finds a defect

### Slice 5 — Convict, bounty, and terminal tombstone (T116-S5)

Change `Convict` to carry wire evidence and admit ACTIVE|FROZEN→TOMBSTONE.
Enforce exact `TombstoneV1`, token, address, min-ADA-only state value, and no
own-policy mint/burn. Add the pre-dispatch role matrix so every redeemer against
a tombstone fails, including Close. RED covers witnessed fork transaction
acceptance plus F1b/F3b/F11/F13 and post-conviction Register; GREEN establishes
the complete terminal lifecycle.

Owned files:

- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_tests.ak`
- `onchain/validators/checkpoint_measurements.ak`

### Slice 6 — measurement matrix + report (T116-S6)

Measure final live ACCEPT paths and write `MEASUREMENTS.md`. Register rows sum
the Register mint and RecordRegistration spend executions from the same
transaction; absence proofs cover depths 0/8/16. Freeze covers lag/2-key/7-key;
Convict covers witnessed ACTIVE and FROZEN; bootstrap is separate. Record raw
memory/CPU, used percentage, and headroom. Any cell below 25.00% on either axis
stops before commit and opens an epic Q-file.

Owned files:

- `onchain/validators/checkpoint_measurements.ak`
- proof fixtures/generator only where required to materialize declared depths
- `specs/116-enforcement/MEASUREMENTS.md`
- `justfile` measurement recipe if missing

This slice may be docs-only after measurement fixture code lands earlier; its
RED may be explicitly logged as a measurement/report RED-SKIP. It still gets
one task trailer and independent navigator review.

## Slice ordering

S1 precedes S2 because offsets are oracle output, not hand-authored constants.
S2 closes schema holes before any live spend path trusts the predicates. S3
lands role helpers and makes registration permanently unique before S5 creates
a tombstone. S4 opens the reversible path first. S5 opens irreversible
conviction only after thaw and unicity are executable. S6 measures the settled
script and cannot be used to weaken an earlier invariant.

## Review and gate obligations

- Driver writes RED, posts `red.diff`, waits for navigator RED approval, then
  writes GREEN and posts `green.diff`; navigator reviews pre-commit.
- Workers never push. The orchestrator reviews every changed file (not only the
  diff), reruns the fresh gate, amends only task boxes/report facts, and pushes.
- Each behavior commit is Conventional Commits with exactly one
  `Tasks: T116-Sn` trailer.
- Generated fixtures/vectors must be drift-stable; existing registration,
  advance, and enforcement event bytes may not change accidentally.
- A measurement miss, wire-contract ambiguity, or runtime freeze is a Q-file,
  not an improvised fallback.
- Finalization creates a BLOCKED mark-ready Q-file. `gh pr ready` runs only
  after the epic-owner A-file; the orchestrator never merges.

## Risks

- **Aggregate Register budget.** Registration now executes the checkpoint
  script twice and verifies a non-zero-depth MPFS proof. The depth matrix and
  aggregate accounting are mandatory; depth-0 handler numbers are insufficient.
- **Combined-script dispatch confusion.** The registry thread and AID tokens
  share one policy/payment script. Exact role, datum, asset-name, and redeemer
  pairing vectors prevent one state kind being interpreted as another.
- **Irreversible output mistakes.** Tombstone value/address/datum and the F11
  role gate receive their own slice so review cannot be obscured by unicity
  plumbing.
- **Fixture churn.** S1 adds offsets only. Any event or signature byte change is
  a veto and regeneration must stop.
