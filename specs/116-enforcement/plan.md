# Plan: enforcement wiring — conviction as penalty and record (#116)

A-010 deletes the entire unicity/bounty/finalization redesign. Accepted S1,
S2, S4, and S5 behavior stays frozen. S3 is removed by one deletion-heavy
Register/fixed-bond commit, and S6 measurements are replaced by one final
measurement commit. The aborted A-009 S7 candidate never committed and has no
place in branch history.

Each corrective slice is one RED→GREEN driver/navigator commit. `gate.sh`
stays present, PR #121 remains draft, and this planning pass stops at Q-011
before any code dispatch.

## Frozen and superseded history

| Existing slice | A-010 disposition |
| --- | --- |
| S1 `4d8948b` | FROZEN: keripy enforcement offsets and byte preservation |
| S2 `6807096` | FROZEN: EE0–EE9, distinct witness indices, `kt` conflict axis |
| S3 `8837f19` | SUPERSEDED: delete the complete registration-registry surface in S7 |
| S4 `da363e7` | FROZEN: Freeze and ordinary-Advance thaw |
| S5 `5916555` | RESTORED/FROZEN: sovereign Convict, exact tombstone, direct bond release |
| S6 `653bcfb` | SUPERSEDED MEASUREMENTS: registry rows replaced in S8 |

S5 is not rewritten: A-010 explicitly re-ratifies the delivered
ACTIVE|FROZEN → TOMBSTONE handler and its “min-ADA/token stays; surplus leaves
checkpoint custody” shape. F11 is token terminality, not an AID-wide mint bar.

## Final module map

| Artifact | Final fate |
| --- | --- |
| `offchain/app/GenUnicityVectors.hs` | DELETE |
| `offchain/lib/Cardano/KERI/AID/Checkpoint/Unicity.hs` and unit spec | DELETE |
| `onchain/lib/cardano_keri/checkpoint/unicity.ak`, tests, vectors | DELETE |
| `onchain/validators/checkpoint_registry_tests.ak` | DELETE |
| `justfile` | AMEND: remove unicity generation/drift recipes and wiring only |
| `offchain/cardano-keri.cabal`, `offchain/test/Main.hs` | AMEND: remove deleted module/test/executable wiring |
| `offchain/e2e/Cardano/KERI/AID/E2E/MpfProof.hs` | AMEND: remove only S3 registry-proof exports; preserve shared MPF support |
| Haskell registration model/spec/generator | AMEND: one generic deployment-floor predicate and generated floor/one-below values |
| Aiken registration model/tests/vectors | AMEND: consume the same generated deployment-floor boundaries |
| `onchain/lib/cardano_keri/checkpoint/role.ak` and tests | AMEND: retain ACTIVE/FROZEN/TOMBSTONE bytes; remove REGISTRY |
| `onchain/validators/checkpoint.ak` | AMEND: remove registry parameter/redeemers/handlers and simplify Register; enforce fixed parameter floor |
| `onchain/validators/checkpoint_tests.ak` | AMEND: remove registry harness, accept repeated registration, add fixed-bond boundaries |
| `onchain/validators/checkpoint_measurements.ak` | AMEND: compile after S7 and hold only final Register/Freeze/Convict/Advance rows after S8 |
| `specs/116-enforcement/MEASUREMENTS.md` | AMEND in S8: replace registry-era acceptance with the simplified live matrix |

No MPF patch, dependency fork, new datum, token, role, bootstrap, claim,
finalizer, or ordering service is introduced. Net production/test LOC must
decrease in S7.

## Corrective slices

### Slice 7 — delete unicity and fix the registration bond (T116-S7)

Remove S3 end-to-end. The applied checkpoint validator loses
`registry_seed`; `MintRedeemer` loses `BootstrapRegistry`; Register loses
`registry_ref` and `absence_proof`; `SpendRedeemer` loses
`RecordRegistration`; spend classification loses REGISTRY. Delete the MPFS
model, generator, generated vectors, registry tests, and their build/test
wiring. Retain the role module with only ACTIVE, FROZEN, and TOMBSTONE.

Register then returns to the #114 R1–R8 transaction shape with no shared input
or output. The applied `d_reg` is one deployment parameter, absent from the
redeemer, and every fresh or repeated registration output must hold at least
`checkpoint_min_ada + d_reg`. Reject any applied `d_reg < 5_000_000`; retain
the 4,999,999 negative on both mint and spend dispatch and an output one
lovelace below the applied minimum.
The floor predicate lives in the shared Haskell/Aiken registration model and
the Haskell generator supplies both numeric boundary values to Aiken; the live
validator reuses it before dispatch.
Ordinary fixtures use `d_reg = 1_000_000_000`. Advance preserves the same
bond, while Freeze preserves complete value and S5 Convict removes every
surplus lovelace from the tombstone.

RED first proves the delivered validator rejects a registry-free Register and
same-AID post-conviction re-registration, while accepting a mechanically
invalid applied parameter. GREEN reverses those verdicts exactly. Full-context
coverage also proves an underfunded re-registration rejects, duplicate ACTIVE
mint is the explicit admitted residual, and every old registry constructor,
role, parameter, handler, module, recipe, and test is absent.

Owned files:

- `justfile`
- `offchain/app/GenUnicityVectors.hs` (delete)
- `offchain/lib/Cardano/KERI/AID/Checkpoint/Unicity.hs` (delete)
- `offchain/test/Cardano/KERI/AID/Checkpoint/UnicitySpec.hs` (delete)
- `offchain/cardano-keri.cabal`
- `offchain/test/Main.hs`
- `offchain/e2e/Cardano/KERI/AID/E2E/MpfProof.hs`
- `offchain/lib/Cardano/KERI/AID/Checkpoint/Registration.hs`
- `offchain/test/Cardano/KERI/AID/Checkpoint/RegistrationSpec.hs`
- `offchain/app/GenRegistrationVectors.hs`
- `onchain/lib/cardano_keri/checkpoint/unicity.ak` (delete)
- `onchain/lib/cardano_keri/checkpoint/unicity_tests.ak` (delete)
- `onchain/lib/cardano_keri/checkpoint/unicity_vectors.ak` (delete)
- `onchain/lib/cardano_keri/checkpoint/role.ak`
- `onchain/lib/cardano_keri/checkpoint/role_tests.ak`
- `onchain/lib/cardano_keri/checkpoint/registration.ak`
- `onchain/lib/cardano_keri/checkpoint/registration_tests.ak`
- `onchain/lib/cardano_keri/checkpoint/registration_vectors.ak`
- `onchain/validators/checkpoint_registry_tests.ak` (delete)
- `onchain/validators/checkpoint.ak`
- `onchain/validators/checkpoint_tests.ak`
- `onchain/validators/checkpoint_measurements.ak`

Exact commit: `refactor(116): drop unicity and fix registration bonds` with
exactly `Tasks: T116-S7`.

### Slice 8 — replacement sovereign-path measurements (T116-S8)

Remeasure only final ACCEPT paths on the simplified script:

- Register: 2-key, witnessed, and GLEIF 7-key;
- Freeze: lag, 2-key, and GLEIF 7-key;
- Convict: witnessed fork from ACTIVE and FROZEN; and
- ordinary Advance from FROZEN to ACTIVE.

All fixtures apply the non-normative reference
`d_reg = 1_000_000_000` lovelace. There is no registry spend sum, bootstrap,
MPFS depth, claim, right, Finalize, or Redeem row. Replace the S6 acceptance
tables in `MEASUREMENTS.md`, retaining only a concise dated note that those
registry-era rows were superseded by A-010. Keep the SAID non-recomputation
comparison and typed-handler/ledger-deserialization caveat.

Every row reports raw memory/CPU, used percentage, and headroom. Any result
below 25.00% headroom on either axis stops before commit and opens an epic
Q-file; signer-count reduction, fixture weakening, partial-handler
substitution, or live-node overclaim is forbidden.

Owned files:

- `onchain/validators/checkpoint_measurements.ak`
- `specs/116-enforcement/MEASUREMENTS.md`
- `justfile` only if the final measurement recipe is incomplete

Exact commit: `test(116): remeasure sovereign enforcement` with exactly
`Tasks: T116-S8`.

## Slice ordering and bisect safety

S7 removes the rejected deployed surface in one commit: no intermediate HEAD
keeps a thread token without a handler or changes Register before its fixtures
and wiring. The already-accepted Freeze/Convict paths remain usable throughout.
S8 changes only measurement fixtures/reporting after the final script shape is
green. Each HEAD builds and passes the full gate.

## Review and gate obligations

- Driver writes RED, publishes `red.diff`, waits for navigator approval, then
  writes GREEN, publishes `green.diff`, and waits for approval before one
  commit. Navigator verifies that exact commit.
- Workers never edit `specs/116-enforcement/{spec,plan,tasks}.md`, `gate.sh`, PR
  metadata, or sibling protocol files; workers never push.
- The ticket owner reviews every changed file, proves net-LOC reduction for
  S7, reruns a fresh `./gate.sh`, checks only that slice's tasks, amends the
  same commit, and pushes with force-with-lease.
- Generated evidence vectors remain Haskell-sourced and drift-stable. Deleting
  unicity wiring must not weaken registration, advance, or enforcement vector
  gates.
- `5_000_000` is the fixed mechanical parameter floor; `1_000_000_000` is the
  non-normative fixture value. Validator logic otherwise remains generic over
  the deployment parameter.
- Any leftover unicity symbol, retained REGISTRY role, deposit ambiguity,
  measurement miss, analyzer surprise, or cross-slice scope change is a
  Q-file blocker.
- `gate.sh` remains present and PR #121 remains draft. No mark-ready,
  finalization, or merge action is authorized.

## Risks

- **Partial deletion.** A stale registry constructor, applied seed parameter,
  build recipe, generated module, or test fixture would preserve dead protocol
  surface. S7 audits repository-wide symbols and the applied validator arity.
- **Terminality terminology.** F11 must stay strict for each tombstoned token
  without being reused as an AID-wide admission bar.
- **Bond drift.** Controllers never choose `d_reg`; both fresh and repeated
  Register use the applied value, and invalid deployment parameters fail.
- **Payout overclaim.** The validator enforces that no bond remains in the
  tombstone. It does not invent an on-chain real-world convictor identity; the
  transaction builder owns the ordinary off-script payout/change.
- **Historical measurements.** Registry-era numbers are no longer final
  acceptance evidence and must be clearly marked superseded.
